# 📚 План изучения проекта Wayrecall Tracker

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-06` | Версия: `1.0`

## Цель

Полностью разобраться в архитектуре и коде всех 17 микросервисов системы Wayrecall Tracker.

---

## Фаза 1: Общая архитектура (1-2 дня)

### Последовательность чтения:

1. **[docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)** — общая архитектура 3 блоков
2. **[docs/ARCHITECTURE_BLOCK1.md](../docs/ARCHITECTURE_BLOCK1.md)** — Data Collection (CM, DM, HW)
3. **[docs/ARCHITECTURE_BLOCK2.md](../docs/ARCHITECTURE_BLOCK2.md)** — Business Logic
4. **[docs/ARCHITECTURE_BLOCK3.md](../docs/ARCHITECTURE_BLOCK3.md)** — Presentation
5. **[docs/DATA_STORES.md](../docs/DATA_STORES.md)** — все БД и хранилища
6. **[docs/STELS_GAP_ANALYSIS.md](../docs/STELS_GAP_ANALYSIS.md)** — что покрыто, что нет

### Контрольные вопросы:
- [ ] Могу нарисовать схему 17 сервисов и как они связаны
- [ ] Знаю какие БД/кэши использует каждый сервис
- [ ] Понимаю путь GPS-точки от трекера до карты пользователя
- [ ] Знаю все Kafka топики и кто их consume/produce

---

## Фаза 2: Block 1 — Data Collection (3-5 дней)

### Connection Manager (самый сложный, 50 файлов)

**Порядок чтения кода:**
1. `docs/README.md` → `docs/ARCHITECTURE.md` — что делает, как устроен
2. `Main.scala` — точка входа, ZIO layers
3. `config/AppConfig.scala` — конфигурация
4. `domain/` — все типы данных (GpsPoint, DeviceContext, Command)
5. `network/TcpServer.scala` — Netty TCP сервер
6. `network/ProtocolDetector.scala` — определение протокола по первому пакету
7. `protocol/TeltonikaProtocol.scala` — парсинг Teltonika (самый распространённый)
8. `protocol/WialonIpsProtocol.scala` — парсинг Wialon IPS
9. `filter/DeadReckoningFilter.scala` — фильтрация невалидных точек
10. `kafka/GpsEventProducer.scala` — публикация в Kafka
11. `redis/DeviceContextStore.scala` — хранение состояния в Redis
12. `service/CommandService.scala` — обработка команд на трекер

**Контрольные вопросы:**
- [ ] Как работает определение протокола (magic bytes)?
- [ ] Как устроен pipeline: TCP → parse → filter → Kafka?
- [ ] Как хранится состояние соединения (DeviceContext)?
- [ ] Как выполняются команды на трекер (блокировка, перенастройка)?
- [ ] Как работает Dead Reckoning фильтр?

### Device Manager (13 файлов)

1. `docs/README.md` → `docs/API.md`
2. `Main.scala` → `config/`
3. `domain/Device.scala` — модель устройства
4. `api/DeviceRoutes.scala` — REST endpoints
5. `repository/DeviceRepository.scala` — Doobie queries
6. `service/DeviceService.scala` — бизнес-логика
7. `kafka/CommandProducer.scala` — отправка команд в Kafka

**Контрольные вопросы:**
- [ ] Как работает CRUD устройств?
- [ ] Как отправляются команды на трекер через Kafka?
- [ ] Как связан Device Manager с Connection Manager?

### History Writer (12 файлов)

1. `Main.scala` → `config/`
2. `kafka/GpsEventConsumer.scala` — потребление GPS из Kafka
3. `repository/GpsPointRepository.scala` — запись в TimescaleDB
4. `service/HistoryService.scala` — агрегация и обработка

**Контрольные вопросы:**
- [ ] Как работает batch insert в TimescaleDB?
- [ ] Как устроена compression и retention policy?
- [ ] Consumer group и partitioning strategy?

---

## Фаза 3: Block 2 — Business Logic (5-7 дней)

### Порядок изучения:

| # | Сервис | Файлов | Приоритет | Зависит от |
|---|--------|--------|-----------|------------|
| 1 | Rule Checker | 19 | 🔴 | CM, HW |
| 2 | Notification Service | 24 | 🔴 | Rule Checker |
| 3 | Sensors Service | 19 | 🟡 | CM |
| 4 | Maintenance Service | 20 | 🟡 | Sensors |
| 5 | Analytics Service | 29 | 🟡 | HW |
| 6 | User Service | 20 | 🟡 | — |
| 7 | Integration Service | 22 | 🟢 | CM, HW |
| 8 | Admin Service | 13 | 🟢 | — |
| 9 | Billing Service | 15 | 🟢 | — |
| 10 | Ticket Service | 10 | 🟢 | — |

Для каждого сервиса:
1. Читать `docs/README.md` → `docs/ARCHITECTURE.md`
2. `Main.scala` → `config/` → `domain/`
3. `service/` — основная логика
4. `kafka/` или `api/` — входные/выходные точки
5. `repository/` — работа с БД
6. Тесты в `src/test/` — примеры использования

---

## Фаза 4: Block 3 — Presentation (2-3 дня)

### WebSocket Service (12 файлов)
- Real-time позиции через Kafka → WebSocket
- Подписка/отписка на устройства

### API Gateway (10 файлов)
- JWT аутентификация, rate limiting, маршрутизация

### Web Frontend (React + TypeScript)
- Leaflet карта, маршруты, управление устройствами

---

## Фаза 5: Инфраструктура (1-2 дня)

1. **docker-compose.yml** — как запустить весь стек
2. **infra/databases/** — SQL схемы-инициализации
3. **infra/scripts/** — скрипты запуска
4. **test-stand/** — тестовый стенд
5. **build.sbt** — зависимости и модули

---

## Фаза 6: Legacy Stels (справочно, 2-3 дня)

1. **[docs/LEGACY_API.md](../docs/LEGACY_API.md)** — 78 методов старого API
2. **[docs/STELS_GEOZONE_ANALYSIS.md](../docs/STELS_GEOZONE_ANALYSIS.md)** — анализ геозон
3. **[docs/STELS_GAP_ANALYSIS.md](../docs/STELS_GAP_ANALYSIS.md)** — полный GAP-анализ
4. `legacy-stels/packreceiver/` — TCP сервер (аналог CM)
5. `legacy-stels/core/` — парсеры протоколов
6. `legacy-stels/monitoring/` — всё остальное (монолит)

---

## Общий таймлайн

| Фаза | Время | Кумулятивно |
|------|-------|-------------|
| 1. Архитектура | 1-2 дня | 2 дня |
| 2. Block 1 | 3-5 дней | 7 дней |
| 3. Block 2 | 5-7 дней | 14 дней |
| 4. Block 3 | 2-3 дня | 17 дней |
| 5. Инфраструктура | 1-2 дня | 19 дней |
| 6. Legacy | 2-3 дня | 22 дня |

**Итого: ~3-4 недели** на полное изучение всего проекта.

---

*Версия: 1.0 | Обновлён: 6 июня 2026 | Тег: АКТУАЛЬНО*
