# 📖 План изучения проекта Wayrecall Tracker

> Тег: `АКТУАЛЬНО` | Обновлён: `2025-06-02` | Версия: `1.0`

---

## Содержание

1. [Обзор системы](#1-обзор-системы)
2. [Рекомендуемый порядок изучения](#2-рекомендуемый-порядок-изучения)
3. [Общие архитектурные принципы (читать первым!)](#3-общие-архитектурные-принципы)
4. [Block 1 — Data Collection](#4-block-1--data-collection)
   - [4.1 Connection Manager (TCP + GPS протоколы)](#41-connection-manager)
   - [4.2 Device Manager (REST API + CRUD устройств)](#42-device-manager)
   - [4.3 History Writer (Kafka → TimescaleDB)](#43-history-writer)
5. [Block 2 — Business Logic](#5-block-2--business-logic)
   - [5.1 Rule Checker (геозоны + скорость)](#51-rule-checker)
   - [5.2 Notification Service (уведомления)](#52-notification-service)
   - [5.3 Analytics Service (отчёты)](#53-analytics-service)
   - [5.4 User Service (пользователи + права)](#54-user-service)
   - [5.5 Admin Service (администрирование)](#55-admin-service)
   - [5.6 Integration Service (ретрансляция)](#56-integration-service)
   - [5.7 Maintenance Service (ТО)](#57-maintenance-service)
   - [5.8 Sensors Service (датчики)](#58-sensors-service)
6. [Block 3 — Presentation](#6-block-3--presentation)
   - [6.1 WebSocket Service (real-time)](#61-websocket-service)
   - [6.2 API Gateway (прокси + JWT)](#62-api-gateway)
   - [6.3 Web Frontend (React + OpenLayers)](#63-web-frontend)
   - [6.4 Web Billing (React — биллинг)](#64-web-billing)
7. [Сквозные паттерны (cross-cutting)](#7-сквозные-паттерны)
8. [Инфраструктура](#8-инфраструктура)
9. [Legacy Stels (справочный материал)](#9-legacy-stels)
10. [Упражнения и контрольные вопросы](#10-упражнения-и-контрольные-вопросы)
11. [Сводная таблица сервисов](#11-сводная-таблица-сервисов)

---

## 1. Обзор системы

**Wayrecall Tracker** — GPS-система реального времени для мониторинга транспорта. Архитектура: 15 микросервисов, разделённых на 3 блока:

```
┌─────────────────────────────────────────────────────────────┐
│                  Block 3 — PRESENTATION                     │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────────┐│
│  │Web Frontend│  │  API Gateway │  │  WebSocket Service   ││
│  │(React+OL)  │→ │(JWT + Proxy) │→ │(Kafka → WS clients) ││
│  └────────────┘  └──────┬───────┘  └──────────────────────┘│
└─────────────────────────┼──────────────────────────────────┘
                          │
┌─────────────────────────┼──────────────────────────────────┐
│                  Block 2 — BUSINESS LOGIC                   │
│  ┌──────────┐ ┌────────┐ ┌──────────┐ ┌──────────────────┐│
│  │Rule      │ │Notif.  │ │Analytics │ │User Service      ││
│  │Checker   │ │Service │ │Service   │ │(RBAC + компании) ││
│  └──────────┘ └────────┘ └──────────┘ └──────────────────┘│
│  ┌──────────┐ ┌────────┐ ┌──────────┐ ┌──────────────────┐│
│  │Admin     │ │Integr. │ │Mainten.  │ │Sensors Service   ││
│  │Service   │ │Service │ │Service   │ │(калибровка)      ││
│  └──────────┘ └────────┘ └──────────┘ └──────────────────┘│
└───────────────────────┬────────────────────────────────────┘
                        │ Kafka
┌───────────────────────┼────────────────────────────────────┐
│                  Block 1 — DATA COLLECTION                  │
│  ┌──────────────────┐ ┌──────────────┐ ┌────────────────┐ │
│  │Connection Manager│ │Device Manager│ │History Writer   │ │
│  │(TCP + GPS parse) │ │(REST + CRUD) │ │(Kafka→Timescale)│ │
│  └──────────────────┘ └──────────────┘ └────────────────┘ │
└────────────────────────────────────────────────────────────┘
```

**Стек:** Scala 3.4 + ZIO 2 + Netty + zio-http + zio-kafka + Doobie + TimescaleDB + PostGIS + Redis + React + TypeScript + OpenLayers

**Статистика:** 313 source файлов, 39 тестов, 15 сервисов

---

## 2. Рекомендуемый порядок изучения

### Фаза 0: Идеология и принципы (1-2 часа)

| # | Что изучить | Зачем |
|---|---|---|
| 0.1 | [.github/copilot-instructions.md](../.github/copilot-instructions.md) | Все правила проекта: именование, пакеты, ФП, multi-tenant |
| 0.2 | [docs/ARCHITECTURE.md](ARCHITECTURE.md) | Общая архитектура 3 блоков |
| 0.3 | [docs/ARCHITECTURE_BLOCK1.md](ARCHITECTURE_BLOCK1.md) | Data Collection — самый фундаментальный блок |
| 0.4 | [docs/DATA_STORES.md](DATA_STORES.md) | TimescaleDB, PostGIS, PostgreSQL, Redis |

### Фаза 1: Block 1 — Data Collection (4-6 часов)

| # | Сервис | Акцент | Почему первый |
|---|---|---|---|
| 1.1 | **Connection Manager** | TCP, Netty, парсеры протоколов, фильтры, Kafka producer | Точка входа данных. ВСЁ начинается здесь |
| 1.2 | **Device Manager** | REST API, Doobie, PostgreSQL, CRUD | Первый REST-сервис в системе |
| 1.3 | **History Writer** | Kafka consumer, TimescaleDB, batch insert | Замыкает цикл: данные записаны, можно читать |

### Фаза 2: Block 2 — Business Logic (6-8 часов)

| # | Сервис | Акцент | Зависимости от |
|---|---|---|---|
| 2.1 | **Rule Checker** | PostGIS, пространственный индекс, Kafka consumer+producer | GPS-точки из CM |
| 2.2 | **Sensors Service** | IO-параметры, калибровка, медианный фильтр | GPS-точки из CM |
| 2.3 | **Maintenance Service** | Пробег, расписания, напоминания | Пробег из Analytics |
| 2.4 | **Notification Service** | Мультиканал, шаблоны, троттлинг | События из RC/MS |
| 2.5 | **Analytics Service** | Алгоритмы поездок, экспорт PDF/Excel/CSV | GPS-история из HW |
| 2.6 | **User Service** | RBAC, компании, аудит, группы ТС | Фундамент безопасности |
| 2.7 | **Integration Service** | Circuit Breaker, Wialon, webhooks, retry | GPS-точки для ретрансляции |
| 2.8 | **Admin Service** | Мониторинг, фоновые задачи, статистика | Все сервисы |

### Фаза 3: Block 3 — Presentation (3-4 часа)

| # | Сервис | Акцент |
|---|---|---|
| 3.1 | **WebSocket Service** | Kafka → WS broadcast, подписки, троттлинг |
| 3.2 | **API Gateway** | JWT, CORS, proxy, маршрутизация к 13 бэкендам |
| 3.3 | **Web Frontend** | React + OpenLayers, store, модальные окна |
| 3.4 | **Web Billing** | React, Zustand, панели администрирования |

### Фаза 4: Инфраструктура и Legacy (2-3 часа)

| # | Что |
|---|---|
| 4.1 | Kafka топики, Redis ключи, Docker Compose |
| 4.2 | Legacy Stels — как парсеры работали раньше |

**Итого: ~15-21 час** на полное погружение.

---

## 3. Общие архитектурные принципы

### 3.1 Структура каждого Scala-сервиса

Все 13 Scala-сервисов следуют **одинаковой** структуре пакетов:

```
com.wayrecall.tracker.[serviceName]/
├── Main.scala           # Точка входа, сборка ZIO Layers
├── domain/              # Sealed traits, case classes, ошибки
│   ├── Models.scala     # или Entities.scala — доменные модели
│   └── Errors.scala     # Типизированные ошибки (sealed trait)
├── config/
│   └── AppConfig.scala  # HOCON конфигурация (deriveConfig)
├── api/
│   ├── HealthRoutes.scala   # GET /health (обязателен)
│   └── *Routes.scala        # REST эндпоинты
├── service/             # Бизнес-логика (чистые ZIO эффекты)
├── repository/          # SQL через Doobie
├── infrastructure/
│   └── TransactorLayer.scala  # Doobie Transactor ZIO Layer
├── kafka/               # Consumer/Producer
├── cache/ или redis/    # Redis-клиент
└── ...                  # Специфичные для сервиса пакеты
```

### 3.2 Паттерн Main.scala

Каждый `Main.scala` собирает приложение как **композицию ZIO Layers**:

```scala
object Main extends ZIOAppDefault:
  override def run =
    (for {
      config <- ZIO.service[AppConfig]
      _      <- ZIO.logInfo(s"Сервис запущен на порту ${config.server.port}")
      _      <- Server.serve(routes)
    } yield ())
      .provide(
        AppConfig.live,           // Конфигурация
        TransactorLayer.live,     // БД
        SomeRepository.live,      // Репозиторий
        SomeService.live,         // Бизнес-логика
        SomeRoutes.live,          // HTTP маршруты
        Server.defaultWithPort    // HTTP сервер
      )
```

### 3.3 Паттерн ошибок (sealed trait)

```scala
sealed trait ServiceError
case class NotFound(entity: String, id: Long) extends ServiceError
case class ValidationError(msg: String) extends ServiceError
case class DatabaseError(cause: Throwable) extends ServiceError
```

Никогда `throw` — только `ZIO.fail(NotFound(...))`.

### 3.4 Паттерн Kafka Consumer

```scala
// Потребляем из топика → обрабатываем → коммитим offset
Consumer
  .plainStream(Subscription.topics("gps-events"), Serde.string, Serde.string)
  .mapZIO(record => processRecord(record.value))
  .map(_.offset)
  .aggregateAsync(Consumer.offsetBatches)
```

### 3.5 Multi-tenant изоляция

**КАЖДЫЙ** SQL-запрос содержит `WHERE organization_id = ?`. Без этого — data leak.

---

## 4. Block 1 — Data Collection

> Это фундамент системы. GPS-трекеры отправляют данные → CM парсит → Kafka → HW записывает в TimescaleDB.

### 4.1 Connection Manager

**Расположение:** `services/connection-manager/`
**Пакет:** `com.wayrecall.tracker`
**Исходники:** 49 | **Тесты:** 28
**Порт:** TCP 5001-5004, API 10090

#### Что делает

Самый сложный сервис. Принимает TCP-соединения от GPS-трекеров 18 разных производителей, парсит бинарные/текстовые протоколы, фильтрует фантомные точки, публикует валидные GPS-точки в Kafka.

#### Порядок изучения классов

**Шаг 1 — Точка входа и конфигурация:**

| Класс | Что изучить |
|---|---|
| [Main.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/Main.scala) | Сборка всех ZIO Layers, порядок инициализации |
| [config/AppConfig.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/config/AppConfig.scala) | HOCON конфигурация: порты TCP, Kafka, Redis, таймауты |
| [config/DynamicConfigService.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/config/DynamicConfigService.scala) | Горячее обновление конфигурации без рестарта |

**Шаг 2 — Доменная модель (что парсим и отдаём):**

| Класс | Что изучить |
|---|---|
| [domain/GpsPoint.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/domain/GpsPoint.scala) | Главная сущность: широта, долгота, скорость, время, IO-параметры |
| [domain/Protocol.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/domain/Protocol.scala) | Enum всех 18 поддерживаемых GPS-протоколов |
| [domain/Command.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/domain/Command.scala) | Команды для трекеров (блокировка, перезагрузка, интервал) |
| [domain/ParseError.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/domain/ParseError.scala) | Типизированные ошибки парсинга |
| [domain/Vehicle.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/domain/Vehicle.scala) | Связь IMEI → vehicleId → organizationId |

**Шаг 3 — Сетевой слой (TCP-сервер):**

| Класс | Что изучить |
|---|---|
| [network/TcpServer.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/network/TcpServer.scala) | Netty TCP сервер: биндинг портов, pipeline, child handlers |
| [network/ConnectionHandler.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/network/ConnectionHandler.scala) | **КЛЮЧЕВОЙ КЛАСС.** Обработка каждого TCP-соединения: приём байтов → парсинг → фильтрация → Kafka |
| [network/ConnectionRegistry.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/network/ConnectionRegistry.scala) | In-memory реестр всех TCP-соединений (IMEI → Channel) |
| [network/RateLimiter.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/network/RateLimiter.scala) | Token Bucket: защита от DDoS/флуда трекеров |
| [network/IdleConnectionWatcher.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/network/IdleConnectionWatcher.scala) | Закрытие неактивных соединений (экономия ресурсов) |
| [network/CommandService.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/network/CommandService.scala) | Отправка команд на подключённые трекеры через TCP |
| [network/DeviceConfigListener.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/network/DeviceConfigListener.scala) | Слушатель изменений конфигурации устройств |

**Шаг 4 — Парсеры протоколов (18 штук):**

| Класс | Протокол | Формат |
|---|---|---|
| [protocol/ProtocolParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/ProtocolParser.scala) | **Базовый trait** — все парсеры его реализуют | — |
| [protocol/MultiProtocolParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/MultiProtocolParser.scala) | **Диспетчер** — определяет протокол по первым байтам и делегирует | — |
| [protocol/TeltonikaParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/TeltonikaParser.scala) | Teltonika Codec 8/8E | Бинарный |
| [protocol/WialonParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/WialonParser.scala) | Wialon IPS | Текстовый |
| [protocol/WialonBinaryParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/WialonBinaryParser.scala) | Wialon Binary | Бинарный |
| [protocol/WialonAdapterParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/WialonAdapterParser.scala) | Wialon Adapter | Текстовый |
| [protocol/RuptelaParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/RuptelaParser.scala) | Ruptela | Бинарный |
| [protocol/NavTelecomParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/NavTelecomParser.scala) | NavTelecom FLEX | Бинарный |
| [protocol/GalileoskyParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/GalileoskyParser.scala) | Galileosky | Бинарный |
| [protocol/ConcoxParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/ConcoxParser.scala) | Concox | Бинарный |
| [protocol/DtmParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/DtmParser.scala) | DTM | Бинарный |
| [protocol/AdmParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/AdmParser.scala) | ADM | Бинарный |
| [protocol/ArnaviParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/ArnaviParser.scala) | Arnavi | Бинарный |
| [protocol/AutophoneMayakParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/AutophoneMayakParser.scala) | Autophone/Mayak | Бинарный |
| [protocol/GoSafeParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/GoSafeParser.scala) | GoSafe | Текстовый |
| [protocol/GtltParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/GtltParser.scala) | GTLT | Бинарный |
| [protocol/MicroMayakParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/MicroMayakParser.scala) | MicroMayak | Бинарный |
| [protocol/SkySimParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/SkySimParser.scala) | SkySim | Бинарный |
| [protocol/TK102Parser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/TK102Parser.scala) | TK102/TK103 | Текстовый |
| [protocol/DebugProtocolParser.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/protocol/DebugProtocolParser.scala) | Debug (для разработки) | Текстовый |

> **Совет:** начни с `TeltonikaParser` — это самый популярный GPS-трекер. Потом `WialonParser` (текстовый — проще понять). Базу даст `ProtocolParser` trait.

**Шаг 5 — Фильтры GPS-точек:**

| Класс | Что делает |
|---|---|
| [filter/DeadReckoningFilter.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/filter/DeadReckoningFilter.scala) | Отбрасывает фантомные координаты (GPS дрейф, прыжки) |
| [filter/StationaryFilter.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/filter/StationaryFilter.scala) | Подавляет GPS-шум когда машина стоит |

**Шаг 6 — Команды на трекеры:**

| Класс | Что делает |
|---|---|
| [command/CommandEncoder.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/command/CommandEncoder.scala) | Базовый trait — формирует байты команды для отправки |
| [command/TeltonikaEncoder.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/command/TeltonikaEncoder.scala) | Кодирование команд для Teltonika |
| [command/WialonEncoder.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/command/WialonEncoder.scala) | Кодирование команд для Wialon |
| [command/RuptelaEncoder.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/command/RuptelaEncoder.scala) | Кодирование команд для Ruptela |
| [command/NavTelecomEncoder.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/command/NavTelecomEncoder.scala) | Кодирование команд для NavTelecom |
| [command/DtmEncoder.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/command/DtmEncoder.scala) | Кодирование команд для DTM |

**Шаг 7 — Хранилища и Kafka:**

| Класс | Что делает |
|---|---|
| [storage/KafkaProducer.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/storage/KafkaProducer.scala) | Публикация GPS-точек в `gps-events`, событий в `device-events` |
| [storage/RedisClient.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/storage/RedisClient.scala) | Контекст устройства, очереди команд, last position |
| [storage/DeviceRepository.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/storage/DeviceRepository.scala) | Поиск устройства по IMEI |
| [storage/VehicleLookupService.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/storage/VehicleLookupService.scala) | IMEI → Vehicle lookup с кэшированием |

**Шаг 8 — Сервисный слой:**

| Класс | Что делает |
|---|---|
| [service/CommandHandler.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/service/CommandHandler.scala) | Обработка входящих команд из Kafka/Redis |
| [service/DeviceEventConsumer.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/service/DeviceEventConsumer.scala) | Kafka consumer: события об устройствах |

**Шаг 9 — HTTP API:**

| Класс | Что делает |
|---|---|
| [api/HttpApi.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/api/HttpApi.scala) | Health check, метрики, admin endpoints (кол-во соединений и т.д.) |

#### Тесты (28 штук)

Самый протестированный сервис! Тесты покрывают:
- Все 18 парсеров протоколов (по тест-файлу на каждый)
- Оба фильтра (Dead Reckoning, Stationary)
- Все 6 кодировщиков команд
- ConnectionRegistry, RateLimiter
- HTTP API

#### Граф данных (Data Flow)

```
GPS Трекер → [TCP:5001-5004] → TcpServer → ConnectionHandler
    → MultiProtocolParser → [TeltonikaParser|WialonParser|...]
    → DeadReckoningFilter → StationaryFilter
    → KafkaProducer → [topic: gps-events]
```

---

### 4.2 Device Manager

**Расположение:** `services/device-manager/`
**Пакет:** `com.wayrecall.device`
**Исходники:** 13 | **Тесты:** 3
**Порт:** 10092

#### Что делает

REST API для управления устройствами (трекерами), организациями, отправки команд. Это "мастер-данные" системы: кто какой трекер использует, к какой организации он привязан.

#### Порядок изучения классов

**Шаг 1 — Домен:**

| Класс | Что изучить |
|---|---|
| [domain/Entities.scala](../services/device-manager/src/main/scala/com/wayrecall/device/domain/Entities.scala) | Device, Organization, VehicleType — центральные сущности всей системы |
| [domain/Errors.scala](../services/device-manager/src/main/scala/com/wayrecall/device/domain/Errors.scala) | DeviceNotFound, ImeiConflict, OrgNotFound — типизированные ошибки |
| [domain/Events.scala](../services/device-manager/src/main/scala/com/wayrecall/device/domain/Events.scala) | DeviceCreated, CommandSent — события для Kafka |

**Шаг 2 — Бизнес-логика:**

| Класс | Что изучить |
|---|---|
| [service/DeviceService.scala](../services/device-manager/src/main/scala/com/wayrecall/device/service/DeviceService.scala) | CRUD устройств, отправка команд, привязка к организации |

**Шаг 3 — Инфраструктура:**

| Класс | Что изучить |
|---|---|
| [repository/DeviceRepository.scala](../services/device-manager/src/main/scala/com/wayrecall/device/repository/DeviceRepository.scala) | Doobie SQL-запросы: INSERT/UPDATE/SELECT/DELETE устройств |
| [infrastructure/KafkaPublisher.scala](../services/device-manager/src/main/scala/com/wayrecall/device/infrastructure/KafkaPublisher.scala) | Публикация событий устройств в Kafka |
| [infrastructure/RedisSyncService.scala](../services/device-manager/src/main/scala/com/wayrecall/device/infrastructure/RedisSyncService.scala) | Синхронизация данных устройств в Redis для быстрого lookup в CM |
| [infrastructure/TransactorLayer.scala](../services/device-manager/src/main/scala/com/wayrecall/device/infrastructure/TransactorLayer.scala) | Паттерн: как создаётся Doobie Transactor в ZIO |
| [consumer/UnknownDeviceConsumer.scala](../services/device-manager/src/main/scala/com/wayrecall/device/consumer/UnknownDeviceConsumer.scala) | Kafka consumer: когда CM получает данные от незарегистрированного IMEI |

**Шаг 4 — API:**

| Класс | Что изучить |
|---|---|
| [api/DeviceRoutes.scala](../services/device-manager/src/main/scala/com/wayrecall/device/api/DeviceRoutes.scala) | REST API: GET/POST/PUT/DELETE /devices, POST /commands |
| [api/HealthRoutes.scala](../services/device-manager/src/main/scala/com/wayrecall/device/api/HealthRoutes.scala) | GET /health |

#### Граф данных

```
REST Client → DeviceRoutes → DeviceService → DeviceRepository (PostgreSQL)
                                           → KafkaPublisher → [topic: device-events]
                                           → RedisSyncService → Redis (device context)
```

---

### 4.3 History Writer

**Расположение:** `services/history-writer/`
**Пакет:** `com.wayrecall.history`
**Исходники:** 12 | **Тесты:** 4
**Порт:** 10091

#### Что делает

Kafka consumer, который читает GPS-точки из `gps-events` и batch-записывает их в TimescaleDB. Также предоставляет REST API для запроса истории маршрутов.

#### Порядок изучения классов

**Шаг 1 — Домен и конфигурация:**

| Класс | Что изучить |
|---|---|
| [domain/Entities.scala](../services/history-writer/src/main/scala/com/wayrecall/history/domain/Entities.scala) | TelemetryPoint, Track — структуры для хранения в TimescaleDB |
| [domain/Errors.scala](../services/history-writer/src/main/scala/com/wayrecall/history/domain/Errors.scala) | WriteError, QueryError |
| [domain/Events.scala](../services/history-writer/src/main/scala/com/wayrecall/history/domain/Events.scala) | Доменные события записи |

**Шаг 2 — Kafka → БД pipeline:**

| Класс | Что изучить |
|---|---|
| [consumer/TelemetryConsumer.scala](../services/history-writer/src/main/scala/com/wayrecall/history/consumer/TelemetryConsumer.scala) | **КЛЮЧЕВОЙ.** Kafka consumer: батчевое потребление GPS-точек |
| [repository/TelemetryRepository.scala](../services/history-writer/src/main/scala/com/wayrecall/history/repository/TelemetryRepository.scala) | Batch INSERT в TimescaleDB (Doobie + custom types) |
| [infrastructure/DoobieInstances.scala](../services/history-writer/src/main/scala/com/wayrecall/history/infrastructure/DoobieInstances.scala) | Маппинг Scala типов на TimescaleDB типы (timestamptz, geography) |

**Шаг 3 — API запроса истории:**

| Класс | Что изучить |
|---|---|
| [service/HistoryService.scala](../services/history-writer/src/main/scala/com/wayrecall/history/service/HistoryService.scala) | Запрос истории за период, пробег, поездки |
| [api/HistoryRoutes.scala](../services/history-writer/src/main/scala/com/wayrecall/history/api/HistoryRoutes.scala) | GET /history/:vehicleId?from=...&to=... |

#### Граф данных

```
Kafka [gps-events] → TelemetryConsumer → TelemetryRepository → TimescaleDB
REST Client → HistoryRoutes → HistoryService → TelemetryRepository → TimescaleDB
```

---

## 5. Block 2 — Business Logic

> Сервисы бизнес-логики получают данные из Kafka (от Block 1) и между собой, обрабатывают, генерируют события и уведомления.

### 5.1 Rule Checker

**Расположение:** `services/rule-checker/`
**Пакет:** `com.wayrecall.tracker.rulechecker`
**Исходники:** 19 | **Тесты:** 0
**Порт:** 8093

#### Что делает

Проверяет каждую GPS-точку на нарушения: вход/выход из геозоны, превышение скорости. Использует PostGIS для пространственных запросов и in-memory `SpatialGrid` для быстрой проверки.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Entities.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/domain/Entities.scala) | Geozone (полигон, круг, маршрут), SpeedRule, ViolationEvent |
| 2 | [domain/Events.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/domain/Events.scala) | GeozoneViolation, SpeedViolation — JSON-схема событий |
| 3 | [kafka/GpsEventConsumer.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/kafka/GpsEventConsumer.scala) | Потребление GPS-точек из `gps-events` |
| 4 | [service/RuleCheckService.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/service/RuleCheckService.scala) | **Оркестратор:** точка → проверка всех правил |
| 5 | [service/GeozoneChecker.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/service/GeozoneChecker.scala) | ST_Contains, enter/leave логика |
| 6 | [service/SpeedChecker.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/service/SpeedChecker.scala) | Проверка скорости по правилам |
| 7 | [storage/SpatialGrid.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/storage/SpatialGrid.scala) | In-memory пространственный индекс (быстрая фильтрация) |
| 8 | [storage/VehicleStateManager.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/storage/VehicleStateManager.scala) | Текущее состояние ТС (в какой геозоне, скорость) |
| 9 | [repository/GeozoneRepository.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/repository/GeozoneRepository.scala) | PostGIS SQL: ST_Contains, ST_Distance |
| 10 | [api/GeozoneRoutes.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/api/GeozoneRoutes.scala) | CRUD геозон (REST API) |
| 11 | [api/SpeedRuleRoutes.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/api/SpeedRuleRoutes.scala) | CRUD правил скорости |
| 12 | [kafka/EventProducer.scala](../services/rule-checker/src/main/scala/com/wayrecall/tracker/rulechecker/kafka/EventProducer.scala) | Публикация нарушений в `violation-events` |

#### Граф данных

```
Kafka [gps-events] → GpsEventConsumer → RuleCheckService
    → GeozoneChecker (PostGIS + SpatialGrid)
    → SpeedChecker
    → EventProducer → [topic: violation-events]
```

---

### 5.2 Notification Service

**Расположение:** `services/notification-service/`
**Пакет:** `com.wayrecall.tracker.notifications`
**Исходники:** 24 | **Тесты:** 0
**Порт:** 8094

#### Что делает

Мультиканальная доставка уведомлений: Email, SMS, Push, Telegram, Webhook. Получает события нарушений из Kafka, сопоставляет с правилами пользователя, рендерит шаблон и отправляет.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Entities.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/domain/Entities.scala) | NotificationRule, Template, DeliveryRecord, Channel enum |
| 2 | [kafka/EventConsumer.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/kafka/EventConsumer.scala) | Потребление `violation-events` и `maintenance-events` |
| 3 | [service/NotificationOrchestrator.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/service/NotificationOrchestrator.scala) | **Главный pipeline:** событие → правило → шаблон → канал |
| 4 | [service/RuleMatcher.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/service/RuleMatcher.scala) | Какие правила применяются к данному событию |
| 5 | [service/TemplateEngine.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/service/TemplateEngine.scala) | Рендеринг шаблонов с подстановкой переменных |
| 6 | [channel/DeliveryService.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/channel/DeliveryService.scala) | Оркестратор доставки: выбор канала, retry, логирование |
| 7 | [channel/NotificationChannel.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/channel/NotificationChannel.scala) | Базовый trait для всех каналов |
| 8 | [channel/EmailChannel.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/channel/EmailChannel.scala) | SMTP отправка |
| 9 | [channel/SmsChannel.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/channel/SmsChannel.scala) | SMS через внешний API |
| 10 | [channel/TelegramChannel.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/channel/TelegramChannel.scala) | Telegram Bot API |
| 11 | [channel/PushChannel.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/channel/PushChannel.scala) | Push уведомления |
| 12 | [channel/WebhookChannel.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/channel/WebhookChannel.scala) | HTTP POST на URL клиента |
| 13 | [storage/ThrottleService.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/storage/ThrottleService.scala) | Redis-based троттлинг (не чаще X раз/мин) |
| 14 | [api/RuleRoutes.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/api/RuleRoutes.scala) | CRUD правил уведомлений |
| 15 | [api/TemplateRoutes.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/api/TemplateRoutes.scala) | CRUD шаблонов |
| 16 | [api/HistoryRoutes.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/api/HistoryRoutes.scala) | История отправленных уведомлений |

---

### 5.3 Analytics Service

**Расположение:** `services/analytics-service/`
**Пакет:** `com.wayrecall.tracker.analytics`
**Исходники:** 29 | **Тесты:** 0
**Порт:** 8095

#### Что делает

Самый большой по количеству файлов сервис Block 2. Генерирует отчёты (пробег, топливо, поездки, геозоны, скорость, простои), экспортирует в PDF/Excel/CSV. Есть планировщик автоматических отчётов.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Reports.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/domain/Reports.scala) | Модели отчётов: MileageReport, FuelReport, TripReport, etc. |
| 2 | [algorithm/TripDetector.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/algorithm/TripDetector.scala) | **Алгоритм:** определение поездок (старт когда скорость > X, стоп когда < Y) |
| 3 | [algorithm/MileageCalculator.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/algorithm/MileageCalculator.scala) | Расчёт пробега по GPS-точкам (Haversine formula) |
| 4 | [algorithm/FuelEventDetector.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/algorithm/FuelEventDetector.scala) | Обнаружение заправок и сливов топлива |
| 5 | [query/QueryEngine.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/query/QueryEngine.scala) | SQL к TimescaleDB: time_bucket, continuous aggregates |
| 6 | [generator/ReportGenerator.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/generator/ReportGenerator.scala) | Базовый trait генератора |
| 7 | [generator/MileageReportGenerator.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/generator/MileageReportGenerator.scala) | Отчёт по пробегу |
| 8 | [generator/FuelReportGenerator.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/generator/FuelReportGenerator.scala) | Отчёт по топливу |
| 9 | [generator/SpeedReportGenerator.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/generator/SpeedReportGenerator.scala) | Отчёт по скорости |
| 10 | [generator/GeozoneReportGenerator.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/generator/GeozoneReportGenerator.scala) | Отчёт по геозонам |
| 11 | [generator/IdleReportGenerator.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/generator/IdleReportGenerator.scala) | Отчёт по простоям |
| 12 | [generator/SummaryReportGenerator.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/generator/SummaryReportGenerator.scala) | Сводный отчёт |
| 13 | [exporting/ExportService.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/exporting/ExportService.scala) | Оркестратор экспорта: выбор формата |
| 14 | [exporting/PdfExporter.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/exporting/PdfExporter.scala) | Экспорт в PDF |
| 15 | [exporting/ExcelExporter.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/exporting/ExcelExporter.scala) | Экспорт в Excel |
| 16 | [exporting/CsvExporter.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/exporting/CsvExporter.scala) | Экспорт в CSV |
| 17 | [scheduler/ReportScheduler.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/scheduler/ReportScheduler.scala) | Планировщик автоотчётов (CRON-подобный) |
| 18 | [cache/ReportCache.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/cache/ReportCache.scala) | Redis-кэш готовых отчётов |
| 19 | [api/ReportRoutes.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/api/ReportRoutes.scala) | REST: генерация отчётов |
| 20 | [api/ExportRoutes.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/api/ExportRoutes.scala) | REST: скачивание экспортов |
| 21 | [api/ScheduledRoutes.scala](../services/analytics-service/src/main/scala/com/wayrecall/tracker/analytics/api/ScheduledRoutes.scala) | REST: управление расписанием |

---

### 5.4 User Service

**Расположение:** `services/user-service/`
**Пакет:** `com.wayrecall.tracker.users`
**Исходники:** 20 | **Тесты:** 0
**Порт:** 8091

#### Что делает

Управление пользователями, ролями, компаниями, группами ТС и правами доступа. Фундамент безопасности — именно этот сервис определяет кто что может.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Models.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/domain/Models.scala) | User, Role, Company, Permission, VehicleGroup |
| 2 | [service/UserService.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/service/UserService.scala) | CRUD пользователей, назначение ролей |
| 3 | [service/PermissionService.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/service/PermissionService.scala) | Проверка прав: `hasPermission(userId, action, resource)` |
| 4 | [service/RoleService.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/service/RoleService.scala) | CRUD ролей, назначение permissions |
| 5 | [service/CompanyService.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/service/CompanyService.scala) | Управление организациями (multi-tenant) |
| 6 | [service/GroupService.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/service/GroupService.scala) | Группы ТС (видимость автомобилей для пользователя) |
| 7 | [service/AuditService.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/service/AuditService.scala) | Аудит действий: кто что изменил |
| 8 | [cache/PermissionCache.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/cache/PermissionCache.scala) | Redis-кэш прав (инвалидация при изменении) |
| 9 | [repository/UserRepository.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/repository/UserRepository.scala) | SQL: пользователи |
| 10 | [repository/RoleRepository.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/repository/RoleRepository.scala) | SQL: роли |
| 11 | [repository/CompanyRepository.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/repository/CompanyRepository.scala) | SQL: организации |
| 12 | [repository/AuditRepository.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/repository/AuditRepository.scala) | SQL: аудит-лог |
| 13 | [repository/VehicleGroupRepository.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/repository/VehicleGroupRepository.scala) | SQL: группы ТС |
| 14 | [api/UserRoutes.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/api/UserRoutes.scala) | REST: CRUD пользователей |
| 15 | [api/ManagementRoutes.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/api/ManagementRoutes.scala) | REST: управление компаниями, ролями |

---

### 5.5 Admin Service

**Расположение:** `services/admin-service/`
**Пакет:** `com.wayrecall.tracker.admin`
**Исходники:** 13 | **Тесты:** 0
**Порт:** 8097

#### Что делает

Системное администрирование: мониторинг здоровья всех сервисов, управление конфигурацией, просмотр статистики, фоновые задачи, аудит.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Models.scala](../services/admin-service/src/main/scala/com/wayrecall/tracker/admin/domain/Models.scala) | SystemStats, AuditEvent, ServiceHealth |
| 2 | [service/SystemMonitorService.scala](../services/admin-service/src/main/scala/com/wayrecall/tracker/admin/service/SystemMonitorService.scala) | Ping всех сервисов, агрегация health check |
| 3 | [service/StatsService.scala](../services/admin-service/src/main/scala/com/wayrecall/tracker/admin/service/StatsService.scala) | Системная статистика: кол-во устройств, точек/сек, Kafka lag |
| 4 | [service/ConfigService.scala](../services/admin-service/src/main/scala/com/wayrecall/tracker/admin/service/ConfigService.scala) | Управление runtime-конфигурацией |
| 5 | [service/BackgroundTaskService.scala](../services/admin-service/src/main/scala/com/wayrecall/tracker/admin/service/BackgroundTaskService.scala) | Управление фоновыми задачами (cleanup, archiving) |
| 6 | [service/CompanyAdminService.scala](../services/admin-service/src/main/scala/com/wayrecall/tracker/admin/service/CompanyAdminService.scala) | Суперадмин операции (блокировка компаний, квоты) |
| 7 | [service/AdminAuditService.scala](../services/admin-service/src/main/scala/com/wayrecall/tracker/admin/service/AdminAuditService.scala) | Аудит системных действий |
| 8 | [api/AdminRoutes.scala](../services/admin-service/src/main/scala/com/wayrecall/tracker/admin/api/AdminRoutes.scala) | REST: все admin endpoints |

---

### 5.6 Integration Service

**Расположение:** `services/integration-service/`
**Пакет:** `com.wayrecall.tracker.integration`
**Исходники:** 22 | **Тесты:** 0
**Порт:** 8096

#### Что делает

Ретрансляция GPS-данных во внешние системы (Wialon, webhooks), приём данных от внешних систем (Inbound API). Реализует Circuit Breaker и Retry с exponential backoff.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Models.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/domain/Models.scala) | WialonConfig, WebhookConfig, ApiKey, IntegrationStatus |
| 2 | [kafka/EventConsumer.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/kafka/EventConsumer.scala) | Потребление GPS-точек для ретрансляции |
| 3 | [router/IntegrationRouter.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/router/IntegrationRouter.scala) | Маршрутизация: какие точки куда отправлять |
| 4 | [wialon/WialonIpsProtocol.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/wialon/WialonIpsProtocol.scala) | Формирование пакетов Wialon IPS протокола |
| 5 | [wialon/WialonSender.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/wialon/WialonSender.scala) | TCP-клиент Wialon |
| 6 | [webhook/WebhookSender.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/webhook/WebhookSender.scala) | HTTP POST на URL клиента |
| 7 | [circuit/CircuitBreaker.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/circuit/CircuitBreaker.scala) | **Паттерн Circuit Breaker:** open/half-open/closed |
| 8 | [retry/RetryService.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/retry/RetryService.scala) | **Паттерн Retry:** exponential backoff с jitter |
| 9 | [inbound/InboundService.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/inbound/InboundService.scala) | Приём данных от внешних систем |
| 10 | [inbound/ApiKeyValidator.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/inbound/ApiKeyValidator.scala) | Валидация API-ключей |
| 11 | [cache/IntegrationConfigCache.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/cache/IntegrationConfigCache.scala) | Redis-кэш конфигураций интеграций |
| 12 | [sync/RetranslationSyncService.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/sync/RetranslationSyncService.scala) | Синхронизация состояния ретрансляции |

---

### 5.7 Maintenance Service

**Расположение:** `services/maintenance-service/`
**Пакет:** `com.wayrecall.tracker.maintenance`
**Исходники:** 20 | **Тесты:** 0
**Порт:** 8087

#### Что делает

Плановое техническое обслуживание (ТО): расписания по пробегу/времени/моточасам, напоминания, история обслуживания.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Models.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/domain/Models.scala) | Schedule, ServiceRecord, Odometer, MaintenanceType |
| 2 | [kafka/MileageConsumer.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/kafka/MileageConsumer.scala) | Потребление обновлений пробега |
| 3 | [service/MileageTracker.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/service/MileageTracker.scala) | Отслеживание пробега каждого ТС |
| 4 | [service/IntervalCalculator.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/service/IntervalCalculator.scala) | Расчёт: через сколько км / дней следующее ТО |
| 5 | [service/MaintenancePlanner.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/service/MaintenancePlanner.scala) | Планирование предстоящих ТО |
| 6 | [service/ReminderEngine.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/service/ReminderEngine.scala) | Генерация напоминаний → Kafka → Notification Service |
| 7 | [service/MaintenanceService.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/service/MaintenanceService.scala) | CRUD расписаний и записей |
| 8 | [scheduler/MaintenanceJobs.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/scheduler/MaintenanceJobs.scala) | Фоновые задачи: ежедневная проверка расписаний |
| 9 | [cache/MaintenanceCache.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/cache/MaintenanceCache.scala) | Redis-кэш расписаний |
| 10 | [kafka/MaintenanceEventProducer.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/kafka/MaintenanceEventProducer.scala) | Публикация `maintenance-events` |
| 11 | [api/MaintenanceRoutes.scala](../services/maintenance-service/src/main/scala/com/wayrecall/tracker/maintenance/api/MaintenanceRoutes.scala) | REST: CRUD ТО, расписания |

---

### 5.8 Sensors Service

**Расположение:** `services/sensors-service/`
**Пакет:** `com.wayrecall.tracker.sensors`
**Исходники:** 19 | **Тесты:** 0
**Порт:** 8098

#### Что делает

Обработка данных датчиков (топливо, температура, напряжение): извлечение IO-параметров из GPS-пакетов, калибровка, обнаружение событий (слив/заправка), сглаживание шумов.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Models.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/domain/Models.scala) | Sensor, CalibrationTable, FuelEvent, SensorType enum |
| 2 | [kafka/GpsEventConsumer.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/kafka/GpsEventConsumer.scala) | Потребление GPS-точек с IO-параметрами |
| 3 | [processing/SensorProcessor.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/processing/SensorProcessor.scala) | **Оркестратор:** IoExtractor → Calibrator → Smoother → EventDetector |
| 4 | [processing/IoExtractor.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/processing/IoExtractor.scala) | Извлечение IO-параметров (ain1, din2, fuel_level и т.д.) |
| 5 | [processing/FuelCalibrator.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/processing/FuelCalibrator.scala) | Калибровка значений (ADC → литры по таблице) |
| 6 | [processing/Smoother.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/processing/Smoother.scala) | Медианный фильтр для сглаживания шумов |
| 7 | [processing/EventDetector.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/processing/EventDetector.scala) | Обнаружение заправок и сливов |
| 8 | [redis/SensorStateStore.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/redis/SensorStateStore.scala) | Redis: текущее состояние датчиков (скользящее окно) |
| 9 | [kafka/SensorEventProducer.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/kafka/SensorEventProducer.scala) | Публикация `sensor-events` |
| 10 | [api/SensorRoutes.scala](../services/sensors-service/src/main/scala/com/wayrecall/tracker/sensors/api/SensorRoutes.scala) | REST: CRUD датчиков, калибровки |

#### Граф обработки

```
Kafka [gps-events] → GpsEventConsumer → SensorProcessor
    → IoExtractor (вытаскиваем IO данные)
    → FuelCalibrator (ADC → литры)
    → Smoother (медианный фильтр)
    → EventDetector (слив/заправка)
    → SensorEventProducer → [topic: sensor-events]
```

---

## 6. Block 3 — Presentation

### 6.1 WebSocket Service

**Расположение:** `services/websocket-service/`
**Пакет:** `com.wayrecall.tracker.websocket`
**Исходники:** 12 | **Тесты:** 4
**Порт:** 8090

#### Что делает

Real-time доставка данных на Web Frontend через WebSocket: GPS-позиции, события геозон, нарушения скорости. Потребляет из Kafka, фильтрует по подпискам клиента.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [domain/Messages.scala](../services/websocket-service/src/main/scala/com/wayrecall/tracker/websocket/domain/Messages.scala) | JSON-протокол: Subscribe, Unsubscribe, GpsPosition, GeozoneEvent |
| 2 | [domain/Entities.scala](../services/websocket-service/src/main/scala/com/wayrecall/tracker/websocket/domain/Entities.scala) | Subscription, ClientSession |
| 3 | [api/WebSocketHandler.scala](../services/websocket-service/src/main/scala/com/wayrecall/tracker/websocket/api/WebSocketHandler.scala) | **КЛЮЧЕВОЙ.** WS handshake, upgrade, message routing |
| 4 | [service/ConnectionRegistry.scala](../services/websocket-service/src/main/scala/com/wayrecall/tracker/websocket/service/ConnectionRegistry.scala) | Реестр WS-клиентов: кто на что подписан |
| 5 | [service/MessageRouter.scala](../services/websocket-service/src/main/scala/com/wayrecall/tracker/websocket/service/MessageRouter.scala) | GPS-точка → найти подписчиков → отправить |
| 6 | [service/PositionThrottler.scala](../services/websocket-service/src/main/scala/com/wayrecall/tracker/websocket/service/PositionThrottler.scala) | Троттлинг: не чаще 1 позиции в секунду на ТС |
| 7 | [kafka/GpsEventConsumer.scala](../services/websocket-service/src/main/scala/com/wayrecall/tracker/websocket/kafka/GpsEventConsumer.scala) | Потребление GPS-точек |
| 8 | [kafka/EventConsumer.scala](../services/websocket-service/src/main/scala/com/wayrecall/tracker/websocket/kafka/EventConsumer.scala) | Потребление событий (нарушения, уведомления) |

---

### 6.2 API Gateway

**Расположение:** `services/api-gateway/` (или `services/API-Gateway/`)
**Пакет:** `com.wayrecall.gateway`
**Исходники:** 10 | **Тесты:** 0
**Порт:** 8080

#### Что делает

Единая точка входа для всех REST-запросов. JWT аутентификация, CORS, маршрутизация к 13 бэкенд-сервисам, rate limiting, health check агрегация.

#### Порядок изучения классов

| # | Класс | Что изучить |
|---|---|---|
| 1 | [config/GatewayConfig.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/config/GatewayConfig.scala) | Конфигурация: 13 сервисов, JWT секрет, CORS |
| 2 | [domain/Models.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/domain/Models.scala) | AuthToken, UserClaims, Role |
| 3 | [middleware/AuthMiddleware.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/middleware/AuthMiddleware.scala) | JWT валидация: извлечение claims, проверка expiration |
| 4 | [middleware/CorsMiddleware.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/middleware/CorsMiddleware.scala) | CORS заголовки (whitelist) |
| 5 | [middleware/LogMiddleware.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/middleware/LogMiddleware.scala) | Логирование всех HTTP-запросов |
| 6 | [routing/ApiRouter.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/routing/ApiRouter.scala) | **КЛЮЧЕВОЙ.** 24 маршрута → 13 бэкендов. Open, protected, admin routes |
| 7 | [service/AuthService.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/service/AuthService.scala) | Бизнес-логика JWT: issue, refresh, validate |
| 8 | [service/ProxyService.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/service/ProxyService.scala) | HTTP-прокси: переадресация запросов на бэкенд |
| 9 | [service/HealthService.scala](../services/API-Gateway/src/main/scala/com/wayrecall/gateway/service/HealthService.scala) | Агрегированный health check 13 сервисов |

---

### 6.3 Web Frontend

**Расположение:** `services/web-frontend/`
**Стек:** React 19 + TypeScript 5.9 + Vite 7 + TailwindCSS 4 + OpenLayers 10 + Zustand 5 + TanStack Query 5
**Исходники:** 25 | **Тесты:** 0
**Порт:** 3001

#### Что делает

Веб-интерфейс для мониторинга: карта с автомобилями в реальном времени, история маршрутов, геозоны, отчёты, уведомления, управление устройствами.

#### Порядок изучения

| # | Файл | Что изучить |
|---|---|---|
| 1 | [src/main.tsx](../services/web-frontend/src/main.tsx) | React root render |
| 2 | [src/App.tsx](../services/web-frontend/src/App.tsx) | Корневой layout, routing |
| 3 | [src/types/index.ts](../services/web-frontend/src/types/index.ts) | TypeScript-типы: Vehicle, GpsPoint, Geozone, Report |
| 4 | [src/store/appStore.ts](../services/web-frontend/src/store/appStore.ts) | **Zustand store:** состояние приложения (выбранное ТС, окна, фильтры) |
| 5 | [src/api/client.ts](../services/web-frontend/src/api/client.ts) | HTTP-клиент: JWT, авторизация, API-функции |
| 6 | [src/api/mock.ts](../services/web-frontend/src/api/mock.ts) | Mock-данные (806 строк — пока нет реальных API) |
| 7 | [src/hooks/useWebSocket.ts](../services/web-frontend/src/hooks/useWebSocket.ts) | React hook: WS подключение, подписки, reconnect |
| 8 | [src/components/AppLayout.tsx](../services/web-frontend/src/components/AppLayout.tsx) | Общий layout: toolbar + panels + map |
| 9 | [src/components/MapView.tsx](../services/web-frontend/src/components/MapView.tsx) | **OpenLayers карта:** отображение ТС, треков, геозон |
| 10 | [src/components/LeftPanel.tsx](../services/web-frontend/src/components/LeftPanel.tsx) | Дерево транспортных средств |
| 11 | [src/components/Toolbar.tsx](../services/web-frontend/src/components/Toolbar.tsx) | Верхний тулбар: отчёты, геозоны, уведомления |
| 12 | [src/components/WindowManager.tsx](../services/web-frontend/src/components/WindowManager.tsx) | Менеджер плавающих окон |
| 13 | [src/components/modals/ModalManager.tsx](../services/web-frontend/src/components/modals/ModalManager.tsx) | Менеджер модальных окон |
| 14 | [src/components/modals/GeozonesModal.tsx](../services/web-frontend/src/components/modals/GeozonesModal.tsx) | Управление геозонами |
| 15 | [src/components/modals/VehicleDetailsModal.tsx](../services/web-frontend/src/components/modals/VehicleDetailsModal.tsx) | Детали ТС: телеметрия, статус |
| 16 | [src/components/modals/MovingReportModal.tsx](../services/web-frontend/src/components/modals/MovingReportModal.tsx) | Отчёт по поездкам |
| 17 | [src/components/modals/NotificationRulesModal.tsx](../services/web-frontend/src/components/modals/NotificationRulesModal.tsx) | Настройка правил уведомлений |

---

### 6.4 Web Billing

**Расположение:** `services/web-billing/`
**Стек:** React + TypeScript
**Исходники:** 26 | **Тесты:** 0
**Порт:** 3002 (будет)

#### Что делает

Панель биллинга для дилеров: управление аккаунтами, оборудованием, тарифами, ролями, субдилерами.

#### Порядок изучения

| # | Файл | Что изучить |
|---|---|---|
| 1 | [src/App.tsx](../services/web-billing/src/App.tsx) | Корневой компонент |
| 2 | [src/store/billingStore.ts](../services/web-billing/src/store/billingStore.ts) | Zustand store: текущая вкладка, данные |
| 3 | [src/api/client.ts](../services/web-billing/src/api/client.ts) | HTTP-клиент |
| 4 | [src/api/types.ts](../services/web-billing/src/api/types.ts) | API-типы |
| 5 | [src/components/BillingApp.tsx](../services/web-billing/src/components/BillingApp.tsx) | Главный компонент биллинга |
| 6 | [src/components/AccountsPanel.tsx](../services/web-billing/src/components/AccountsPanel.tsx) | Панель аккаунтов |
| 7 | [src/components/TariffsPanel.tsx](../services/web-billing/src/components/TariffsPanel.tsx) | Панель тарифов |
| 8 | [src/components/GridPanel.tsx](../services/web-billing/src/components/GridPanel.tsx) | Универсальный табличный компонент (переиспользуется) |

---

## 7. Сквозные паттерны

Эти паттерны повторяются во всех сервисах. Изучи один раз — поймёшь везде.

### 7.1 ZIO Layer Dependency Injection

Каждый сервис собирается из ZIO Layers в `Main.scala`:
```
AppConfig.live >>> TransactorLayer.live >>> Repository.live >>> Service.live >>> Routes.live
```

**Где посмотреть лучший пример:** [History Writer Main.scala](../services/history-writer/src/main/scala/com/wayrecall/history/Main.scala) — самый чистый и понятный.

### 7.2 Doobie + PostgreSQL

SQL через Doobie = функциональный JDBC:
```scala
sql"SELECT * FROM devices WHERE organization_id = $orgId".query[Device].to[List]
```

**Где посмотреть:** [DeviceRepository.scala](../services/device-manager/src/main/scala/com/wayrecall/device/repository/DeviceRepository.scala) — классический CRUD.

### 7.3 Kafka Producer/Consumer

- **Producer:** [KafkaProducer.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/storage/KafkaProducer.scala) (CM)
- **Consumer:** [TelemetryConsumer.scala](../services/history-writer/src/main/scala/com/wayrecall/history/consumer/TelemetryConsumer.scala) (HW)

### 7.4 Redis Client

- **Контекст устройства:** [RedisClient.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/storage/RedisClient.scala) (CM)
- **Кэш прав:** [PermissionCache.scala](../services/user-service/src/main/scala/com/wayrecall/tracker/users/cache/PermissionCache.scala) (User Service)
- **Троттлинг:** [ThrottleService.scala](../services/notification-service/src/main/scala/com/wayrecall/tracker/notifications/storage/ThrottleService.scala) (Notification Service)

### 7.5 AppConfig (HOCON)

Все конфигурации через `zio-config + magnolia`, deriveConfig:
```scala
final case class AppConfig(server: ServerConfig, kafka: KafkaConfig, redis: RedisConfig)
object AppConfig:
  val live: ZLayer[Any, Config.Error, AppConfig] = ZLayer.fromZIO(...)
```

**Лучший пример:** [AppConfig.scala](../services/connection-manager/src/main/scala/com/wayrecall/tracker/config/AppConfig.scala) (CM — самый полный).

### 7.6 Health Endpoint

Каждый сервис имеет `GET /health`:
```scala
Method.GET / "health" -> handler(Response.json("""{"status":"ok"}"""))
```

### 7.7 Typed Errors (sealed trait)

```scala
sealed trait DeviceError
case class DeviceNotFound(id: Long) extends DeviceError
case class ImeiConflict(imei: String) extends DeviceError
```

Используется через `ZIO[R, DeviceError, A]`.

### 7.8 Circuit Breaker + Retry

**Эталон реализации:** [CircuitBreaker.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/circuit/CircuitBreaker.scala) и [RetryService.scala](../services/integration-service/src/main/scala/com/wayrecall/tracker/integration/retry/RetryService.scala) (Integration Service).

---

## 8. Инфраструктура

### 8.1 Docker Compose

| Файл | Что запускает |
|---|---|
| [docker-compose.yml](../docker-compose.yml) | Dev: PostgreSQL, TimescaleDB, Redis, Kafka, Zookeeper |
| [test-stand/docker-compose.prod.yml](../test-stand/docker-compose.prod.yml) | Prod-like: все сервисы + мониторинг |

### 8.2 Kafka

| Файл | Содержание |
|---|---|
| [infra/scripts/create-kafka-topics.sh](../infra/scripts/create-kafka-topics.sh) | Создание всех топиков |

**Основные топики:**
- `gps-events` — GPS-точки (CM → HW, RC, SS, IS, WS)
- `device-events` — события устройств (DM → CM)
- `violation-events` — нарушения (RC → NS, WS)
- `maintenance-events` — ТО напоминания (MS → NS)
- `sensor-events` — события датчиков (SS → NS, AS)

### 8.3 Базы данных

| Файл | Содержание |
|---|---|
| [infra/databases/timescaledb-init.sql](../infra/databases/timescaledb-init.sql) | Инициализация TimescaleDB: hypertables, retention, compression |

### 8.4 Скрипты

| Скрипт | Что делает |
|---|---|
| [infra/scripts/start-dev.sh](../infra/scripts/start-dev.sh) | Запуск dev-окружения |
| [infra/scripts/stop-all.sh](../infra/scripts/stop-all.sh) | Остановка всего |
| [infra/scripts/health-check.sh](../infra/scripts/health-check.sh) | Проверка здоровья всех сервисов |
| [infra/scripts/init-all.sh](../infra/scripts/init-all.sh) | Полная инициализация |

---

## 9. Legacy Stels

**Расположение:** `legacy-stels/`
**Стек:** Java 8 + Spring MVC + Hibernate + ExtJS
**Назначение:** ТОЛЬКО для справки при переносе бизнес-логики!

### Что полезно изучить

| Файл/Папка | Зачем |
|---|---|
| `legacy-stels/core/` | Парсеры протоколов на Java — для сверки с Scala-реализацией |
| `legacy-stels/packreceiver/` | TCP-сервер — архитектурный предшественник CM |
| `legacy-stels/monitoring/` | Веб-приложение — ExtJS UI, логика отчётов |
| [docs/LEGACY_API.md](LEGACY_API.md) | 78 методов старого API — для полноты миграции |
| [docs/STELS_GEOZONE_ANALYSIS.md](STELS_GEOZONE_ANALYSIS.md) | Анализ геозон — критично для Rule Checker |

> **ВАЖНО:** не копировать код из legacy! Только анализировать бизнес-логику и переписывать на Scala 3 + ZIO 2.

---

## 10. Упражнения и контрольные вопросы

### Уровень 1 — Понимание архитектуры

1. Нарисуй на бумаге путь GPS-точки от трекера до экрана пользователя (все сервисы, все Kafka-топики).
2. Где хранится маппинг IMEI → vehicleId → organizationId? Какие сервисы его используют?
3. Что произойдёт если Redis упал? Какой сервис пострадает первым и почему?

### Уровень 2 — Код

4. Открой `TeltonikaParser.scala` — найди где читается количество точек из бинарного пакета.
5. Открой `ConnectionHandler.scala` — проследи путь от `channelRead()` до `kafkaProducer.publish()`.
6. Открой `ApiRouter.scala` — найди как определяется, на какой бэкенд перенаправить запрос.

### Уровень 3 — Продвинутый

7. Как работает `DeadReckoningFilter`? Какие точки он отбрасывает и почему?
8. Как работает Circuit Breaker в Integration Service? Нарисуй state machine.
9. Как обеспечивается порядок команд для одного трекера? (подсказка: Kafka partitioning)

### Уровень 4 — Проектирование

10. Представь что нужно добавить новый GPS-протокол "SuperTracker Pro". Какие файлы нужно создать/изменить?
11. Представь что Notification Service должен поддерживать Viber. Какие классы нужно добавить?
12. Как добавить новый тип отчёта "Отчёт по простоям с топливом" в Analytics Service?

---

## 11. Сводная таблица сервисов

| # | Сервис | Пакет | Src | Tests | Порт | DB | Kafka | Redis |
|---|---|---|---|---|---|---|---|---|
| 1 | Connection Manager | `com.wayrecall.tracker` | 49 | 28 | TCP:5001-5004, API:10090 | — | produce: gps-events, device-events | device context, commands |
| 2 | Device Manager | `com.wayrecall.device` | 13 | 3 | 10092 | PostgreSQL | produce: device-events; consume: unknown-devices | device sync |
| 3 | History Writer | `com.wayrecall.history` | 12 | 4 | 10091 | TimescaleDB | consume: gps-events | — |
| 4 | Rule Checker | `com.wayrecall.tracker.rulechecker` | 19 | 0 | 8093 | PostGIS | consume: gps-events; produce: violation-events | vehicle state |
| 5 | Notification Service | `com.wayrecall.tracker.notifications` | 24 | 0 | 8094 | PostgreSQL | consume: violation/maintenance-events | throttle |
| 6 | Analytics Service | `com.wayrecall.tracker.analytics` | 29 | 0 | 8095 | TimescaleDB | — | report cache |
| 7 | User Service | `com.wayrecall.tracker.users` | 20 | 0 | 8091 | PostgreSQL | — | permission cache |
| 8 | Admin Service | `com.wayrecall.tracker.admin` | 13 | 0 | 8097 | PostgreSQL | — | — |
| 9 | Integration Service | `com.wayrecall.tracker.integration` | 22 | 0 | 8096 | PostgreSQL | consume: gps-events | config cache |
| 10 | Maintenance Service | `com.wayrecall.tracker.maintenance` | 20 | 0 | 8087 | PostgreSQL | consume: mileage; produce: maintenance-events | schedule cache |
| 11 | Sensors Service | `com.wayrecall.tracker.sensors` | 19 | 0 | 8098 | PostgreSQL | consume: gps-events; produce: sensor-events | sensor state |
| 12 | WebSocket Service | `com.wayrecall.tracker.websocket` | 12 | 4 | 8090 | — | consume: gps-events, events | — |
| 13 | API Gateway | `com.wayrecall.gateway` | 10 | 0 | 8080 | — | — | — |
| 14 | Web Billing | — (React) | 26 | 0 | 3002 | — | — | — |
| 15 | Web Frontend | — (React) | 25 | 0 | 3001 | — | — | — |
| **Итого** | | | **313** | **39** | | | | |

---

*Версия: 1.0 | Обновлён: 2 июня 2025 | Тег: АКТУАЛЬНО*
