# Модуль 5: Redis — кэширование и реальное время

> 📁 Файлы: `RedisClient.scala`, `CommandService.scala`, `DeviceConfigListener.scala`

---

## 5.1 Зачем Redis в Wayrecall?

| Задача | Кто пишет | Кто читает | Тип данных |
|--------|-----------|-----------|-----------|
| IMEI → VehicleId маппинг | Device Manager | Connection Manager | String |
| Последние GPS позиции | Connection Manager | WebSocket, API | JSON |
| Регистрация соединений | Connection Manager | Device Manager | JSON |
| Очередь команд | Device Manager | Connection Manager | ZSET |
| Pub/Sub уведомления | Device Manager | Connection Manager | Channels |

**Redis = общая шина данных** между сервисами в реальном времени.

---

## 5.2 Lettuce — async Redis клиент

Мы используем **Lettuce** (Java библиотека) с обёрткой в ZIO.

```scala
// RedisClient.scala — интерфейс
trait RedisClient:
  def getVehicleId(imei: String): IO[RedisError, Option[Long]]
  def setPosition(point: GpsPoint): IO[RedisError, Unit]
  def subscribe(channel: String)(handler: String => Task[Unit]): Task[Unit]
  def hset(key: String, values: Map[String, String]): Task[Unit]
  def hgetall(key: String): Task[Map[String, String]]
```

### Мост Java CompletionStage → ZIO:

```scala
private def fromCompletionStage[A](cs: => CompletionStage[A]): Task[A] =
  ZIO.fromFuture(_ => cs.asScala)
```

Это **ключевой паттерн**: любая Java async библиотека → ZIO через Future.

---

## 5.3 Кэширование позиций

### Запись (Connection Manager):

```scala
override def setPosition(point: GpsPoint): IO[RedisError, Unit] =
  val key = positionKey(point.vehicleId)   // "position:42"
  val value = point.toJson                  // JSON строка
  val ttlSeconds = config.positionTtlSeconds // 300 сек
  
  fromCompletionStage(commands.setex(key, ttlSeconds, value))
    .unit
    .mapError(e => RedisError.OperationFailed(e.getMessage))
```

### Чтение (Connection Manager при аутентификации):

```scala
override def getPosition(vehicleId: Long): IO[RedisError, Option[GpsPoint]] =
  fromCompletionStage(commands.get(positionKey(vehicleId)))
    .map { value =>
      Option(value).flatMap(_.fromJson[GpsPoint].toOption)
    }
    .mapError(e => RedisError.OperationFailed(e.getMessage))
```

### Паттерн: Option(value) защита от null

```scala
Option(value)  // null → None, "data" → Some("data")
  .flatMap(_.fromJson[GpsPoint].toOption)  // парсинг JSON, None если ошибка
```

Java Lettuce может вернуть `null` если ключ не найден — `Option(_)` защищает.

---

## 5.4 Pub/Sub — реальное время

### Подписка на канал:

```scala
override def subscribe(channel: String)(handler: String => Task[Unit]): Task[Unit] =
  ZIO.attempt {
    val listener = new RedisPubSubAdapter[String, String] {
      override def message(ch: String, message: String): Unit =
        if ch == channel then
          Unsafe.unsafe { implicit unsafe =>
            runtime.unsafe.run(
              handler(message).catchAll(e => ZIO.logError(s"Handler error: $e"))
            ).getOrThrowFiberFailure()
          }
    }
    pubSubConnection.addListener(listener)
    pubSubConnection.sync().subscribe(channel)
  }
```

### Что тут происходит?

1. Lettuce вызывает `message()` в своём потоке (не ZIO!)
2. `Unsafe.unsafe` — мост из обычного Java-кода в ZIO runtime
3. `runtime.unsafe.run(...)` — запускает ZIO эффект синхронно

### Pattern subscribe (glob):

```scala
override def psubscribe(pattern: String)(handler: (String, String) => Task[Unit]): Task[Unit] =
  // pattern = "commands:*" → подписка на все каналы commands:860719...
```

### Использование в Connection Manager:

```scala
// Слушаем команды для конкретных устройств:
redis.psubscribe("commands:*") { (channel, message) =>
  // channel = "commands:860719020025346"
  // message = '{"type":"reboot","params":{}}'
  val imei = channel.stripPrefix("commands:")
  sendCommandToDevice(imei, message)
}
```

---

## 5.5 ZLayer для RedisClient

```scala
val live: ZLayer[RedisConfig, Throwable, RedisClient] =
  ZLayer.scoped {
    for
      config  <- ZIO.service[RedisConfig]
      runtime <- ZIO.runtime[Any]
      
      // Создаём Lettuce клиент
      client <- ZIO.acquireRelease(
        ZIO.attempt(LettuceClient.create(uri))
      )(client => ZIO.attempt(client.shutdown()).orDie)
      
      // Соединение для обычных команд
      connection <- ZIO.acquireRelease(
        ZIO.attempt(client.connect())
      )(conn => ZIO.attempt(conn.close()).orDie)
      
      // Отдельное соединение для Pub/Sub
      pubSubConnection <- ZIO.acquireRelease(
        ZIO.attempt(client.connectPubSub())
      )(conn => ZIO.attempt(conn.close()).orDie)
      
      commands = connection.async()  // async команды
    yield Live(commands, pubSubConnection, runtime, config)
  }
```

### Три ресурса, три `acquireRelease`:

```
1. LettuceClient      → client.shutdown()
2. Connection          → connection.close()
3. PubSubConnection    → pubSubConnection.close()
```

Все закроются при shutdown в **обратном порядке**.

---

## 5.6 Ключи Redis в проекте

```
vehicle:{imei}           = vehicleId (String → Long)
position:{vehicleId}     = GpsPoint JSON (TTL 5min)
connection:{imei}        = ConnectionInfo JSON
```

Подробная структура: см. `infra/redis/KEYS.md`

---

## 📝 Упражнение

1. Открой `RedisClient.scala` — найди `fromCompletionStage`. Почему это `Task[A]`, а не `IO[RedisError, A]`?
2. Как `setex` отличается от `set`? (Подсказка: TTL)
3. Зачем отдельное соединение для Pub/Sub? (Подсказка: блокирующая подписка)
4. Что произойдёт при `Unsafe.unsafe` если handler бросит исключение?
5. Почему `getPosition` возвращает `Option[GpsPoint]`, а не `GpsPoint`?

---

**→ Следующий: [06-DOOBIE.md](06-DOOBIE.md) — PostgreSQL + Doobie**
