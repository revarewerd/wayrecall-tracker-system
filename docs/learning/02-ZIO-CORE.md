# Модуль 2: ZIO Core — функциональные эффекты

> 📁 Файлы: `DeviceService.scala`, `DeadReckoningFilter.scala`, `ConnectionHandler.scala`

---

## 2.1 Что такое ZIO[R, E, A]?

ZIO — это **описание вычисления**, которое:
- **R** (environment) — что нужно для выполнения (зависимости)
- **E** (error) — какая ошибка может произойти
- **A** (success) — что возвращает при успехе

```
ZIO[R, E, A]  =  "Программа, которой нужно R, может упасть с E, вернёт A"
```

### Аналогия:

```
ZIO[RedisClient, RedisError, Option[Long]]
     ↑              ↑              ↑
     Мне нужен      Может упасть   Вернёт Option[Long]
     Redis клиент   с RedisError   если всё ок
```

### Алиасы типов (сокращения):

```scala
type Task[A]     = ZIO[Any, Throwable, A]  // Не нужно окружение, может бросить любую ошибку
type UIO[A]      = ZIO[Any, Nothing, A]     // Не может упасть (infallible)
type IO[E, A]    = ZIO[Any, E, A]           // Не нужно окружение, конкретная ошибка
type URIO[R, A]  = ZIO[R, Nothing, A]       // Нужно окружение, не может упасть
type RIO[R, A]   = ZIO[R, Throwable, A]     // Нужно окружение, любая ошибка
```

### В нашем коде:

```scala
// DeviceRepository.scala — конкретная типизация ошибок
def findById(id: DeviceId): IO[DomainError, Option[Device]]
//                           ↑               ↑
//                           Может упасть    Вернёт Option
//                           с DomainError

// ConnectionRegistry.scala — не может упасть
def connectionCount: UIO[Int]
//                   ↑
//                   Всегда успешно (работает с Ref в памяти)

// RedisClient.scala — нужно окружение
def getVehicleId(imei: String): ZIO[RedisClient, RedisError, Option[Long]]
//                               ↑               ↑            ↑
//                               Зависимость     Ошибка       Результат
```

---

## 2.2 Создание ZIO эффектов

### Чистые значения:

```scala
ZIO.succeed(42)              // UIO[Int] — всегда возвращает 42
ZIO.fail(DeviceNotFound(1))  // IO[NotFoundError, Nothing] — всегда ошибка
ZIO.unit                     // UIO[Unit] — ничего не делает
ZIO.none                     // UIO[Option[Nothing]] — всегда None
```

### Оборачивание побочных эффектов:

```scala
// Небезопасный код → ZIO
ZIO.attempt(producer.send(record))  // Task[RecordMetadata]
//  ↑ оборачивает любое исключение в Throwable

// Из Future → ZIO
ZIO.fromFuture(_ => completionStage.asScala)  // Task[A]

// Из Option → ZIO
ZIO.fromOption(maybeVehicleId)
  .orElseFail(ProtocolError.UnknownDevice(imei))
// Если None → ошибка UnknownDevice

// Из Either → ZIO
ZIO.fromEither(Imei("860719020025346"))
  .mapError(e => InvalidImei("bad"))
// Left → ошибка, Right → успех
```

### Наш реальный пример (RedisClient.scala):

```scala
// Конвертация Java CompletionStage в ZIO
private def fromCompletionStage[A](cs: => CompletionStage[A]): Task[A] =
  ZIO.fromFuture(_ => cs.asScala)

// Использование:
override def getVehicleId(imei: String): IO[RedisError, Option[Long]] =
  fromCompletionStage(commands.get(vehicleKey(imei)))  // Task[String]
    .map(Option(_).flatMap(_.toLongOption))              // Task[Option[Long]]
    .mapError(e => RedisError.OperationFailed(e.getMessage))  // IO[RedisError, ...]
```

---

## 2.3 For-comprehension — цепочка эффектов

Это **главный паттерн** в нашем проекте. Каждый `<-` — это шаг программы.

```scala
// DeviceService.scala — создание устройства
override def createDevice(request: CreateDeviceCommand): IO[DomainError, Device] =
  for
    // 1. Валидация IMEI (может вернуть ValidationError)
    imei <- ZIO.fromEither(Imei(request.imei))
               .mapError(e => InvalidImei(request.imei))
    
    // 2. Проверка уникальности (может вернуть ConflictError)
    exists <- deviceRepo.existsByImei(imei)
    _ <- ZIO.when(exists)(
      ZIO.fail(ImeiAlreadyExists(request.imei))
    )
    
    // 3. Создание в БД (может вернуть DatabaseError)
    deviceId <- deviceRepo.create(createReq)
    
    // 4. Получаем созданное
    device <- deviceRepo.findById(deviceId).flatMap {
      case Some(d) => ZIO.succeed(d)
      case None => ZIO.fail(DeviceNotFound(deviceId))
    }
    
    // 5. Публикуем в Kafka (ошибки логируем, но не падаем)
    _ <- eventPublisher.publish(event).catchAll(e =>
           ZIO.logError(s"Ошибка публикации: ${e.getMessage}")
         )
    
    // 6. Синхронизация с Redis (аналогично)
    _ <- redisSync.syncDevice(device).catchAll(e =>
           ZIO.logError(s"Ошибка Redis: ${e.getMessage}")
         )
  yield device
```

### Что тут происходит?

Каждая строка `<-` — это:
1. Выполнить эффект
2. Если ошибка — **остановить всю цепочку** и вернуть ошибку
3. Если успех — передать результат дальше

```
Шаг 1 (OK) → Шаг 2 (OK) → Шаг 3 (FAIL!) → Шаги 4,5,6 НЕ ВЫПОЛНЯЮТСЯ
                                    ↓
                              Возвращается ошибка
```

---

## 2.4 Обработка ошибок

### mapError — трансформация типа ошибки:

```scala
// RedisClient: Throwable → RedisError
fromCompletionStage(commands.get(key))
  .mapError(e => RedisError.OperationFailed(e.getMessage))
```

### catchAll — перехват всех ошибок:

```scala
// DeviceService: не падаем если Kafka недоступен
eventPublisher.publish(event).catchAll(e =>
  ZIO.logError(s"Kafka error: ${e.getMessage}")
)
```

### orElseFail — замена None на ошибку:

```scala
// ConnectionHandler: IMEI не найден в Redis → ошибка
ZIO.fromOption(maybeVehicleId)
  .orElseFail(ProtocolError.UnknownDevice(imei))
```

### someOrFail — Option → значение или ошибка:

```scala
// Вместо flatMap + match:
deviceRepo.findById(id).someOrFail(DeviceNotFound(id))
// Эквивалент:
deviceRepo.findById(id).flatMap {
  case Some(d) => ZIO.succeed(d)
  case None    => ZIO.fail(DeviceNotFound(id))
}
```

### .either — превращает ошибку в значение:

```scala
val result: UIO[Either[DomainError, Device]] =
  deviceService.getDevice(id).either
// Теперь ошибка — это обычное значение, не может упасть
```

---

## 2.5 Комбинаторы

### ZIO.when — условное выполнение:

```scala
// DeviceRepository: проверка уникальности
_ <- ZIO.when(exists)(
  ZIO.fail(ImeiAlreadyExists(request.imei))
)
// Если exists=true → fail, если false → ничего не делает
```

### ZIO.foreach — для каждого элемента:

```scala
// Валидация каждой точки в пакете
_ <- ZIO.foreach(prev)(validateNoTeleportation(point, _, config))
```

### ZIO.foldLeft — аккумулятор:

```scala
// ConnectionHandler: обработка точек с аккумулятором
result <- ZIO.foldLeft(rawPoints)((List.empty[GpsPoint], prevPosition)) {
  case ((processed, prev), raw) =>
    processPoint(raw, vehicleId, prev).map { point =>
      (processed :+ point, Some(point))
    }.catchAll { error =>
      ZIO.logDebug(s"Точка отфильтрована: ${error.getMessage}") *>
      ZIO.succeed((processed, prev))
    }
}
```

### `*>` и `<*` — выполни оба, верни один:

```scala
ZIO.logInfo("Начинаю") *> doWork()
// Выполнит logInfo, потом doWork, вернёт результат doWork

doWork() <* ZIO.logInfo("Готово")
// Выполнит doWork, потом logInfo, вернёт результат doWork
```

---

## 2.6 Ref — потокобезопасное состояние

Вместо `var` и `AtomicInteger` мы используем `Ref`:

```scala
// ConnectionRegistry.scala
final case class Live(
    connectionsRef: Ref[Map[String, ConnectionEntry]]
) extends ConnectionRegistry:
  
  override def register(imei: String, ctx: ChannelHandlerContext, ...): UIO[Unit] =
    for
      now <- Clock.currentTime(java.util.concurrent.TimeUnit.MILLISECONDS)
      entry = ConnectionEntry(imei, ctx, parser, now, now)
      
      // Атомарная модификация + получение старого значения
      oldEntry <- connectionsRef.modify { map =>
        val old = map.get(imei)
        (old, map + (imei -> entry))  // (возвращаем, новое состояние)
      }
      
      // Обработка reconnect
      _ <- ZIO.foreach(oldEntry) { old =>
        ZIO.attempt(old.ctx.close()).ignore
      }
    yield ()
```

### Ключевые операции Ref:

```scala
val ref: UIO[Ref[Int]] = Ref.make(0)

ref.get                    // UIO[Int] — прочитать
ref.set(42)                // UIO[Unit] — записать
ref.update(_ + 1)          // UIO[Unit] — атомарно изменить
ref.modify(n => (n, n+1))  // UIO[Int] — прочитать старое + записать новое
```

---

## 📝 Упражнение

1. Открой `DeviceService.scala`, метод `createDevice`
2. Проследи цепочку `for`: какой шаг может упасть с какой ошибкой?
3. Найди все `.catchAll` — почему ошибки Kafka и Redis не останавливают создание?
4. Открой `ConnectionRegistry.scala` — почему `register` возвращает `UIO[Unit]`?
5. Что вернёт `ZIO.fromOption(None).orElseFail("oops")`?

---

**→ Следующий: [03-ZIO-LAYERS.md](03-ZIO-LAYERS.md) — ZIO Layers и Dependency Injection**
