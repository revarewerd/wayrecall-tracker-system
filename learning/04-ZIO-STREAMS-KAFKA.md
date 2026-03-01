# Модуль 4: ZIO Streams + Apache Kafka

> 📁 Файлы: `TelemetryConsumer.scala`, `KafkaProducer.scala`

---

## 4.1 Что такое ZStream?

`ZStream[R, E, A]` — поток значений типа `A`, который:
- **R** — нужные зависимости
- **E** — возможная ошибка
- **A** — тип элементов потока

```
ZIO    = одно значение           (запрос → ответ)
ZStream = много значений по одному (Kafka → поток сообщений)
```

---

## 4.2 Kafka Producer (Connection Manager)

Connection Manager **отправляет** GPS точки в Kafka.

```scala
// KafkaProducer.scala — интерфейс
trait KafkaProducer:
  def publish(topic: String, key: String, value: String): IO[KafkaError, Unit]
  def publishGpsEvent(point: GpsPoint): IO[KafkaError, Unit]
  def publishDeviceStatus(status: DeviceStatus): IO[KafkaError, Unit]
```

### Отправка сообщения — ZIO.async:

```scala
override def publish(topic: String, key: String, value: String): IO[KafkaError, Unit] =
  ZIO.async { callback =>
    val record = new ProducerRecord[String, String](topic, key, value)
    producer.send(record, (metadata: RecordMetadata, exception: Exception) =>
      if exception != null then
        callback(ZIO.fail(KafkaError.ProducerError(exception.getMessage)))
      else
        callback(ZIO.unit)
    )
  }
```

### Что тут происходит?

1. `ZIO.async` — мост из callback-мира в ZIO-мир
2. Java Kafka Producer принимает callback `(metadata, exception) =>`
3. Если ошибка → `callback(ZIO.fail(...))`
4. Если успех → `callback(ZIO.unit)`

### Партиционирование (КРИТИЧНО для порядка):

```scala
override def publishGpsEvent(point: GpsPoint): IO[KafkaError, Unit] =
  serializeAndPublish(point, config.topics.rawGpsEvents, point.vehicleId.toString)
//                                                       ^^^^^^^^^^^^^^^^^^^^
//                         KEY = vehicleId → все точки одного устройства в ОДНОМ partition
//                         Это ГАРАНТИРУЕТ порядок доставки для одного устройства!
```

---

## 4.3 Kafka Consumer (History Writer)

History Writer **читает** из Kafka и пишет батчами в TimescaleDB.

```scala
// TelemetryConsumer.scala
private def consumeStream: ZStream[Any, Throwable, Unit] =
  Consumer
    .plainStream(subscription, Serde.string, Serde.string)  // Шаг 1: Читаем
    .mapZIO { record =>                                       // Шаг 2: Парсим
      ZIO.fromEither(record.value.fromJson[TelemetryEvent])
        .map(_.toTelemetryPoint)
        .option                                               // None если ошибка парсинга
    }
    .collect { case Some(point) => point }                    // Шаг 3: Фильтруем None
    .groupedWithin(batchConfig.maxBatchSize, flushInterval)   // Шаг 4: Батчим
    .mapZIO { chunk =>                                        // Шаг 5: Пишем в БД
      writeBatchWithRetry(TelemetryBatch(chunk.toList))
    }
```

### Визуально:

```
Kafka topic "gps-events"
  │
  ├─ msg1 ─┐
  ├─ msg2  ─┤
  ├─ msg3  ─┤ groupedWithin(500, 1.second)
  ├─ ...   ─┤
  ├─ msg500 ┘ → [batch of 500] → INSERT INTO gps_positions (...) VALUES (...)
  │
  ├─ msg501 ─┐
  ├─ ...    ─┤ (или 1 секунда прошла — flush по времени)
  └─ msg520  ┘ → [batch of 20] → INSERT INTO gps_positions ...
```

---

## 4.4 Ключевые операторы ZStream

### groupedWithin — батчинг:

```scala
stream.groupedWithin(500, 1.second)
// Собирает до 500 элементов ИЛИ 1 секунду (что раньше)
// Идеально для батч-записи в БД
```

### mapZIO — трансформация с эффектом:

```scala
stream.mapZIO { record =>
  // Каждый элемент обрабатывается через ZIO
  parseRecord(record)  // может упасть с ошибкой
}
```

### collect — фильтрация:

```scala
stream.collect { case Some(point) => point }
// Пропускает None, извлекает значение из Some
```

### retry — повтор при ошибке:

```scala
repository.insertBatch(batch)
  .retry(Schedule.recurs(3) && Schedule.spaced(1.second))
// 3 попытки с интервалом 1 секунда
```

---

## 4.5 Schedule — расписания повторов

```scala
Schedule.recurs(3)                    // 3 попытки
Schedule.spaced(1.second)             // каждую секунду
Schedule.exponential(100.millis)      // 100ms, 200ms, 400ms, 800ms...
Schedule.recurs(5) && Schedule.spaced(500.millis)  // 5 попыток по 500ms
```

В нашем коде:

```scala
// TelemetryConsumer.scala
private def writeBatchWithRetry(batch: TelemetryBatch): Task[Unit] =
  repository.insertBatch(batch)
    .retry(Schedule.recurs(batchConfig.maxRetries) && 
           Schedule.spaced(batchConfig.retryDelayMs.millis))
    .tapError(e => ZIO.logError(s"Не удалось записать после ${batchConfig.maxRetries} попыток"))
```

---

## 4.6 Сериализация сообщений

```scala
// KafkaProducer.scala — generic сериализация
private def serializeAndPublish[A: JsonEncoder](
  value: A,
  topic: String,
  key: String
): IO[KafkaError, Unit] =
  ZIO.attempt(value.toJson)                                    // A → JSON String
    .mapError(e => KafkaError.SerializationError(e.getMessage)) // Ошибка сериализации
    .flatMap(json => publish(topic, key, json))                 // Отправляем
```

### `[A: JsonEncoder]` — context bound:

Означает: "тип A должен иметь `JsonEncoder`". Благодаря `derives JsonCodec` в case classes, это работает автоматически.

---

## 4.7 Топология Kafka в проекте

```
Connection Manager (Producer)
  ├→ gps-events         key=deviceId     → History Writer (Consumer)
  ├→ device-status      key=imei         → Device Manager, WebSocket
  └→ unknown-devices    key=imei         → Device Manager

Device Manager (Producer)
  ├→ device-events      key=deviceId     → Connection Manager, Analytics
  └→ command-audit      key=deviceId     → Audit log

Connection Manager (Consumer) ← будет слушать gps-events-retranslation
```

---

## 📝 Упражнение

1. В `KafkaProducer.scala` — почему `key = point.vehicleId.toString`? Что если использовать random ключ?
2. В `TelemetryConsumer.scala` — что делает `.option` после `fromJson`? Зачем не падать?
3. Нарисуй поток данных: GPS трекер → Connection Manager → Kafka → History Writer → TimescaleDB
4. Что произойдёт если TimescaleDB недоступен? (Подсказка: `.retry`)
5. Объясни разницу между `publish` (одно сообщение) и `consumeStream` (поток)

---

**→ Следующий: [05-REDIS.md](05-REDIS.md) — Redis паттерны**
