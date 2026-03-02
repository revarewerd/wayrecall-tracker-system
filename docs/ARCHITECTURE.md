# 🏗️ Архитектура Wayrecall Tracker System

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-02` | Версия: `4.0`

---

## 📋 Обзор

Микросервисная GPS-система реального времени для мониторинга транспорта.  
**14 сервисов** (12 Scala 3 + ZIO 2, 2 React/TypeScript).

**Стек:** Scala 3.4.0 + ZIO 2.0.20 + Kafka + TimescaleDB + PostGIS + Redis (lettuce)

> **Redis (2026-06-02):** `zio-redis` несовместим. Connection Manager и API Gateway используют **lettuce-core 6.3.2**.
> Остальные 7 сервисов используют **ZIO Ref** (in-memory) — допустимо для MVP.
> Подробнее: [REDIS_VS_REF_DECISION.md](./REDIS_VS_REF_DECISION.md)
>
> Версии зависимостей: zio-kafka **2.7.3**, zio-logging **2.1.16**, doobie **1.0.0-RC4**, zio-http **3.0.0-RC4** / **3.0.1**.

**Целевые показатели:**
- 20,000+ трекеров
- 20,000 GPS точек/сек
- Latency < 100ms (parse → Kafka)
- 99.9% uptime

---

## 🏛️ Высокоуровневая архитектура

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       GPS Трекеры (10K+ устройств)                          │
│                 Teltonika, Wialon, Ruptela, NavTelecom                      │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ TCP (ports 5001-5004)
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  BLOCK 1: СБОР И ОБРАБОТКА ДАННЫХ                                          │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  Connection Manager                     History Writer                      │
│  ├─ TCP Server (Netty)                  ├─ Kafka consumer (gps-events)     │
│  ├─ Protocol Parsers (4 протокола)      ├─ Batch aggregation (500 pts)     │
│  ├─ Redis: getDeviceData(imei)          └─ TimescaleDB insert              │
│  ├─ Filters (Dead Reckoning, Stationary)                                   │
│  ├─ Kafka: gps-events (все точки)                                          │
│  └─ Kafka: gps-events-rules (точки с геозонами/правилами)                  │
│                                                                             │
│  Device Manager                                                             │
│  ├─ REST API (CRUD устройств)                                              │
│  ├─ Redis: device:{imei} (context fields)                                  │
│  ├─ PostgreSQL (master data)                                               │
│  └─ Daily Sync Job (Redis ↔ PostgreSQL)                                    │
│                                                                             │
│  Подробнее: docs/blocks/ARCHITECTURE_BLOCK1.md                             │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ Kafka: gps-events, gps-events-rules
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  BLOCK 2: БИЗНЕС-ЛОГИКА                                                    │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  Geozones Service                       Notifications Service               │
│  ├─ Kafka consumer (gps-events-rules)   ├─ Rules engine                    │
│  ├─ PostGIS: ST_Contains queries        ├─ Email/SMS/Push/Telegram         │
│  └─ Kafka producer: geozone-events      └─ Webhook integrations            │
│                                                                             │
│  Analytics Service                      Sensors Service                     │
│  ├─ Reports (Excel/PDF/CSV)             ├─ Fuel calibration                │
│  └─ Scheduled aggregation jobs          └─ Temperature monitoring          │
│                                                                             │
│  Подробнее: docs/blocks/ARCHITECTURE_BLOCK2.md                             │
└─────────────────────────────┬───────────────────────────────────────────────┘
                              │ REST / WebSocket
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│  BLOCK 3: ПРЕДСТАВЛЕНИЕ                                                    │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  API Gateway                            WebSocket Service                   │
│  ├─ REST endpoints                      ├─ Realtime positions              │
│  ├─ JWT authentication                  ├─ Live alerts                     │
│  └─ Rate limiting                       └─ Command results                 │
│                                                                             │
│  Web Frontend (React + Leaflet)                                            │
│  ├─ Map с позициями                                                        │
│  ├─ Устройства и группы                                                    │
│  └─ Отчёты и уведомления                                                   │
│                                                                             │
│  Подробнее: docs/blocks/ARCHITECTURE_BLOCK3.md                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📊 Потоки данных

### Data Flow: GPS Point

```
Трекер (TCP)
    ↓ Binary packet (Teltonika/Wialon/...)
Connection Manager
    ├─ Parse protocol → GpsRawPoint
    ├─ HGETALL device:{imei} → DeviceData (context + prev position)
    ├─ Validate IMEI (vehicleId exists?)
    ├─ Dead Reckoning Filter (скорость валидна?)
    ├─ Stationary Filter (едет или стоит?)
    ├─ Enrich point (vehicleId, orgId, hasGeozones, speedLimit)
    ├─ HMSET device:{imei} → update position fields
    ├─ Kafka: gps-events (ALL points)
    └─ Kafka: gps-events-rules (if hasGeozones OR hasSpeedRules)
         ↓                              ↓
    History Writer              Geozones Service
         ↓                              ↓
    TimescaleDB                 geozone-events
```

### Kafka Topics

| Топик | Partitions | Retention | Throughput | Consumer |
|-------|------------|-----------|------------|----------|
| **gps-events** | 12 | 7 дней | ~2 MB/s | History Writer |
| **gps-events-rules** | 6 | 7 дней | ~0.6 MB/s | Geozones Service |
| device-status | 6 | 7 дней | ~15 KB/s | Device Manager |
| geozone-events | 6 | 30 дней | ~100 KB/s | Notifications |
| command-audit | 3 | 90 дней | ~15 KB/s | Analytics |

---

## 💾 Хранилища данных

### Redis (HASH per device)

> **⚠️ Текущее состояние:** Redis-клиент удалён из всех сервисов (несовместимость zio-redis).
> Схема ниже описывает **целевой дизайн**. В текущей реализации используется ZIO `Ref` (in-memory).

```
device:{imei}  (единый ключ на устройство)
├── CONTEXT (Device Manager пишет)
│   ├── vehicleId, organizationId, name
│   ├── speedLimit, hasGeozones, hasSpeedRules
│   └── fuelTankVolume
├── POSITION (Connection Manager пишет)
│   ├── lat, lon, speed, course, altitude
│   ├── satellites, time, isMoving
│   └── lastActivity
└── CONNECTION (Connection Manager пишет)
    ├── instanceId, protocol
    ├── connectedAt, remoteAddress
    └── (удаляется при disconnect)

pending_commands:{imei}  (ZSET, TTL 24h)
command_status:{requestId}  (HASH, TTL 1h)
unknown:{imei}:attempts  (STRING, TTL 1h)
```

### TimescaleDB

| Таблица | Тип | Сжатие | Retention |
|---------|-----|--------|-----------|
| gps_points | Hypertable | 15x после 7 дней | 90 дней |
| sensor_data | Hypertable | 10x после 7 дней | 90 дней |
| geozones | PostGIS | — | Permanent |
| geozone_events | Regular | — | 1 год |

### PostgreSQL (config)

- devices, device_groups
- organizations, users
- notification_rules
- command_log

---

## 📦 Список сервисов

### Block 1 — Сбор данных

| # | Сервис | Порт | Статус |
|---|--------|------|--------|
| 1 | Connection Manager | TCP 5001-5017, HTTP 10090 | ✅ Компилируется |
| 2 | Device Manager | HTTP 10092 | ✅ Компилируется |
| 3 | History Writer | HTTP 10091 (Kafka consumer) | ✅ Компилируется |

### Block 2 — Бизнес-логика

| # | Сервис | Порт | Статус |
|---|--------|------|--------|
| 4 | Rule Checker | HTTP 8093 | ✅ Компилируется |
| 5 | Notification Service | HTTP 8094 | ✅ Компилируется |
| 6 | Sensors Service | HTTP 8098 | ✅ Компилируется |
| 7 | Integration Service | HTTP 8096 | ✅ Компилируется |
| 8 | Analytics Service | HTTP 8095 | ✅ Компилируется |
| 9 | Maintenance Service | HTTP 8087 | ✅ Компилируется |
| 10 | Admin Service | HTTP 8097 | ✅ Компилируется |
| 11 | User Service | HTTP 8091 | ✅ Компилируется |

### Block 3 — Представление

| # | Сервис | Порт | Статус |
|---|--------|------|--------|
| 12 | API Gateway | HTTP 8080 | ✅ Компилируется |
| 13 | Web Frontend | HTTP 3001 | ✅ Компилируется |
| 14 | Web Billing | HTTP 3002 | ✅ Компилируется (React shell) |

---

## 📈 Расчёт хранения

### Входные данные
- 10,000 трекеров
- 1 точка/сек (движущиеся ~30%)
- ~200 bytes/точка

### Объёмы

| Хранилище | Объём/день | Retention | Итого |
|-----------|------------|-----------|-------|
| **Kafka gps-events** | 170 GB | 7 дней | ~1.2 TB |
| **Kafka gps-events-rules** | 50 GB | 7 дней | ~350 GB |
| **TimescaleDB** (сжатые) | 11 GB | 90 дней | ~1 TB |
| **Redis** | ~5 MB | — | ~50 MB |

---

## 🎯 Порты

```
TCP (GPS protocols — 18 протоколов):
  5001-5017: Connection Manager (Teltonika, Wialon, Ruptela, NavTelecom, etc.)

HTTP (Block 1):
  10090: Connection Manager (health, metrics)
  10091: History Writer (health, metrics)
  10092: Device Manager (REST API)

HTTP (Block 2):
  8087: Maintenance Service
  8091: User Service
  8093: Rule Checker
  8094: Notification Service
  8095: Analytics Service
  8096: Integration Service
  8097: Admin Service
  8098: Sensors Service

HTTP (Block 3):
  8080: API Gateway (public)
  3001: Web Frontend (React dev)
  3002: Web Billing (React dev)

Infrastructure:
  6379: Redis
  9092: Kafka
  5432: TimescaleDB / PostgreSQL
  9090: Prometheus
  3000: Grafana
```

---

## 📚 Связанные документы

### Архитектура блоков
- [blocks/ARCHITECTURE_BLOCK1.md](./blocks/ARCHITECTURE_BLOCK1.md) — Сбор данных (CM, DM, HW)
- [blocks/ARCHITECTURE_BLOCK2.md](./blocks/ARCHITECTURE_BLOCK2.md) — Бизнес-логика (8 сервисов)
- [blocks/ARCHITECTURE_BLOCK3.md](./blocks/ARCHITECTURE_BLOCK3.md) — Представление (API GW, WS, Frontend)

### Анализ и решения
- [REDIS_VS_REF_DECISION.md](./REDIS_VS_REF_DECISION.md) — Redis (lettuce) vs ZIO Ref
- [STELS_GAP_ANALYSIS.md](./STELS_GAP_ANALYSIS.md) — Gap-анализ: legacy Stels vs новая система
- [REALTIME_POSITIONS_DESIGN.md](./REALTIME_POSITIONS_DESIGN.md) — Real-time отображение позиций

### Хранилища и данные
- [DATA_STORES.md](./DATA_STORES.md) — Схемы хранилищ

### Сервисы
- [services/CONNECTION_MANAGER.md](./services/CONNECTION_MANAGER.md) — Connection Manager
- [services/DEVICE_MANAGER.md](./services/DEVICE_MANAGER.md) — Device Manager
- [services/HISTORY_WRITER.md](./services/HISTORY_WRITER.md) — History Writer
- [services/GEOZONES_SERVICE.md](./services/GEOZONES_SERVICE.md) — Rule Checker (Geozones)
- [services/NOTIFICATIONS_SERVICE.md](./services/NOTIFICATIONS_SERVICE.md) — Notification Service
- [services/SENSORS_SERVICE.md](./services/SENSORS_SERVICE.md) — Sensors Service
- [services/ANALYTICS_SERVICE.md](./services/ANALYTICS_SERVICE.md) — Analytics Service
- [services/MAINTENANCE_SERVICE.md](./services/MAINTENANCE_SERVICE.md) — Maintenance Service
- [services/INTEGRATION_SERVICE.md](./services/INTEGRATION_SERVICE.md) — Integration Service
- [services/ADMIN_SERVICE.md](./services/ADMIN_SERVICE.md) — Admin Service
- [services/USER_SERVICE.md](./services/USER_SERVICE.md) — User Service
- [services/API_GATEWAY.md](./services/API_GATEWAY.md) — API Gateway
- [services/WEB_FRONTEND.md](./services/WEB_FRONTEND.md) — Web Frontend

### Legacy
- [stels/LEGACY_API.md](./stels/LEGACY_API.md) — 78 методов старого API

---

**Версия:** 4.0  
**Дата:** 2 июня 2026
