# Модуль 9: Асинхронность, параллельность и ZIO Fibers

> 📁 Файлы: `Main.scala` (CM), `ConnectionHandler.scala`, `TcpServer.scala`

---

## 9.1 Три модели выполнения: последовательно / асинхронно / параллельно

### Последовательное (sequential):
```
Задача A ████████████
                     Задача B ████████████
                                          Задача C ████
Время: ──────────────────────────────────────────────→
```
Каждая задача ждёт завершения предыдущей.

### Асинхронное (async):
```
Задача A ███░░░░███          ░ = ожидание I/O (БД, сеть)
         Задача B ███░░░░███
              Задача C ██░██
Время: ──────────────────────→
```
Пока A ждёт ответа Redis — выполняется B. **Один поток**, но задачи чередуются.

### Параллельное (parallel):
```
Поток 1: Задача A ████████
Поток 2: Задача B ████████
Поток 3: Задача C ████
Время: ──────────────────→
```
Каждая задача на **отдельном ядре CPU** одновременно.

### Ключевая разница:

| | Async | Parallel |
|---|-------|----------|
| Потоки | 1 (или мало) | Много (по числу CPU) |
| Задача | Ждём I/O — переключаемся | Считаем на CPU одновременно |
| Пример | Запрос в Redis + Kafka | Парсинг 4 протоколов |
| ZIO | `flatMap`, `for` | `zipPar`, `collectAllPar` |

---

## 9.2 Проблема потоков в JVM

```
Java Thread = OS Thread = ~1MB стека

10,000 трекеров × 1 поток = 10 GB RAM только на стеки!
```

**Решение: ZIO Fibers** — лёгкие «зелёные потоки».

```
ZIO Fiber = ~400 байт

10,000 трекеров × 1 файбер = ~4 MB RAM  ← в 2500 раз меньше!
```

---

## 9.3 ZIO Fiber — виртуальный поток

Fiber — это описание вычисления, которое **выполняется на пуле потоков ZIO**.

```scala
// Запуск файбера (не блокирует текущий!)
val fiber: UIO[Fiber[Throwable, Unit]] = myEffect.fork

// fork = "запусти в фоне, дай мне хэндл"
```

### В нашем проекте (Main.scala Connection Manager):

```scala
// Шаг 2: Запуск фоновых слушателей как daemon fibers
_ <- deviceConfigListener.start.forkDaemon  // Файбер 1: слушает Redis pub/sub
_ <- commandService.startCommandListener.forkDaemon  // Файбер 2: слушает команды
```

### fork vs forkDaemon:

```scala
effect.fork        // Дочерний файбер — умрёт если родитель завершится
effect.forkDaemon  // Daemon файбер — живёт пока жив весь ZIO runtime
```

Для наших слушателей нужен `forkDaemon` — они должны жить всё время работы сервера.

---

## 9.4 Операции с Fiber

```scala
// Запустить и получить результат позже
val fiber = myEffect.fork
val result = fiber.flatMap(_.join)  // Ждёт завершения, возвращает результат

// Прервать файбер
fiber.flatMap(_.interrupt)  // Грациозная остановка

// Запустить два файбера, получить результат первого завершившегося
val fast = ZIO.raceAll(effect1, List(effect2, effect3))
```

---

## 9.5 Параллельность в ZIO — комбинаторы

### zipPar — два эффекта параллельно:

```scala
val both: Task[(ResultA, ResultB)] = effectA.zipPar(effectB)
// Запускает A и B одновременно, ждёт оба
```

### collectAllPar — список эффектов параллельно:

```scala
// Main.scala — запуск 4 TCP серверов ПАРАЛЛЕЛЬНО:
_ <- ZIO.collectAllParDiscard(
  List(
    startServerIfEnabled("Teltonika", config.tcp.teltonika, server, teltonikaFactory),
    startServerIfEnabled("Wialon",    config.tcp.wialon,    server, wialonFactory),
    startServerIfEnabled("Ruptela",   config.tcp.ruptela,   server, ruptelaFactory),
    startServerIfEnabled("NavTelecom",config.tcp.navtelecom, server, navtelecomFactory)
  )
)
// 4 сервера стартуют ОДНОВРЕМЕННО, а не один за другим!
```

### foreachPar — параллельный foreach:

```scala
ZIO.foreachPar(devices)(device => syncToRedis(device))
// Все устройства синхронизируются параллельно
```

---

## 9.6 ZIO.async — мост из callback-мира

Netty и Lettuce работают на callback'ах. ZIO — на эффектах. Мост:

```scala
// TcpServer.scala
ZIO.async { callback =>
  channel.close().addListener { (future: ChannelFuture) =>
    if future.isSuccess then callback(ZIO.unit)
    else callback(ZIO.fail(new Exception("...")))
  }
}
```

### Как это работает внутри:

```
1. ZIO создаёт Promise (ожидание результата)
2. Передаёт функцию callback в Netty
3. Текущий файбер ПРИОСТАНАВЛИВАЕТСЯ (не блокирует поток!)
4. Netty вызывает callback в своём потоке
5. ZIO ВОЗОБНОВЛЯЕТ файбер с результатом
```

Ключевое: **файбер не занимает поток** пока ждёт callback.

---

## 9.7 Unsafe.unsafe — выход из ZIO мира

Иногда Java-код требует синхронный результат. Тогда:

```scala
// RateLimitHandler.scala — Netty handler вызывает ZIO
override def channelActive(ctx: ChannelHandlerContext): Unit =
  val effect = rateLimiter.tryAcquire(ip).flatMap { ... }
  
  Unsafe.unsafe { implicit unsafe =>
    runtime.unsafe.run(effect).getOrThrowFiberFailure()
  }
```

### Когда это нужно:

| Ситуация | Решение |
|----------|---------|
| ZIO вызывает Java | `ZIO.attempt(javaCode)` |
| Java вызывает ZIO | `Unsafe.unsafe { runtime.unsafe.run(effect) }` |
| Netty handler → ZIO | `Unsafe.unsafe` (наш случай) |
| Redis pub/sub callback → ZIO | `Unsafe.unsafe` (RedisClient.scala) |

---

## 9.8 ZIO.never — ожидание навечно

```scala
// Main.scala — последняя строка программы
_ <- ZIO.never
```

`ZIO.never` — файбер, который никогда не завершится. Он **не занимает поток** — просто ждёт. Программа остановится только при `SIGTERM` (Ctrl+C), и тогда ZIO запустит graceful shutdown (закроет все `acquireRelease`).

---

## 9.9 Structured concurrency — структурированная конкурентность

ZIO гарантирует: если родительский файбер завершается — все дочерние тоже.

```scala
for
  fiber1 <- longTask1.fork
  fiber2 <- longTask2.fork
  _      <- doSomething
yield ()
// Если doSomething упадёт — fiber1 и fiber2 будут прерваны!
// Нет утечек ресурсов, нет зависших файберов.
```

Исключение: `forkDaemon` — живёт независимо от родителя.

---

## 📝 Упражнение

1. В `Main.scala` — найди все `.forkDaemon`. Почему не просто `.fork`?
2. Что произойдёт с файберами при нажатии Ctrl+C?
3. `ZIO.collectAllParDiscard` vs `ZIO.collectAllPar` — в чём разница?
4. Почему `ZIO.never` не потребляет CPU? (Подсказка: файбер suspended)
5. Сколько файберов создаётся при запуске Connection Manager?

---

**→ Следующий: [10-CATS-ECOSYSTEM.md](10-CATS-ECOSYSTEM.md) — Cats и экосистема**
