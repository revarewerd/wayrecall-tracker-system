# Модуль 8: Тестирование ZIO

> 📁 Файлы: `RateLimiterSpec.scala`, `TeltonikaParserSpec.scala`, `DeviceServiceSpec.scala`

---

## 8.1 ZIOSpecDefault — базовый класс тестов

```scala
object RateLimiterSpec extends ZIOSpecDefault:
  def spec = suite("RateLimiter")(
    test("разрешает соединения в пределах лимита") {
      for
        limiter <- makeTestLimiter(maxConnections = 3)
        r1 <- limiter.tryAcquire("192.168.1.1")
        r2 <- limiter.tryAcquire("192.168.1.1")
        r3 <- limiter.tryAcquire("192.168.1.1")
      yield assertTrue(r1 && r2 && r3)
    }
  )
```

### Структура:

- `extends ZIOSpecDefault` — тесты выполняются в ZIO runtime
- `suite("name")` — группа тестов
- `test("name") { ... }` — один тест
- `assertTrue(...)` — проверка условия
- Внутри теста — обычный `for`/`yield` с ZIO эффектами

---

## 8.2 assertTrue — утверждения

```scala
// Простые проверки
assertTrue(r1 && r2 && r3)          // все true
assertTrue(!r3)                      // r3 == false
assertTrue(count == 3)               // равенство
assertTrue(stats.isEmpty)            // пустой
assertTrue(result.isLeft)            // Either.Left

// Составные проверки
assertTrue(
  stats.get("192.168.1.1").contains(2) &&
  stats.get("192.168.1.2").contains(1)
)
```

---

## 8.3 Тестовый RateLimiter — Ref вместо внешних зависимостей

```scala
private def makeTestLimiter(
  maxConnections: Int = 5,
  windowSeconds: Int = 1
): UIO[RateLimiter] =
  Ref.make(Map.empty[String, ConnectionRecord]).map { ref =>
    RateLimiter.Live(
      recordsRef = ref,
      maxConnectionsPerIp = maxConnections,
      windowMs = windowSeconds * 1000L,
      cleanupIntervalMs = 60 * 1000L
    )
  }
```

### Почему это работает:

- `Ref` — in-memory, не нужен Redis
- Создаём новый `Ref` в каждом тесте → **изоляция**
- Параметризуем лимиты → легко тестировать граничные случаи

---

## 8.4 TestClock — управление временем

```scala
test("восстанавливается после истечения окна") {
  for
    limiter <- makeTestLimiter(maxConnections = 1, windowSeconds = 1)
    r1 <- limiter.tryAcquire("192.168.1.1")
    r2 <- limiter.tryAcquire("192.168.1.1")  // Заблокирован
    _ <- TestClock.adjust(2.seconds)           // ⏰ Перемотка на 2 сек!
    r3 <- limiter.tryAcquire("192.168.1.1")  // Разблокирован
  yield assertTrue(r1 && !r2 && r3)
} @@ TestAspect.withLiveClock
```

### `TestClock.adjust`:

- Перематывает виртуальное время **мгновенно**
- Не ждёт реальные 2 секунды
- Тест выполняется за миллисекунды

### `@@ TestAspect.withLiveClock`:

Аспект теста — модификатор поведения. `withLiveClock` использует реальные часы для `Clock.currentTime` внутри тестируемого кода.

---

## 8.5 Тестирование парсеров — ByteBuf

```scala
// TeltonikaParserSpec.scala
test("парсит валидный IMEI") {
  val imei = "352093082745395"
  val buffer = Unpooled.buffer()
  buffer.writeShort(15)       // длина IMEI
  buffer.writeBytes(imei.getBytes("US-ASCII"))
  
  for
    result <- parser.parseImei(buffer)
  yield assertTrue(result == imei)
}
```

### Тестирование ошибок с `.either`:

```scala
test("отклоняет IMEI неверной длины") {
  val buffer = Unpooled.buffer()
  buffer.writeShort(5)
  buffer.writeBytes("12345".getBytes("US-ASCII"))
  
  for
    result <- parser.parseImei(buffer).either  // IO[E,A] → UIO[Either[E,A]]
  yield assertTrue(result.isLeft)              // Ожидаем ошибку
}
```

`either` превращает ошибку в значение → тест не падает, а проверяет ошибку.

---

## 8.6 Организация тестов

### Вложенные suites:

```scala
def spec = suite("RateLimiter")(
  suite("tryAcquire")(
    test("разрешает в пределах лимита") { ... },
    test("блокирует при превышении") { ... },
    test("изолирует разные IP") { ... }
  ),
  suite("getConnectionCount")(
    test("возвращает 0 для нового IP") { ... },
    test("корректно считает") { ... }
  ),
  suite("getStats")(
    test("пустая статистика") { ... },
    test("статистика по всем IP") { ... }
  )
)
```

### Паттерн для тестов:

```
1. Arrange — создаём тестовые данные (makeTestLimiter)
2. Act     — выполняем действия (tryAcquire)
3. Assert  — проверяем результат (assertTrue)
```

---

## 8.7 Идеи для тестов в проекте

| Что тестировать | Как | Зависимости |
|-----------------|-----|-------------|
| RateLimiter | Ref + TestClock | Нет |
| DeadReckoningFilter | Тестовые GpsPoint | Mock DynamicConfigService |
| DeviceRepository | testcontainers-postgresql | Реальная БД |
| KafkaProducer | embedded-kafka | Реальный Kafka |
| ConnectionHandler | Mock RedisClient + KafkaProducer | ZIO Mock |

---

## 📝 Упражнение

1. Открой `RateLimiterSpec.scala` — сколько тестов? Все ли проходят?
2. Зачем `TestClock.adjust(2.seconds)` вместо `ZIO.sleep(2.seconds)`?
3. В `TeltonikaParserSpec.scala` — почему тест CRC ожидает ошибку?
4. Напиши мысленно тест: "создание устройства с дублирующимся IMEI вернёт ошибку"
5. Какие тесты можно написать для `DeadReckoningFilter`?

---

## 🎓 Заключение

Ты прошёл 8 модулей. Теперь ты знаешь:

| Модуль | Ты понял |
|--------|----------|
| Scala 3 | Opaque types, enums, case classes, extensions, ADT |
| ZIO Core | ZIO[R,E,A], for-comprehension, error handling, Ref |
| ZIO Layers | ZLayer, provide, scoped, acquireRelease |
| Streams + Kafka | Consumer stream, Producer async, батчинг, retry |
| Redis | Lettuce → ZIO, pub/sub, кэш, Unsafe bridge |
| Doobie | sql interpolator, Meta, Transactor, ConnectionIO |
| Netty | EventLoopGroup, pipeline, handlers, ZIO.async bridge |
| Тестирование | ZIOSpecDefault, assertTrue, TestClock, .either |

**→ Вернуться к [README.md](README.md)**
