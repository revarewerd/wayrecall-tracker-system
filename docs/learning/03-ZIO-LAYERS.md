# Модуль 3: ZIO Layers — Dependency Injection

> 📁 Файлы: `Main.scala` (CM), `KafkaProducer.scala`, `TcpServer.scala`, `RedisClient.scala`

---

## 3.1 Проблема: как собрать приложение из компонентов?

Наш Connection Manager зависит от:
- `AppConfig` → конфигурация
- `RedisClient` → кэш и pub/sub
- `KafkaProducer` → публикация событий
- `TcpServer` → TCP серверы Netty
- `ConnectionRegistry` → реестр соединений
- `DeadReckoningFilter` → фильтрация GPS

**Как связать всё это без глобального состояния?** → **ZLayer**

---

## 3.2 Что такое ZLayer?

```scala
ZLayer[R, E, A]
//     ↑  ↑  ↑
//     Что нужно для создания
//        Ошибка при создании
//           Что предоставляет
```

Пример: `KafkaProducer` нужна `KafkaConfig`, может упасть с `Throwable`, предоставляет `KafkaProducer`:

```scala
val live: ZLayer[KafkaConfig, Throwable, KafkaProducer]
```

---

## 3.3 Паттерн trait + Live + ZLayer

В нашем проекте каждый компонент следует паттерну:

```scala
// 1. ИНТЕРФЕЙС (что умеет)
trait KafkaProducer:
  def publish(topic: String, key: String, value: String): IO[KafkaError, Unit]
  def publishGpsEvent(point: GpsPoint): IO[KafkaError, Unit]

// 2. COMPANION OBJECT (accessor методы + layer)
object KafkaProducer:
  // Accessor — позволяет вызвать метод из ZIO окружения
  def publish(topic: String, key: String, value: String): ZIO[KafkaProducer, KafkaError, Unit] =
    ZIO.serviceWithZIO(_.publish(topic, key, value))
  
  // 3. РЕАЛИЗАЦИЯ (final case class Live)
  final case class Live(producer: JavaKafkaProducer[String, String], config: KafkaConfig) 
    extends KafkaProducer:
    // ... реализация методов ...
  
  // 4. LAYER (как создать Live)
  val live: ZLayer[KafkaConfig, Throwable, KafkaProducer] = ZLayer.scoped { ... }
```

### Зачем это нужно?

```scala
// В бизнес-коде пишем через интерфейс:
KafkaProducer.publishGpsEvent(point)
// Реализацию подставим ПОЗЖЕ через Layer!

// В тестах можно подставить мок:
val testLayer: ZLayer[Any, Nothing, KafkaProducer] = ZLayer.succeed(mockKafka)
```

---

## 3.4 ZLayer.scoped — управление ресурсами

Для ресурсов, которые нужно **открыть и закрыть** (подключения, пулы потоков):

```scala
// KafkaProducer.scala
val live: ZLayer[KafkaConfig, Throwable, KafkaProducer] =
  ZLayer.scoped {
    for
      config <- ZIO.service[KafkaConfig]
      
      // acquireRelease = создать + зарегистрировать закрытие
      producer <- ZIO.acquireRelease(
        // ACQUIRE: создаём producer
        ZIO.attempt(new JavaKafkaProducer[String, String](props))
          .tap(_ => ZIO.logInfo("Kafka producer создан"))
      )(
        // RELEASE: закрываем при shutdown (гарантированно!)
        prod => ZIO.attempt(prod.close()).orDie
          .tap(_ => ZIO.logInfo("Kafka producer закрыт"))
      )
    yield Live(producer, config)
  }
```

### Гарантия: RELEASE всегда выполнится!

```
Приложение запущено → producer создан
    ↓
... работа ...
    ↓
SIGTERM (Ctrl+C) → producer.close() ГАРАНТИРОВАННО вызван
```

### TcpServer — то же для Netty EventLoopGroup:

```scala
// TcpServer.scala
bossGroup <- ZIO.acquireRelease(
  ZIO.attempt(new NioEventLoopGroup(config.bossThreads))
)(group => 
  ZIO.async[Any, Nothing, Unit] { callback =>
    group.shutdownGracefully().addListener(_ => callback(ZIO.unit))
  }
)
```

---

## 3.5 Композиция слоёв

### Горизонтальная (`++`): объединить независимые слои

```scala
val configLayer: ZLayer[Any, Throwable, AppConfig] = AppConfig.live
val redisLayer: ZLayer[RedisConfig, Throwable, RedisClient] = RedisClient.live
val kafkaLayer: ZLayer[KafkaConfig, Throwable, KafkaProducer] = KafkaProducer.live

// Объединяем:
val combined = redisLayer ++ kafkaLayer
// ZLayer[RedisConfig & KafkaConfig, Throwable, RedisClient & KafkaProducer]
```

### Вертикальная (`>>>`): выход одного → вход следующего

```scala
// Config → Redis
val redisFromConfig = configLayer >>> redisLayer
// ZLayer[Any, Throwable, RedisClient]
//  ↑ больше не нужна RedisConfig снаружи!
```

### Граф зависимостей Connection Manager:

```
AppConfig
  ├── RedisConfig → RedisClient
  ├── KafkaConfig → KafkaProducer  
  ├── TcpConfig → TcpServer
  └── FiltersConfig → DeadReckoningFilter
                    → StationaryFilter

    ↓ Всё вместе ↓

GpsProcessingService(RedisClient, KafkaProducer, Filters)
ConnectionHandler(GpsProcessingService)
Main.program (запуск TCP серверов)
```

---

## 3.6 ZIO.service — получение зависимости

```scala
// Main.scala — получаем все сервисы из окружения
val program: ZIO[AppConfig & TcpServer & ..., Throwable, Unit] =
  for
    config  <- ZIO.service[AppConfig]
    server  <- ZIO.service[TcpServer]
    registry <- ZIO.service[ConnectionRegistry]
    // ...
  yield ()
```

### ZIO.serviceWithZIO — вызвать метод сервиса:

```scala
// Вместо:
for
  service <- ZIO.service[DeviceService]
  device  <- service.getDevice(id)
yield device

// Короче:
ZIO.serviceWithZIO[DeviceService](_.getDevice(id))
```

---

## 3.7 .provide — подключение слоёв к программе

```scala
// Main.scala (Connection Manager)
override def run: ZIO[Any, Any, Any] =
  program.provide(
    AppConfig.live,          // Конфигурация
    RedisClient.live,        // Redis
    KafkaProducer.live,      // Kafka
    TcpServer.liveWithRateLimiter,  // TCP с rate limiting
    ConnectionRegistry.live, // Реестр соединений
    DeadReckoningFilter.live,// Фильтр GPS
    StationaryFilter.live,   // Фильтр стоянок
    RateLimiter.live,        // Rate limiter
    // ... и т.д.
  )
```

ZIO **автоматически** построит граф зависимостей:
1. Создаст `AppConfig`
2. Из `AppConfig` извлечёт `RedisConfig`, `KafkaConfig`, `TcpConfig`
3. Создаст `RedisClient`, `KafkaProducer`, `TcpServer`
4. Соберёт `GpsProcessingService` из всех зависимостей
5. Запустит `program`
6. При shutdown — закроет всё в обратном порядке

---

## 3.8 ZLayer.fromFunction — простой слой

Если не нужны ресурсы (не нужен release), достаточно:

```scala
// DeadReckoningFilter.scala
val live: ZLayer[DynamicConfigService, Nothing, DeadReckoningFilter] =
  ZLayer.fromFunction(Live(_))
// Просто вызывает конструктор Live(configService)

// DeviceRepository.scala
val live: ZLayer[Transactor[Task], Nothing, DeviceRepository] =
  ZLayer.fromFunction(Live.apply)
```

---

## 📝 Упражнение

1. Открой `KafkaProducer.scala` — найди `acquireRelease`. Что создаётся? Что закрывается?
2. Открой `TcpServer.scala` — почему `bossGroup` и `workerGroup` используют `acquireRelease`?
3. В `Main.scala` (CM) — сколько слоёв передаётся в `.provide`?
4. Нарисуй на бумаге граф зависимостей: что от чего зависит
5. Почему `ConnectionRegistry.live` не использует `scoped`? (Подсказка: нет внешних ресурсов)

---

**→ Следующий: [04-ZIO-STREAMS-KAFKA.md](04-ZIO-STREAMS-KAFKA.md) — ZIO Streams + Kafka**
