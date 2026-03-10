# Аудит логирования всех сервисов

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-02` | Версия: `1.0`

## Итоги аудита

**Дата аудита:** 2 июня 2026
**Всего сервисов:** 15
**Общее количество ZIO.log* до аудита:** ~537
**Добавлено логирования:** ~80+ новых log-выражений в 20+ файлах

---

## Результаты по сервисам

### Сервисы с адекватным логированием (не изменялись)

| Сервис | Логов | Файлов | Комментарий |
|--------|-------|--------|-------------|
| Connection Manager | 210 | 36 | Отлично покрыт |
| API Gateway | 105 | 24 | Middleware + routes |
| Device Manager | 51 | 18 | CRUD + Kafka |
| WebSocket Service | 21 | 12 | WS + Kafka consumers |
| History Writer | 19 | 12 | Consumer + service OK |

### Сервисы с улучшенным логированием

| Сервис | Было | Стало (≈) | Файлов изменено | Что добавлено |
|--------|------|-----------|-----------------|---------------|
| **User Service** | 4 | ~35 | 6 | createUser, updateProfile, changePassword, assignRole, deactivateUser, permissions cache, audit, roles, companies, groups |
| **Admin Service** | 6 | ~26 | 4 | CompanyAdmin CRUD, BackgroundTask lifecycle, AuditLog, SystemMonitor health |
| **Sensors Service** | 11 | ~18 | 2 | createSensor, deleteSensor, calibration CRUD, pipeline entry/events |
| **Rule Checker** | 18 | ~35 | 2 | GeozoneChecker (SpatialGrid→PostGIS→anti-bounce), SpeedChecker (rules/violations/cooldown/cache) |
| **Analytics Service** | 10 | ~22 | 4 | MileageReport, FuelReport (+ drain warning), SummaryReport, ExportService |
| **Notification Service** | 24 | ~34 | 4 | DeliveryService routing, TemplateEngine render/fallback, ThrottleService throttle/rate-limit, RuleMatcher conditions |
| **Integration Service** | 24 | ~35 | 3 | WebhookSender (send/status/error), WialonSender (connect/login/reject), ApiKeyValidator (validate/disabled warning) |
| **Maintenance Service** | 33 | ~42 | 1 | updateTemplate, deleteTemplate, createSchedule, pauseSchedule, resumeSchedule, getCompanyOverview |

---

## Стандарт логирования

Полный стандарт добавлен в `.github/copilot-instructions.md` (секция 12).

### Ключевые правила:
1. **Все логи на русском** (кроме технических ID)
2. **Префикс модуля**: `"Геозоны: ..."`, `"Скорость: ..."`, `"ТО: ..."`
3. **Контекст всегда**: vehicleId, orgId, userId, count
4. **logInfo** → мутации (create/update/delete)
5. **logWarning** → permission denied, деактивация, аномалии
6. **logDebug** → cache hit/miss, pipeline шаги, queries
7. **logError** → непредвиденные сбои (не для бизнес-ошибок)

### Файлы без логов (допустимо)
- `domain/` — case classes, sealed traits
- `config/` — AppConfig
- `infrastructure/` — TransactorLayer
- Чистые алгоритмы (MileageCalculator, TripDetector)
