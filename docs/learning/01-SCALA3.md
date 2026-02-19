# Модуль 1: Scala 3 — основы на примерах проекта

> 📁 Основной файл: `services/device-manager/.../domain/Entities.scala`

---

## 1.1 Case Classes — неизменяемые данные

В Wayrecall **все данные** — это `case class`. Никаких `var`, никаких мутаций.

```scala
// services/device-manager/.../domain/Entities.scala
final case class Device(
    id: DeviceId,
    imei: Imei,
    name: Option[String],
    protocol: Protocol,
    status: DeviceStatus,
    organizationId: OrganizationId,
    vehicleId: Option[VehicleId],
    createdAt: Instant,
    updatedAt: Instant
) derives JsonCodec
```

### Что тут важно понять:

| Элемент | Что делает | Зачем |
|---------|-----------|-------|
| `final` | Запрет наследования | Безопасность ADT |
| `case class` | Автоматические `equals`, `hashCode`, `copy`, `toString` | Иммутабельность |
| `derives JsonCodec` | Scala 3 derivation — автогенерация JSON сериализации | Нет бойлерплейта |
| `Option[String]` | Может быть `Some("Truck-01")` или `None` | Нет `null` |

### Как создать и изменить (copy):

```scala
val device = Device(id = DeviceId(1), imei = Imei.unsafe("860719020025346"), ...)

// Так нельзя — иммутабельность:
// device.name = "New Name"  // ❌ НЕ КОМПИЛИРУЕТСЯ

// Правильно — создаём НОВЫЙ объект:
val updated = device.copy(name = Some("Truck-02"))
// device остался прежним, updated — новый
```

### Pattern matching:

```scala
device.status match
  case DeviceStatus.Active    => println("Онлайн")
  case DeviceStatus.Inactive  => println("Офлайн")
  case DeviceStatus.Suspended => println("Заблокирован")
  case DeviceStatus.Deleted   => println("Удалён")
  // Компилятор проверяет что все варианты покрыты!
```

---

## 1.2 Enums — перечисления Scala 3

```scala
// services/device-manager/.../domain/Entities.scala
enum Protocol derives JsonCodec:
  case Teltonika   // Порт 5001
  case Wialon      // Порт 5002
  case Ruptela     // Порт 5003
  case NavTelecom  // Порт 5004
  case Galileo     // Порт 5005
  case Custom

enum DeviceStatus derives JsonCodec:
  case Active, Inactive, Suspended, Deleted
```

### Ключевые концепции:

- **`derives JsonCodec`** — Scala 3 автоматически генерирует парсер/сериализатор
- **Exhaustive matching** — компилятор заставляет обработать ВСЕ варианты
- **Нет `null`** — вместо `null` используем `Option` и `enum`

### Сравни с Java:

```java
// Java — многословно
public enum Protocol {
    TELTONIKA, WIALON, RUPTELA, NAVTELECOM, GALILEO, CUSTOM;
    
    // Нужно руками писать JSON сериализацию...
}
```

```scala
// Scala 3 — одна строка + автогенерация JSON
enum Protocol derives JsonCodec:
  case Teltonika, Wialon, Ruptela, NavTelecom, Galileo, Custom
```

---

## 1.3 Opaque Types — типобезопасность без оверхеда

Это **самая важная** фича Scala 3 для нашего проекта.

```scala
// services/device-manager/.../domain/Entities.scala

/** ID устройства — в runtime это просто Long */
opaque type DeviceId = Long
object DeviceId:
  def apply(value: Long): DeviceId = value
  extension (id: DeviceId) def value: Long = id
  given JsonCodec[DeviceId] = JsonCodec.long.transform(DeviceId.apply, _.value)

/** IMEI — в runtime это просто String, но с валидацией */
opaque type Imei = String
object Imei:
  def apply(value: String): Either[String, Imei] =
    if value.matches("^\\d{15}$") then Right(value)
    else Left(s"IMEI должен быть 15-значным числом: $value")
  
  def unsafe(value: String): Imei = value
  extension (imei: Imei) def value: String = imei
```

### Зачем это нужно?

```scala
// БЕЗ opaque types — легко перепутать:
def assignDevice(deviceId: Long, vehicleId: Long, orgId: Long): Unit
assignDevice(42, 1, 100)    // Что есть что? Легко перепутать!
assignDevice(100, 42, 1)    // Компилятор не поймает ошибку!

// С opaque types — невозможно перепутать:
def assignDevice(deviceId: DeviceId, vehicleId: VehicleId, orgId: OrganizationId): Unit
assignDevice(DeviceId(42), VehicleId(1), OrganizationId(100))  // ✅ Ясно
assignDevice(OrganizationId(100), DeviceId(42), VehicleId(1))  // ❌ НЕ КОМПИЛИРУЕТСЯ!
```

### Zero-cost abstraction:

```
Compile time:  DeviceId ≠ VehicleId ≠ Long  (типобезопасно)
Runtime:       DeviceId = VehicleId = Long   (никакого оверхеда)
```

### Паттерн валидации (Imei):

```scala
// Безопасное создание — возвращает Either
val result: Either[String, Imei] = Imei("860719020025346")
// Right("860719020025346") ✅

val bad: Either[String, Imei] = Imei("123")  
// Left("IMEI должен быть 15-значным числом: 123") ❌

// Небезопасное создание — для тестов и внутреннего кода
val imei: Imei = Imei.unsafe("860719020025346")
```

---

## 1.4 Extension Methods — расширение типов

```scala
// services/connection-manager/.../domain/GpsPoint.scala

extension (p1: GpsPoint)
  def distance(p2: GpsPoint): Double = p1.distanceTo(p2)
```

### Что это значит?

Мы **добавляем метод** к существующему типу без наследования:

```scala
val point1 = GpsPoint(vehicleId = 1, latitude = 54.68, longitude = 25.27, ...)
val point2 = GpsPoint(vehicleId = 1, latitude = 54.69, longitude = 25.28, ...)

// Вызываем как обычный метод:
val meters = point1.distance(point2)  // ~1400 метров
```

### Given instances — автодериваторы

```scala
// В companion object DeviceId:
given JsonCodec[DeviceId] = JsonCodec.long.transform(DeviceId.apply, _.value)
```

Это аналог `implicit` из Scala 2, но яснее:
- `given` — «я предоставляю экземпляр JsonCodec для DeviceId»
- Компилятор **автоматически** найдёт его когда нужно сериализовать `DeviceId`

---

## 1.5 Sealed Traits — ADT (алгебраические типы данных)

```scala
// services/device-manager/.../domain/Errors.scala

sealed trait DomainError extends Throwable:
  def message: String
  def code: String

sealed trait ValidationError extends DomainError:
  val code = "VALIDATION_ERROR"

object ValidationError:
  final case class InvalidImei(imei: String) extends ValidationError:
    val message = s"Невалидный IMEI: '$imei'"
  
  final case class EmptyField(fieldName: String) extends ValidationError:
    val message = s"Поле '$fieldName' не может быть пустым"

sealed trait NotFoundError extends DomainError:
  val code = "NOT_FOUND"

object NotFoundError:
  final case class DeviceNotFound(id: DeviceId) extends NotFoundError:
    val message = s"Устройство с ID ${id.value} не найдено"
```

### Иерархия ошибок:

```
DomainError (sealed)
├── ValidationError (sealed)
│   ├── InvalidImei
│   ├── EmptyField
│   └── LimitExceeded
├── NotFoundError (sealed)
│   ├── DeviceNotFound
│   └── VehicleNotFound
├── ConflictError (sealed)
│   └── ImeiAlreadyExists
└── InfrastructureError (sealed)
    └── DatabaseError
```

### Exhaustive matching:

```scala
def handleError(error: DomainError): Response = error match
  case e: ValidationError => Response.badRequest(e.message)
  case e: NotFoundError   => Response.notFound(e.message)
  case e: ConflictError   => Response.conflict(e.message)
  case e: InfrastructureError => Response.serverError(e.message)
  // Компилятор гарантирует: если добавишь новый тип — заставит обработать!
```

---

## 1.6 Значащий отступ (Indentation syntax)

Scala 3 поддерживает Python-like синтаксис без фигурных скобок:

```scala
// Scala 2 стиль (с фигурными скобками):
object Main extends ZIOAppDefault {
  def run = {
    for {
      config <- ZIO.service[AppConfig]
      _ <- ZIO.logInfo("Starting...")
    } yield ()
  }
}

// Scala 3 стиль (наш проект):
object Main extends ZIOAppDefault:
  def run =
    for
      config <- ZIO.service[AppConfig]
      _ <- ZIO.logInfo("Starting...")
    yield ()
```

Правила:
- `:` вместо `{`
- Отступ определяет блок
- `for`/`yield` без скобок

---

## 📝 Упражнение

1. Открой `services/device-manager/.../domain/Entities.scala`
2. Найди все `opaque type` — сколько их?
3. Для каждого: какой базовый тип (Long, String)?
4. Найди `enum` — какие значения у `VehicleType`?
5. Создай мысленно `DeviceId(5)` и попробуй присвоить его в `VehicleId` — почему не скомпилируется?

---

**→ Следующий модуль: [02-ZIO-CORE.md](02-ZIO-CORE.md) — ZIO эффекты**
