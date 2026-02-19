# 🏗️ План доработок Блока 1 — Connection Manager + Device Manager + History Writer

> **Дата:** 12 февраля 2026 (v2.0 — после полного аудита)  
> **Цель:** Довести Блок 1 до работающего End-to-End состояния  
> **Маршрут:** GPS Трекер → TCP → Connection Manager → Kafka → History Writer → TimescaleDB  
> **Параллельно:** Device Manager CRUD → Redis → Connection Manager использует контекст

---

## 📊 Текущее состояние (аудит 12.02.2026)

| Сервис | Файлов | Компиляция | Критичные проблемы |
|--------|--------|-----------|----------|
| **connection-manager** | 32 .scala | ⚠️ Вероятно да | 19 `throw new Exception` в парсерах, команды через Kafka Static Partition |
| **device-manager** | 14 .scala | ❌ Нет | Нет zio-interop-cats/TransactorLayer, пропущены поля из Stels |
| **history-writer** | 10 .scala | ❌ Нет | Весь код на ClickHouse JDBC → нужно переписать на Doobie |
| **Интеграция** | — | ❌ | Топики расходятся, схема БД не синхронизирована |

### Ключевые находки аудита

1. **19 `throw new Exception`** в 4 парсерах Connection Manager → заменить на ADT ошибки (FP)
2. **History Writer полностью на ClickHouse** — TelemetryRepository.scala (340 строк) использует ClickHouse JDBC, а инфра — TimescaleDB
3. **Пропущены поля из legacy Stels** — SIM карта (provider, ICCID), марка/модель трекера, логин/пароль устройства, таблица ретрансляции
4. **Команды через Kafka Static Partition** — DM публикует в device-commands с key=instanceId, CM читает свой partition через assign()
5. **GPS spoofing (Москва, РЭБ)** — Post-MVP фильтр расширяющегося круга
6. **Ретранслятор Stels отправлял обработанные данные** (не бинарь) — Wialon IPS текст / NIS HTTP JSON

---

## 🔥 Фаза 0: Архитектурные решения (ЗАФИКСИРОВАНЫ ✅)

### Решение 1: TimescaleDB (не ClickHouse) ✅
**Принято.** Единая TimescaleDB-инстанция = PostgreSQL 15 + hypertables. Doobie для SQL. Всё в одном контейнере.

### Решение 2: Единая PostgreSQL ✅
**Принято.** Одна TimescaleDB-инстанция. Схема `public` для метаданных, `timeseries` для hypertables.

### Решение 3: Доставка команд через Kafka Static Partition Assignment ✅
**Принято (12 февраля 2026).** Вместо Redis Pub/Sub:
- **Команды:** Device Manager определяет `instanceId` по протоколу устройства (статический маппинг) и публикует в Kafka `device-commands` с key=instanceId → каждый CM читает только свой partition через `kafkaConsumer.assign()`
- **Маппинг:** `teltonika → cm-instance-1 → partition 0`, `wialon → cm-instance-2 → partition 1`, `ruptela → cm-instance-3 → partition 2`, `navtelecom → cm-instance-4 → partition 3`
- **Оффлайн:** CM кладёт команду в in-memory queue + Redis ZSET backup (`pending_commands:{imei}`)
- **При подключении:** CM мержит in-memory + Redis, дедуплицирует по commandId, отправляет всё, очищает обе очереди
- **Реальное время:** CM → Kafka `gps-events` → Real-time Service → Frontend polling REST API (3 сек)
- **WebSocket:** Block 2 (Post-MVP). WebSocket Service будет потребителем Kafka, не Redis

### Решение 4: Ретрансляция — обработанные данные ✅
**Принято.** Как и в Stels, ретрансляция отправляет обработанные GPS точки (JSON), не сырой бинарь. Connection Manager → Kafka `gps-events-retranslation` → Retranslation Service формирует целевой протокол (Wialon IPS, EGTS, HTTP).

---

## 🔴 Фаза 1: Устранить критические расхождения (3-4 дня)

### 1.1 Синхронизация Kafka топиков

**Проблема:** Connection Manager публикует в конфигурируемый `rawGpsEvents`, History Writer слушает `telemetryEvents`, Device Manager публикует в `deviceEvents/vehicleEvents/organizationEvents` — нигде нет единого стандарта.

**Зафиксированные имена топиков:**
```
├─ gps-events                  (CM → HW, Real-time Service)
├─ gps-events-rules            (CM → Geozones Service, Rule Checker)
├─ gps-events-retranslation    (CM → Retranslation Service)
├─ device-status               (CM → Notifications, HW)
├─ device-commands             (DM → CM, Static Partition Assignment)
├─ device-events               (DM → CM, всем кто слушает изменения устройств)
├─ unknown-devices             (CM → DM auto-provisioning)
└─ command-audit               (CM + DM → аудит команд)
```

**Файлы для правки:**
- `services/connection-manager/.../config/AppConfig.scala` — имена топиков
- `services/history-writer/.../config/AppConfig.scala` — `telemetryEvents` → `gps-events`
- `services/device-manager/.../infrastructure/KafkaPublisher.scala` — `deviceEvents`
- `infra/scripts/create-kafka-topics.sh` — обновить список

### 1.2 Синхронизация схемы PostgreSQL + пропущенные поля из Stels

**Проблема:** `timescaledb-init.sql` не совпадает с `Entities.scala`, плюс обнаружены пропущенные поля из legacy Stels.

**Действия:**
- Переписать `infra/databases/timescaledb-init.sql` — привести в соответствие с моделью `Entities.scala`
- **Добавить пропущенные Stels поля в devices:**
  - `device_brand VARCHAR(50)` — марка трекера (eqMark)
  - `device_model VARCHAR(50)` — модель трекера (eqModel)
  - `device_login VARCHAR(50)` — логин устройства (для Wialon/NavTelecom)
  - `device_password VARCHAR(50)` — пароль устройства
  - `sim_provider VARCHAR(50)` — оператор SIM
  - `sim_iccid VARCHAR(25)` — ICCID SIM карты
- **Добавить поле в vehicles:** `comment TEXT`
- **Добавить поле в organizations:** `full_name VARCHAR(200)`
- **Создать таблицу `retranslation_targets`** — цели ретрансляции GPS данных
- Добавить Flyway миграции в `services/device-manager/src/main/resources/db/migration/`

### 1.3 Перевод History Writer с ClickHouse на TimescaleDB

**Проблема:** Весь `TelemetryRepository.scala` (340 строк) использует ClickHouse JDBC.

**Действия:**
1. `build.sbt` — заменить `clickhouse-jdbc` на `org.postgresql:postgresql` + `org.tpolecat:doobie-core/doobie-hikari`
2. Переписать `TelemetryRepository.scala`:
   - `insertBatch` → Doobie `.updateMany()` с `gps_positions` hypertable
   - `getByVehicle` → PostgreSQL SQL (не ClickHouse `geoDistance`)
   - `getLastPoint` → `ORDER BY device_time DESC LIMIT 1`
   - `getDailyStats` → `time_bucket('1 day', ...)` TimescaleDB функция
3. Обновить `AppConfig.scala` — PostgreSQL config вместо ClickHouse

### 1.4 ADT ошибки в парсерах Connection Manager (НОВОЕ)

**Проблема:** 19 `throw new Exception` в 4 парсерах — нарушает FP принципы, крашит fiber.

**Файлы (количество throw):**
| Файл | throw | Типичные ошибки |
|------|-------|-----------------|
| TeltonikaParser.scala | 8 | Invalid IMEI, CRC mismatch, unsupported codec |
| WialonParser.scala | 4 | Invalid field, unknown packet type |
| NavTelecomParser.scala | 5 | Invalid signature, insufficient data |
| RuptelaParser.scala | 2 | Record count mismatch, CRC mismatch |

**Действия:**
1. Создать `domain/ParseError.scala`:
```scala
sealed trait ParseError extends Throwable:
  def message: String
  def protocol: String

case class InsufficientData(protocol: String, expected: Int, actual: Int) extends ParseError
case class InvalidField(protocol: String, field: String, value: String) extends ParseError
case class InvalidImei(protocol: String, imei: String) extends ParseError
case class CrcMismatch(protocol: String, expected: Int, actual: Int) extends ParseError
case class UnsupportedCodec(protocol: String, codecId: Int) extends ParseError
case class RecordCountMismatch(protocol: String, expected: Int, actual: Int) extends ParseError
case class InvalidSignature(protocol: String) extends ParseError
case class UnknownPacketType(protocol: String, packetType: String) extends ParseError
```

2. Изменить сигнатуры парсеров: `def parse(data: ByteBuffer): Either[ParseError, List[GpsRecord]]`
3. В `ConnectionHandler.scala` — обработка `Left(error)` → лог + метрика + Kafka DLQ
4. **НЕ отключать соединение** при ошибке парсинга — трекер продолжает работу

### 1.5 Обновить Entities.scala в Device Manager (НОВОЕ)

**Проблема:** Пропущены поля из legacy Stels Equipment/Object/Account.

**Действия — добавить в case class Device:**
```scala
deviceBrand: Option[String],      // марка трекера (Teltonika, Ruptela)
deviceModel: Option[String],      // модель (FMB920, FM-Pro4)
serialNumber: Option[String],     // серийный номер
simProvider: Option[String],      // оператор SIM (МТС, Билайн)
simIccid: Option[String],         // ICCID SIM карты
```

**Добавить в case class Vehicle:**
```scala
comment: Option[String],          // примечание
```

**Добавить в case class Organization:**
```scala
fullName: Option[String],         // полное название
```

**Создать новую сущность RetranslationTarget:**
```scala
final case class RetranslationTarget(
  id: Long,
  organizationId: OrganizationId,
  name: String,
  protocol: RetranslationProtocol,
  host: String,
  port: Int,
  isActive: Boolean,
  vehicleIds: List[VehicleId],
  createdAt: Instant,
  updatedAt: Instant
)
```

---

## 🟡 Фаза 2: Исправить компиляцию (1-2 дня)

### 2.1 Device Manager — Doobie Transactor Layer

**Проблема:** `DeviceRepository.live` требует `Transactor[Task]`, но нет слоя, который его создаёт.

**Действия:**
1. Добавить в `build.sbt`:
   ```scala
   "dev.zio" %% "zio-interop-cats" % "23.1.0.0"
   ```
2. Создать `infrastructure/TransactorLayer.scala`:
   ```scala
   object TransactorLayer:
     val live: ZLayer[AppConfig, Throwable, Transactor[Task]] = ...
   ```
3. Подключить в `Main.scala` Layer композицию

### 2.2 Device Manager — Подключить UnknownDeviceConsumer

**Проблема:** Consumer для авто-регистрации неизвестных трекеров существует, но не запускается в Main.

**Действия:**
- Добавить `UnknownDeviceConsumer.run.fork` в Main.scala рядом с HTTP сервером

### 2.3 History Writer — ZIO Kafka API

**Проблема:** `Consumer.live.make(consumerSettings)` — нестандартный API в zio-kafka 2.7.

**Действия:**
- Проверить версию zio-kafka в build.sbt
- Исправить на стандартный `Consumer.make` или `ZLayer.scoped(Consumer.make(...))`

### 2.4 Connection Manager — компиляция + ADT ошибки

**Действия:**
1. `cd services/connection-manager && sbt compile`
2. Создать `domain/ParseError.scala` (ADT иерархия из задачи 1.4)
3. Заменить 19 `throw` в 4 парсерах на `Left(ParseError.XXX)`
4. Обновить `ConnectionHandler.scala` — обработка `Left(error)`
5. Добавить Kafka Consumer для `device-commands` (Static Partition Assignment — `kafkaConsumer.assign()`)
6. Добавить `CommandHandler` — in-memory queue + Redis ZSET backup для оффлайн трекеров

---

## 🟢 Фаза 3: Добавить недостающие компоненты (2-3 дня)

### 3.1 Flyway миграции (Device Manager)

Создать SQL-миграции:
```
services/device-manager/src/main/resources/db/migration/
├─ V1__create_organizations.sql
├─ V2__create_vehicles.sql
├─ V3__create_devices.sql
├─ V4__create_sensor_profiles.sql
└─ V5__create_audit_log.sql
```

### 3.2 Docker Compose — добавить сервисы приложений

Сейчас docker-compose.yml поднимает только инфру. Нужно:
- Добавить `connection-manager` (порт 5001-5004)
- Добавить `device-manager` (порт 8092)
- Добавить `history-writer` (внутренний)
- Настроить `depends_on`, health checks

### 3.3 Connection Manager — добавить hasRetranslation в код

Обновить `GpsPoint.scala`:
```scala
case class GpsPoint(
  ...
  hasRetranslation: Boolean,
  retranslationTargets: Option[List[String]],
  ...
)
```

Обновить `KafkaProducer.scala` — добавить публикацию в `gps-events-retranslation`.

Обновить `RedisClient.scala` — читать `hasRetranslation` и `retranslationTargets` из хеша.

### 3.4 application.conf для всех сервисов

Проверить / создать:
- `services/connection-manager/src/main/resources/application.conf`
- `services/device-manager/src/main/resources/application.conf`
- `services/history-writer/src/main/resources/application.conf`

### 3.5 Обновить create-kafka-topics.sh

```bash
# Все топики Блока 1 + Блока 2 (retranslation)
kafka-topics --create --topic gps-events --partitions 12 --replication-factor 1
kafka-topics --create --topic gps-events-rules --partitions 6 --replication-factor 1
kafka-topics --create --topic gps-events-retranslation --partitions 6 --replication-factor 1
kafka-topics --create --topic device-status --partitions 3 --replication-factor 1
kafka-topics --create --topic device-events --partitions 3 --replication-factor 1
kafka-topics --create --topic unknown-devices --partitions 3 --replication-factor 1
kafka-topics --create --topic command-audit --partitions 3 --replication-factor 1
```

---

## 🧪 Фаза 4: Тестирование (2-3 дня)

### 4.1 Unit тесты (ZIOSpecDefault)

| Сервис | Приоритетные тесты |
|--------|--------------------|
| **connection-manager** | TeltonikaParserSpec, GpsProcessingServiceSpec, StationaryFilterSpec, DeadReckoningFilterSpec |
| **device-manager** | DeviceServiceSpec, DeviceRepositorySpec (с testcontainers) |
| **history-writer** | TelemetryConsumerSpec, TelemetryRepositorySpec (с testcontainers) |

### 4.2 Integration тесты

```
testcontainers:
├─ PostgreSQL/TimescaleDB → DeviceRepository, TelemetryRepository
├─ Kafka → KafkaProducer/Consumer
└─ Redis → RedisClient, RedisSyncService
```

### 4.3 E2E тест

```
Фейковый TCP клиент (Teltonika протокол)
    ↓ TCP connect + IMEI packet
Connection Manager
    ↓ Kafka gps-events
History Writer
    ↓ Batch insert
TimescaleDB
    ↓ SELECT query
✅ Точка записана
```

---

## 📋 Порядок работы (рекомендуемый)

```
День 1: Решения + Kafka + PostgreSQL схема
├─ [x] Принять решение: TimescaleDB (не ClickHouse)
├─ [x] Принять решение: единая БД + разные схемы
├─ [x] Принять решение: команды через Kafka Static Partition Assignment
├─ [x] Принять решение: ретрансляция обработанных данных
├─ [ ] Синхронизировать имена Kafka топиков (задача 1.1)
├─ [ ] Обновить create-kafka-topics.sh (задача 3.5)
└─ [ ] Обновить timescaledb-init.sql + пропущенные поля Stels (задача 1.2)

День 2: Device Manager — компиляция + пропущенные поля
├─ [ ] Добавить пропущенные поля в Entities.scala (задача 1.5)
├─ [ ] Создать RetranslationTarget сущность (задача 1.5)
├─ [ ] Добавить zio-interop-cats (задача 2.1)
├─ [ ] Создать TransactorLayer (задача 2.1)
├─ [ ] Подключить UnknownDeviceConsumer (задача 2.2)
├─ [ ] Flyway миграции (задача 3.1)
├─ [ ] sbt compile → 0 ошибок
└─ [ ] DeviceServiceSpec (базовый unit тест)

День 3: Connection Manager — ADT ошибки + Redis cleanup
├─ [ ] Создать domain/ParseError.scala (задача 1.4)
├─ [ ] Заменить 8 throw в TeltonikaParser → Left(ParseError.XXX)
├─ [ ] Заменить 4 throw в WialonParser
├─ [ ] Заменить 5 throw в NavTelecomParser
├─ [ ] Заменить 2 throw в RuptelaParser
├─ [ ] Добавить Kafka Consumer для device-commands (Static Partition, задача 2.4)
├─ [ ] Добавить CommandHandler (in-memory + Redis backup, задача 2.4)
├─ [ ] sbt compile → 0 ошибок
└─ [ ] TeltonikaParserSpec (unit тесты ADT ошибок)

День 4: History Writer — полная переработка
├─ [ ] Заменить ClickHouse JDBC → Doobie PostgreSQL (задача 1.3)
├─ [ ] Переписать TelemetryRepository (insertBatch, getByVehicle, getDailyStats)
├─ [ ] Исправить ZIO Kafka consumer API (задача 2.3)
├─ [ ] sbt compile → 0 ошибок
└─ [ ] TelemetryRepositorySpec (testcontainers)

День 5: Connection Manager — retranslation + интеграция
├─ [ ] Добавить hasRetranslation в GpsPoint (задача 3.3)
├─ [ ] Добавить gps-events-retranslation публикацию
├─ [ ] Проверить парсеры (Wialon, Ruptela, NavTelecom полнота)
├─ [ ] application.conf для всех сервисов (задача 3.4)
└─ [ ] GPS spoofing TODO в StationaryFilter (Post-MVP пометка)

День 6: Docker + Integration тесты
├─ [ ] Docker Compose с сервисами (задача 3.2)
├─ [ ] docker-compose up → все 3 сервиса стартуют
├─ [ ] Integration тесты (Kafka, Redis, DB)
└─ [ ] E2E тест (фейковый трекер → DB)

День 7: Тесты + полировка
├─ [ ] Unit тесты ≥ 60% покрытие для service layer
├─ [ ] Error handling (Redis down, Kafka down, DB down)
├─ [ ] Метрики + health checks
├─ [ ] Документация финально обновлена
└─ [ ] Git push all services
```

---

## 📌 Post-MVP задачи (НЕ входят в Блок 1)

| Задача | Описание | Блок |
|--------|----------|------|
| GPS spoofing фильтр | Расширяющийся круг от последней валидной точки (Москва, РЭБ) | Post-MVP |
| WebSocket Service | Реальное время через WebSocket вместо polling | Block 2 |
| Retranslation Service | Wialon IPS / EGTS / HTTP — формирование выходного протокола | Block 2 |
| Device login/password auth | Аутентификация трекеров по логину/паролю (Wialon, NavTelecom) | Post-MVP |
| Billing поля | balance, plan, subscriptionFee — в Organization/Vehicle | Block 3 |
| Команды управления | fuelPumpLock, ignitionLock — блокировка насоса/зажигания | Post-MVP |

---

## 🎯 Критерии приёмки (Definition of Done)

- [ ] Все 3 сервиса компилируются без ошибок (`sbt compile`)
- [ ] `docker-compose up` поднимает полную среду (инфра + сервисы)
- [ ] GPS трекер (симулятор) подключается к Connection Manager по TCP
- [ ] GPS точки сохраняются в TimescaleDB через History Writer
- [ ] Device Manager CRUD работает через REST API
- [ ] Redis содержит актуальные данные устройств
- [ ] Kafka топики корректно настроены
- [ ] Unit тесты ≥ 60% для service layer
- [ ] Минимум 1 integration тест на сервис
- [ ] `hasRetranslation` флаг работает в pipeline

---

**Версия:** 2.0 (после полного аудита 12.02.2026)  
**Автор:** AI + Разработчик  
**Связано:** [ARCHITECTURE_BLOCK1.md](ARCHITECTURE_BLOCK1.md), [CONNECTION_MANAGER.md](services/CONNECTION_MANAGER.md), [DEVICE_MANAGER.md](services/DEVICE_MANAGER.md), [HISTORY_WRITER.md](services/HISTORY_WRITER.md), [DATA_STORES.md](DATA_STORES.md)
