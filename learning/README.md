# 🎓 План глубинного изучения технологий Wayrecall Tracker

> Каждый модуль привязан к реальному коду проекта.
> Порядок: от базы к сложному. Не пропускай модули!

## 📋 Модули

### Часть 1: Основы (привязаны к коду проекта)

| # | Модуль | Темы | Где в проекте |
|---|--------|------|---------------|
| 1 | [Scala 3 основы](01-SCALA3.md) | Типы, enums, opaque types, extensions, ADT | `Entities.scala`, `Errors.scala` |
| 2 | [ZIO Core — эффекты](02-ZIO-CORE.md) | ZIO[R,E,A], for-comprehension, ошибки, Ref | `DeviceService.scala`, `ConnectionRegistry.scala` |
| 3 | [ZIO Layers — DI](03-ZIO-LAYERS.md) | ZLayer, provide, scoped, acquireRelease | `Main.scala`, `KafkaProducer.scala` |
| 4 | [ZIO Streams + Kafka](04-ZIO-STREAMS-KAFKA.md) | ZStream, Consumer, Producer, батчинг, retry | `TelemetryConsumer.scala`, `KafkaProducer.scala` |
| 5 | [Redis паттерны](05-REDIS.md) | Lettuce, pub/sub, кэш, async → ZIO | `RedisClient.scala` |
| 6 | [PostgreSQL + Doobie](06-DOOBIE.md) | Transactor, sql interpolator, Meta, ConnectionIO | `DeviceRepository.scala` |
| 7 | [Netty TCP сервер](07-NETTY.md) | EventLoopGroup, pipeline, ByteBuf, handlers | `TcpServer.scala`, `ConnectionHandler.scala` |
| 8 | [Тестирование ZIO](08-TESTING.md) | ZIOSpecDefault, TestClock, assertTrue, .either | `RateLimiterSpec.scala`, `TeltonikaParserSpec.scala` |

### Часть 2: Глубокое погружение

| # | Модуль | Темы |
|---|--------|------|
| 9 | [Fibers и асинхронность](09-FIBERS-ASYNC.md) | fork/forkDaemon, async vs parallel, ZIO.async, Unsafe, structured concurrency |
| 10 | [Cats и выбор библиотек](10-CATS-ECOSYSTEM.md) | Cats Effect vs ZIO, почему Doobie а не Slick/Skunk, zio-interop-cats, Circe vs zio-json |
| 11 | [Экосистема Scala](11-SCALA-ECOSYSTEM.md) | FS2, Tapir, http4s, gRPC, Quill, Chimney, Refined — карта роста скалиста |

## 🗺️ Рекомендуемый порядок

```
Неделя 1: Модули 1-2  (Scala 3 + ZIO основы)
Неделя 2: Модули 3-4  (Layers + Streams/Kafka)
Неделя 3: Модули 5-6  (Redis + Doobie)
Неделя 4: Модули 7-8  (Netty + Тесты)
Неделя 5: Модули 9-11 (Fibers, Cats ecosystem, рост)
```

## 💡 Как изучать каждый модуль

1. **Прочитай теорию** в файле модуля
2. **Найди код** в проекте (ссылки указаны)
3. **Разбери пример** построчно
4. **Выполни упражнение** в конце модуля
5. **Задай вопрос** Copilot если что-то непонятно
