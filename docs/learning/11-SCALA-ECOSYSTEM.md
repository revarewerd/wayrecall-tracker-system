# Модуль 11: Экосистема Scala — библиотеки профессионала

> Что ещё знать кроме ZIO? FS2, Tapir, Circe, http4s, gRPC, и карта роста.

---

## 11.1 Карта экосистемы Scala

```
                        ┌──────────────────────┐
                        │   Scala 3 Language    │
                        └──────────┬───────────┘
                                   │
              ┌────────────────────┼────────────────────┐
              │                    │                    │
     ┌────────▼─────────┐ ┌───────▼────────┐  ┌───────▼────────┐
     │  Typelevel стек   │ │   ZIO стек     │  │  Akka стек     │
     │  (Cats core)      │ │   (ZIO core)   │  │  (устаревает)  │
     ├───────────────────┤ ├────────────────┤  ├────────────────┤
     │ cats-effect       │ │ zio            │  │ akka-actors    │
     │ fs2 (streams)     │ │ zio-streams    │  │ akka-streams   │
     │ http4s (HTTP)     │ │ zio-http       │  │ akka-http      │
     │ doobie (SQL)      │ │ zio-json       │  │ slick (SQL)    │
     │ circe (JSON)      │ │ zio-kafka      │  │ play-json      │
     │ tapir (API docs)  │ │ zio-redis      │  │ play framework │
     └───────────────────┘ └────────────────┘  └────────────────┘
            ↑                     ↑
            │   zio-interop-cats  │
            └─────────────────────┘
                  Мы тут!
```

---

## 11.2 FS2 — Functional Streams for Scala

**FS2** = аналог ZIO Streams, но из мира Typelevel.

```scala
// FS2 поток
import fs2.Stream
import cats.effect.IO

val numbers: Stream[IO, Int] = Stream(1, 2, 3)
  .evalMap(n => IO(n * 2))
  .filter(_ > 2)

// ZIO Stream (наш проект)
val numbers: ZStream[Any, Nothing, Int] = ZStream(1, 2, 3)
  .mapZIO(n => ZIO.succeed(n * 2))
  .filter(_ > 2)
```

### Когда нужно знать FS2:

- Многие Typelevel библиотеки возвращают `fs2.Stream`
- Kafka consumers (fs2-kafka — альтернатива zio-kafka)
- Если работаешь в компании с Typelevel стеком

### Для нашего проекта:

Мы используем `zio-streams` — FS2 не нужен. Но **понимать его стоит** — на собеседованиях спрашивают.

---

## 11.3 Tapir — описание API

**Tapir** — библиотека для описания HTTP эндпоинтов, которая генерирует:
- HTTP сервер (http4s, zio-http, Akka HTTP)
- OpenAPI/Swagger документацию
- HTTP клиент

```scala
import sttp.tapir.*
import sttp.tapir.json.zio.*
import sttp.tapir.ztapir.*

// Описание эндпоинта
val getDevice: Endpoint[Unit, DeviceId, DomainError, Device, Any] =
  endpoint
    .get
    .in("api" / "v1" / "devices" / path[DeviceId]("id"))
    .out(jsonBody[Device])
    .errorOut(jsonBody[DomainError])

// Из описания автоматически:
// 1. Генерируется HTTP handler
// 2. Генерируется Swagger UI
// 3. Генерируется TypeScript клиент
```

### Для нашего проекта:

Сейчас мы пишем роуты руками в zio-http. Tapir можно добавить позже для автогенерации Swagger. **Полезно изучить для будущих проектов.**

---

## 11.4 http4s vs zio-http

### http4s (Typelevel):

```scala
val routes = HttpRoutes.of[IO] {
  case GET -> Root / "devices" / LongVar(id) =>
    deviceService.getDevice(id).flatMap(Ok(_))
}
```

### zio-http (наш выбор):

```scala
val routes = Routes(
  Method.GET / "api" / "v1" / "devices" / long("id") ->
    handler { (id: Long, req: Request) =>
      DeviceService.getDevice(DeviceId(id)).map(d => Response.json(d.toJson))
    }
)
```

**Почему zio-http:** нативная интеграция с ZIO, без interop-прослойки.

---

## 11.5 gRPC — для межсервисного общения

Сейчас наши сервисы общаются через **Kafka + Redis**. Но для синхронных вызовов gRPC лучше REST:

```protobuf
// device.proto
service DeviceService {
  rpc GetDevice (GetDeviceRequest) returns (Device);
  rpc ListDevices (ListDevicesRequest) returns (stream Device);
}
```

Библиотеки для Scala:
- **scalapb** — генерация Scala case classes из .proto
- **zio-grpc** — gRPC сервер/клиент на ZIO
- **fs2-grpc** — gRPC на Typelevel

### Когда пригодится:

Если добавим синхронные вызовы между сервисами (например, API Gateway → Device Manager вместо REST).

---

## 11.6 Quill — compile-time SQL

```scala
import io.getquill.*

val ctx = new PostgresZioJdbcContext(SnakeCase, "db")

// SQL генерируется НА ЭТАПЕ КОМПИЛЯЦИИ
val devices = ctx.run(
  query[Device].filter(_.organizationId == lift(orgId))
)
// Компилятор проверяет типы и генерирует:
// SELECT id, imei, ... FROM devices WHERE organization_id = ?
```

**Плюсы:** ошибка SQL = ошибка компиляции.
**Минусы:** сложный для изучения, не всегда предсказуемый SQL.

---

## 11.7 Chimney — трансформация case classes

```scala
import io.scalaland.chimney.dsl.*

// Автоматическое преобразование DTO → Entity
val device: Device = createRequest
  .into[Device]
  .withFieldConst(_.id, DeviceId(0))
  .withFieldConst(_.status, DeviceStatus.Active)
  .withFieldConst(_.createdAt, Instant.now)
  .transform
```

Убирает бойлерплейт при маппинге между слоями (API DTO ↔ Domain ↔ DB).

---

## 11.8 Что изучать и в каком порядке

### Tier 1 — Знаешь (наш проект):
- ✅ ZIO Core, Layers, Streams
- ✅ zio-http
- ✅ zio-json
- ✅ Doobie
- ✅ Netty

### Tier 2 — Выучи следующим:
- 📌 **Tapir** — API документация (добавим в проект)
- 📌 **zio-test** глубже — property-based testing, generators
- 📌 **Flyway** — миграции БД (нужно для проекта)
- 📌 **zio-config** глубже — HOCON, env variables

### Tier 3 — Для собеседований и кругозора:
- 📖 **Cats** — Functor, Monad, Applicative (теория)
- 📖 **Cats Effect IO** — понимать разницу с ZIO
- 📖 **FS2** — хотя бы базовый уровень
- 📖 **http4s** — основной HTTP сервер Typelevel мира
- 📖 **Circe** — JSON из мира Typelevel

### Tier 4 — Продвинутый уровень:
- 🔬 **gRPC (scalapb + zio-grpc)** — межсервисная коммуникация
- 🔬 **Quill** — compile-time SQL
- 🔬 **Chimney** — трансформация моделей
- 🔬 **Refined** — типы с ограничениями (`String Refined NonEmpty`)
- 🔬 **Monocle** — линзы для вложенных case classes

---

## 11.9 Сравнительная таблица стеков

| Задача | Typelevel | ZIO | Akka | Наш проект |
|--------|-----------|-----|------|-----------|
| Runtime | cats-effect | zio | akka-actor | **zio** |
| HTTP | http4s | zio-http | akka-http | **zio-http** |
| JSON | circe | zio-json | play-json | **zio-json** |
| SQL | doobie | zio-sql | slick | **doobie** |
| Streams | fs2 | zio-streams | akka-streams | **zio-streams** |
| Kafka | fs2-kafka | zio-kafka | alpakka | **zio-kafka + java** |
| Config | ciris | zio-config | typesafe-config | **zio-config** |
| Tests | munit + weaver | zio-test | scalatest | **zio-test** |
| API docs | tapir | tapir | — | **будет tapir** |

---

## 📝 Упражнение

1. Зайди на https://zio.dev — найди документацию по ZLayer
2. Зайди на https://typelevel.org — посмотри какие библиотеки входят
3. Почему Akka-стек «устаревает»? (Подсказка: смена лицензии → Pekko)
4. Если бы мы начинали с Typelevel — что заменили бы? (zio→cats-effect, zio-http→http4s, ...)
5. Какую библиотеку из Tier 2 ты бы хотел изучить первой?

---

**→ Вернуться к [README.md](README.md)**
