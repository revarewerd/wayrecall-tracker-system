> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-02` | Версия: `1.0`

# Wayrecall Tracker — План тестирования

## Текущее состояние

### Block 1 — Data Collection

| Сервис | Unit Tests | Файлов | Покрытие |
|---|---|---|---|
| **Connection Manager** | 286+ | 28 | Протоколы (16), команды (6), API (1), фильтры (2), сеть (2), домен (1) |
| **History Writer** | 92 | 4 | Домен (3), сервис (1) |
| **Device Manager** | 69 | 3 | Домен (2), сервис (1) |
| **Итого Block 1** | **447+** | **35** | — |

### Block 2 — Business Logic

| Сервис | Unit Tests | Статус |
|---|---|---|
| Rule Checker | 0 | Код написан, тесты не начаты |
| Notification Service | 0 | Код написан, тесты не начаты |
| Analytics / User / Admin / Integration / Maintenance / Sensors | 0 | Код написан, тесты в планах |

---

## Тестовая пирамида

```
         /  E2E  \         ← Полный вебсокет-сценарий: трекер → kafka → БД → API → карта
        / Integration \    ← docker-compose: сервис + TimescaleDB/Redis/Kafka
       /   Contract    \   ← Kafka schema, API contract (JSON validation)
      /     Unit        \  ← Каждый сервис: домен, сервис, репозиторий (mock)
     /_____________________\
```

---

## 1. Unit Tests (текущий уровень)

### Подход

- **Фреймворк:** ZIO Test (`ZIOSpecDefault`)
- **DI:** In-Memory реализации на ZIO `Ref` (без контейнеров)
- **Mock:** Кастомные mock-классы (InMemoryDeviceRepository, MockEventPublisher)
- **Цель:** >80% coverage для `service/` и `domain/` слоёв

### Что покрыто

✅ Парсеры всех 16 GPS-протоколов (CM)
✅ Энкодеры команд 5 протоколов + фабрика (CM)
✅ HTTP API endpoints (CM)
✅ Фильтры точек: Dead Reckoning, Stationary (CM)
✅ Доменные типы: opaque types, Imei валидация, GeoPoint, Haversine (CM, HW, DM)
✅ Kafka события: TelemetryEvent, TripEvent, DomainEvent (HW, DM)
✅ Типизированные ошибки: полная иерархия (HW, DM)
✅ Сервисные слои: HistoryService, DeviceService (HW, DM)

### Что НЕ покрыто (нужны integration tests)

❌ Doobie SQL запросы (TimescaleDB, PostgreSQL)
❌ Kafka consumer/producer (реальные топики)
❌ Redis операции (кэш, Pub/Sub)
❌ Flyway миграции
❌ Multi-tenant isolation на уровне БД

---

## 2. Integration Tests (план)

### Подход

- **Фреймворк:** ZIO Test + `testcontainers-scala`
- **Инфраструктура:** Docker-контейнеры запускаются на лету
- **Цель:** проверка реальных операций с БД, Kafka, Redis

### Нужные контейнеры

| Контейнер | Образ | Для чего |
|---|---|---|
| TimescaleDB | `timescale/timescaledb:latest-pg15` | GPS-история, гипертаблицы |
| PostgreSQL | `postgres:15-alpine` | Master data (devices, orgs) |
| Redis | `redis:7-alpine` | Кэш, очередь команд, Pub/Sub |
| Kafka + ZooKeeper | `confluentinc/cp-kafka:7.5.0` | Топики, consumer groups |

### Сценарии по сервисам

#### Connection Manager

| Тест | Контейнеры | Описание |
|---|---|---|
| `KafkaProducerIntSpec` | Kafka | Публикация GPS-точек → чтение из топика `gps-raw-data` |
| `RedisStateIntSpec` | Redis | HSET/HGET device context, TTL, Pub/Sub |
| `CommandQueueIntSpec` | Redis + Kafka | RPUSH команда → CM считывает из очереди |

#### History Writer

| Тест | Контейнеры | Описание |
|---|---|---|
| `TelemetryRepoIntSpec` | TimescaleDB | INSERT + SELECT + фильтрация по vehicleId/timeRange |
| `HypertableIntSpec` | TimescaleDB | Проверка гипертаблицы, compression policy |
| `KafkaConsumerIntSpec` | Kafka + TimescaleDB | Чтение из `gps-raw-data` → запись в TimescaleDB |

#### Device Manager

| Тест | Контейнеры | Описание |
|---|---|---|
| `DeviceRepoIntSpec` | PostgreSQL | CRUD devices, Flyway миграции |
| `OrgIsolationIntSpec` | PostgreSQL | Multi-tenant: org A не видит devices org B |
| `KafkaEventIntSpec` | Kafka | Публикация DeviceCreated → чтение из `device-events` |
| `RedisSyncIntSpec` | Redis | Синхронизация device context в Redis |

### Пример шаблона (ZIO + testcontainers)

```scala
import zio.*
import zio.test.*
import com.dimafeng.testcontainers.PostgreSQLContainer

object DeviceRepoIntSpec extends ZIOSpecDefault:
  
  val postgresLayer: ZLayer[Any, Throwable, PostgreSQLContainer] =
    ZLayer.scoped {
      ZIO.acquireRelease(
        ZIO.attempt {
          val container = PostgreSQLContainer()
          container.start()
          container
        }
      )(c => ZIO.attempt(c.stop()).ignoreLogged)
    }

  def spec = suite("DeviceRepository Integration")(
    test("create и findById roundtrip") {
      // ... тестовая логика с реальной БД
      assertTrue(true)
    }
  ).provideShared(postgresLayer)
```

---

## 3. Contract Tests (план)

### Kafka Schema Validation

- Проверить что JSON schema сообщений совместима между producer и consumer
- Например: CM публикует `TelemetryEvent` → HW десериализует его в `TelemetryEvent`
- Инструмент: ручные тесты с `zio-json` decode/encode roundtrip

### API Contract

- Device Manager REST API → contract тесты для будущего API Gateway
- Response JSON format validation

---

## 4. Load Tests (план)

### Целевые метрики (из SLA)

| Метрика | Цель |
|---|---|
| GPS packet latency (p99) | < 100ms |
| GPS points/sec throughput | 20,000+ |
| Concurrent TCP connections | 20,000+ |
| History write latency | < 10 sec |

### Инструменты

- **Gatling** (Scala) — нагрузочные тесты REST API
- **Кастомный TCP клиент** — имитация GPS-трекеров (вариант: ZIO + Netty)
- **k6** — альтернатива для HTTP нагрузки

### Сценарии

| Сценарий | Описание | Целевая нагрузка |
|---|---|---|
| `GpsFlood` | 10K трекеров шлют по 1 точке/сек | 10,000 rps по TCP |
| `BurstTraffic` | 5K трекеров шлют пакеты по 50 точек | 250,000 точек за 5 сек |
| `CommandStorm` | 1K одновременных команд на разные трекеры | 1,000 команд/сек |
| `HistoryQuery` | 100 параллельных запросов истории за 30 дней | 100 rps REST |
| `MixedLoad` | GPS + команды + API запросы одновременно | Смешанная нагрузка |

### Инфраструктура для нагрузки

```yaml
# docker-compose.load-test.yml
services:
  gps-simulator:
    build: ./test-stand/gps-simulator
    environment:
      TARGET_HOST: connection-manager
      TARGET_PORT: 5001
      TRACKER_COUNT: 10000
      INTERVAL_MS: 1000
      PROTOCOL: teltonika
```

---

## 5. E2E Tests (план)

### Full Data Path

```
GPS Simulator → TCP (CM) → Kafka → HW → TimescaleDB → REST API → JSON response
```

**Проверяем:** точка, отправленная трекером, через <10 сек доступна через REST API History Writer.

### WebSocket Real-time

```
GPS Simulator → CM → Kafka → WebSocket Service → Browser (mock)
```

**Проверяем:** позиция обновляется на "карте" в реальном времени (<1 сек).

---

## Приоритеты реализации

| Приоритет | Что | Когда |
|---|---|---|
| 🟢 Готово | Unit tests Block 1 (447+ тестов) | Сейчас |
| 🟡 Следующий | Integration tests (testcontainers) для Block 1 | Перед production |
| 🟡 Следующий | Unit tests Block 2 (Rule Checker, Notifications) | При стабилизации Block 2 |
| 🟠 Потом | Contract tests (Kafka schema compatibility) | При добавлении новых consumer'ов |
| 🟠 Потом | Load tests (GPS Simulator) | При подготовке к 10K+ трекеров |
| 🔴 Позже | E2E tests (full data path) | При интеграции Block 3 |

---

## CI Pipeline (план)

```yaml
# .github/workflows/test.yml
name: Tests
on: [push, pull_request]
jobs:
  unit-tests:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        service: [connection-manager, history-writer, device-manager]
    steps:
      - uses: actions/checkout@v4
        with:
          submodules: recursive
      - uses: actions/setup-java@v4
        with:
          java-version: '21'
          distribution: 'temurin'
      - name: Run tests
        run: cd services/${{ matrix.service }} && sbt test

  integration-tests:
    needs: unit-tests
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15-alpine
      redis:
        image: redis:7-alpine
      kafka:
        image: confluentinc/cp-kafka:7.5.0
    steps:
      - name: Run integration tests
        run: sbt "testOnly *IntSpec"
```
