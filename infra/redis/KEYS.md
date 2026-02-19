# 🔴 Redis — Структура ключей и владение

> **Версия:** Redis 7.0 (Alpine)  
> **Порт:** 6379  
> **Persistence:** RDB snapshots (по умолчанию)  
> **Обновлено:** 12 февраля 2026

---

## Принцип: каждый сервис владеет своими полями

Redis используется как **shared state** между сервисами. Основной паттерн — HASH `device:{imei}`, где **разные сервисы пишут в разные поля** одного хеша.

> ⚠️ **Правило:** сервис НИКОГДА не перезаписывает поля, которыми владеет другой сервис. Только HMSET своих полей.

---

## 1. `device:{imei}` — Главный HASH (основной ключ системы)

**Тип:** HASH  
**TTL:** Нет (master data, управляется Device Manager)  
**Пример ключа:** `device:860719020025346`

### Поля и владение

| Поле | Тип | Владелец (WRITE) | Читатели (READ) | Описание |
|------|-----|-------------------|-----------------|----------|
| **CONTEXT — Device Manager пишет** | | | | |
| `vehicleId` | Long | Device Manager | Connection Manager | ID транспортного средства |
| `organizationId` | Long | Device Manager | Connection Manager | ID организации (мультитенант!) |
| `name` | String | Device Manager | WebSocket, Frontend | Имя устройства |
| `speedLimit` | Int? | Device Manager | Connection Manager | Лимит скорости (км/ч) |
| `hasGeozones` | "true"/"false" | Device Manager | Connection Manager | Есть ли геозоны для этого ТС |
| `hasSpeedRules` | "true"/"false" | Device Manager | Connection Manager | Есть ли правила скорости |
| `fuelTankVolume` | Double? | Device Manager | Connection Manager | Объём бака (литры) |
| `sensorConfig` | JSON | Device Manager | Connection Manager | Конфигурация датчиков |
| **RETRANSLATION — Integration Service пишет** | | | | |
| `hasRetranslation` | "true"/"false" | Integration Service | Connection Manager | Есть ли ретрансляция |
| `retranslationTargets` | CSV | Integration Service | Connection Manager | "wialon-42,webhook-7" — цели |
| **POSITION — Connection Manager пишет** | | | | |
| `lat` | Double | Connection Manager | WebSocket, Frontend | Широта (последняя) |
| `lon` | Double | Connection Manager | WebSocket, Frontend | Долгота (последняя) |
| `speed` | Int | Connection Manager | WebSocket, Frontend | Скорость (км/ч) |
| `course` | Int | Connection Manager | WebSocket, Frontend | Курс (0-360°) |
| `altitude` | Int? | Connection Manager | WebSocket, Frontend | Высота (м) |
| `satellites` | Int? | Connection Manager | WebSocket, Frontend | Количество спутников |
| `time` | ISO8601 | Connection Manager | WebSocket, Frontend | Время с устройства |
| `isMoving` | "true"/"false" | Connection Manager | WebSocket, Frontend | Движется ли |
| `sensors` | JSON | Connection Manager | WebSocket, Frontend | Данные датчиков |
| `lastActivity` | ISO8601 | Connection Manager | Frontend, health-check | Время последней активности |
| **CONNECTION — Connection Manager пишет** | | | | |
| `instanceId` | String? | Connection Manager | Device Manager | ID инстанса CM (для routing) |
| `protocol` | String? | Connection Manager | Device Manager | Протокол (teltonika, wialon, ...) |
| `connectedAt` | ISO8601? | Connection Manager | Device Manager | Время подключения |
| `remoteAddress` | String? | Connection Manager | Device Manager | IP:port трекера |

### Жизненный цикл

```
1. Device Manager создаёт устройство:
   HMSET device:{imei}
     vehicleId 12345
     organizationId 100
     name "Truck-001"
     speedLimit 80
     hasGeozones true
     hasSpeedRules false

2. Integration Service обновляет флаги ретрансляции:
   HMSET device:{imei}
     hasRetranslation true
     retranslationTargets "wialon-42,webhook-7"

3. Connection Manager при подключении трекера:
   HMSET device:{imei}
     instanceId "cm-01"
     protocol "teltonika"
     connectedAt "2026-02-11T10:00:00Z"
     remoteAddress "192.168.1.100:54321"

4. Connection Manager на каждый GPS пакет:
   HMSET device:{imei}
     lat 55.7558
     lon 37.6176
     speed 60
     course 180
     time "2026-02-11T10:30:00Z"
     isMoving true
     lastActivity "2026-02-11T10:30:01Z"

5. Connection Manager при disconnect:
   HDEL device:{imei} instanceId protocol connectedAt remoteAddress
```

### Определение online/offline

Устройство считается online если:
```
lastActivity существует И (NOW - lastActivity) < 5 минут
```

---

## 2. `pending_commands:{imei}` — Backup очереди команд

**Тип:** ZSET (sorted set, score = timestamp)  
**TTL:** 24 часа  
**Владелец (WRITE):** Connection Manager (при получении команды из Kafka для offline трекера)  
**Читатель (READ):** Connection Manager (при подключении трекера)  

> **Роль:** Персистентный backup для in-memory очереди команд. Основной канал доставки команд — 
> Kafka `device-commands` (Static Partition Assignment). Redis ZSET — страховка на случай рестарта CM.

```
ZADD pending_commands:860719020025346 1707648000 '{"commandId":12345,"type":"reboot","data":{}}'
```

Connection Manager при получении команды из Kafka (трекер offline):
1. Кладёт в in-memory queue (быстро)
2. Параллельно `ZADD pending_commands:{imei}` (backup)

Connection Manager при подключении трекера:
1. Читает in-memory queue
2. `ZRANGE pending_commands:{imei} 0 -1` — читает Redis backup (на случай рестарта CM)
3. Объединяет + дедупликация по `commandId`
4. Отправляет все pending команды на трекер по TCP
5. `DEL pending_commands:{imei}` — очищает backup

---

## 3. ~~`connection_registry`~~ — Убрано (12 февраля 2026)

> **Больше не нужен.** Раньше использовался для routing команд (Device Manager → нужный CM).
> Теперь маршрутизация через **Kafka Static Partition Assignment**: 
> `protocol → instanceId → partition`. Device Manager знает протокол устройства 
> из БД и публикует команду в нужную партицию Kafka напрямую.
> 
> Поле `instanceId` в `device:{imei}` HASH остаётся для мониторинга/диагностики,
> но НЕ используется для routing команд.

---

## 4. `rate_limit:{imei}` — Rate Limiting

**Тип:** STRING (counter)  
**TTL:** 60 секунд  
**Владелец (WRITE):** Connection Manager  
**Читатель (READ):** Connection Manager  

```
INCR rate_limit:860719020025346
EXPIRE rate_limit:860719020025346 60
```

Максимум N пакетов в минуту от одного устройства. Защита от флуда.

---

## 5. ~~Pub/Sub каналы~~ — УБРАНО из MVP (12 февраля 2026)

> **Redis Pub/Sub не используется.** Все коммуникации между сервисами идут через **Kafka**:
> - **Команды на трекеры:** Kafka `device-commands` (Static Partition Assignment по instanceId)
> - **Обновление контекста устройства:** Kafka `device-events` → CM consumer обновляет Redis
> - **Конфигурация:** CM делает `HGETALL device:{imei}` на каждый пакет (всегда свежие данные)

---

## Сводная таблица ключей

| Паттерн ключа | Тип | TTL | Owner | Количество |
|----------------|------|-----|-------|------------|
| `device:{imei}` | HASH | нет | DM + CM + IS | ~10,000 (по числу устройств) |
| `pending_commands:{imei}` | ZSET | 24ч | CM (backup) | ~100 (только offline трекеры с командами) |
| `rate_limit:{imei}` | STRING | 60с | CM | ~10,000 (по числу онлайн устройств) |

**Оценка памяти:**
- `device:{imei}` × 10,000 × ~500 байт ≈ 5 MB
- `pending_commands` × 100 × ~200 байт ≈ 20 KB
- `rate_limit` × 10,000 × ~20 байт ≈ 200 KB
- **Итого: ~5.2 MB** (Redis спокойно справится)

---

**Связано:** [CONNECTION_MANAGER.md](../../docs/services/CONNECTION_MANAGER.md), [DEVICE_MANAGER.md](../../docs/services/DEVICE_MANAGER.md), [INTEGRATION_SERVICE.md](../../docs/services/INTEGRATION_SERVICE.md), [DATA_STORES.md](../../docs/DATA_STORES.md)
