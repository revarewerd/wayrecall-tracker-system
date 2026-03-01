# 📊 Kafka — Топики и маршруты сообщений

> **Брокер:** Apache Kafka 3.4+ (Confluent Platform 7.5.0)  
> **Протокол сжатия:** LZ4  
> **Replication Factor:** 1 (dev) / 3 (prod)  
> **Обновлено:** 2 июня 2026 | Версия: 2.0

---

## Все топики

| Топик | Партиции | Retention | Описание |
|-------|:--------:|-----------|----------|
| `gps-events` | 12 | 7 дней | **ВСЕ** GPS точки (валидные + невалидные + стационарные) |
| `gps-events-rules` | 6 | 1 день | GPS точки для проверки геозон и скорости (только `isMoving=true`) |
| `gps-events-retranslation` | 6 | 1 день | GPS точки для ретрансляции (только `isMoving=true`) |
| `gps-parse-errors` | 3 | 3 дня | **NEW** Ошибки парсинга GPS пакетов (для дебага и мониторинга) |
| `device-status` | 6 | 30 дней | Статусы устройств (online/offline) |
| `device-commands` | 6 | 7 дней | Команды на трекеры (Static Partition Assignment) |
| `device-events` | 3 | 30 дней | CRUD события устройств (создание, обновление, удаление) |
| `unknown-devices` | 3 | 7 дней | Попытки подключения незарегистрированных IMEI |
| `unknown-gps-events` | 6 | 30 дней | GPS точки от незарегистрированных трекеров |
| `command-audit` | 3 | 90 дней | Аудит команд отправленных на устройства |

---

## Маршруты: кто пишет → кто читает

### `gps-events` — Основной поток GPS (ALL points)

> ⚠️ **Изменение v2.0:** теперь публикуются ВСЕ точки, включая невалидные и стационарные.
> Поля `isValid` и `isMoving` позволяют consumers фильтровать нужное.

```
Partition key: vehicleId (гарантирует ordering для одного ТС)
Размер сообщения: ~200-250 байт (JSON)
Нагрузка: 10,000 точек/сек (100% трафика — ВСЕ точки)

┌────────────────────────┐
│  Connection Manager    │ ── WRITE ──→  gps-events
│  (ВСЕ точки: valid +   │
│   invalid + stationary)│
└────────────────────────┘
                                          │
                          ┌───────────────┼───────────────┐
                          ↓               ↓               ↓
                   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
                   │  History    │ │  WebSocket  │ │  Analytics  │
                   │  Writer    │ │  Service    │ │  Service    │
                   └─────────────┘ └─────────────┘ └─────────────┘
                   batch → DB       real-time WS     агрегация
```

**Формат сообщения (GpsPoint):**
```json
{
  "vehicleId": 12345,
  "organizationId": 100,
  "imei": "860719020025346",
  "latitude": 55.7558,
  "longitude": 37.6176,
  "altitude": 150,
  "speed": 60,
  "course": 180,
  "satellites": 12,
  "deviceTime": "2026-02-11T10:30:00Z",
  "serverTime": "2026-02-11T10:30:01Z",
  "speedLimit": 80,
  "hasGeozones": true,
  "hasSpeedRules": true,
  "hasRetranslation": false,
  "retranslationTargets": null,
  "isMoving": true,
  "isValid": true,
  "sensors": { "ignition": true, "fuel": 45.5 },
  "protocol": "teltonika",
  "instanceId": "cm-01"
}
```

---

### `gps-events-rules` — Проверка геозон и скоростей

> Только точки с `isMoving=true` И (`hasGeozones=true` ИЛИ `hasSpeedRules=true`)

```
Partition key: vehicleId
Условие публикации: isMoving=true И (hasGeozones=true ИЛИ hasSpeedRules=true)
Нагрузка: ~3,000 точек/сек (~30% трафика)

Connection Manager ── WRITE (условно) ──→  gps-events-rules
                                                │
                                    ┌───────────┼───────────┐
                                    ↓                       ↓
                             ┌─────────────┐        ┌─────────────┐
                             │  Geozones   │        │  Rule       │
                             │  Service    │        │  Checker    │
                             └─────────────┘        └─────────────┘
                             въезд/выезд            скорость, датчики
```

Формат сообщения: тот же `GpsPoint` что и в `gps-events`.

---

### `gps-events-retranslation` — Ретрансляция

> Только точки с `isMoving=true` И `hasRetranslation=true`

```
Partition key: vehicleId
Условие публикации: isMoving=true И hasRetranslation=true
Нагрузка: ~1,000 точек/сек (~5-15% трафика)

Connection Manager ── WRITE (условно) ──→  gps-events-retranslation
                                                │
                                                ↓
                                        ┌─────────────────┐
                                        │  Integration    │
                                        │  Service        │
                                        └─────────────────┘
                                        Wialon, webhooks
```

Формат сообщения: тот же `GpsPoint`. Поле `retranslationTargets` содержит список целей (`["wialon-42", "webhook-7"]`), чтобы consumer не делал lookup в PostgreSQL.

---

### `gps-parse-errors` — Ошибки парсинга GPS пакетов (**NEW v2.0**)

```
Partition key: imei (или "unknown" если IMEI не определён)
Размер сообщения: ~500-2000 байт (JSON + hex dump)
Нагрузка: эпизодически (~10-100 событий/мин)
Retention: 3 дня (отладочный топик)

┌────────────────────────┐
│  Connection Manager    │ ── WRITE ──→  gps-parse-errors
│  (ошибки парсинга:     │
│   checksum, codec,     │
│   insufficient data)   │
└────────────────────────┘
                                          │
                          ┌───────────────┼───────────────┐
                          ↓               ↓               ↓
                   ┌─────────────┐ ┌─────────────┐ ┌─────────────┐
                   │  Admin      │ │  Grafana    │ │  (будущий)  │
                   │  Service    │ │  Dashboard  │ │  Alert      │
                   └─────────────┘ └─────────────┘ └─────────────┘
                   просмотр ошибок  метрики          алерт при spike
```

**Формат сообщения (GpsParseErrorEvent):**
```json
{
  "imei": "860719020025346",
  "protocol": "teltonika",
  "errorType": "InvalidChecksum",
  "errorMessage": "CRC mismatch: expected 0xA3F1, got 0xB2E0",
  "rawPacketHex": "000000000000004308...",
  "rawPacketSize": 67,
  "remoteAddress": "192.168.1.100:54321",
  "instanceId": "cm-01",
  "timestamp": "2026-06-02T10:30:00Z"
}
```

**Типы ошибок (`errorType`):**

| Тип | Описание | Когда возникает |
|-----|----------|-----------------|
| `InvalidChecksum` | CRC не совпадает | Битые пакеты, плохой канал |
| `InvalidCodec` | Неизвестный codec ID | Новая прошивка трекера |
| `ParseError` | Общая ошибка парсинга | Неожиданный формат данных |
| `InsufficientData` | Недостаточно байт | Обрыв TCP соединения |
| `InvalidImei` | IMEI не проходит проверку | Повреждённый IMEI |
| `UnknownDevice` | IMEI не найден в системе | Незарегистрированный трекер |
| `UnsupportedProtocol` | Протокол не поддерживается | Неизвестный трекер |
| `ProtocolDetectionFailed` | Не удалось определить протокол | multi-protocol порт |

**Использование:**
- **Admin Service** — UI для просмотра ошибок парсинга, фильтрация по протоколу/IMEI
- **Grafana** — дашборд с метриками ошибок (rate per protocol, top IMEI)
- **Alerting** — алерт при резком росте ошибок (>100/мин) → возможная проблема с протоколом

---

### `device-status` — Online/Offline устройств

```
Partition key: imei
Нагрузка: ~100 событий/мин (только connect/disconnect)

Connection Manager ── WRITE ──→  device-status
                                      │
                          ┌───────────┼───────────┐
                          ↓                       ↓
                   ┌─────────────┐        ┌─────────────┐
                   │ Notification│        │  History    │
                   │  Service    │        │  Writer     │
                   └─────────────┘        └─────────────┘
                   алерты                 запись в БД
```

**Формат сообщения (DeviceStatusMessage):**
```json
{
  "vehicleId": 12345,
  "imei": "860719020025346",
  "status": "online",
  "timestamp": "2026-02-11T10:30:00Z",
  "instanceId": "cm-01",
  "protocol": "teltonika",
  "connectionDuration": null,
  "disconnectReason": null
}
```

---

### `device-events` — CRUD устройств

```
Partition key: deviceId
Нагрузка: ~10 событий/мин (редко)

Device Manager ── WRITE ──→  device-events
                                   │
                       ┌───────────┼───────────┐
                       ↓                       ↓
                ┌─────────────┐        ┌─────────────┐
                │  Connection │        │  Integration│
                │  Manager    │        │  Service    │
                │  (pub/sub)  │        │  (reсync)   │
                └─────────────┘        └─────────────┘
                обновить DeviceData     обновить Redis flags
```

**Формат сообщения (DeviceEvent):**
```json
{
  "eventType": "device.updated",
  "deviceId": 12345,
  "organizationId": 100,
  "imei": "860719020025346",
  "timestamp": "2026-02-11T10:30:00Z",
  "changes": {
    "name": "Truck-001",
    "hasGeozones": true
  }
}
```

---

### `unknown-devices` — Неизвестные IMEI

```
Partition key: imei
Нагрузка: эпизодически

Connection Manager ── WRITE ──→  unknown-devices
                                       │
                                       ↓
                               ┌─────────────┐
                               │  Device     │
                               │  Manager    │
                               │ (auto-prov) │
                               └─────────────┘
```

**Формат сообщения (UnknownDeviceEvent):**
```json
{
  "imei": "999888777666555",
  "protocol": "teltonika",
  "remoteAddress": "192.168.1.100:54321",
  "timestamp": "2026-02-11T10:30:00Z",
  "instanceId": "cm-01"
}
```

---

### `unknown-gps-events` — GPS точки от незарегистрированных трекеров

```
Partition key: imei
Нагрузка: зависит от количества незарегистрированных трекеров

Сценарий: трекер настроен слать данные на сервер, но ещё не зарегистрирован
в системе. CM принимает соединение, парсит GPS данные и публикует сюда.
History Writer пишет в таблицу unknown_device_positions.
Device Manager показывает в вебе для ручной регистрации/подтверждения.

Connection Manager ── WRITE ──→  unknown-gps-events
                                       │
                          ┌────────────┼────────────┐
                          ↓                         ↓
                   ┌─────────────┐          ┌─────────────┐
                   │  History    │          │  Device     │
                   │  Writer    │          │  Manager    │
                   └─────────────┘          └─────────────┘
                   → unknown_device_        показ в вебе,
                     positions              регистрация
```

**Формат сообщения (UnknownGpsPoint):**
```json
{
  "imei": "999888777666555",
  "latitude": 55.7558,
  "longitude": 37.6176,
  "altitude": 150,
  "speed": 60,
  "angle": 180,
  "satellites": 12,
  "deviceTime": 1707645000000,
  "serverTime": 1707645001000,
  "protocol": "teltonika",
  "instanceId": "cm-instance-1"
}
```

---

### `device-commands` — Команды на трекеры

```
Partition key: instanceId (статический маппинг protocol → CM instance)
Нагрузка: ~50 команд/сек

⚠️ Static Partition Assignment (НЕ Consumer Group!)
   Каждый CM читает только свою партицию.

Device Manager ── WRITE ──→  device-commands
                                   │
                     ┌─────────────┼─────────────┐
                     ↓             ↓             ↓
              ┌───────────┐ ┌───────────┐ ┌───────────┐
              │ CM        │ │ CM        │ │ CM        │
              │ Teltonika │ │ Wialon    │ │ Ruptela   │
              │ part. 0   │ │ part. 1   │ │ part. 2   │
              └───────────┘ └───────────┘ └───────────┘
```

**Маппинг protocol → instance → partition:**
```
teltonika  → cm-instance-1 → partition 0
wialon     → cm-instance-2 → partition 1
ruptela    → cm-instance-3 → partition 2
navtelecom → cm-instance-4 → partition 3
```

**Формат сообщения (DeviceCommand):**
```json
{
  "commandId": 12345,
  "deviceId": 123,
  "imei": "860719020025346",
  "commandType": "reboot",
  "payload": {},
  "createdAt": "2026-02-12T10:30:00Z",
  "createdBy": 1,
  "timeoutSeconds": 30
}
```

**Логика CM при получении команды:**
- Трекер онлайн → отправляем сразу по TCP (<100ms)
- Трекер offline → in-memory queue + Redis ZSET backup
- При подключении трекера → объединяем in-memory + Redis, дедупликация по commandId, отправляем

---

### `command-audit` — Аудит команд

```
Partition key: deviceId (ordering команд одного устройства)
Нагрузка: ~50 событий/час

Device Manager ── WRITE ──→  command-audit
Connection Manager ── WRITE ──→  command-audit (результаты выполнения)
                                   │
                                   ↓
                            ┌─────────────┐
                            │  (будущий)  │
                            │  аудит-лог  │
                            └─────────────┘
```

---

## Сводная матрица: сервис → топик

| Сервис | gps-events | gps-events-rules | gps-events-retranslation | gps-parse-errors | device-status | device-commands | device-events | unknown-devices | command-audit | unknown-gps-events |
|--------|:----------:|:-----------------:|:------------------------:|:----------------:|:-------------:|:---------------:|:-------------:|:---------------:|:-------------:|:------------------:|
| **Connection Manager** | **W** | **W** | **W** | **W** | **W** | R* | R | — | **W** | **W** |
| **History Writer** | R | — | — | — | R | — | — | — | — | R |
| **Device Manager** | — | — | — | — | — | **W** | **W** | R | **W** | R |
| **WebSocket Service** | R | — | — | — | R | — | R | — | — | — |
| **Geozones Service** | — | R | — | — | — | — | — | — | — | — |
| **Rule Checker** | — | R | — | — | — | — | — | — | — | — |
| **Integration Service** | — | — | R | — | — | — | — | — | — | — |
| **Notification Service** | — | — | — | — | R | — | — | — | — | — |
| **Analytics Service** | R | — | — | — | — | — | — | — | — | — |
| **Admin Service** | — | — | — | R | — | — | — | — | — | — |

**W** = пишет, **R** = читает, **R*** = Static Partition Assignment (не Consumer Group)

---

## Consumer Groups

| Consumer Group | Сервис | Топики |
|---------------|--------|--------|
| `history-writer` | History Writer | gps-events, device-status |
| `websocket-service` | WebSocket Service | gps-events, device-status, device-events |
| `geozones-service` | Geozones Service | gps-events-rules |
| `rule-checker` | Rule Checker | gps-events-rules |
| `integration-service` | Integration Service | gps-events-retranslation |
| `notification-service` | Notification Service | device-status |
| `device-manager-unknown` | Device Manager | unknown-devices |
| `analytics-service` | Analytics Service | gps-events |
| `admin-parse-errors` | Admin Service | gps-parse-errors |

> ⚠️ **device-commands** НЕ использует Consumer Group! Каждый CM инстанс привязан к своей партиции
> через Static Partition Assignment (`kafkaConsumer.assign(partition)`), чтобы команды
> гарантированно попадали на нужный CM по маппингу `protocol → instanceId → partition`.

---

## Настройки Producer (Connection Manager)

```properties
acks=1
batch.size=16384
linger.ms=5
compression.type=lz4
retries=3
max.in.flight.requests.per.connection=5
```

## Настройки Consumer (типичные)

```properties
auto.offset.reset=earliest
enable.auto.commit=false
max.poll.records=500
fetch.min.bytes=1024
fetch.max.wait.ms=500
```

---

**Связано:** [CONNECTION_MANAGER.md](../../docs/services/CONNECTION_MANAGER.md), [HISTORY_WRITER.md](../../docs/services/HISTORY_WRITER.md), [INTEGRATION_SERVICE.md](../../docs/services/INTEGRATION_SERVICE.md)
