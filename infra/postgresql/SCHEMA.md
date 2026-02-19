# 🐘 PostgreSQL / TimescaleDB — Схема базы данных

> **Движок:** TimescaleDB 2.x на базе PostgreSQL 15  
> **Расширения:** TimescaleDB, PostGIS  
> **Порт:** 5432  
> **БД:** `tracker`  
> **Пользователь:** `tracker` / `tracker123`  
> **Обновлено:** 11 февраля 2026

---

## Принцип: единая БД, разные контексты

Все сервисы используют **одну** TimescaleDB-инстанцию. TimescaleDB — это PostgreSQL 15 с расширением для time-series. Обычные таблицы (devices, vehicles) работают как обычный PostgreSQL.

| Контекст | Таблицы | Тип | Сервис-владелец |
|----------|---------|-----|-----------------|
| **Метаданные** | organizations, devices, vehicles, sensor_profiles | Обычные | Device Manager |
| **GPS история** | gps_positions | Hypertable (7 дней) | History Writer |
| **Команды** | device_commands | Hypertable (30 дней) | Device Manager |
| **Геозоны** | geozones, geozone_events | Обычная + Hypertable | Geozones Service |
| **Интеграции** | wialon_integrations, webhook_configs, api_keys, integration_logs | Обычные + Hypertable | Integration Service |
| **Статистика** | daily_device_stats | Continuous Aggregate | — (авто) |

---

## Таблицы метаданных (Device Manager)

### `organizations`

| Поле | Тип | NULL | Default | Описание |
|------|-----|------|---------|----------|
| `id` | BIGSERIAL | PK | auto | ID организации |
| `name` | VARCHAR(200) | NOT NULL | — | Название организации |
| `inn` | VARCHAR(20) | NULL | — | ИНН |
| `email` | VARCHAR(200) | NOT NULL | — | Контактный email |
| `phone` | VARCHAR(50) | NULL | — | Контактный телефон |
| `address` | TEXT | NULL | — | Адрес |
| `timezone` | VARCHAR(50) | NOT NULL | 'Europe/Moscow' | Часовой пояс |
| `max_devices` | INTEGER | NOT NULL | 100 | Лимит устройств по тарифу |
| `is_active` | BOOLEAN | NOT NULL | true | Активна ли |
| `created_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата создания |
| `updated_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата обновления |

**Индексы:** `idx_organizations_email` (email), `idx_organizations_inn` (inn)

---

### `vehicles`

| Поле | Тип | NULL | Default | Описание |
|------|-----|------|---------|----------|
| `id` | BIGSERIAL | PK | auto | ID ТС |
| `organization_id` | BIGINT | NOT NULL | — | FK → organizations |
| `name` | VARCHAR(200) | NOT NULL | — | Название ТС |
| `vehicle_type` | VARCHAR(20) | NOT NULL | 'Car' | Тип: Car, Truck, Bus, Motorcycle, Trailer, Special, Other |
| `license_plate` | VARCHAR(20) | NULL | — | Госномер |
| `vin` | VARCHAR(20) | NULL | — | VIN-код |
| `brand` | VARCHAR(100) | NULL | — | Марка |
| `model` | VARCHAR(100) | NULL | — | Модель |
| `year` | INTEGER | NULL | — | Год выпуска |
| `color` | VARCHAR(50) | NULL | — | Цвет |
| `fuel_type` | VARCHAR(30) | NULL | — | Тип топлива |
| `fuel_tank_capacity` | DOUBLE PRECISION | NULL | — | Объём бака (литры) |
| `icon_url` | VARCHAR(500) | NULL | — | URL иконки на карте |
| `created_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата создания |
| `updated_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата обновления |

**Индексы:** `idx_vehicles_org` (organization_id), `idx_vehicles_plate` (license_plate)
**FK:** `organization_id` → `organizations(id)`

---

### `devices`

| Поле | Тип | NULL | Default | Описание |
|------|-----|------|---------|----------|
| `id` | BIGSERIAL | PK | auto | ID устройства |
| `imei` | VARCHAR(20) | NOT NULL, UNIQUE | — | IMEI (15 цифр) |
| `name` | VARCHAR(200) | NULL | — | Имя устройства |
| `protocol` | VARCHAR(20) | NOT NULL | — | Протокол: Teltonika, Wialon, Ruptela, NavTelecom, Galileo, Custom |
| `status` | VARCHAR(20) | NOT NULL | 'Active' | Статус: Active, Inactive, Suspended, Deleted |
| `organization_id` | BIGINT | NOT NULL | — | FK → organizations |
| `vehicle_id` | BIGINT | NULL | — | FK → vehicles (привязка к ТС) |
| `sensor_profile_id` | BIGINT | NULL | — | FK → sensor_profiles |
| `phone_number` | VARCHAR(20) | NULL | — | Номер SIM-карты |
| `firmware_version` | VARCHAR(50) | NULL | — | Версия прошивки |
| `last_seen_at` | TIMESTAMPTZ | NULL | — | Последнее подключение |
| `created_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата создания |
| `updated_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата обновления |

**Индексы:** `idx_devices_imei` (imei, UNIQUE), `idx_devices_org` (organization_id), `idx_devices_vehicle` (vehicle_id)
**FK:** `organization_id` → `organizations(id)`, `vehicle_id` → `vehicles(id)`, `sensor_profile_id` → `sensor_profiles(id)`

---

### `sensor_profiles`

| Поле | Тип | NULL | Default | Описание |
|------|-----|------|---------|----------|
| `id` | BIGSERIAL | PK | auto | ID профиля |
| `organization_id` | BIGINT | NOT NULL | — | FK → organizations |
| `name` | VARCHAR(200) | NOT NULL | — | Название профиля |
| `description` | TEXT | NULL | — | Описание |
| `sensors` | JSONB | NOT NULL | '[]' | Список датчиков (SensorConfig[]) |
| `created_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата создания |
| `updated_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата обновления |

**FK:** `organization_id` → `organizations(id)`

Формат `sensors` JSONB:
```json
[
  {
    "name": "Уровень топлива",
    "ioElementId": 9,
    "sensorType": "fuel",
    "unit": "литры",
    "formula": "x * 0.1",
    "minValue": 0,
    "maxValue": 100
  }
]
```

---

## Hypertable: GPS позиции (History Writer)

### `gps_positions`

| Поле | Тип | NULL | Default | Описание |
|------|-----|------|---------|----------|
| `time` | TIMESTAMPTZ | NOT NULL | — | Время с устройства (partition key) |
| `device_id` | BIGINT | NOT NULL | — | FK → devices |
| `vehicle_id` | BIGINT | NULL | — | FK → vehicles (денормализация) |
| `organization_id` | BIGINT | NOT NULL | — | Для мультитенант-фильтрации |
| `imei` | VARCHAR(20) | NOT NULL | — | IMEI (денормализация для быстрого поиска) |
| `latitude` | DOUBLE PRECISION | NOT NULL | — | Широта |
| `longitude` | DOUBLE PRECISION | NOT NULL | — | Долгота |
| `altitude` | DOUBLE PRECISION | NULL | — | Высота (м) |
| `speed` | DOUBLE PRECISION | NOT NULL | — | Скорость (км/ч) |
| `course` | DOUBLE PRECISION | NULL | — | Курс (0-360°) |
| `satellites` | INTEGER | NULL | — | Количество спутников |
| `hdop` | DOUBLE PRECISION | NULL | — | Точность GPS |
| `is_moving` | BOOLEAN | NOT NULL | true | Движется ли |
| `is_valid` | BOOLEAN | NOT NULL | true | Валидна ли точка |
| `sensors` | JSONB | NULL | — | Данные датчиков |
| `protocol` | VARCHAR(20) | NULL | — | Протокол связи |
| `location` | GEOGRAPHY(POINT) | NULL | — | PostGIS точка (SRID 4326) |

**Hypertable:** `chunk_time_interval => '7 days'`
**Сжатие:** `compress_segmentby = 'imei'`, `compress_orderby = 'time DESC'`, после 7 дней
**Retention:** удаление после 1 года
**Индексы:** `idx_gps_imei_time` (imei, time DESC), `idx_gps_vehicle_time` (vehicle_id, time DESC), `idx_gps_org_time` (organization_id, time DESC), GIST (location)

---

## Hypertable: Команды (Device Manager)

### `device_commands`

| Поле | Тип | NULL | Default | Описание |
|------|-----|------|---------|----------|
| `time` | TIMESTAMPTZ | NOT NULL | — | Время создания команды |
| `command_id` | UUID | NOT NULL | — | Уникальный ID команды |
| `device_id` | BIGINT | NOT NULL | — | FK → devices |
| `imei` | VARCHAR(20) | NOT NULL | — | IMEI (денормализация) |
| `command_type` | VARCHAR(50) | NOT NULL | — | Тип команды |
| `command_data` | JSONB | NULL | — | Параметры команды |
| `status` | VARCHAR(20) | NOT NULL | 'pending' | pending, sent, acknowledged, failed |
| `sent_at` | TIMESTAMPTZ | NULL | — | Когда отправлена |
| `ack_at` | TIMESTAMPTZ | NULL | — | Когда подтверждена |
| `error_message` | TEXT | NULL | — | Текст ошибки |

**Hypertable:** `chunk_time_interval => '30 days'`
**Retention:** удаление после 90 дней

---

## Таблицы геозон (Geozones Service, Блок 2)

### `geozones`

| Поле | Тип | NULL | Default | Описание |
|------|-----|------|---------|----------|
| `id` | SERIAL | PK | auto | ID геозоны |
| `organization_id` | BIGINT | NOT NULL | — | FK → organizations |
| `name` | VARCHAR(200) | NOT NULL | — | Название |
| `zone_type` | VARCHAR(50) | NULL | — | Тип зоны |
| `geometry` | GEOGRAPHY(POLYGON) | NOT NULL | — | Полигон (PostGIS, SRID 4326) |
| `is_active` | BOOLEAN | NOT NULL | true | Активна ли |
| `created_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата создания |
| `updated_at` | TIMESTAMPTZ | NOT NULL | NOW() | Дата обновления |

### `geozone_events`

Hypertable, `chunk_time_interval => '30 days'`, retention 6 месяцев.

---

## Таблицы интеграций (Integration Service, Блок 2)

### `wialon_integrations`

Конфигурации ретрансляции в Wialon. Подробнее → [INTEGRATION_SERVICE.md](../../docs/services/INTEGRATION_SERVICE.md)

### `webhook_configs`

Конфигурации webhook-отправок.

### `integration_logs`

Hypertable, retention 7 дней. Логи всех интеграций.

---

## Continuous Aggregate

### `daily_device_stats`

```sql
SELECT
    time_bucket('1 day', time) AS day,
    imei, vehicle_id,
    COUNT(*)            AS position_count,
    AVG(speed)          AS avg_speed,
    MAX(speed)          AS max_speed,
    SUM(CASE WHEN is_moving THEN 1 ELSE 0 END) AS moving_count
FROM gps_positions
GROUP BY day, imei, vehicle_id;
```

Обновляется каждый час. Offset: 3 дня назад — 1 час назад.

---

## Функции

| Функция | Описание |
|---------|----------|
| `get_last_position(device_imei)` | Последняя GPS позиция устройства |
| `check_point_in_geozone(lat, lon)` | Проверить точку в геозоне (PostGIS) |

---

## Расхождения со старым `timescaledb-init.sql`

> Старый файл `infra/databases/timescaledb-init.sql` был создан на раннем этапе и **расходится** с текущими моделями в коде:

| Расхождение | Старая схема | Новая схема (из Entities.scala) |
|-------------|-------------|----------------------------------|
| `devices.organization_id` | ❌ Нет | ✅ BIGINT NOT NULL |
| `devices.status` | `is_active BOOLEAN` | `status VARCHAR(20)` (enum) |
| `devices.sensor_profile_id` | ❌ Нет | ✅ BIGINT NULL |
| `devices.phone_number` | ❌ Нет | ✅ VARCHAR(20) NULL |
| `devices.firmware_version` | ❌ Нет | ✅ VARCHAR(50) NULL |
| `organizations` таблица | ❌ Нет | ✅ Полная таблица |
| `vehicles.organization_id` | ❌ Нет (только company_id) | ✅ BIGINT NOT NULL |
| `vehicles` поля | Минимум | 15 полей (brand, model, year, ...) |
| `sensor_profiles` таблица | ❌ Нет | ✅ Полная таблица |
| `gps_positions.device_id` | ❌ Нет | ✅ BIGINT NOT NULL |
| `gps_positions.organization_id` | ❌ Нет | ✅ BIGINT NOT NULL |
| `gps_positions.sensors` | `raw_data TEXT` | `sensors JSONB` |

**TODO:** Обновить `init.sql` в соответствии с этой документацией.

---

**Связано:** [DEVICE_MANAGER.md](../../docs/services/DEVICE_MANAGER.md), [HISTORY_WRITER.md](../../docs/services/HISTORY_WRITER.md), [DATA_STORES.md](../../docs/DATA_STORES.md)
