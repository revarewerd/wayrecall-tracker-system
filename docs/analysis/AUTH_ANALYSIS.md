# Анализ аутентификации и авторизации

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-02` | Версия: `1.0`

---

## Общая схема аутентификации

```
┌──────────┐    Bearer JWT     ┌───────────────┐    X-User-Id        ┌─────────────┐
│  Client   │ ───────────────► │  API Gateway   │ ──────────────────► │  Backend    │
│ (Browser) │                  │                │    X-Company-Id     │  Service    │
│           │ ◄─────────────── │  AuthMiddleware │    X-User-Roles    │             │
│           │   LoginResponse  │  ProxyService  │    X-Request-Id    │  Routes     │
└──────────┘                   └───────┬────────┘                    └──────┬──────┘
                                       │                                    │
                                JWT HS256                           WHERE org_id = ...
                                (jwt-zio-json)                      (Doobie SQL)
```

**Принцип:** JWT обрабатывается **только** в API Gateway. Backend-сервисы получают идентификацию из X-headers, заголовок `Authorization` удаляется при проксировании.

---

## 1. JWT — API Gateway

### Параметры

| Параметр | Значение |
|----------|----------|
| Библиотека | `jwt-zio-json` v10.0.0 (`com.github.jwt-scala`) |
| Алгоритм | **HMAC-SHA256** (симметричный) |
| Секрет | `jwt.secret` в HOCON, override `${?JWT_SECRET}` |
| Время жизни | `expirationHours` (дефолт 24ч) |
| Формат | `Authorization: Bearer <token>` |

### JWT Payload

```json
{
  "sub": "userId (UUID)",
  "cid": "companyId (UUID)",
  "email": "user@company.com",
  "roles": ["Admin", "User"],
  "sid": "sessionId (UUID)",
  "exp": 1234567890
}
```

### Pipeline обработки (AuthMiddleware → ApiRouter)

1. Извлечение `Bearer` токена из `Authorization` header
2. `AuthMiddleware.authenticate()` → decode JWT → parse `UserContext` → validate `exp`
3. `AuthResult`: `Authenticated(ctx)` | `Anonymous` | `Failed(error)`
4. `resolveAppDomain()` — определение домена по Origin/Host
5. `authorizeForDomain()` — проверка ролей для домена (Billing → Admin+, Monitoring → User+)
6. `resolveEndpoint()` — маршрутизация к backend-сервису
7. `enrichHeaders()` — `X-User-Id`, `X-Company-Id`, `X-User-Roles`, `X-Request-Id`
8. `ProxyService.proxyRequest()` — strip `Host`, `Authorization`, `Content-Length`; add X-headers

---

## 2. AuthService (MVP-заглушка)

### Текущее состояние: встроен в API Gateway

⚠️ **Auth Service не существует как отдельный микросервис.** Логика аутентификации в [AuthService.scala](services/api-gateway/src/main/scala/com/wayrecall/gateway/service/AuthService.scala) с захардкоженными пользователями:

| Email | Пароль | Роли | CompanyId |
|-------|--------|------|-----------|
| `admin@wayrecall.com` | `admin` | Admin, User | `...000100` |
| `user@wayrecall.com` | `user` | User | `...000100` |

### Login flow

```
POST /api/v1/auth/login { email, password }
  → lookup в hardcoded Map
  → AuthMiddleware.createToken(ctx) → JWT HS256
  → LoginResponse { token, expiresAt, user }
```

### Что НЕ реализовано

- ❌ Refresh token — нет обновления, 1 токен на 24ч
- ❌ Session invalidation / logout — токен валиден до `exp`
- ❌ Rate limiting на `/auth/login` — возможен brute-force
- ❌ Реальная проверка credentials в PostgreSQL
- ❌ MFA / 2FA
- ❌ Password reset flow

---

## 3. RBAC — User Service

### Иерархия ролей (6 уровней)

| Роль | Уровень | Описание |
|------|---------|----------|
| SuperAdmin | 0 | Полные права на всё |
| Admin | 10 | Управление организацией |
| Manager | 20 | Управление командами |
| Operator | 30 | Операционные задачи |
| Dispatcher | 40 | Диспетчерские функции |
| Viewer | 50 | Только просмотр |

**Правило:** актор может назначать только роли **≥** своего уровня. Проверка в `PermissionService.canAssignRole()`.

### 27 разрешений (8 категорий)

```
users:view|create|edit|delete
vehicles:view|create|edit|delete|command
geozones:view|create|edit|delete
reports:view|create|export
maintenance:view|create|edit
notifications:view|create|edit
settings:view|edit
integrations:view|create|edit
```

**Wildcard matching:** `Permission.matchesWildcard("reports:*", "reports:view")` → `true`

### Проверка прав

```
PermissionService.hasPermission(userId, permission):
  1. Cache → PermissionCache.getPermissions(userId) — in-memory Ref
  2. Fallback → RoleRepository.getUserRoles(userId) + collect permissions
  3. Wildcard match → matchesWildcard(cached, requested)
```

### Пароли

Хэширование: **BCrypt** с salt factor 12 (`BCrypt.gensalt(12)`)

### Аудит

Все мутирующие операции → `users.audit_log`: userId, companyId, action, entityType, details, ipAddress, timestamp

---

## 4. API Keys — Integration Service

### Механизм

| Параметр | Значение |
|----------|----------|
| Передача | `X-API-Key` header |
| Хэширование | BCrypt (`BCrypt.checkpw`) |
| Поиск | По prefix (первые 10 символов) |
| Хранение | PostgreSQL `integration.api_keys` |
| Удаление | Soft delete (`enabled = false`) |

### Pipeline валидации (ApiKeyValidator)

```
X-API-Key header
  → extractPrefix (first 10 chars)
  → findByPrefix (DB: WHERE prefix = ? AND enabled = true)
  → BCrypt.checkpw(rawKey, keyHash)
  → check enabled + check expires_at
  → check rate limit (per-key, per-minute, in-memory Ref)
  → update last_used_at (fire-and-forget .fork)
  → return ApiKey { organizationId, permissions, rateLimit }
```

### Rate Limiting

- In-memory `ZIO Ref` — per-minute счётчик per-key
- Очистка каждую минуту
- ⚠️ **Не распределённый** — сбрасывается при рестарте, не работает в кластере

---

## 5. Multi-Tenant изоляция

Изоляция на **3 уровнях**:

### Уровень 1: API Gateway → X-Company-Id

JWT содержит `cid` (companyId). `enrichHeaders()` добавляет `X-Company-Id` header. `Authorization` header удаляется.

### Уровень 2: Backend Routes → extractOrgId

| Сервис | Источник orgId |
|--------|---------------|
| Rule Checker | `X-Company-Id` header |
| Notification Service | `?orgId=` query param |
| Analytics Service | `?orgId=` query param |
| User Service | `X-Company-Id` header → `companyId` |
| Integration Service | Из `ApiKey.organizationId` |

⚠️ **Неконсистентный подход** — нет единого стандарта.

### Уровень 3: Repository → WHERE organization_id

**КАЖДЫЙ** SQL-запрос во **ВСЕХ** сервисах содержит фильтр по org:
- `WHERE organization_id = ${orgId.value}` (rule-checker, notification, integration)
- `WHERE company_id = $companyId` (user-service)

Grep по codebase: 50+ совпадений — изоляция на уровне БД соблюдена.

---

## Обнаруженные проблемы

### 🔴 Критичные (MVP blockers для production)

| # | Проблема | Где | Рекомендация |
|---|----------|-----|-------------|
| 1 | Захардкоженные credentials | AuthService.scala | Вынести в PostgreSQL, выделить Auth Service |
| 2 | Дефолтный JWT secret | application.conf | `"change-me-..."` → обязательный `JWT_SECRET` env |
| 3 | Нет refresh token | AuthService | Реализовать refresh token flow |
| 4 | Нет session invalidation | API Gateway | Redis blocklist для отозванных JWT |

### 🟡 Важные

| # | Проблема | Где | Рекомендация |
|---|----------|-----|-------------|
| 5 | In-memory rate limiter | ApiKeyValidator | Перенести в Redis |
| 6 | PermissionCache без TTL | PermissionCache | Добавить TTL или Redis |
| 7 | Неконсистентный extractOrgId | Routes разных сервисов | Унифицировать: всегда X-Company-Id |
| 8 | `throw RuntimeException` | analytics ReportRoutes | Заменить на `ZIO.fail` |
| 9 | Нет rate limiting на login | ApiRouter | Добавить Token Bucket |

### 🟢 Рекомендации на будущее

- OAuth2 / OpenID Connect для enterprise клиентов
- API Key rotation с grace period
- Audit log в API Gateway (все запросы)
- CORS strict mode в production
- CSP headers для web frontend

---

## Сравнение с Legacy Stels

| Аспект | Legacy Stels | Wayrecall Tracker |
|--------|------------|-------------------|
| Аутентификация | Session-based (Spring Security) | JWT + Bearer token |
| Хранение паролей | Неизвестно (предполагается bcrypt) | BCrypt salt=12 |
| Multi-tenant | Слабая изоляция | `organization_id` в каждом SQL |
| Роли | Простая система (Admin/User) | 6-level иерархия + 27 permissions |
| API Keys | Нет | BCrypt + prefix lookup + rate limit |
| Аудит | Базовый | Полный audit log |
| Шифрование | HTTP (вероятно) | JWT HS256 (→ RS256 рекомендуется) |

---

## План улучшений для Production

### Приоритет 1 — Перед первым деплоем
1. Выделить Auth Service → PostgreSQL credentials
2. Обязательный `JWT_SECRET` (не дефолт)
3. Rate limiting на `/auth/login` (5 попыток / минуту)
4. HTTPS everywhere

### Приоритет 2 — Первый месяц
5. Refresh token flow
6. Session invalidation через Redis blocklist
7. Унифицировать extractOrgId → X-Company-Id everywhere  
8. Redis-based rate limiting для API Keys

### Приоритет 3 — Следующий квартал
9. OAuth2 / SSO для enterprise
10. MFA для Admin ролей
11. API Key rotation
12. JWT RS256 вместо HS256
