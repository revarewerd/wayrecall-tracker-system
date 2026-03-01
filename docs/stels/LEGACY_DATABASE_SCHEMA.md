# 🗄️ Legacy Database Schema (Stels)

> Дата: 12 февраля 2026 (v2.0 — полный аудит)
> Источник: legacy-stels (MongoDB 3.4, PostgreSQL 9.6 + PostGIS)

## Обзор

```
┌─────────────────────────────────────────────────────────┐
│                    Legacy Stels                         │
│                                                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  MongoDB 3.4 │  │ PostgreSQL   │  │  Nominatim   │  │
│  │  Seniel-dev2 │  │  seniel-pg   │  │  (PostGIS)   │  │
│  │  порт 27017  │  │  порт 5432   │  │  порт 5432   │  │
│  │              │  │              │  │              │  │
│  │ 41 коллекция │  │ PostGIS only │  │ Reverse geo  │  │
│  │ + динамич.   │  │ (пустая)     │  │ координаты   │  │
│  │ objPacks.*   │  │              │  │  → адрес     │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

**MongoDB** — основное хранилище (метаданные + GPS-позиции)
**PostgreSQL** — PostGIS для геопространственных запросов (legacy почти не использует)
**Nominatim** — отдельная PostgreSQL БД для обратного геокодирования (координаты → адрес)

---

## 1. MongoDB (Seniel-dev2) — Главная БД

### 1.1 UML-диаграмма связей

```
┌─────────────────────┐       ┌─────────────────────┐
│      accounts       │       │       tariffs        │
├─────────────────────┤       ├─────────────────────┤
│ _id: ObjectId       │──┐    │ _id: ObjectId       │
│ name: String        │  │    │ name: String         │
│ default: Boolean    │  │    │ comment: String      │
│ plan: ObjectId ─────│──│───▶│ abonentPrice: [{     │
│ balance: Number     │  │    │   name, comment, cost│
│ comment: String     │  │    │ }]                   │
│ blocked: Boolean    │  │    │ additionalAbonent... │
│ blockedReason: Str  │  │    │ servicePrice: [...]  │
│ billingType: String │  │    │ hardwarePrice: [...] │
│ lastCalcDate: Date  │  │    │ messageHistoryLen..  │
└─────────────────────┘  │    │ default: Boolean     │
         ▲               │    └─────────────────────┘
         │               │
         │ accountId     │
         │               │
┌────────┴────────────┐  │    ┌─────────────────────┐
│       users         │  │    │    billingRoles      │
├─────────────────────┤  │    ├─────────────────────┤
│ _id: ObjectId       │  │    │ _id: ObjectId       │
│ name: String        │  │    │ name: String         │
│ password: String    │  │    │ description: String  │
│ enabled: Boolean    │  │    │ permissions: [Str]   │
│ roles: [String]     │──│───▶│ authorities: [Str]   │
│ accountId: ObjId ───│──┘    └─────────────────────┘
│ lastLoginDate: Date │
│ groups: [{          │       ┌─────────────────────┐
│   name, objectIds   │──────▶│  (группы объектов   │
│ }]                  │       │   встроены в users)  │
│ settings: {...}     │       └─────────────────────┘
└─────────────────────┘
         │
         │ userId (в usersPermissions)
         ▼
┌─────────────────────┐       ┌─────────────────────┐
│  usersPermissions   │       │      objects         │
├─────────────────────┤       ├─────────────────────┤
│ _id: ObjectId       │       │ _id: ObjectId       │
│ userId: ObjectId    │       │ uid: String (unique) │
│ objectIds: [ObjId]  │──────▶│ name: String         │
│ permissions: {...}  │       │ customName: String   │
│   canBlock: Bool    │       │ accountId: ObjectId  │
│   canView: Bool     │       │ comment: String      │
│   canFuel: Bool     │       │ blocked: Boolean     │
│   canTrips: Bool    │       │ disabled: Boolean    │
└─────────────────────┘       │ equipment: [{        │
                              │   eqIMEI, model,     │
                              │   simNumber, type    │
                              │ }]                   │
                              │ settings: {          │
                              │   trips, fuel, view, │
                              │   imgSource, sensors │
                              │ }                    │
                              └──────────┬──────────┘
                                         │ uid
                                         ▼
                              ┌─────────────────────┐
                              │  objPacks.o{uid}    │
                              │  (ДИНАМИЧЕСКИЕ!)    │
                              ├─────────────────────┤
                              │ uid: String          │
                              │ imei: String         │
                              │ time: Date           │
                              │ lon: Double          │
                              │ lat: Double          │
                              │ spd: Short (скор.)   │
                              │ crs: Short (курс)    │
                              │ stn: Byte (спутн.)   │
                              │ pn: String (адрес)   │
                              │ insTime: Date        │
                              │ data: {sensors...}   │
                              │ privateData: {...}   │
                              └─────────────────────┘
                              По 1 коллекции на объект!
                              Индекс: (time:-1, lon:1, lat:1)
```

### 1.2 Все коллекции MongoDB (41 коллекция — полный аудит)

> ⚠️ v1.0 документа содержал только 24 коллекции. После аудита кода найдено **41 уникальная коллекция**.
> Новые (ранее не документированные) помечены 🆕

#### A. Основные бизнес-данные

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `accounts` | Учётные записи клиентов (balance, plan, blocked) | AccountAggregate, AccountData |
| `users` | Пользователи (логин, роли, настройки) | billing/security |
| `tariffs` | Тарифные планы (abonentPrice, servicePrice, hardwarePrice) | TariffPlans |
| `objects` | Объекты/транспорт (uid, name, equipment, settings, sensors) | ObjectAggregate, ObjectData |
| `equipments` | Оборудование (eqIMEI, eqtype, eqMark, eqModel, simNumber) | EquipmentAggregate |
| 🆕 `objects.removed` | Архив soft-deleted объектов (та же структура что `objects`) | ObjectsRepositoryScala |
| 🆕 `equipmentTypes` | **Справочник типов оборудования** (type, mark, model) — Axon CQRS | EquipmentTypesAggregate |

#### B. Права и роли

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `billingRoles` | Роли пользователей (name, permissions, authorities) | RolesService |
| `usersPermissions` | Права пользователей на объекты (userId, objectIds, canBlock/View/Fuel) | PermissionsEditor |
| 🆕 `usersPermissions.removed` | Архив удалённых прав пользователей | billing/security |
| 🆕 `billingPermissions` | Отдельные права для биллинг-модуля | billing/security |
| 🆕 `authBackdors` | ⚠️ Бэкдор-аутентификация (security антипаттерн!) | BackdoorEnterProvider |

#### C. Группы и датчики

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| 🆕 `groupsOfObjects` | **Группы объектов** (_id, name, uid (owner), objects [{uid}]) | GroupsOfObjects, UserGroupsOfObjects |
| 🆕 `sensorNames` | **Авто-определённые имена датчиков по IMEI** (imei, params []) | MapObjects, SensorsList, PathDataServlet |

#### D. GPS-позиции

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `objPacks.o{uid}` | **ДИНАМИЧЕСКИЕ** — GPS-позиции (по 1 коллекции на объект!) | PackagesStore |
| 🆕 `objPacks.buffer` | Буфер входящих GPS пакетов (промежуточное хранение) | packreceiver |
| 🆕 `objPacks.removed` | Удалённые/архивные GPS пакеты | core |
| `lbses` | LBS данные — позиционирование по базовым станциям (uid, imei, lbs, time) | core |

#### E. SMS и "спящие" устройства

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `smses` | Отправленные SMS (text, fromObject, status, sendDate) | SMS.scala |
| 🆕 `smsconversation` | **SMS-диалоги** — state machine (phone, pendingForSend, pendingForAnswer) | SmsConversation.scala |
| 🆕 `sleeping` | **"Спящие" устройства / радиозакладки** (uid, history, sleeperState, batValue, batPercentage) — мониторинг через SMS | SleeperData.scala |

#### F. Уведомления и события

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `events` | Уведомления/события (eid, uid, type, time, message) | EventsStoreService |
| `notificationRules` | Правила уведомлений (type, objectUids, params, action) | monitoring |
| `notificationRulesStates` | Состояния правил (последнее срабатывание, cooldown) | monitoring |
| `geoZonesState` | Геозоны (id, name, ftColor, points [{lat, lon}]) | monitoring |

#### G. Event Sourcing (Axon Framework)

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `domainEvents` | Лог событий Axon (aggregateIdentifier, sequenceNumber, serializedPayload XML) | Axon |
| `domainEventsView` | Read-Model проекция событий (для UI) | Axon |
| `snapshotEvents` | Снапшоты агрегатов (для быстрого восстановления) | Axon |

#### H. Дилеры (мульти-инстанс)

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| 🆕 `dealers` | **Дилеры/субоп-ры** (id, balance, tariffication, baseTariff, block, accounts) | DealerReadDBWriter, DealersService |
| 🆕 `dealers.balanceHistory` | История баланса дилеров | DealerMonthlyPaymentService |

#### I. Биллинг и платежи

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `balanceHistoryWithDetails` | Детализированная история баланса аккаунтов | BalanceHistoryStoreService |
| 🆕 `balanceHistory` | Упрощённая история баланса (отдельная от WithDetails) | billing/finance |
| 🆕 `paymentProcess` | Процессы оплаты (состояние платёжной транзакции) | PaymentServlet |
| 🆕 `paymentStat` | Статистика платежей | PaymentClientService |
| 🆕 `yandexPayment` | Интеграция Яндекс.Оплата (checkOrder / paymentAviso) | PaymentServlet |
| 🆕 `checkOrderResult` | Результат проверки заказа (Яндекс) | PaymentServlet |
| 🆕 `processOrderResult` | Результат обработки заказа (Яндекс) | PaymentServlet |
| 🆕 `removalPeriods` | **Политики удаления данных** по объектам (retention periods) | billing |
| 🆕 `accountslastblocks` | Последние блокировки аккаунтов (для AfterBlockingRetranslator) | AfterBlockingRetranslator |

#### J. Логирование и поддержка

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `authlog` | Лог аутентификации | billing/security |
| `supportRequest` | Тикеты техподдержки (subject, status, messages) | monitoring |

#### K. Сессии и push

| Коллекция | Назначение | Используется в |
|-----------|-----------|----------------|
| `monitoringwebapp-sessions` | Spring HTTP сессии (мониторинг UI) | Spring Session |
| `billingwebapp-sessions` | Spring HTTP сессии (биллинг UI) | Spring Session |
| `usersPlayerIds` | Push-токены OneSignal для мобильных уведомлений | notifications |

### 1.3 Детальные схемы ключевых коллекций

#### equipments (Оборудование)
```
{
  _id: ObjectId,
  eqtype: String,          // "gps-tracker", "radio-tag"
  accountId: ObjectId,     // → accounts._id
  objectId: ObjectId,      // → objects._id
  eqMark: String,          // Марка: "Teltonika", "Wialon"
  eqModel: String,         // Модель: "FMB920", "PRO"
  eqSerNum: String,        // Серийный номер
  eqIMEI: String,          // IMEI (уникальный идентификатор)
  simNumber: String,       // Номер SIM-карты
  status: String           // "active", "inactive", "stock"
}
```

#### events (Уведомления)
```
{
  _id: ObjectId,
  eid: Long,               // ID события
  uid: String,             // ID объекта (→ objects.uid)
  type: String,            // "speed", "geofence", "sos"
  time: Date,              // Время события
  message: String,         // Текст уведомления
  read: Boolean,           // Прочитано?
  additionalData: {...}    // Доп. данные (координаты, порог скорости)
}
```

#### notificationRules (Правила уведомлений)
```
{
  _id: ObjectId,
  name: String,            // Название правила
  type: String,            // "speed", "geofence_enter", "geofence_exit", "sos"
  objectUids: [String],    // Объекты под наблюдением
  params: {                // Параметры
    speedLimit: Number,    // Порог скорости (для speed)
    geozoneId: ObjectId    // Геозона (для geofence)
  },
  action: String,          // "push", "sms", "email"
  email: String,
  phone: String,
  enabled: Boolean
}
```

#### geoZonesState (Геозоны)
```
{
  _id: ObjectId,
  id: Long,                // ID геозоны
  name: String,            // Название
  ftColor: String,         // Цвет отображения (#RRGGBB)
  points: [{               // Полигон
    lat: Double,
    lon: Double
  }],
  description: String
}
```

#### supportRequest (Тикеты поддержки)
```
{
  _id: ObjectId,
  subject: String,
  status: String,          // "open", "in_progress", "closed"
  priority: String,        // "low", "medium", "high"
  category: String,
  accountId: ObjectId,
  userId: ObjectId,
  messages: [{
    author: String,
    text: String,
    date: Date
  }]
}
```

#### domainEvents (Event Sourcing — Axon Framework)
```
{
  _id: ObjectId,
  aggregateIdentifier: String,  // UUID агрегата
  sequenceNumber: Long,         // Порядковый номер
  type: String,                 // Тип агрегата
  serializedPayload: String,    // XML (Axon) — полезная нагрузка
  serializedMetaData: String,   // XML — метаданные
  timestamp: String,            // ISO дата
  payloadType: String,          // Java class name
  payloadRevision: String
}
// Используется для: создание/изменение аккаунтов, биллинг
// Axon восстанавливает состояние из цепочки событий
```

#### 🆕 groupsOfObjects (Группы объектов)
```
{
  _id: ObjectId,
  name: String,            // Название группы ("Грузовики", "Маршрут 5")
  uid: ObjectId,           // Владелец (→ users._id)
  objects: [{              // Массив объектов в группе
    uid: String            // → objects.uid
  }]
}
// Пользователь создаёт именованные группы ТС для группового просмотра
// Фильтруется по permission — видны только группы доступных объектов
// Есть отдельные view: GroupsOfObjects (admin), UserGroupsOfObjects (юзер)
```

#### 🆕 sensorNames (Имена датчиков по IMEI)
```
{
  _id: ObjectId,
  imei: String,            // IMEI трекера
  params: [String]         // Имена параметров, которые трекер присылает
  // Примеры: ["fuel_lvl", "battery", "gsm_signal", "can_rpm", "temp_sens_0",
  //           "in1", "adc1", "speed", "odometer", "Total Odometer"]
}
// Заполняется автоматически из входящих GPS-пакетов
// Используется для:
//   - MapObjects.getSensorNames() — список доступных датчиков ТС
//   - SensorsList.getObjectSensorsCodenames() — codenames датчиков
//   - PathDataServlet — вывод значений датчиков в отчётах
// 
// Есть набор "скрытых" (sensorHide) и "показываемых" (sensorShow) сенсоров
// Всего 100+ типов датчиков: CAN, ADC, temperature, fuel, battery, etc.
```

#### 🆕 equipmentTypes (Справочник типов оборудования)
```
{
  _id: ObjectId,
  type: String,            // Тип: "GPS-трекер", "Спящий блок", "Датчик топлива"
  mark: String,            // Марка: "Teltonika", "Ruptela", "Omnicomm"
  model: String,           // Модель: "FMB920", "FM-Pro4", "LLS 30160"
  // + другие произвольные поля через Axon CQRS (Map<String, Object> submitMap)
}
// CQRS агрегат: EquipmentTypesCreateCommand / EquipmentTypesDataSetCommand
// Используется для каскадного выбора: type → mark → model
// API: loadMarkByType(type), loadModelByMark(type, mark)
```

#### 🆕 dealers (Дилеры / субоператоры)
```
{
  id: String,              // Идентификатор дилера (== имя инстанса)
  balance: Number,         // Баланс дилера
  baseTariff: Object,      // Базовый тариф
  tariffication: {         // Тарификация (Map произвольных полей)
    key: value             
  },
  block: Boolean,          // Заблокирован ли дилер
  // Связь: id == MultiserverConfig.name (имя сервера)
}
// Дилер = субоператор системы мониторинга с несколькими аккаунтами
// Мультисерверная архитектура: каждый дилер может иметь свою БД
// Events: DealerTarifficationChangeEvent, DealerBalanceChangeEvent, DealerBlockingEvent
```

#### 🆕 sleeping (Спящие устройства / радиозакладки)
```
{
  uid: String,             // → objects.uid
  history: Map[String, Stream[SMS]],  // Ключ = имя закладки, значение = поток SMS
  sleeperState: String,    // "OK", "Warning", "Unknown"
  batValue: String,        // Уровень заряда батареи (сырое значение)
  batPercentage: Int       // Процент заряда батареи
}
// Радиозакладки ("спящие блоки") — устройства без GPS, отчитываются через SMS
// SMS содержат: статус, уровень батареи, тревоги
// Используется: ObjectData.getObjectSleepers(), MapObjects, SleeperData.scala
```

#### 🆕 smsconversation (SMS-диалоги)
```
{
  phone: String,                   // Номер телефона устройства
  pendingForSend: [SMSCommand],    // Очередь команд на отправку
  pendingForAnswer: [SMSCommand],  // Ожидающие ответа (уже отправлены)
  commandAnswers: [...]            // Полученные ответы
}
// State machine для SMS-команд на устройства
// SMSCommand содержит: commandText, callback, timeout
// Workflow: pendingForSend → send SMS → pendingForAnswer → receive answer → done
```

#### 🆕 removalPeriods (Политики удаления данных)
```
{
  _id: ObjectId,
  objectId: ObjectId,      // → objects._id или uid
  retentionDays: Number,   // Сколько дней хранить GPS-данные
  // Используется для: очистка старых objPacks
}
```

---

## 2. PostgreSQL (seniel-pg) — PostGIS

> ⚠️ БД `seniel-pg` **фактически пустая** — только системные таблицы PostGIS.
> В legacy Stels PostgreSQL не используется для бизнес-данных.

```
┌──────────────────────────────────────┐
│        seniel-pg (PostgreSQL 9.6)    │
├──────────────────────────────────────┤
│ Схема public:                        │
│   └── spatial_ref_sys (PostGIS)     │
│       srid, auth_name, auth_srid,   │
│       srtext, proj4text             │
│                                      │
│ Схема topology:                      │
│   ├── layer                         │
│   └── topology                      │
│                                      │
│ ⚠ Нет бизнес-таблиц!               │
└──────────────────────────────────────┘
```

---

## 3. Nominatim (PostGIS) — Обратное геокодирование

> Отдельная PostgreSQL БД для преобразования GPS-координат в адреса

```
Конфиг: jdbc:postgresql://localhost/nominatim
Класс: DirectNominatimRegeocoder.scala
```

### Основная таблица: `placex`

```
┌──────────────────────────────────────┐
│             placex                    │
├──────────────────────────────────────┤
│ place_id: BIGINT (PK)               │
│ osm_type: CHAR(1)  // N/W/R         │
│ osm_id: BIGINT                       │
│ class: TEXT         // building,road │
│ type: TEXT          // residential   │
│ name: HSTORE       // 'name'=>'...' │
│ admin_level: INT                     │
│ address: HSTORE                      │
│ extratags: HSTORE                    │
│ geometry: GEOMETRY  // PostGIS       │
│ country_code: TEXT                   │
│ rank_search: INT                     │
│ rank_address: INT                    │
│ importance: FLOAT                    │
│ parent_place_id: BIGINT              │
└──────────────────────────────────────┘

Запрос из кода:
  SELECT * FROM placex
  WHERE ST_DWithin(geometry, ST_GeomFromText('POINT(lon lat)', 4326), radius)
  ORDER BY ST_Distance(...)
```

### Типы GeoObject в коде:
```scala
case class GeoObject(
  placeId: Long,
  placeType: String,     // "city", "road", "building"
  name: String,          // "ул. Ленина, 15"
  geometry: Geometry      // PostGIS GEOMETRY
)
```

---

## 4. НОВЫЙ ПРОЕКТ — TimescaleDB (целевая архитектура)

> Файл: `infra/databases/timescaledb-init.sql`

### 4.1 ER-диаграмма

```
┌─────────────────┐     ┌─────────────────────┐     ┌──────────────────┐
│    vehicles     │     │      devices         │     │  device_commands │
├─────────────────┤     ├─────────────────────┤     ├──────────────────┤
│ id: BIGSERIAL PK│◀────│ vehicle_id: BIGINT FK│     │ time: TIMESTAMPTZ│
│ name: VARCHAR   │     │ id: BIGSERIAL PK    │     │ command_id: UUID │
│ plate_number    │     │ imei: VARCHAR(20) UQ │────▶│ imei: VARCHAR(20)│
│ vehicle_type    │     │ name: VARCHAR        │     │ command_type     │
│ company_id      │     │ protocol: VARCHAR    │     │ command_data JSON│
│ is_active: BOOL │     │ is_active: BOOL      │     │ status: VARCHAR  │
│ created_at      │     │ last_seen: TIMESTMPTZ│     │ sent_at          │
│ updated_at      │     │ created_at           │     │ ack_at           │
└─────────────────┘     └──────────┬──────────┘     └──────────────────┘
        │                          │ imei                (hypertable)
        │ vehicle_id               │
        ▼                          ▼
┌─────────────────────────────────────────────────┐
│                 gps_positions                    │
│               (HYPERTABLE — TimescaleDB)         │
├─────────────────────────────────────────────────┤
│ time: TIMESTAMPTZ (NOT NULL)                     │
│ imei: VARCHAR(20)                                │
│ vehicle_id: BIGINT → vehicles.id                 │
│ latitude: DOUBLE PRECISION                       │
│ longitude: DOUBLE PRECISION                      │
│ altitude: DOUBLE PRECISION                       │
│ speed: DOUBLE PRECISION                          │
│ heading: DOUBLE PRECISION                        │
│ satellites: INTEGER                              │
│ hdop: DOUBLE PRECISION                           │
│ is_moving: BOOLEAN                               │
│ is_valid: BOOLEAN                                │
│ protocol: VARCHAR(20)                            │
│ raw_data: JSONB                                  │
│ location: GEOMETRY(POINT, 4326)  — PostGIS!      │
│                                                   │
│ Chunk interval: 1 day                            │
│ Индексы: (imei, time DESC), (vehicle_id, time)   │
│          GIST(location)                           │
└─────────────────────────────────────────────────┘

┌─────────────────┐     ┌─────────────────────────┐
│    geozones     │     │     geozone_events      │
├─────────────────┤     ├─────────────────────────┤
│ id: BIGSERIAL PK│◀────│ geozone_id: BIGINT FK   │
│ name: VARCHAR   │     │ time: TIMESTAMPTZ       │
│ zone_type       │     │ event_id: UUID          │
│ geometry: GEOM  │     │ vehicle_id: BIGINT FK   │
│  (POLYGON,4326) │     │ event_type: VARCHAR     │
│ company_id      │     │  ("enter"/"exit")       │
│ is_active: BOOL │     │ latitude: DOUBLE        │
│ created_at      │     │ longitude: DOUBLE       │
│ updated_at      │     └─────────────────────────┘
└─────────────────┘          (hypertable)

┌─────────────────────────────────────────────┐
│      daily_device_stats                      │
│   (CONTINUOUS AGGREGATE — автообновление)     │
├─────────────────────────────────────────────┤
│ bucket: DATE (1 day)                         │
│ imei: VARCHAR                                │
│ total_points: COUNT(*)                       │
│ avg_speed: AVG(speed)                        │
│ max_speed: MAX(speed)                        │
│ first_point: FIRST(time, time)               │
│ last_point: LAST(time, time)                 │
└─────────────────────────────────────────────┘
```

---

## 5. Маппинг: Legacy MongoDB → Новый TimescaleDB/PostgreSQL

### Основные сущности

| Legacy (MongoDB) | Новый (TimescaleDB/PostgreSQL) | Комментарий |
|---|---|---|
| `objPacks.o{uid}` | `gps_points` (hypertable) | 1 таблица вместо N коллекций! |
| `objects` | `devices` | Объекты мониторинга → устройства |
| `equipments` | `devices` (поля device_brand, device_model) | Слито в одну таблицу |
| `accounts` | `organizations` | Account → Organization |
| `users` | `users` (Auth Service) | JWT + Redis вместо MongoDB-сессий |
| `tariffs` | Billing Service (Post-MVP) | Отдельный микросервис |
| `events` | Kafka topics + `notification_log` | Event-driven архитектура |
| `notificationRules` | `notification_rules` | Notification Service |
| `geoZonesState` | `geozones` (PostGIS POLYGON) | Полноценный PostGIS |
| `lbses` | `gps_points` (valid=false, protocol='lbs') | LBS как подтип GPS-точек |

### 🆕 Новые маппинги (ранее не документированные)

| Legacy (MongoDB) | Новый проект | Статус |
|---|---|---|
| `groupsOfObjects` | **`vehicle_groups` + `vehicle_group_members`** | **MVP** — нужно добавить |
| `sensorNames` | **`sensor_profiles`** | **MVP** — автоопределённые датчики |
| `equipmentTypes` | **`device_types`** (уже есть!) | ✅ Покрыто |
| `sleeping` | `devices` (device_type='radio_tag') + SMS-модуль | **Post-MVP** |
| `smsconversation` | **`sms_commands`** | **Post-MVP** — SMS как канал команд |
| `smses` | **`sms_log`** | **Post-MVP** |
| `removalPeriods` | **`data_retention_policies`** | **Post-MVP** |
| `dealers` | `organizations` с иерархией (parent_organization_id) | **Post-MVP** — дилерская модель |
| `dealers.balanceHistory` | Billing Service | **Post-MVP** |
| `domainEvents` | Kafka topics (event log) | Kafka вместо Axon |
| `authlog` | **`audit_log`** | **MVP** — аудит-лог |
| `supportRequest` | Интеграция с Jira/Zendesk | **Post-MVP** |
| `authBackdors` | ❌ НЕ МИГРИРУЕМ | Security антипаттерн |
| `billingPermissions` | `users.permissions` JSONB | Единая модель прав |
| `paymentProcess/Stat` | Billing Service (внешний) | **Post-MVP** |
| `yandexPayment` | Billing Service | **Post-MVP** |
| `accountslastblocks` | ❌ НЕ НУЖНО | Legacy-костыль для ретрансляции после блокировки |
| `objects.removed` | `devices.deleted_at` (soft delete) | ✅ Покрыто |
| `usersPermissions.removed` | `audit_log` | Мягкое удаление |
| `objPacks.buffer` | Kafka (буфер по дизайну) | ✅ Покрыто архитектурно |
| `objPacks.removed` | TimescaleDB retention policy | ✅ Покрыто автоматически |

---

## 6. Ключевые отличия архитектур

### Legacy (MongoDB-centric)
- **Всё в одной БД** (MongoDB Seniel-dev2)
- GPS-позиции: **отдельная коллекция на каждый объект** (`objPacks.o{uid}`)
- Event Sourcing через **Axon Framework** (XML-сериализация)
- Геозоны: массив точек `[{lat, lon}]` (без пространственных индексов)
- Адреса: **Nominatim** (отдельный PostgreSQL с PostGIS)

### Новый проект (TimescaleDB + микросервисы)
- **Разделение на микросервисы** с выделенными хранилищами
- GPS-позиции: **одна hypertable** с автоматическим партиционированием по времени
- Events через **Kafka** (вместо Axon)
- Геозоны: **PostGIS POLYGON** с пространственными индексами GIST
- Continuous aggregates для аналитики (автоматические)
- **10,000+ точек/сек** (вместо ~100 в legacy)
