# 📖 План изучения технологий

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-06` | Версия: `1.0`

## Содержание

1. [Функциональное программирование (Red Book)](#1-функциональное-программирование-red-book)
2. [Scala 3](#2-scala-3)
3. [ZIO 2](#3-zio-2)
4. [Cats / Cats Effect](#4-cats--cats-effect)
5. [Doobie](#5-doobie)
6. [PostgreSQL / TimescaleDB / PostGIS](#6-postgresql--timescaledb--postgis)
7. [Apache Kafka](#7-apache-kafka)
8. [Redis](#8-redis)
9. [TypeScript + React](#9-typescript--react)
10. [Netty](#10-netty)
11. [Docker / DevOps](#11-docker--devops)
12. [Общий план чтения](#12-общий-план-чтения)

---

## 1. Функциональное программирование (Red Book)

> **Начать сюда!** Фундамент для всего остального.

### 📕 «Красная книга» — Functional Programming in Scala

| | |
|---|---|
| **Авторы** | Paul Chiusano, Rúnar Bjarnason |
| **Издание** | 2-е издание (2023, для Scala 3) |
| **Купить** | [Manning](https://www.manning.com/books/functional-programming-in-scala-second-edition) |
| **GitHub** | [fpinscala/fpinscala](https://github.com/fpinscala/fpinscala) |
| **Уровень** | Intermediate → Advanced |

### Главы и что они дают проекту:

| Глава | Тема | Применение в Wayrecall |
|-------|------|------------------------|
| 1-3 | Intro to FP, Pure functions, Data structures | Основа: immutability, val, Option |
| 4 | Handling errors without exceptions | Наши sealed trait DomainError |
| 5 | Strictness and laziness | ZIO lazy evaluation, Streams |
| 6 | Purely functional state | Redis state management паттерн |
| 7 | Purely functional parallelism | ZIO Fiber, concurrent GPS processing |
| 8 | Property-based testing | Тестирование парсеров протоколов |
| 9 | Parser combinators | Парсинг GPS бинарных пакетов |
| 10-11 | Monoids, Monads | For-comprehension, ZIO композиция |
| 12-13 | Applicative, Traversable | Batch операции, валидация |
| 14 | IO Monad | ZIO = IO on steroids |
| 15 | Streaming | Kafka streams, GPS point pipeline |

### План изучения Red Book:

```
Неделя 1: Главы 1-3  (основы ФП, ADT)
Неделя 2: Главы 4-6  (ошибки, laziness, state)
Неделя 3: Главы 7-9  (параллелизм, тестирование, парсеры)
Неделя 4: Главы 10-12 (monoids, monads, applicative)
Неделя 5: Главы 13-15 (IO, streaming)
```

**Практика:** решать упражнения из книги на Scala 3, коммитить в `learning/fp-in-scala/`.

### Дополнительные ресурсы по ФП:

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| Category Theory for Programmers (Milewski) | Книга (бесплатно) | [GitHub](https://github.com/hmemcpy/milewski-ctfp-pdf) |
| Scala with Cats (Underscore) | Книга (бесплатно) | [underscore.io](https://www.scalawithcats.com/) |
| FP Tower (Julien Truffaut) | Курс | [fp-tower.com](https://www.fp-tower.com/) |
| Rock the JVM — FP in Scala | Видео | [YouTube](https://www.youtube.com/c/RocktheJVM) |

---

## 2. Scala 3

### 📘 Основные книги

| Книга | Автор | Ссылка | Уровень |
|-------|-------|--------|---------|
| **Programming in Scala 5th Ed** | Odersky, Spoon, Venners | [Artima](https://www.artima.com/shop/programming_in_scala_5ed) | Beginner→Advanced |
| **Scala 3 Book** (бесплатно) | docs.scala-lang.org | [scala-lang.org](https://docs.scala-lang.org/scala3/book/introduction.html) | Beginner |
| **Creative Scala** (бесплатно) | Underscore | [creativescala.org](https://www.creativescala.org/) | Beginner |
| **Essential Scala** (бесплатно) | Underscore | [underscore.io](https://books.underscore.io/essential-scala/essential-scala.html) | Beginner→Inter |

### Ключевые темы Scala 3 для проекта:

| Тема | Почему важно | Где используем |
|------|-------------|----------------|
| Opaque types | Type safety без overhead | `Imei`, `VehicleId`, `OrgId` |
| Enums / Sealed traits | ADT для ошибок и событий | `DomainError`, `Command`, `EventType` |
| Given / Using (implicits) | ZIO Layer, JSON codecs | Везде |
| Extension methods | Утилиты на типах | `ByteBuf` extensions в CM |
| Union types | `A | B` | Альтернатива sealed trait |
| Match types | Conditional types | Продвинутые паттерны |
| Inline / Macros | Compile-time derivation | `deriveConfig`, `DeriveJsonCodec` |
| Context functions | `ExecutionContext` замена | ZIO Environment |

### Онлайн-ресурсы:

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| Scala 3 Migration Guide | Документация | [docs.scala-lang.org/scala3/guides/migration](https://docs.scala-lang.org/scala3/guides/migration/compatibility-intro.html) |
| Scala Exercises | Практика | [scala-exercises.org](https://www.scala-exercises.org/) |
| Scastie (playground) | Песочница | [scastie.scala-lang.org](https://scastie.scala-lang.org/) |
| Rock the JVM | YouTube | [youtube.com/c/RocktheJVM](https://www.youtube.com/c/RocktheJVM) |
| DevInsideYou | YouTube | [youtube.com/c/DevInsideYou](https://www.youtube.com/c/DevInsideYou) |

---

## 3. ZIO 2

### 📗 Книги и документация

| Ресурс | Тип | Ссылка | Уровень |
|--------|-----|--------|---------|
| **Zionomicon** | Книга | [zionomicon.com](https://www.zionomicon.com/) | Inter→Advanced |
| **ZIO 2 Official Docs** | Документация | [zio.dev](https://zio.dev/) | Все |
| **ZIO Ecosystem** | Библиотеки | [zio.dev/ecosystem](https://zio.dev/ecosystem/) | Все |

### Темы для изучения (в порядке приоритета):

| # | Тема | Время | Применение |
|---|------|-------|------------|
| 1 | ZIO[R, E, A] — тройка типов | 2 дня | Базовое понимание всех эффектов |
| 2 | ZLayer — dependency injection | 2 дня | Вся сборка сервисов в Main.scala |
| 3 | Error handling (typed errors) | 1 день | Sealed trait DomainError |
| 4 | Fiber — concurrency | 2 дня | Параллельная обработка GPS |
| 5 | Ref, Queue, Hub — concurrent state | 2 дня | In-memory state в CM |
| 6 | Schedule — retry/repeat | 1 день | Reconnect, health check |
| 7 | ZIO Streams | 3 дня | Kafka consumer/producer pipelines |
| 8 | ZIO Test / ZIOSpecDefault | 2 дня | Все тесты |
| 9 | ZIO Config | 1 день | HOCON конфигурация |
| 10 | ZIO Logging | 0.5 дня | Логирование |
| 11 | ZIO HTTP | 2 дня | REST API (DM, RC, NS и др.) |
| 12 | ZIO Kafka | 2 дня | Consumer/Producer обёртки |

### Видео и курсы:

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| Rock the JVM — ZIO | YouTube | [ZIO playlist](https://www.youtube.com/playlist?list=PLmtsMNDRU0BxryRX4wiwrTZ661xcp6VPM) |
| ZIO World — конференция | Видео | [youtube.com/c/ZIODev](https://www.youtube.com/@zioDev) |
| Jorge Vásquez — ZIO 2 | Блог | [blog.rockthejvm.com](https://blog.rockthejvm.com/) |
| Functional Justin | YouTube | [youtube.com/@FunctionalJustin](https://www.youtube.com/@FunctionalJustin) |

---

## 4. Cats / Cats Effect

> Cats используется косвенно через Doobie и некоторые ZIO interop.

### 📙 Книги

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **Scala with Cats** (бесплатно) | Книга | [scalawithcats.com](https://www.scalawithcats.com/) |
| **Essential Effects** | Книга | [essentialeffects.dev](https://essentialeffects.dev/) |
| **Cats Official Docs** | Документация | [typelevel.org/cats](https://typelevel.org/cats/) |

### Что нужно знать для проекта:

| Тема | Зачем | Где |
|------|-------|-----|
| Monad, Functor, Applicative | Doobie query composition | Repository слой |
| `IO` / `IOApp` | Понимание Cats Effect (interop) | ZIO-Cats interop |
| `Traverse` | Batch операции | `List[F[A]]` → `F[List[A]]` |
| `NonEmptyList` | Валидация | API validation |

---

## 5. Doobie

### 📒 Ресурсы

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **Doobie Book of Doobie** | Документация | [tpolecat.github.io/doobie](https://tpolecat.github.io/doobie/) |
| **Doobie Typechecking** | Гайд | [doobie/docs/typechecking](https://tpolecat.github.io/doobie/docs/17-Typechecking.html) |
| Rock the JVM — Doobie | Видео | [YouTube](https://www.youtube.com/watch?v=hGNXBJEqPqc) |

### Ключевые темы:

| Тема | Приоритет | Применение |
|------|-----------|------------|
| `sql"..."` interpolator | 🔴 | Все SQL запросы |
| `Fragment` composition | 🔴 | Динамические фильтры |
| `Transactor` with ZIO | 🔴 | HikariTransactor в Main |
| `Query0` / `Update0` | 🔴 | Repository паттерн |
| Meta instances | 🟡 | Custom types (UUID, Instant) |
| Typechecking | 🟡 | CI проверка SQL |
| Batch operations | 🟡 | History Writer bulk insert |

---

## 6. PostgreSQL / TimescaleDB / PostGIS

### 📘 Книги и ресурсы

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **PostgreSQL 15 Official Docs** | Документация | [postgresql.org/docs/15](https://www.postgresql.org/docs/15/) |
| **The Art of PostgreSQL** | Книга | [theartofpostgresql.com](https://theartofpostgresql.com/) |
| **TimescaleDB Docs** | Документация | [docs.timescale.com](https://docs.timescale.com/) |
| **PostGIS Introduction** | Туториал | [postgis.net/workshops](https://postgis.net/workshops/postgis-intro/) |
| **PostGIS in Action 3rd Ed** | Книга | [Manning](https://www.manning.com/books/postgis-in-action-third-edition) |

### Ключевые темы:

| Тема | Приоритет | Где используем |
|------|-----------|----------------|
| Hypertables (TimescaleDB) | 🔴 | GPS история (history-writer) |
| Compression, Retention | 🔴 | Политики хранения GPS |
| Continuous Aggregates | 🔴 | Часовые/дневные агрегаты |
| ST_Contains, ST_DWithin (PostGIS) | 🔴 | Геозоны (rule-checker) |
| JSONB columns | 🟡 | Настройки, метаданные |
| Partitioning | 🟡 | Масштабирование |
| Window functions | 🟡 | Аналитика |
| EXPLAIN ANALYZE | 🟡 | Оптимизация запросов |

---

## 7. Apache Kafka

### 📕 Книги и ресурсы

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **Kafka: The Definitive Guide 2nd Ed** | Книга | [O'Reilly](https://www.oreilly.com/library/view/kafka-the-definitive/9781492043072/) |
| **Designing Event-Driven Systems** (бесплатно) | Книга | [Confluent](https://www.confluent.io/designing-event-driven-systems/) |
| **Apache Kafka Docs** | Документация | [kafka.apache.org](https://kafka.apache.org/documentation/) |
| **ZIO Kafka Docs** | Библиотека | [zio.dev/zio-kafka](https://zio.dev/zio-kafka/) |
| **Confluent Developer** | Курсы | [developer.confluent.io](https://developer.confluent.io/) |

### Ключевые темы:

| Тема | Приоритет | Применение |
|------|-----------|------------|
| Partitions & Consumer Groups | 🔴 | Масштабирование, ordering по deviceId |
| Exactly-once semantics | 🔴 | Идемпотентность consumers |
| Serialization (JSON) | 🔴 | zio-json + Kafka |
| Retention & Compaction | 🟡 | Политики хранения сообщений |
| Consumer lag monitoring | 🟡 | Мониторинг healthcheck |
| Kafka Streams vs consumer | 🟢 | Архитектурный выбор |

---

## 8. Redis

### 📗 Ресурсы

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **Redis in Action** | Книга | [Manning](https://www.manning.com/books/redis-in-action) |
| **Redis University** (бесплатно) | Курсы | [university.redis.com](https://university.redis.com/) |
| **Redis Official Docs** | Документация | [redis.io/docs](https://redis.io/docs/) |
| **Redis Best Practices** | Гайд | [redis.io/docs/manual](https://redis.io/docs/management/optimization/) |

### Ключевые темы:

| Тема | Приоритет | Применение |
|------|-----------|------------|
| HSET/HGET/HGETALL | 🔴 | DeviceContext в CM |
| TTL и expiration | 🔴 | Кэш, сессии |
| Pub/Sub | 🔴 | Real-time уведомления |
| RPUSH/LPOP (очереди) | 🔴 | Очередь команд |
| Pipelining | 🟡 | Batch операции |
| Lua scripting | 🟡 | Атомарные операции |
| Memory management | 🟡 | Оптимизация (maxmemory) |

---

## 9. TypeScript + React

### 📘 Ресурсы

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **TypeScript Handbook** | Документация | [typescriptlang.org/docs](https://www.typescriptlang.org/docs/handbook/) |
| **React Docs (new)** | Документация | [react.dev](https://react.dev/) |
| **Leaflet Docs** | Документация | [leafletjs.com/reference](https://leafletjs.com/reference.html) |
| **React-Leaflet** | Библиотека | [react-leaflet.js.org](https://react-leaflet.js.org/) |
| **Fullstack React with TS** | Книга | [fullstackreact.com](https://www.fullstackreact.com/) |
| **Total TypeScript** | Курс | [totaltypescript.com](https://www.totaltypescript.com/) |

### Ключевые темы:

| Тема | Приоритет | Применение |
|------|-----------|------------|
| React Hooks (useState, useEffect) | 🔴 | Вся логика компонентов |
| TypeScript generics | 🔴 | Типизация API |
| WebSocket client | 🔴 | Real-time GPS позиции |
| Leaflet markers/polylines | 🔴 | Карта с машинами |
| State management (Zustand/Redux) | 🟡 | Глобальное состояние |
| React Query | 🟡 | REST API запросы |

---

## 10. Netty

### 📕 Ресурсы

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **Netty in Action** | Книга | [Manning](https://www.manning.com/books/netty-in-action) |
| **Netty Official Docs** | Документация | [netty.io/wiki](https://netty.io/wiki/) |
| **Netty User Guide** | Гайд | [netty.io/wiki/user-guide](https://netty.io/wiki/user-guide-for-4.x.html) |

### Ключевые темы:

| Тема | Приоритет | Применение |
|------|-----------|------------|
| Channel pipeline | 🔴 | TCP обработка в CM |
| ByteBuf | 🔴 | Парсинг бинарных GPS пакетов |
| EventLoop | 🔴 | Concurrency модель |
| Codec framework | 🟡 | Encoder/Decoder |
| Connection management | 🟡 | Keep-alive, timeout |

---

## 11. Docker / DevOps

### 📒 Ресурсы

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **Docker Deep Dive** | Книга | [Nigel Poulton](https://nigelpoulton.com/books/) |
| **Docker Docs** | Документация | [docs.docker.com](https://docs.docker.com/) |
| **Docker Compose Docs** | Документация | [docs.docker.com/compose](https://docs.docker.com/compose/) |
| **Prometheus Docs** | Мониторинг | [prometheus.io/docs](https://prometheus.io/docs/) |
| **Grafana Tutorials** | Мониторинг | [grafana.com/tutorials](https://grafana.com/tutorials/) |

---

## 12. Общий план чтения

### Приоритет 1 — Читать первыми (фундамент):

```
📕 FP in Scala (Red Book) 2nd Ed    — 5 недель
📗 Zionomicon                        — 3 недели (параллельно с Red Book)
📘 Scala 3 Book (бесплатно, онлайн)  — 1 неделя
```

### Приоритет 2 — После фундамента:

```
📙 Scala with Cats (бесплатно)       — 2 недели
📒 Doobie Book of Doobie             — 1 неделя
📕 Kafka: The Definitive Guide       — 2 недели
📗 Redis in Action                   — 1 неделя
```

### Приоритет 3 — По мере необходимости:

```
📘 PostGIS in Action                 — при работе с геозонами
📕 Netty in Action                   — при работе с CM
📘 TypeScript Handbook               — при работе с frontend
```

### Ежедневная рутина:

```
Утро (30 мин):  Чтение книги (Red Book / Zionomicon)
Обед (15 мин):  Решение 1 упражнения из книги
Вечер (30 мин): Практика — применить к проекту Wayrecall
```

---

*Версия: 1.0 | Обновлён: 6 июня 2026 | Тег: АКТУАЛЬНО*
