# 📦 Connection Manager — Хранилища данных

> Что, где и зачем хранится в Redis/Kafka

## 🔴 Redis

### Единый HASH `device:{imei}` (ОСНОВНОЙ ПАТТЕРН)

Все данные об устройстве в ОДНОМ ключе. CM делает `HGETALL` на каждый data-пакет.

```
HGETALL device:860719020025346
```

| Поле | Тип | Кто пишет | Пример | Описание |
|------|-----|-----------|--------|----------|
| **CONTEXT (Device Manager)** ||||
| `vehicleId` | Long | DM | `42` | ID транспорта в PostgreSQL |
| `organizationId` | Long | DM | `7` | ID организации (мультитенантность) |
| `name` | String | DM | `Газель АА123` | Название ТС |
| `speedLimit` | Int? | DM | `90` | Ограничение скорости км/ч |
| `hasGeozones` | Boolean | DM | `true` | Есть геозоны → `gps-events-rules` |
| `hasSpeedRules` | Boolean | DM | `false` | Есть правила скорости → `gps-events-rules` |
| `hasRetranslation` | Boolean | DM | `true` | Ретрансляция → `gps-events-retranslation` |
| `retranslationTargets` | CSV | DM | `wialon-42,webhook-7` | Цели ретрансляции |
| `fuelTankVolume` | Double? | DM | `120.0` | Объём бака (литры) |
| **POSITION (Connection Manager)** ||||
| `lat` | Double | CM | `55.7558` | Широта |
| `lon` | Double | CM | `37.6173` | Долгота |
| `speed` | Int | CM | `67` | Скорость км/ч |
| `course` | Int | CM | `180` | Курс 0-359° |
| `altitude` | Int | CM | `156` | Высота м |
| `satellites` | Int | CM | `12` | Количество спутников |
| `time` | ISO8601 | CM | `2026-02-16T19:30:00Z` | Время позиции |
| `isMoving` | Boolean | CM | `true` | Движется/стоит |
| **CONNECTION (Connection Manager)** ||||
| `instanceId` | String | CM | `cm-teltonika-1` | ID инстанса CM |
| `protocol` | String | CM | `teltonika` | Протокол связи |
| `connectedAt` | ISO8601 | CM | `2026-02-16T19:00:00Z` | Время подключения |
| `lastActivity` | ISO8601 | CM | `2026-02-16T19:30:00Z` | Последняя активность |
| `remoteAddress` | String | CM | `85.12.34.56:44893` | IP:port трекера |

**Жизненный цикл:**
```
1. DM создаёт device:{imei} с context-полями при регистрации ТС
2. CM при CONNECT: HMSET connection-полей (instanceId, protocol...)
3. CM при DATA: HGETALL (чтение) → HMSET position-полей (lat, lon...)
4. CM при DISCONNECT: HDEL connection-полей
5. DM при config_updated: HMSET маршрутизационных флагов
```

### Legacy ключи (обратная совместимость)

> ⚠️ Будут удалены после полной миграции на `device:{imei}`

| Ключ | Тип | TTL | Описание |
|------|-----|-----|----------|
| `vehicle:{imei}` | STRING | ∞ | vehicleId (Long как строка) |
| `position:{vehicleId}` | STRING | 300с | GpsPoint JSON |
| `connection:{imei}` | STRING | ∞ | ConnectionInfo JSON |
| `vehicle:config:{imei}` | HASH | ∞ | VehicleConfig JSON в поле "data" |

### Служебные ключи

| Ключ | Тип | Описание |
|------|-----|----------|
| `pending_commands:{imei}` | ZSET | Очередь команд для offline-трекеров (score=timestamp) |
| `config:filters` | Pub/Sub channel | Динамическая конфигурация фильтров |
| `device:control:{imei}` | Pub/Sub pattern | Включение/отключение устройств администратором |

---

## 📨 Kafka Topics

### Исходящие (CM → другие сервисы)

| Топик | Partition Key | Формат | Описание |
|-------|--------------|--------|----------|
| `gps-events` | `vehicleId` | GpsPoint JSON | Основной поток GPS точек (только при движении) |
| `gps-events-rules` | `vehicleId` | GpsEventMessage JSON | Точки для проверки геозон и скорости |
| `gps-events-retranslation` | `vehicleId` | GpsEventMessage JSON | Точки для пересылки во внешние системы |
| `device-status` | `imei` | DeviceStatus JSON | Online/offline события |
| `unknown-devices` | `imei` | UnknownDeviceEvent JSON | Попытки подключения незарегистрированных трекеров |
| `unknown-gps-events` | `imei` | UnknownGpsPoint JSON | GPS точки от незарегистрированных трекеров |

### Входящие (другие сервисы → CM)

| Топик | Consumer Group | Формат | Описание |
|-------|---------------|--------|----------|
| `device-events` | `cm-device-events` | DeviceEvent JSON | Обновления конфигурации от Device Manager |
| `device-commands` | Static Assignment | PendingCommand JSON | Команды для отправки на трекеры |

### Маршрутизация точек (flow)

```
GPS Tracker → TCP пакет
    ↓
CM: parseData → GpsRawPoint[]
    ↓
CM: Dead Reckoning Filter (отсев аномалий)
    ↓
CM: Stationary Filter → shouldPublish?
    ↓
┌─ shouldPublish=true ──────────────────────────────────────────┐
│                                                                │
│   → gps-events (GpsPoint)         ← всегда при движении       │
│                                                                │
│   DeviceData.hasGeozones || hasSpeedRules?                     │
│     → gps-events-rules (GpsEventMessage)                       │
│                                                                │
│   DeviceData.hasRetranslation?                                 │
│     → gps-events-retranslation (GpsEventMessage)               │
│                                                                │
└────────────────────────────────────────────────────────────────┘
    ↓ (всегда)
Redis: HMSET device:{imei} (position + lastActivity)
Redis: SETEX position:{vehicleId} (legacy)
```

---

## 🔑 Форматы данных

### GpsPoint (gps-events)
```json
{
  "vehicleId": 42,
  "latitude": 55.7558,
  "longitude": 37.6173,
  "altitude": 156,
  "speed": 67,
  "angle": 180,
  "satellites": 12,
  "timestamp": 1739734200000
}
```

### GpsEventMessage (gps-events-rules / gps-events-retranslation)
```json
{
  "vehicleId": 42,
  "organizationId": 7,
  "imei": "860719020025346",
  "latitude": 55.7558,
  "longitude": 37.6173,
  "altitude": 156,
  "speed": 67,
  "course": 180,
  "satellites": 12,
  "deviceTime": 1739734200000,
  "serverTime": 1739734200100,
  "hasGeozones": true,
  "hasSpeedRules": false,
  "hasRetranslation": true,
  "retranslationTargets": ["wialon-42", "webhook-7"],
  "isMoving": true,
  "isValid": true,
  "protocol": "teltonika"
}
```

### DeviceStatus (device-status)
```json
{
  "imei": "860719020025346",
  "vehicleId": 42,
  "isOnline": true,
  "lastSeen": 1739734200000,
  "disconnectReason": null,
  "sessionDurationMs": null
}
```

### DeviceEvent (device-events, входящий)
```json
{
  "imei": "860719020025346",
  "vehicleId": 42,
  "organizationId": 7,
  "eventType": "config_updated",
  "vehicleConfig": {
    "organizationId": 7,
    "imei": "860719020025346",
    "name": "Газель АА123",
    "hasGeozones": true,
    "hasSpeedRules": false,
    "hasRetranslation": true,
    "retranslationTargets": ["wialon-42"]
  },
  "timestamp": 1739734200000
}
```
