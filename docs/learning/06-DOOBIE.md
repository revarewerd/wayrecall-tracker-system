# Модуль 6: PostgreSQL + Doobie — типобезопасный SQL

> 📁 Файл: `services/device-manager/.../repository/DeviceRepository.scala`

---

## 6.1 Что такое Doobie?

Doobie — это **типобезопасная** обёртка над JDBC для функционального Scala.

```
SQL запрос → ConnectionIO[A] → Transactor → Task[A]
  Строка       Описание SQL      Выполнение    Результат ZIO
```

Ключевая идея: SQL запрос — это **значение** (ConnectionIO), а не побочный эффект.

---

## 6.2 Импорты

```scala
import doobie.*
import doobie.implicits.*
import doobie.postgres.implicits.*  // PostgreSQL-специфичные типы
```

---

## 6.3 SQL запросы — sql интерполятор

### SELECT (query):

```scala
// DeviceRepository.scala — Queries object
def selectDeviceById(id: DeviceId): ConnectionIO[Option[Device]] =
  sql"""
    SELECT id, imei, name, protocol, status, organization_id, vehicle_id,
           sensor_profile_id, phone_number, firmware_version, 
           last_seen_at, created_at, updated_at
    FROM devices
    WHERE id = $id AND status != ${DeviceStatus.Deleted}
  """.query[Device].option
```

### Что тут происходит:

1. `sql"..."` — интерполятор, `$id` подставляется как **параметр** (защита от SQL injection!)
2. `.query[Device]` — Doobie автоматически маппит столбцы в case class `Device`
3. `.option` — возвращает `Option[Device]` (None если не найдено)

### INSERT (update + returning):

```scala
def insertDevice(r: CreateDeviceRequest, now: Instant): ConnectionIO[DeviceId] =
  sql"""
    INSERT INTO devices (
      imei, name, protocol, status, organization_id, vehicle_id, 
      sensor_profile_id, phone_number, created_at, updated_at
    ) VALUES (
      ${r.imei}, ${r.name}, ${r.protocol}, ${DeviceStatus.Active}, 
      ${r.organizationId}, ${r.vehicleId}, ${r.sensorProfileId}, 
      ${r.phoneNumber}, $now, $now
    )
    RETURNING id
  """.query[DeviceId].unique  // unique = ожидаем ровно 1 строку
```

### UPDATE (run):

```scala
def softDeleteDevice(id: DeviceId, now: Instant): ConnectionIO[Int] =
  sql"""
    UPDATE devices SET
      status = ${DeviceStatus.Deleted},
      updated_at = $now
    WHERE id = $id AND status != ${DeviceStatus.Deleted}
  """.update.run  // Int = количество затронутых строк
```

### Список (to[List]):

```scala
def selectDevicesByOrganization(orgId: OrganizationId): ConnectionIO[List[Device]] =
  sql"""
    SELECT *
    FROM devices
    WHERE organization_id = $orgId AND status != ${DeviceStatus.Deleted}
    ORDER BY created_at DESC
  """.query[Device].to[List]
```

### Boolean check:

```scala
def checkImeiExists(imei: Imei): ConnectionIO[Boolean] =
  sql"SELECT EXISTS(SELECT 1 FROM devices WHERE imei = ${imei.value})"
    .query[Boolean].unique
```

---

## 6.4 Meta — маппинг типов

Doobie не знает про наши opaque types и enums. Нужно объяснить:

```scala
private object Queries:
  // Enum → String
  given Meta[Protocol] = Meta[String].timap(Protocol.valueOf)(_.toString)
  given Meta[DeviceStatus] = Meta[String].timap(DeviceStatus.valueOf)(_.toString)
  
  // Opaque type → базовый тип
  given Meta[DeviceId] = Meta[Long].timap(DeviceId.apply)(_.value)
  given Meta[VehicleId] = Meta[Long].timap(VehicleId.apply)(_.value)
  given Meta[OrganizationId] = Meta[Long].timap(OrganizationId.apply)(_.value)
  given Meta[Imei] = Meta[String].timap(Imei.unsafe)(_.value)
```

### `timap` — двустороннее преобразование:

```scala
Meta[Long].timap(DeviceId.apply)(_.value)
//               ↑                ↑
//         Long → DeviceId   DeviceId → Long
//         (чтение из БД)    (запись в БД)
```

---

## 6.5 Transactor — выполнение запросов

`Transactor[Task]` — пул соединений к PostgreSQL. Всё проходит через него.

### Выполнение ConnectionIO через ZIO:

```scala
// DeviceRepository.Live
private def runQuery[A](query: ConnectionIO[A]): IO[DomainError, A] =
  ZIO.fromFuture(_ => 
    import cats.effect.unsafe.implicits.global
    query.transact(xa).unsafeToFuture()
  ).mapError(e => InfrastructureError.DatabaseError(e.getMessage))
```

### Что тут:

1. `query.transact(xa)` — выполняет SQL через пул соединений (одна транзакция)
2. `.unsafeToFuture()` — cats-effect IO → Future
3. `ZIO.fromFuture` — Future → ZIO Task
4. `.mapError` — Throwable → DomainError

### Использование в бизнес-логике:

```scala
override def create(request: CreateDeviceRequest): IO[DomainError, DeviceId] =
  for
    exists <- runQuery(checkImeiExists(request.imei))  // SQL → ZIO
    _ <- ZIO.when(exists)(ZIO.fail(ImeiAlreadyExists(...)))
    
    now <- Clock.instant
    id <- runQuery(insertDevice(request, now))  // SQL → ZIO
  yield id
```

---

## 6.6 ZLayer для Repository:

```scala
object DeviceRepository:
  val live: ZLayer[Transactor[Task], Nothing, DeviceRepository] =
    ZLayer.fromFunction(Live.apply)
```

Простой слой: получает `Transactor`, создаёт `Live`.

---

## 6.7 Multi-tenant изоляция

**КАЖДЫЙ запрос** фильтрует по `organization_id`:

```scala
// ✅ ПРАВИЛЬНО: всегда фильтруем по организации
def selectDevicesByOrganization(orgId: OrganizationId) =
  sql"... WHERE organization_id = $orgId ..."

// ❌ ЗАПРЕЩЕНО: запрос без фильтра = утечка данных!
def selectAllDevices() =
  sql"SELECT * FROM devices"  // Видит ВСЕ устройства ВСЕХ организаций!
```

---

## 📝 Упражнение

1. Открой `DeviceRepository.scala` — найди все SQL запросы
2. Сколько разных типов `ConnectionIO[X]` используется? (option, unique, to[List], run)
3. Почему `checkImeiExists` использует `unique`, а не `option`?
4. Найди все `given Meta[...]` — зачем для `Imei` используется `Imei.unsafe`, а не `Imei.apply`?
5. Что вернёт `softDeleteDevice` если устройство уже удалено?

---

**→ Следующий: [07-NETTY.md](07-NETTY.md) — Netty TCP сервер**
