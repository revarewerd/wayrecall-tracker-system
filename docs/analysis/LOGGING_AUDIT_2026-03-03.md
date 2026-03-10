> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-03` | Версия: `1.0`

# 📊 Аудит логирования — Wayrecall Tracker (все 13 Scala сервисов)

## Общая сводка

| Метрика | Значение |
|---|---|
| **Всего .scala файлов (main)** | 263 |
| **Всего log statements** | 537 |
| **Файлов с логированием** | 88 (33%) |
| **Файлов без логирования** | 175 (67%) |
| **Avg log statements / file** | 2.04 |
| **Используемый фреймворк** | Исключительно `ZIO.log*` (0 сторонних) |
| **logTrace** | 0 во всех сервисах |
| **Комментариев на рус. языке** | 2505 — ✅ требование соблюдается |

### Распределение по уровням (все сервисы)

| Уровень | Кол-во | % |
|---|---|---|
| `ZIO.logInfo` | 296 | 55.1% |
| `ZIO.logDebug` | 107 | 19.9% |
| `ZIO.logWarning` | 61 | 11.4% |
| `ZIO.logError` | 73 | 13.6% |
| `ZIO.logTrace` | 0 | 0% |

---

## 1. Connection Manager (CM)

| Метрика | Значение |
|---|---|
| **Файлов main** | 50 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 104 / 46 / 32 / 28 / 0 |
| **Всего log statements** | 210 |
| **Файлов с логированием** | 18 (36%) |
| **Файлов без логирования** | 32 (64%) |
| **Комментариев (рус.)** | 713 |
| **Оценка** | ✅ **Адекватно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `network/ConnectionHandler.scala` | 61 |
| `Main.scala` | 44 |
| `service/CommandHandler.scala` | 13 |
| `service/DeviceEventConsumer.scala` | 11 |
| `network/TcpServer.scala` | 10 |
| `storage/VehicleLookupService.scala` | 9 |
| `storage/RedisClient.scala` | 8 |
| `protocol/DebugProtocolParser.scala` | 8 |
| `network/DeviceConfigListener.scala` | 8 |
| `network/ConnectionRegistry.scala` | 7 |
| `storage/KafkaProducer.scala` | 6 |
| `protocol/WialonAdapterParser.scala` | 6 |
| `network/CommandService.scala` | 6 |
| `config/DynamicConfigService.scala` | 5 |
| `network/IdleConnectionWatcher.scala` | 3 |
| `protocol/MultiProtocolParser.scala` | 2 |
| `network/RateLimiter.scala` | 2 |
| `api/HttpApi.scala` | 1 |

### Файлы БЕЗ логирования (32 файла)

- **6 command encoders**: `CommandEncoder`, `DtmEncoder`, `NavTelecomEncoder`, `RuptelaEncoder`, `TeltonikaEncoder`, `WialonEncoder`
- **5 domain models**: `Command`, `GpsPoint`, `ParseError`, `Protocol`, `Vehicle`
- **1 config**: `AppConfig`
- **2 filters**: `DeadReckoningFilter`, `StationaryFilter`
- **17 protocol parsers**: `AdmParser`, `ArnaviParser`, `AutophoneMayakParser`, `ConcoxParser`, `DtmParser`, `GalileoskyParser`, `GoSafeParser`, `GtltParser`, `MicroMayakParser`, `NavTelecomParser`, `ProtocolParser` (trait), `RuptelaParser`, `SkySimParser`, `TK102Parser`, `TeltonikaParser`, `WialonBinaryParser`, `WialonParser`
- **1 repository**: `DeviceRepository`

### Пробелы

- ⚠️ **17 GPS парсеров** — ни одного log statement. Ошибки парсинга будут незаметны в продакшене
- ⚠️ **6 command encoders** — нет логов при формировании команд для трекеров (критично для дебага)
- ⚠️ **DeadReckoningFilter / StationaryFilter** — фильтрация точек без логирования может скрыть потерю данных
- ⚠️ **DeviceRepository** — 0 логов при работе с БД
- ✅ ConnectionHandler (61 логов), Main (44), CommandHandler (13) — хорошо покрыты

---

## 2. Device Manager (DM)

| Метрика | Значение |
|---|---|
| **Файлов main** | 13 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 34 / 8 / 1 / 8 / 0 |
| **Всего log statements** | 51 |
| **Файлов с логированием** | 8 (62%) |
| **Файлов без логирования** | 5 (38%) |
| **Комментариев (рус.)** | 132 |
| **Оценка** | ✅ **Адекватно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `consumer/UnknownDeviceConsumer.scala` | 15 |
| `service/DeviceService.scala` | 12 |
| `infrastructure/RedisSyncService.scala` | 7 |
| `repository/DeviceRepository.scala` | 6 |
| `infrastructure/TransactorLayer.scala` | 3 |
| `infrastructure/KafkaPublisher.scala` | 3 |
| `Main.scala` | 3 |
| `api/DeviceRoutes.scala` | 2 |

### Файлы БЕЗ логирования (5 файлов)

- `api/HealthRoutes.scala`
- `config/AppConfig.scala`
- `domain/Entities.scala`, `domain/Errors.scala`, `domain/Events.scala`

### Пробелы

- ✅ Сервисный слой хорошо покрыт (DeviceService: 12, UnknownDeviceConsumer: 15)
- ✅ Единственный сервис с логированием в Repository (6 statements)
- ℹ️ `HealthRoutes.scala` — допустимо без логов (простая проверка)

---

## 3. History Writer (HW)

| Метрика | Значение |
|---|---|
| **Файлов main** | 12 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 8 / 6 / 1 / 4 / 0 |
| **Всего log statements** | 19 |
| **Файлов с логированием** | 6 (50%) |
| **Файлов без логирования** | 6 (50%) |
| **Комментариев (рус.)** | 71 |
| **Оценка** | ⚠️ **Недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `consumer/TelemetryConsumer.scala` | 6 |
| `service/HistoryService.scala` | 5 |
| `infrastructure/TransactorLayer.scala` | 3 |
| `Main.scala` | 3 |
| `repository/TelemetryRepository.scala` | 1 |
| `api/HistoryRoutes.scala` | 1 |

### Файлы БЕЗ логирования (6 файлов)

- `api/HealthRoutes.scala`
- `config/AppConfig.scala`
- `domain/Entities.scala`, `domain/Errors.scala`, `domain/Events.scala`
- `infrastructure/DoobieInstances.scala`

### Пробелы

- ⚠️ Всего **19 логов** для сервиса записи GPS-истории — **критически мало**
- ⚠️ Нет логирования **batch write performance** (сколько точек записано за запуск)
- ⚠️ Нет логирования **Kafka consumer lag**, скорости обработки
- ⚠️ `TelemetryRepository` — только 1 лог (должен логировать batch sizes, ошибки записи)

---

## 4. Rule Checker (RC)

| Метрика | Значение |
|---|---|
| **Файлов main** | 19 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 15 / 0 / 0 / 3 / 0 |
| **Всего log statements** | 18 |
| **Файлов с логированием** | 6 (32%) |
| **Файлов без логирования** | 13 (68%) |
| **Комментариев (рус.)** | 132 |
| **Оценка** | 🔴 **Критически недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `Main.scala` | 6 |
| `storage/SpatialGrid.scala` | 4 |
| `service/RuleCheckService.scala` | 2 |
| `kafka/GpsEventConsumer.scala` | 2 |
| `kafka/EventProducer.scala` | 2 |
| `infrastructure/TransactorLayer.scala` | 2 |

### Файлы БЕЗ логирования (13 файлов)

- **3 API routes**: `GeozoneRoutes`, `HealthRoutes`, `SpeedRuleRoutes`
- **2 repositories**: `GeozoneRepository`, `SpeedRuleRepository`
- **2 core checkers**: `GeozoneChecker`, `SpeedChecker` ❗
- **1 state manager**: `VehicleStateManager` ❗
- `config/AppConfig.scala`, `domain/Entities.scala`, `domain/Errors.scala`, `domain/Events.scala`, `infrastructure/DoobieInstances.scala`

### Пробелы

- 🔴 **0 logDebug / 0 logWarning** — невозможно диагностировать проблемы без DEBUG уровня
- 🔴 **GeozoneChecker** и **SpeedChecker** — **0 логов** в ключевой бизнес-логике!
- 🔴 **VehicleStateManager** — нет логов при изменении состояния транспорта
- ⚠️ **API routes** — 0 логов (нет request/response logging)
- ⚠️ Repositories — 0 логов при DB операциях

---

## 5. Notification Service (NS)

| Метрика | Значение |
|---|---|
| **Файлов main** | 24 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 14 / 3 / 1 / 6 / 0 |
| **Всего log statements** | 24 |
| **Файлов с логированием** | 9 (38%) |
| **Файлов без логирования** | 15 (62%) |
| **Комментариев (рус.)** | 137 |
| **Оценка** | ⚠️ **Недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `Main.scala` | 7 |
| `service/NotificationOrchestrator.scala` | 4 |
| `channel/WebhookChannel.scala` | 3 |
| `kafka/EventConsumer.scala` | 2 |
| `channel/TelegramChannel.scala` | 2 |
| `channel/SmsChannel.scala` | 2 |
| `channel/PushChannel.scala` | 2 |
| `service/RuleMatcher.scala` | 1 |
| `channel/EmailChannel.scala` | 1 |

### Файлы БЕЗ логирования (15 файлов)

- **4 API routes**: `HealthRoutes`, `HistoryRoutes`, `RuleRoutes`, `TemplateRoutes`
- **3 repositories**: `HistoryRepository`, `RuleRepository`, `TemplateRepository`
- **2 services**: `TemplateEngine`, `DeliveryService` ❗
- **1 channel trait**: `NotificationChannel`
- **1 throttle**: `ThrottleService` ❗
- `config/AppConfig.scala`, `domain/Entities.scala`, `domain/Errors.scala`, `infrastructure/TransactorLayer.scala`

### Пробелы

- ⚠️ **DeliveryService** — координирует доставку уведомлений, 0 логов
- ⚠️ **ThrottleService** — контроль rate limiting, 0 логов (невозможно определить throttled уведомления)
- ⚠️ **TemplateEngine** — rendering шаблонов, 0 логов
- ⚠️ Email/SMS/Push/Telegram channels имеют только 1-3 лога каждый — мало для внешних интеграций
- ⚠️ 4 API routes без логирования

---

## 6. Analytics Service (AS)

| Метрика | Значение |
|---|---|
| **Файлов main** | 29 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 7 / 0 / 0 / 4 / 0 |
| **Всего log statements** | 11 |
| **Файлов с логированием** | 4 (14%) |
| **Файлов без логирования** | 25 (86%) |
| **Комментариев (рус.)** | 191 |
| **Оценка** | 🔴 **Критически недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `scheduler/ReportScheduler.scala` | 7 |
| `exporting/ExportService.scala` | 2 |
| `generator/GeozoneReportGenerator.scala` | 1 |
| `Main.scala` | 1 |

### Файлы БЕЗ логирования (25 файлов)

- **4 API routes**: `ExportRoutes`, `HealthRoutes`, `ReportRoutes`, `ScheduledRoutes`
- **3 repositories**: `ReportHistoryRepository`, `ReportTemplateRepository`, `ScheduledReportRepository`
- **3 algorithms**: `FuelEventDetector`, `MileageCalculator`, `TripDetector` ❗
- **5 report generators**: `FuelReportGenerator`, `IdleReportGenerator`, `MileageReportGenerator`, `SpeedReportGenerator`, `SummaryReportGenerator` ❗
- **3 exporters**: `CsvExporter`, `ExcelExporter`, `PdfExporter`
- **1 cache**: `ReportCache`
- **1 query engine**: `QueryEngine` ❗
- `config/AppConfig.scala`, `domain/Errors.scala`, `domain/Reports.scala`, `infrastructure/TransactorLayer.scala`, `generator/ReportGenerator.scala` (trait)

### Пробелы

- 🔴 **11 логов на 29 файлов** — самое слабое логирование из всех сервисов
- 🔴 **0 logDebug / 0 logWarning** — невозможна диагностика
- 🔴 **5 из 6 report generators** без логирования — неизвестно, какие отчёты генерируются
- 🔴 **QueryEngine** — 0 логов (все SQL запросы невидимы)
- 🔴 **3 algorithm files** — 0 логов (MileageCalculator, TripDetector, FuelEventDetector)
- ⚠️ 4 API routes без логирования
- ⚠️ ReportCache — 0 логов (cache hits/misses невидимы)

---

## 7. User Service (US)

| Метрика | Значение |
|---|---|
| **Файлов main** | 20 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 2 / 0 / 0 / 2 / 0 |
| **Всего log statements** | 4 |
| **Файлов с логированием** | 4 (20%) |
| **Файлов без логирования** | 16 (80%) |
| **Комментариев (рус.)** | 95 |
| **Оценка** | 🔴 **Критически недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `service/UserService.scala` | 1 |
| `api/UserRoutes.scala` | 1 |
| `api/ManagementRoutes.scala` | 1 |
| `Main.scala` | 1 |

### Файлы БЕЗ логирования (16 файлов)

- **5 repositories**: `AuditRepository`, `CompanyRepository`, `RoleRepository`, `UserRepository`, `VehicleGroupRepository`
- **5 services**: `AuditService` ❗, `CompanyService`, `GroupService`, `PermissionService` ❗, `RoleService`
- **1 cache**: `PermissionCache`
- `api/HealthRoutes.scala`, `config/AppConfig.scala`, `domain/Errors.scala`, `domain/Models.scala`, `infrastructure/TransactorLayer.scala`

### Пробелы

- 🔴 **4 лога на весь сервис** — **КРИТИЧНО** для сервиса авторизации и пользователей!
- 🔴 **AuditService** — 0 логов в сервисе аудита (ирония: аудит без логов)
- 🔴 **PermissionService** — 0 логов при проверке прав доступа (security concern)
- 🔴 **UserService** — только 1 лог для всего CRUD пользователей
- 🔴 **0 logDebug / 0 logWarning** — слепая зона
- 🔴 Все 5 repositories — 0 логов

---

## 8. Admin Service (ADS)

| Метрика | Значение |
|---|---|
| **Файлов main** | 13 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 4 / 0 / 0 / 2 / 0 |
| **Всего log statements** | 6 |
| **Файлов с логированием** | 4 (31%) |
| **Файлов без логирования** | 9 (69%) |
| **Комментариев (рус.)** | 62 |
| **Оценка** | 🔴 **Критически недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `service/ConfigService.scala` | 3 |
| `service/StatsService.scala` | 1 |
| `api/AdminRoutes.scala` | 1 |
| `Main.scala` | 1 |

### Файлы БЕЗ логирования (9 файлов)

- **4 services**: `AdminAuditService` ❗, `BackgroundTaskService` ❗, `CompanyAdminService`, `SystemMonitorService` ❗
- `api/HealthRoutes.scala`, `config/AppConfig.scala`, `domain/Errors.scala`, `domain/Models.scala`, `infrastructure/TransactorLayer.scala`

### Пробелы

- 🔴 **6 логов** для сервиса системного администрирования — **КРИТИЧНО**
- 🔴 **SystemMonitorService** — 0 логов (мониторинг без логирования!)
- 🔴 **AdminAuditService** — 0 логов (ещё один аудит без логов)
- 🔴 **BackgroundTaskService** — 0 логов (фоновые задачи невидимы)
- ⚠️ AdminRoutes — 20+ catchAll handlers, но только 1 лог

---

## 9. Integration Service (IS)

| Метрика | Значение |
|---|---|
| **Файлов main** | 22 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 10 / 2 / 6 / 6 / 0 |
| **Всего log statements** | 24 |
| **Файлов с логированием** | 9 (41%) |
| **Файлов без логирования** | 13 (59%) |
| **Комментариев (рус.)** | 106 |
| **Оценка** | ⚠️ **Недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `retry/RetryService.scala` | 4 |
| `sync/RetranslationSyncService.scala` | 3 |
| `router/IntegrationRouter.scala` | 3 |
| `api/IntegrationRoutes.scala` | 3 |
| `Main.scala` | 3 |
| `kafka/EventConsumer.scala` | 2 |
| `inbound/InboundService.scala` | 2 |
| `circuit/CircuitBreaker.scala` | 2 |
| `api/InboundRoutes.scala` | 2 |

### Файлы БЕЗ логирования (13 файлов)

- **3 repositories**: `ApiKeyRepository`, `WebhookRepository`, `WialonRepository`
- **2 senders**: `WebhookSender` ❗, `WialonSender` ❗
- **1 protocol**: `WialonIpsProtocol`
- **1 validator**: `ApiKeyValidator` ❗
- **1 cache**: `IntegrationConfigCache`
- `api/HealthRoutes`, `config/AppConfig`, `domain/Errors`, `domain/Models`, `infrastructure/TransactorLayer`

### Пробелы

- ⚠️ **WebhookSender** и **WialonSender** — 0 логов в компонентах отправки данных наружу
- ⚠️ **ApiKeyValidator** — 0 логов при валидации API ключей (security concern)
- ⚠️ CircuitBreaker — только 2 лога (недостаточно для отслеживания state transitions)
- ✅ RetryService (4), IntegrationRouter (3) — покрыты удовлетворительно

---

## 10. Maintenance Service (MS)

| Метрика | Значение |
|---|---|
| **Файлов main** | 20 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 16 / 9 / 1 / 7 / 0 |
| **Всего log statements** | 33 |
| **Файлов с логированием** | 9 (45%) |
| **Файлов без логирования** | 11 (55%) |
| **Комментариев (рус.)** | 215 |
| **Оценка** | ⚠️ **Частично адекватно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `scheduler/MaintenanceJobs.scala` | 13 |
| `service/MaintenancePlanner.scala` | 4 |
| `service/ReminderEngine.scala` | 3 |
| `service/MileageTracker.scala` | 3 |
| `kafka/MileageConsumer.scala` | 3 |
| `service/MaintenanceService.scala` | 2 |
| `kafka/MaintenanceEventProducer.scala` | 2 |
| `Main.scala` | 2 |
| `api/MaintenanceRoutes.scala` | 1 |

### Файлы БЕЗ логирования (11 файлов)

- **4 repositories**: `OdometerRepository`, `ScheduleRepository`, `ServiceRecordRepository`, `TemplateRepository`
- **1 service**: `IntervalCalculator`
- **1 cache**: `MaintenanceCache`
- `api/HealthRoutes`, `config/AppConfig`, `domain/Errors`, `domain/Models`, `infrastructure/TransactorLayer`

### Пробелы

- ✅ MaintenanceJobs (13 логов), MaintenancePlanner (4) — хорошо покрыты
- ⚠️ 4 repositories — 0 логов (операции с расписанием ТО, пробегом невидимы)
- ⚠️ MaintenanceCache — 0 логов

---

## 11. Sensors Service (SS)

| Метрика | Значение |
|---|---|
| **Файлов main** | 19 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 3 / 1 / 5 / 2 / 0 |
| **Всего log statements** | 11 |
| **Файлов с логированием** | 5 (26%) |
| **Файлов без логирования** | 14 (74%) |
| **Комментариев (рус.)** | 78 |
| **Оценка** | 🔴 **Критически недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `processing/SensorProcessor.scala` | 4 |
| `kafka/GpsEventConsumer.scala` | 4 |
| `kafka/SensorEventProducer.scala` | 1 |
| `api/SensorRoutes.scala` | 1 |
| `Main.scala` | 1 |

### Файлы БЕЗ логирования (14 файлов)

- **3 repositories**: `CalibrationRepository`, `EventRepository`, `SensorRepository`
- **3 processing**: `EventDetector` ❗, `FuelCalibrator` ❗, `IoExtractor`, `Smoother`
- **1 service**: `SensorsService` ❗
- **1 state store**: `SensorStateStore`
- `api/HealthRoutes`, `config/AppConfig`, `domain/Errors`, `domain/Models`, `infrastructure/TransactorLayer`

### Пробелы

- 🔴 **SensorsService** — 0 логов в основном сервисном слое
- 🔴 **EventDetector** — 0 логов (обнаружение слива/заправки невидимо)
- 🔴 **FuelCalibrator** — 0 логов (калибровка датчиков топлива невидима)
- ⚠️ SensorStateStore — 0 логов при работе с Redis state

---

## 12. WebSocket Service (WS)

| Метрика | Значение |
|---|---|
| **Файлов main** | 12 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 14 / 0 / 7 / 0 / 0 |
| **Всего log statements** | 21 |
| **Файлов с логированием** | 6 (50%) |
| **Файлов без логирования** | 6 (50%) |
| **Комментариев (рус.)** | 96 |
| **Оценка** | ⚠️ **Недостаточно** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `api/WebSocketHandler.scala` | 6 |
| `Main.scala` | 5 |
| `kafka/EventConsumer.scala` | 4 |
| `service/ConnectionRegistry.scala` | 3 |
| `kafka/GpsEventConsumer.scala` | 2 |
| `service/MessageRouter.scala` | 1 |

### Файлы БЕЗ логирования (6 файлов)

- `service/PositionThrottler.scala`
- `api/HealthRoutes.scala`, `config/AppConfig.scala`
- `domain/Entities.scala`, `domain/Errors.scala`, `domain/Messages.scala`

### Пробелы

- ⚠️ **0 logError** — ошибки WS-соединений не логируются на уровне ERROR (всё через Warning)
- ⚠️ **0 logDebug** — отсутствует debug-уровень для диагностики
- ⚠️ **PositionThrottler** — 0 логов (throttling невидим)
- ✅ WebSocketHandler (6), ConnectionRegistry (3) — базовое покрытие есть

---

## 13. API Gateway (AG)

| Метрика | Значение |
|---|---|
| **Файлов main** | 10 |
| **logInfo / logDebug / logWarning / logError / logTrace** | 65 / 32 / 7 / 1 / 0 |
| **Всего log statements** | 105 |
| **Файлов с логированием** | 8 (80%) |
| **Файлов без логирования** | 2 (20%) |
| **Комментариев (рус.)** | 477 |
| **Оценка** | ✅ **Хорошо** |

### Файлы С логированием

| Файл | Кол-во |
|---|---|
| `Main.scala` | 56 |
| `routing/ApiRouter.scala` | 23 |
| `service/HealthService.scala` | 6 |
| `middleware/AuthMiddleware.scala` | 6 |
| `service/AuthService.scala` | 5 |
| `middleware/LogMiddleware.scala` | 4 |
| `service/ProxyService.scala` | 3 |
| `middleware/CorsMiddleware.scala` | 2 |

### Файлы БЕЗ логирования (2 файла)

- `config/GatewayConfig.scala`
- `domain/Models.scala`

### Пробелы

- ⚠️ Только **1 logError** — маловато для Gateway (ошибки проксирования, timeout'ы)
- ✅ 80% файлов с логированием — лучший показатель среди всех сервисов
- ✅ AuthMiddleware (6 логов), LogMiddleware (4) — запросы логируются
- ✅ ApiRouter (23 лога) — маршрутизация прозрачна

---

## Сводная таблица

| # | Сервис | Файлов main | Логов | С лог. | Без лог. | logError | Оценка |
|---|---|---|---|---|---|---|---|
| 1 | **Connection Manager** | 50 | 210 | 18 (36%) | 32 (64%) | 28 | ✅ Адекватно |
| 2 | **Device Manager** | 13 | 51 | 8 (62%) | 5 (38%) | 8 | ✅ Адекватно |
| 3 | **History Writer** | 12 | 19 | 6 (50%) | 6 (50%) | 4 | ⚠️ Недостаточно |
| 4 | **Rule Checker** | 19 | 18 | 6 (32%) | 13 (68%) | 3 | 🔴 Критично |
| 5 | **Notification Service** | 24 | 24 | 9 (38%) | 15 (62%) | 6 | ⚠️ Недостаточно |
| 6 | **Analytics Service** | 29 | 11 | 4 (14%) | 25 (86%) | 4 | 🔴 Критично |
| 7 | **User Service** | 20 | 4 | 4 (20%) | 16 (80%) | 2 | 🔴 Критично |
| 8 | **Admin Service** | 13 | 6 | 4 (31%) | 9 (69%) | 2 | 🔴 Критично |
| 9 | **Integration Service** | 22 | 24 | 9 (41%) | 13 (59%) | 6 | ⚠️ Недостаточно |
| 10 | **Maintenance Service** | 20 | 33 | 9 (45%) | 11 (55%) | 7 | ⚠️ Частично |
| 11 | **Sensors Service** | 19 | 11 | 5 (26%) | 14 (74%) | 2 | 🔴 Критично |
| 12 | **WebSocket Service** | 12 | 21 | 6 (50%) | 6 (50%) | 0 | ⚠️ Недостаточно |
| 13 | **API Gateway** | 10 | 105 | 8 (80%) | 2 (20%) | 1 | ✅ Хорошо |
| | **ИТОГО** | **263** | **537** | **96 (37%)** | **167 (63%)** | **73** | |

---

## Русские комментарии в коде

| Сервис | Кол-во комментариев на русском |
|---|---|
| Connection Manager | 713 |
| API Gateway | 477 |
| Maintenance Service | 215 |
| Analytics Service | 191 |
| Notification Service | 137 |
| Rule Checker | 132 |
| Device Manager | 132 |
| Integration Service | 106 |
| WebSocket Service | 96 |
| User Service | 95 |
| Sensors Service | 78 |
| History Writer | 71 |
| Admin Service | 62 |
| **ИТОГО** | **2505** |

✅ Все сервисы содержат русскоязычные комментарии. Требование `copilot-instructions.md` соблюдается.

---

## Критические нарушения (ТОП-10 по приоритету)

| # | Проблема | Сервис | Влияние |
|---|---|---|---|
| 1 | **AuditService без логов** | User Service | Security: аудит действий пользователей не отслеживается |
| 2 | **PermissionService без логов** | User Service | Security: проверки доступа невидимы |
| 3 | **AdminAuditService без логов** | Admin Service | Security: админ-аудит без логов |
| 4 | **SystemMonitorService без логов** | Admin Service | Ops: мониторинг системы без логов |
| 5 | **GeozoneChecker / SpeedChecker без логов** | Rule Checker | Core biz: нарушения правил невидимы |
| 6 | **EventDetector / FuelCalibrator без логов** | Sensors Service | Core biz: события датчиков невидимы |
| 7 | **5 из 6 ReportGenerators без логов** | Analytics Service | Core biz: генерация отчётов слепая |
| 8 | **WebhookSender / WialonSender без логов** | Integration Service | Integrations: исходящие запросы невидимы |
| 9 | **17 GPS парсеров без логов** | Connection Manager | Core: ошибки парсинга протоколов невидимы |
| 10 | **0 logTrace** во всех сервисах | Все | Debug: нет самого детального уровня |

---

## Системные паттерны (что отсутствует повсеместно)

1. **Repository layer** — 24 из 26 repository файлов (92%) не имеют ни одного лога
2. **API Routes** — 19 из 27 routes файлов (70%) не имеют логирования
3. **HealthRoutes** — 0 логов во всех 13 сервисах (допустимо)
4. **logTrace** — не используется ни в одном сервисе
5. **Structured logging** (key-value annotations) — не обнаружен `@@ LogAnnotation` паттерн
6. **Request ID / Correlation ID** — не обнаружен в логах

---

## Рекомендации

### Приоритет 1 (Security + Core Business)
- Добавить логирование в **User Service** (AuditService, PermissionService, UserService) — минимум INFO для каждой операции
- Добавить логирование в **Admin Service** (SystemMonitorService, AdminAuditService, BackgroundTaskService)
- Добавить логирование в **Rule Checker** (GeozoneChecker, SpeedChecker, VehicleStateManager) — каждое срабатывание правила

### Приоритет 2 (Observability)
- Добавить `logDebug` во все service layer файлы (параметры вызовов, промежуточные результаты)
- Добавить `logError` с `tapError` для всех DB операций в repository layer
- Добавить `logWarning` для деградированных ситуаций (cache miss, retry, fallback)

### Приоритет 3 (Архитектура)
- Внедрить **structured logging** через `ZIO.logAnnotate` (добавлять `deviceId`, `orgId`, `requestId`)
- Ввести **correlation ID** для трассировки запросов между сервисами
- Добавить `logTrace` для hot-path операций (парсинг GPS, обработка потока точек)
- Создать единый **logging middleware** для всех API routes (request/response с timing)
