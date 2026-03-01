# Модуль 10: Cats, Cats Effect и выбор библиотек

> Почему Doobie, а не Slick? Что такое Cats? Как связаны ZIO и Cats Effect?

---

## 10.1 Два мира функционального Scala

В Scala два конкурирующих runtime для эффектов:

```
            ┌─────────────────┐     ┌─────────────────┐
            │   Typelevel      │     │   ZIO            │
            │   (Cats Effect)  │     │   (ZIO Effect)   │
            ├─────────────────┤     ├─────────────────┤
            │ IO[A]            │     │ ZIO[R, E, A]     │
            │ Resource[IO, A]  │     │ ZLayer[R, E, A]  │
            │ fs2.Stream       │     │ ZStream          │
            │ http4s           │     │ zio-http         │
            │ doobie           │     │ zio-sql (слабый) │
            │ circe            │     │ zio-json         │
            │ tapir            │     │ tapir (оба мира) │
            └─────────────────┘     └─────────────────┘
```

**Мы выбрали ZIO**, но используем **Doobie из мира Cats** — это нормально!

---

## 10.2 Cats — библиотека типклассов

**Cats** — это фундамент функционального Scala. Определяет абстракции:

```scala
// Functor — можно делать .map
trait Functor[F[_]]:
  def map[A, B](fa: F[A])(f: A => B): F[B]

// Monad — можно делать .flatMap (for-comprehension)
trait Monad[F[_]] extends Functor[F]:
  def flatMap[A, B](fa: F[A])(f: A => F[B]): F[B]
  def pure[A](a: A): F[A]
```

### Где мы это видим?

```scala
// В for-comprehension каждый `<-` — это flatMap
for
  config <- ZIO.service[AppConfig]     // flatMap
  server <- ZIO.service[TcpServer]     // flatMap
yield ()                                // map
```

ZIO, Option, List, Future — все они Monad!

---

## 10.3 Cats Effect — IO runtime

```scala
// Cats Effect
import cats.effect.IO

val program: IO[Unit] = for
  _ <- IO.println("Hello")
  x <- IO(42)
yield ()

program.unsafeRunSync()
```

### Сравнение с ZIO:

| Cats Effect IO | ZIO | Комментарий |
|----------------|-----|-------------|
| `IO[A]` | `Task[A]` = `ZIO[Any, Throwable, A]` | ZIO типизирует ошибки |
| `IO.pure(42)` | `ZIO.succeed(42)` | Чистое значение |
| `IO(sideEffect)` | `ZIO.attempt(sideEffect)` | Побочный эффект |
| `IO.raiseError(e)` | `ZIO.fail(e)` | Ошибка |
| `Resource[IO, A]` | `ZLayer.scoped` | Управление ресурсами |
| Не типизирует ошибки | `ZIO[R, E, A]` — E конкретный | **Главное отличие** |
| Не типизирует зависимости | `ZIO[R, E, A]` — R конкретный | **Второе отличие** |

### Почему мы выбрали ZIO:

1. **Типизированные ошибки** — `IO[DomainError, Device]` а не `IO[Device]`
2. **Типизированные зависимости** — `ZIO[RedisClient, ...]` а не передача через конструктор
3. **Встроенные Layers** — DI "из коробки"
4. **ZIO Test** — TestClock, Ref, всё встроено
5. **Лучшая документация** — zio.dev

---

## 10.4 Почему Doobie, а не Slick / Skunk / zio-sql?

### Slick — ORM для Scala

```scala
// Slick — таблица как класс
class Devices(tag: Tag) extends Table[Device](tag, "devices"):
  def id = column[Long]("id", O.PrimaryKey, O.AutoInc)
  def imei = column[String]("imei")
  def * = (id, imei).mapTo[Device]

// Запрос
val query = Devices.filter(_.imei === "860719020025346")
db.run(query.result)
```

**Проблемы Slick:**
- Своя DSL вместо SQL — нужно учить отдельный язык
- Сложная генерация SQL для сложных запросов
- Плохо работает с геопространственными функциями TimescaleDB
- Тянет за собой много зависимостей
- Не функциональный — мутабельные сессии

### Skunk — pure FP PostgreSQL

```scala
// Skunk — типобезопасный SQL с проверкой на компиляции
val query: Query[String, Device] =
  sql"SELECT * FROM devices WHERE imei = $varchar".query(device)
```

**Хорош**, но:
- Только PostgreSQL (нет MySQL, H2 для тестов)
- Менее зрелый, меньше community
- Нет поддержки HikariCP из коробки

### zio-sql — родной для ZIO

```scala
// zio-sql — попытка SQL DSL для ZIO
select(deviceId, imei).from(devices).where(imei === "...")
```

**Проблемы:**
- Экспериментальный, незрелый
- Неполная поддержка SQL
- Маленькое community

### ✅ Doobie — наш выбор

```scala
// Doobie — пишешь чистый SQL, получаешь типобезопасность
sql"SELECT * FROM devices WHERE imei = $imei".query[Device].option
```

**Почему Doobie лучший выбор для нас:**

| Критерий | Doobie | Slick | Skunk | zio-sql |
|----------|--------|-------|-------|---------|
| Чистый SQL | ✅ Да | ❌ DSL | ✅ Да | ❌ DSL |
| TimescaleDB | ✅ | ⚠️ Сложно | ✅ | ❌ |
| Зрелость | ✅ 10+ лет | ✅ Старый | ⚠️ Молодой | ❌ Эксп. |
| FP паттерн | ✅ ConnectionIO | ❌ | ✅ | ✅ |
| ZIO совместимость | ✅ Через interop | ⚠️ | ⚠️ | ✅ |
| Сложные запросы | ✅ SQL напрямую | ❌ | ✅ | ❌ |

**Doobie + zio-interop-cats** = лучшее из обоих миров.

---

## 10.5 zio-interop-cats — мост между мирами

Doobie работает на `cats.effect.IO`, а мы на ZIO. Мост:

```scala
// build.sbt
"dev.zio" %% "zio-interop-cats" % "23.1.0.0"
```

Это позволяет использовать `Transactor[Task]` вместо `Transactor[IO]`:

```scala
// DeviceRepository.scala
final case class Live(xa: Transactor[Task]) extends DeviceRepository
//                              ↑
//                    Task = ZIO[Any, Throwable, A]
//                    Doobie думает что это cats IO, но это ZIO!
```

---

## 10.6 Circe vs zio-json

### Circe (Typelevel мир):

```scala
import io.circe.generic.auto.*
import io.circe.syntax.*

case class Device(id: Long, imei: String) derives Encoder, Decoder

val json = device.asJson.noSpaces
val parsed = decode[Device](json)
```

### zio-json (наш выбор):

```scala
import zio.json.*

case class Device(id: Long, imei: String) derives JsonCodec

val json = device.toJson
val parsed = json.fromJson[Device]
```

**Почему zio-json:**
- Быстрее Circe на ~30-50% (бенчмарки)
- `derives` — одно ключевое слово вместо двух (Encoder + Decoder)
- Нативная интеграция с ZIO
- Стриминговый парсинг (не загружает весь JSON в память)

---

## 📝 Упражнение

1. Открой `DeviceRepository.scala` — найди `Transactor[Task]`. Как Doobie работает с ZIO?
2. Что даёт `zio-interop-cats`? Что сломается если его убрать?
3. Почему для TimescaleDB лучше писать SQL руками, а не через ORM?
4. В чём разница `IO[A]` (Cats) и `Task[A]` (ZIO)?
5. Найди в проекте `derives JsonCodec` — сколько case classes его используют?

---

**→ Следующий: [11-SCALA-ECOSYSTEM.md](11-SCALA-ECOSYSTEM.md) — Экосистема Scala для профессионала**
