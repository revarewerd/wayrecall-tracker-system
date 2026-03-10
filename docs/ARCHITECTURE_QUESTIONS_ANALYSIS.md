# 🔍 Архитектурный анализ: открытые вопросы и решения

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-03` | Версия: `1.1`

---

## 📑 Содержание

1. [Real-time мониторинг: доставка данных на фронтенд](#1-real-time-мониторинг-доставка-данных-на-фронтенд)
2. [Аутентификация и роли: где проверять?](#2-аутентификация-и-роли-где-проверять)
3. [Безопасность: изоляция внутренних сервисов](#3-безопасность-изоляция-внутренних-сервисов)
4. [Недостающие сервисы и компоненты](#4-недостающие-сервисы-и-компоненты)
5. [Рекомендации и приоритеты](#5-рекомендации-и-приоритеты)

---

## 1. Real-time мониторинг: доставка данных на фронтенд

### 1.1 Как было в Legacy Stels

Legacy Stels использовал **HTTP polling каждые 2 секунды**:

```
Browser (ExtJS 4.2)
    ↓ setInterval(2000ms)
    ↓ Ext.Direct.MapObjects.getUpdatedAfter(lastTimestamp)
    ↓ HTTP POST → Spring MVC → PostgreSQL query
    ↓ JSON ответ: ВСЕ объекты с обновлёнными позициями
    ↓ Полная перерисовка маркеров на OpenLayers
```

**Проблемы legacy-подхода:**
- **Задержка 2-4 сек** — неприемлемо для мониторинга в реальном времени
- **Тяжёлая нагрузка на БД** — SELECT по всем устройствам каждые 2 сек × N пользователей
- **Неэффективно**: полная перерисовка даже если 1 из 500 устройств обновилось
- **Плохо масштабируется**: 100 пользователей × 1 запрос/2сек = 50 req/sec на один SELECT

### 1.2 Как будет в Wayrecall Tracker

**Push-модель через WebSocket + Kafka:**

```
GPS Трекер (1 пакет/1-60сек)
    ↓ TCP packet
Connection Manager
    ↓ parse → filter → enrich
    ↓ publish Kafka "gps-events" (key=deviceId)
    ↓   (CM НЕ пишет позиции в Redis — только Kafka)
    ↓
WebSocket Service (Kafka consumer group: ws-positions)
    ↓ consume gps-events
    ↓ lookup: deviceId → orgId → rooms
    ↓ throttle: max 1 msg/sec per device
    ↓ WS frame (JSON) → Browser
    ↓
React + Leaflet → zustand store → marker.setLatLng()
```

### 1.3 Отдельный Kafka-топик или тот же gps-events?

#### Вариант A: WebSocket Service читает напрямую из `gps-events` ⭐ РЕКОМЕНДУЕМ

```
CM → publish → gps-events (12 partitions)
                    ↓ consumer group: history-writer     → TimescaleDB
                    ↓ consumer group: ws-positions        → WebSocket → Browser
                    ↓ consumer group: sensors-processor   → Sensors Service
```

**Плюсы:**
- Нет дополнительного топика → проще инфраструктура
- Kafka consumer groups гарантируют что каждая группа получит ВСЕ сообщения
- Минимальная задержка (нет дополнительного hop)
- Каждый consumer group читает независимо — не мешают друг другу

**Минусы:**
- WS Service получает ВСЕ точки (включая stationary/invalid) — нужен фильтр на стороне WS
- Больше load на Kafka (дополнительный consumer group)

#### Вариант B: Отдельный топик `gps-events-realtime`

```
CM → publish → gps-events         → History Writer, Sensors
CM → publish → gps-events-realtime → WebSocket Service (только moving + valid)
```

**Плюсы:**
- WS Service получает только нужные точки (уже отфильтрованные CM)
- Можно настроить другой retention (например, 1 день вместо 7)

**Минусы:**
- CM публикует в 2 (или 3) топика — больше Kafka writes (+50% produce)
- Ещё один топик для поддержки
- Дублирование данных

#### Вариант C: WebSocket Service читает из `gps-events` + события из отдельных топиков

```
gps-events            → WS consumer group "ws-positions"  (позиции)
geozone-events        → WS consumer group "ws-events"     (события геозон)
speed-events          → WS consumer group "ws-events"     (превышения)
sensor-events         → WS consumer group "ws-events"     (датчики)
maintenance-events    → WS consumer group "ws-events"     (ТО)
```

**Плюсы:**
- Полная картина: и позиции, и события в одном WS-соединении
- Consumer groups обеспечивают надёжную доставку
- Идеально для Dashboard: карта + лента событий в реальном времени

**Минусы:**
- WS Service подписан на 5+ топиков — чуть сложнее
- Потребляет больше ресурсов при высоком потоке

#### 📊 Сравнительная матрица

| Критерий | A: gps-events напрямую | B: Отдельный топик | C: gps-events + события |
|---|---|---|---|
| Задержка | ~100ms ⭐ | ~100ms | ~100ms |
| Сложность инфры | Низкая ⭐ | Средняя | Средняя |
| Kafka writes CM | Без изменений ⭐ | +50% | Без изменений ⭐ |
| Фильтрация на WS | Нужна | Не нужна | Частично нужна |
| Полнота данных | Только позиции | Только позиции | Позиции + события ⭐ |
| Production-ready | Хорошо | Хорошо | Лучше ⭐ |

**Вывод:** Рекомендую **Вариант C** — WS Service читает `gps-events` для позиций + событийные топики для алертов. Так Dashboard получает полную картину: карта в реальном времени + лента событий.

### 1.4 Частота обновлений

| Сценарий | Частота от трекера | Частота в WS (throttled) | Комментарий |
|---|---|---|---|
| Движение (обзор org) | 1-60 pk/sec | **Max 1 msg/sec** на устройство | Достаточно для плавного перемещения маркера |
| Движение (фокус на 1 устройстве) | 1-60 pk/sec | **Max 2 msg/sec** | Более детальное обновление при zoom |
| Стоянка | 1 pk/5-60 min | **Не отправляется** | Маркер не двигается — нет смысла слать |
| Событие (геозона, скорость) | По факту | **Немедленно** (без throttle) | Алерты не throttle'ятся |

### 1.5 Initial Load (первое открытие карты)

Когда пользователь открывает карту, ему нужны **текущие позиции всех устройств** организации.

```
1. Browser → REST GET /api/v1/devices/positions?org_id=X
   → API Gateway → Device Manager → TimescaleDB (последняя точка каждого устройства)
   → JSON: [{deviceId, lat, lon, speed, course, ts}, ...]

2. Browser → WebSocket connect ws://host/ws?token=xxx
   → WS Service → subscribe {type: "vehicles", orgId: 123}
   → Server → "subscribed" confirmation

3. WS → push позиций по мере обновления (delta, не full state)
```

**Почему не только WebSocket?** WS не хранит историю. Если пользователь подключился, он получит только новые обновления. Initial load нужен через REST + TimescaleDB (или кэш).

### 1.6 Диаграмма потока данных

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                        REAL-TIME МОНИТОРИНГ                                  │
│                                                                              │
│  GPS Трекер ──TCP──► Connection Manager                                     │
│                         │                                                    │
│                         ├─► Kafka: gps-events ──────────┬──► History Writer  │
│                         │                                │                    │
│                         │                                ├──► Sensors Service │
│                         │                                │                    │
│                         │                                └──► WebSocket Svc  │
│                         │                                       │             │
│                         │    ┌───────────────────────────────────┘             │
│                         │    │                                                │
│  Browser ◄── REST ◄── API GW ◄── Device Manager (initial load из TimescaleDB)│
│  Browser ◄── WS ◄──── WebSocket Service (real-time delta from Kafka)          │
│                                                                              │
│  Legacy Stels:  HTTP polling 2sec → PostgreSQL SELECT → полная перерисовка    │
│  Wayrecall:     WS push on change → Kafka stream → delta update < 150ms     │
└──────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Аутентификация и роли: где проверять?

### 2.1 Текущий дизайн

Да, в текущем дизайне **аутентификация и авторизация сосредоточены в API Gateway**:

```
Browser → API Gateway → Auth Middleware → проверка JWT/API Key
                            │
                            ├─ Bearer token → authService.validateToken(token)
                            │                  → UserContext {userId, companyId, roles, permissions}
                            │
                            ├─ ApiKey key   → authService.validateApiKey(key)
                            │                  → ApiKeyContext {keyId, companyId, permissions}
                            │
                            └─ Нет заголовка → AuthResult.Anonymous → 401 Unauthorized
```

После проверки API Gateway добавляет заголовки и проксирует запрос:

```
API Gateway → Backend Service
  Headers:
    X-User-Id: uuid
    X-Company-Id: uuid
    X-Roles: admin,user
    X-Permissions: devices:read,devices:write
    X-Request-Id: uuid
```

Backend-сервисы **доверяют этим заголовкам** и не проверяют JWT повторно.

### 2.2 Варианты реализации auth

#### Вариант A: Только API Gateway (Centralized Auth) ⭐ РЕКОМЕНДУЕМ для MVP

```
                    ┌────────────────────┐
Browser ──────────► │    API Gateway     │
                    │  ┌──────────────┐  │
                    │  │ JWT Validate │  │
                    │  │ Role Check   │  │
                    │  │ Rate Limit   │  │
                    │  └──────┬───────┘  │
                    │         │          │
                    └─────────┼──────────┘
                              │ X-User-Id, X-Company-Id, X-Roles
                              ▼
                    ┌──────────────────┐
                    │  Backend Service │  ← доверяет заголовкам
                    │  (Device Manager)│
                    └──────────────────┘
```

**Плюсы:**
- Единая точка проверки — DRY, нет дублирования логики авторизации
- Проще обновлять правила доступа (одно место)
- Backend-сервисы легче и быстрее (нет JWT-библиотек)
- Проще тестировать (mock заголовки)

**Минусы:**
- **Single point of failure** — если API GW пропустит неаутентифицированный запрос
- Если кто-то обратится напрямую к backend (обходя GW) — нет защиты
- Backend-сервисы "слепо доверяют" заголовкам

#### Вариант B: API Gateway + легковесная проверка в каждом сервисе (Defense in Depth)

```
API Gateway:
  ✓ JWT validation (полная)
  ✓ Token expiry check
  ✓ Rate limiting
  ✓ Role-based routing (грубая: admin vs user)
  → Forwards: X-User-Id, X-Company-Id, X-Roles + X-Auth-Signature (HMAC)

Backend Service:
  ✓ Проверка X-Auth-Signature (shared secret между GW и сервисами)
  ✓ Проверка X-Company-Id совпадает с organization_id в запросе
  ✓ Fine-grained permissions (devices:write нужен для PUT /devices/)
  ✗ НЕ проверяет JWT повторно
```

**Плюсы:**
- Защита от прямого доступа к backend (без подписи GW — 403)
- Backend подтверждает что org_id в запросе = org_id пользователя (multi-tenant safety!)
- Fine-grained permissions: API GW не знает бизнес-логику, сервис знает
- Defence in depth — 2 уровня защиты

**Минусы:**
- Чуть больше кода в каждом сервисе (middleware для проверки подписи)
- HMAC shared secret нужно ротировать и хранить в секретах
- Усложняет тестирование (нужно генерировать подписи)

#### Вариант C: JWT Propagation (каждый сервис проверяет JWT)

```
API Gateway:
  ✓ Rate limiting
  ✓ Грубая маршрутизация
  → Forwards: оригинальный JWT в Authorization header

Backend Service:
  ✓ Полная JWT validation (RS256 public key)
  ✓ Token expiry check
  ✓ Role + permission check
```

**Плюсы:**
- Полная независимость сервисов (Zero Trust)
- Каждый сервис сам решает, какие роли допустимы
- Работает даже если API GW обойдён

**Минусы:**
- Дублирование JWT-библиотеки в каждом сервисе
- На каждый запрос N сервисов проверяют один и тот же JWT → CPU waste
- Все сервисы должны иметь доступ к public key
- Сложнее управлять правами (распределены по N сервисам)

#### 📊 Сравнительная матрица

| Критерий | A: Только GW | B: GW + Signature | C: JWT Propagation |
|---|---|---|---|
| Простота реализации | ⭐ Простейшая | Средняя | Сложная |
| Защита от bypass | ❌ Нет | ✅ HMAC signature | ✅ JWT в каждом сервисе |
| Multi-tenant safety | ⚠️ Только в GW | ✅ + проверка в сервисе | ✅ + проверка в сервисе |
| Производительность | ⭐ | ⭐ (HMAC дешёвый) | ⚠️ (RSA verify × N) |
| DRY | ⭐ | Хорошо | ❌ Дублирование |
| Fine-grained permissions | В GW (неудобно) | В сервисах ⭐ | В сервисах ⭐ |
| Для MVP | ⭐ Рекомендуем | Рекомендуем post-MVP | Избыточно |

**Вывод:** Для MVP **Вариант A** — auth только в API Gateway. После выхода в production рекомендуется перейти к **Вариант B** (GW + HMAC signature) для defence in depth.

### 2.3 Auth Service — отдельный или часть API Gateway?

Сейчас в документация описаны два отдельных сервиса:
- **API Gateway** (port 8080) — маршрутизация, middleware pipeline
- **Auth Service** (port 8092) — JWT, refresh tokens, 2FA, сессии

#### Вариант A: Auth Service как отдельный сервис ⭐ РЕКОМЕНДУЕМ

```
API Gateway ──HTTP──► Auth Service (8092)
                        ├─ validateToken(jwt)
                        ├─ refreshToken(refreshToken)
                        ├─ login(email, password)
                        └─ logout(sessionId)
```

**Плюсы:**
- Чистое разделение concerns
- Auth Service масштабируется независимо
- Можно переиспользовать для WebSocket Service и других клиентов

**Минусы:**
- Дополнительный network hop при каждом запросе
- Ещё один сервис для деплоя

#### Вариант B: Auth встроен в API Gateway

**Плюсы:**
- Один сервис, нет network hop
- Проще деплой
- JWT validation + routing в одном процессе

**Минусы:**
- Монолитный API Gateway
- Сложнее масштабировать отдельно

**Вывод:** **Вариант A** (отдельный Auth Service) — правильный дизайн. Network hop на JWT validation можно минимизировать Redis-кэшированием session context'а прямо в API Gateway.

---

## 3. Безопасность: изоляция внутренних сервисов

### 3.1 Проблема

Каждый наш backend-сервис имеет HTTP-сервер:
- Device Manager: 10092
- History Writer: 10091
- Rule Checker: 8093
- Notification Service: 8094
- и т.д.

**Вопрос:** что если кто-то обратится напрямую к `http://device-manager:10092/api/devices` обходя API Gateway?

### 3.2 Варианты защиты

#### Уровень 1: Network Isolation (Docker/K8s) ⭐ ОБЯЗАТЕЛЬНО

```yaml
# docker-compose.yml
networks:
  # Внешняя сеть — только API Gateway и Web Frontend
  public:
    driver: bridge
  # Внутренняя сеть — все backend-сервисы
  internal:
    driver: bridge
    internal: true  # ← НЕ доступна извне!

services:
  api-gateway:
    networks:
      - public      # доступен извне
      - internal    # видит backend-сервисы
    ports:
      - "8080:8080" # единственный открытый порт

  device-manager:
    networks:
      - internal    # ТОЛЬКО внутренняя сеть
    # НЕТ ports: секции! → недоступен снаружи

  history-writer:
    networks:
      - internal
    # НЕТ ports: секции!
```

**В Kubernetes:**
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-isolation
spec:
  podSelector:
    matchLabels:
      tier: backend
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: api-gateway
      ports:
        - port: 8080
  # Разрешаем входящий трафик ТОЛЬКО от API Gateway
```

**Результат:** backend-сервисы физически недоступны извне. Единственный путь — через API Gateway.

#### Уровень 2: Internal Auth Header (HMAC Signature)

Даже внутри сети добавить проверку что запрос пришёл от API Gateway:

```scala
// API Gateway: при проксировании
val hmac = HMAC_SHA256(
  secret = internalSecret,
  data   = s"$method:$path:$timestamp:$requestId"
)
request.addHeader("X-Internal-Signature", hmac)
request.addHeader("X-Internal-Timestamp", timestamp)

// Backend Service: middleware
def validateInternalRequest(req: Request): IO[AuthError, Unit] =
  for {
    sig       <- req.header("X-Internal-Signature").someOrFail(MissingSignature)
    timestamp <- req.header("X-Internal-Timestamp").someOrFail(MissingTimestamp)
    _         <- ZIO.when(isExpired(timestamp, maxAge = 30.seconds))(ZIO.fail(ExpiredRequest))
    expected   = HMAC_SHA256(internalSecret, s"${req.method}:${req.path}:$timestamp:${req.requestId}")
    _         <- ZIO.when(sig != expected)(ZIO.fail(InvalidSignature))
  } yield ()
```

**Стоимость:** ~10 строк middleware на сервис + shared secret.

#### Уровень 3: Mutual TLS (mTLS) — для production (необязательно для MVP)

```
API Gateway ──mTLS──► Backend Service
  Клиентский сертификат GW → Backend проверяет:
    - Сертификат подписан нашим CA
    - CN = "api-gateway"
```

**Плюсы:** Криптографическая гарантия идентичности. **Минусы:** Сложнее в настройке и ротации.

#### 📊 Матрица уровней защиты

| Уровень | Что защищает | Сложность | Рекомендация |
|---|---|---|---|
| **Network Isolation** | Физический доступ | Минимальная (docker-compose.yml) | ⭐ MVP, ОБЯЗАТЕЛЬНО |
| **HMAC Signature** | Подделка запросов внутри сети | Средняя (~10 строк/сервис) | Post-MVP, рекомендуется |
| **mTLS** | Всё (криптографическая гарантия) | Высокая (CA, сертификаты) | Production, опционально |

### 3.3 А нужно ли дублировать проверку ролей в каждом сервисе?

**Короткий ответ:** Для MVP — **НЕТ**, для production — **частично ДА**.

Что стоит проверять в каждом сервисе ВСЕГДА (это не авторизация, а бизнес-валидация):

```scala
// В КАЖДОМ сервисе — ОБЯЗАТЕЛЬНО:
def getDevice(deviceId: DeviceId, orgIdFromHeader: OrgId): Task[Device] = for {
  device <- repository.findById(deviceId)
  // ★ КРИТИЧНО: проверка multi-tenant изоляции
  _      <- ZIO.when(device.organizationId != orgIdFromHeader)(
              ZIO.fail(AccessDenied("Device belongs to different organization"))
            )
} yield device
```

Это **НЕ проверка ролей** (это делает GW). Это **бизнес-инвариант** — пользователь организации A не может видеть данные организации B. Даже если API Gateway пропустит — сервис должен проверить. Этот чек уже есть в нашем коде.

---

## 4. Недостающие сервисы и компоненты

### 4.1 Инвентаризация текущего состояния

| # | Сервис | Директория | Код (Scala) | Документация | Статус |
|---|---|---|---|---|---|
| 1 | Connection Manager | ✅ `services/connection-manager/` | ✅ ~60 файлов | ✅ Полная | 286 тестов |
| 2 | History Writer | ✅ `services/history-writer/` | ✅ 12 файлов | ✅ Полная | 92 теста |
| 3 | Device Manager | ✅ `services/device-manager/` | ✅ есть | ✅ Полная | 69 тестов |
| 4 | Rule Checker | ✅ `services/rule-checker/` | ✅ ~15 файлов | ✅ | Компилируется |
| 5 | Notification Service | ✅ `services/notification-service/` | ✅ 24 файла | ✅ | Компилируется |
| 6 | Analytics Service | ✅ `services/analytics-service/` | ✅ ~25 файлов | ✅ | Компилируется |
| 7 | User Service | ✅ `services/user-service/` | ✅ 20 файлов | ✅ | Компилируется |
| 8 | Admin Service | ✅ `services/admin-service/` | ✅ ~12 файлов | ✅ | Компилируется |
| 9 | Integration Service | ✅ `services/integration-service/` | ✅ 22 файла | ✅ | Компилируется |
| 10 | Maintenance Service | ✅ `services/maintenance-service/` | ✅ 20 файлов | ✅ | Компилируется |
| 11 | Sensors Service | ✅ `services/sensors-service/` | ✅ есть | ✅ | Компилируется |
| 12 | API Gateway | ✅ `services/api-gateway/` | ⚠️ Минимум кода | ✅ | Заглушка |
| 13 | Web Frontend | ✅ `services/web-frontend/` | ✅ 24 файла (React+TS) | ✅ | Реализован (карта, панели, модалы) |
| 14 | Web Billing | ✅ `services/web-billing/` | ✅ 18 компонентов (React) | ✅ | Реализован (админка, тарифы, пользователи) |

### 4.2 Что НЕ ХВАТАЕТ для завершения проекта

#### 🔴 КРИТИЧНО — без этого проект не работает

| # | Компонент | Описание | Оценка сложности |
|---|---|---|---|
| 1 | **WebSocket Service** | ✅ **РЕАЛИЗОВАН** (2026-03-03). 12 Scala файлов, 60 unit тестов, 10 документов. Smart Consumer pattern: Kafka (gps-events, geozone-events, rule-violations) → WS push. Порт 8090. | — |
| 2 | **Auth Service** | JWT, refresh tokens, login/logout, 2FA. Документация описана (AUTH_SERVICE.md, port 8092), **но нет директории** `services/auth-service/`. Без него API Gateway не может проверять токены. | Средняя (2-3 дня) |
| 3 | **API Gateway — полная реализация** | Сейчас заглушка. Нужно: JWT middleware, rate limiting (Redis), service proxy, routing, circuit breaker, response aggregation. | Высокая (3-5 дней) |
| 4 | **Web Frontend** | ✅ **РЕАЛИЗОВАН**. React + TypeScript + Leaflet. 24 файла: MapView, LeftPanel, Toolbar, AppLayout, 9 модалов (Geozones, VehicleDetails, Track, Notifications, Reports и т.д.), appStore (zustand), mock API. | — |
| 5 | **Flyway миграции** | SQL-миграции для всех сервисов с PostgreSQL/TimescaleDB/PostGIS. Частично есть в `infra/databases/`, но не для всех сервисов. | Средняя (2-3 дня) |
| 6 | **Redis клиент (lettuce)** | Connection Manager и API Gateway по документации используют lettuce-core 6.3.2. Остальные сервисы используют ZIO Ref (in-memory) — допустимо для MVP, но нужен Redis для production. | Средняя (1-2 дня на CM) |

#### 🟡 ВАЖНО — нужно для production quality

| # | Компонент | Описание | Оценка |
|---|---|---|---|
| 7 | **Integration тесты (testcontainers)** | Тесты с реальной PostgreSQL, TimescaleDB, Kafka, Redis. Описаны в TESTING_PLAN.md, не реализованы. | Высокая (1 неделя) |
| 8 | **Docker Compose — полная конфигурация** | Сейчас `docker-compose.yml` не покрывает все 14 сервисов с правильными сетями, health check и volumes. | Средняя (1-2 дня) |
| 9 | **Prometheus метрики** | ZIO-HTTP + Prometheus export в каждом сервисе. Health checks стандартизированы, метрики нет. | Средняя (1-2 дня) |
| 10 | **Grafana dashboards** | Мониторинг: GPS throughput, Kafka lag, WS connections, error rates. | Средняя (1-2 дня) |
| 11 | **CI/CD pipeline** | GitHub Actions: build, test, docker build, push to registry. | Средняя (1-2 дня) |
| 12 | **Graceful shutdown** | Описан как обязательный, но не во всех сервисах реализован корректно. | Низкая (1 день) |

#### 🟢 ОПЦИОНАЛЬНО — PostMVP

| # | Компонент | Описание | Оценка |
|---|---|---|---|
| 13 | ~~Web Billing~~ | ✅ **РЕАЛИЗОВАН** (React). 18 компонентов: BillingApp, AccountsPanel, TariffsPanel, ObjectsPanel, GroupsPanel, RecycleBinPanel, RetranslatorsPanel, SubdealersPanel, RolesPanel, UsersPanel, SupportPanel и т.д. | — |
| 14 | Mobile App | iOS/Android клиент | 1+ месяц |
| 15 | Load Testing | GPS simulation (20K trackers) | 3-5 дней |
| 16 | mTLS между сервисами | Криптографическая защита | 2-3 дня |
| 17 | Consul/Eureka service discovery | Динамическое обнаружение сервисов | 1-2 дня |

### 4.3 Порядок реализации (рекомендация)

```
ФАЗА 1: Инфраструктура безопасности (1 неделя)
├── 1. Auth Service (JWT, login, sessions)
├── 2. API Gateway (полная реализация: auth middleware, routing, rate limit)
└── 3. Docker Compose с network isolation

ФАЗА 2: Real-time (1 неделя)
├── 4. ✅ WebSocket Service (Kafka consumer → WS push) — СДЕЛАНО
├── 5. Redis клиент (lettuce) для CM и API GW
└── 6. Flyway миграции для всех сервисов

ФАЗА 3: Frontend (2-4 недели)
├── 7. Web Frontend: каркас (React + Zustand + React Router)
├── 8. Карта (Leaflet + маркеры + маршруты)
├── 9. Dashboard (устройства, события, статистика)
└── 10. Администрирование (пользователи, устройства, геозоны)

ФАЗА 4: Production hardening (1-2 недели)
├── 11. Integration тесты (testcontainers)
├── 12. CI/CD (GitHub Actions)
├── 13. Prometheus + Grafana
└── 14. Load testing (GPS simulator)
```

### 4.4 Расхождения в документации

Обнаруженные несоответствия между документацией и реальным кодом:

| Проблема | Где | Что не так |
|---|---|---|
| Geozones Service vs Rule Checker | API_GATEWAY.md | Ссылается на `geozones-service:8084`, но геозоны в `rule-checker:8093` |
| Auth Service | docs/services/AUTH_SERVICE.md | Документация есть, директории `services/auth-service/` нет |
| ~~WebSocket Service~~ | services/websocket-service/ | ✅ Реализован: 12 файлов, 60 тестов, порт 8090 |
| ~~Web Frontend~~ | services/web-frontend/ | ✅ Реализован: 24 файла, MapView, LeftPanel, 9 модалов, zustand store |
| ~~Web Billing~~ | services/web-billing/ | ✅ Реализован: 18 компонентов (админка, тарифы, пользователи) |
| Redis pos:{imei} | ARCHITECTURE_QUESTIONS_ANALYSIS.md | CM НЕ пишет позиции в Redis — только Kafka (исправлено) |
| Redis | Все сервисы | Дизайн с Redis, реализация на ZIO Ref (задокументировано) |

---

## 5. Рекомендации и приоритеты

### 5.1 Решения для принятия СЕЙЧАС

| # | Вопрос | Рекомендация | Нужно решить до |
|---|---|---|---|
| 1 | WS: топик для позиций? | ✅ **Решено и реализовано**: Вариант C (gps-events + geozone-events + rule-violations) | ✅ Сделано |
| 2 | Auth: где проверять? | **Вариант A** (только GW) для MVP, **Вариант B** (GW + HMAC) для prod | Перед реализацией API GW |
| 3 | Network isolation? | **Обязательно** через Docker networks: internal + public | Перед деплоем |
| 4 | Auth Service: отдельный? | **Да**, отдельный сервис (port 8092) | Перед API GW |
| 5 | Первый шаг после Block 1? | Auth Service → API Gateway → WebSocket Service | Сейчас |

### 5.2 Минимальный путь до работающего MVP

```
Минимальный набор для демонстрации:
1. ✅ CM принимает GPS пакеты → Kafka
2. ✅ HW пишет в TimescaleDB
3. ✅ DM управляет устройствами
4. ❌ Auth Service — вход в систему
5. ❌ API Gateway — единая точка входа
6. ✅ WebSocket Service — real-time карта (12 файлов, 60 тестов)
7. ✅ Web Frontend — карта, панели, модалы (24 файла React+TS)
8. ❌ Docker Compose — всё поднимается одной командой
```

Пункты 4, 5, 8 — это минимум до **работающего MVP**, который можно показать.

### 5.3 Что я НЕ рекомендую делать сейчас

- ✅ ~~Web Billing~~ — **реализовано** (18 React-компонентов)
- ❌ mTLS — Docker network isolation достаточно для MVP
- ❌ Service Discovery (Consul) — static config в docker-compose достаточно
- ❌ Mobile App — сначала Web
- ❌ Тяжёлые оптимизации (Redis cluster, Kafka partitions tuning) — рано

---

*Документ для обсуждения. После принятия решений — обновить ARCHITECTURE.md и начать реализацию.*
