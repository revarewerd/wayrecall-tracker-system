# Анализ безопасности: Stels Legacy vs Wayrecall Tracker

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-03` | Версия: `1.0`

## Содержание

1. [Старый Stels — как была реализована безопасность](#1-старый-stels--как-была-реализована-безопасность)
2. [Наш Wayrecall Tracker — текущее состояние](#2-наш-wayrecall-tracker--текущее-состояние)
3. [Сравнительная таблица](#3-сравнительная-таблица)
4. [Проблемы безопасности в Stels (что НЕ повторять)](#4-проблемы-безопасности-в-stels-что-не-повторять)
5. [Хорошие идеи из Stels (что взять)](#5-хорошие-идеи-из-stels-что-взять)
6. [План реализации безопасности в Wayrecall](#6-план-реализации-безопасности-в-wayrecall)
7. [Матрица ролей и прав](#7-матрица-ролей-и-прав)
8. [Рекомендации по внедрению](#8-рекомендации-по-внедрению)

---

## 1. Старый Stels — как была реализована безопасность

### 1.1 Технологический стек безопасности

| Компонент | Технология | Версия |
|---|---|---|
| Фреймворк | Spring Security | 4.1.3 |
| Хранилище пользователей | MongoDB коллекция `users` | 3.4 |
| Сессии | HTTP Session + Remember-Me Cookie | — |
| Токен | TokenBasedRememberMeServices | — |
| Кеш прав | Guava CacheBuilder | — |
| Аудит | MongoDB коллекция `authlog` | — |
| CQRS команды | Axon Framework | — |

### 1.2 Три механизма аутентификации

#### 1.2.1 Form Login (основной)

```
Пользователь → POST /j_spring_security_check (email + пароль)
            → WayrecallAuthenticationProvider (extends DaoAuthenticationProvider)
            → WayrecallUserDetailsService (MongoDB `users` коллекция)
            → Проверка BlockedUserChecker (enabled + blockcause)
            → Выдача HTTP Session
```

**Исходные файлы:**
- `core/src/main/java/ru/sosgps/wayrecall/security/WayrecallAuthenticationProvider.scala` (122 строки)
- Поля MongoDB `users`: `name`, `password`, `enabled`, `blockcause`, `lastLoginDate`, `lastAction`
- Все аутентифицированные пользователи получают `ROLE_USER` как GrantedAuthority

#### 1.2.2 Remember-Me (постоянная сессия)

```
Spring Security TokenBasedRememberMeServices
├── Ключ: захардкожен "avoaSBOhMnOJLuh3Gf0IzJ9DTfDp0qVA" (⚠️ ПРОБЛЕМА!)
├── Cookie: wayrecall-remember-me
├── loginSuccess → устанавливает cookie
└── При входе с cookie → автоматическая аутентификация
```

#### 1.2.3 Backdoor (переход Billing → Monitoring)

**Это не "бэкдор" в плохом смысле, а механизм SSO между модулями:**

```
1. Админ в Billing → нажимает "войти в мониторинг дилера"
2. BackdoorEnterProvider.reserveBackdoorKey()
   → Генерирует UUID
   → Записывает в MongoDB коллекцию "authBackdors": {backdoorKey, login, date}
3. Редирект на → /backdoorAuth?key=<uuid>
4. BackdoorAuthenticationFilter (перехватывает /backdoorAuth)
   → Ищет ключ в MongoDB "authBackdors"
   → Очищает старую сессию
   → Создаёт BackdoorAuthenticationToken с правами целевого пользователя
   → Удаляет использованный ключ (одноразовый)
5. Ключи старше 1 минуты — автоматически удаляются (TTL)
```

**Исходные файлы:**
- `monitoring/security/BackdoorAuthenticationProvider.scala` (147 строк)
- `billing/security/BackdoorEnterProvider.scala` (87 строк)

### 1.3 Защита от брутфорса

```
LoginAttemptService
├── Хранение: Guava LoadingCache<IP, AtomicInteger>, TTL = 1 минута
├── Лимит: MAX_ATTEMPT = 5 попыток
├── Блокировка: по IP-адресу, НЕ по логину
├── При провале: AuthenticationFailureListener → loginFailed(remoteAddress)
├── При успехе: AuthenticationSuccessEventListener → loginSucceeded(remoteAddress) (сброс)
└── BruteforceChecker (pre-auth check) → LockedException("Too many attempts! Wait for 1 minute")
```

**Слабости:**
- Блокировка в памяти одного инстанса (не работает за балансером)
- Сбрасывается при рестарте
- Нет эскалации (всегда 1 минута)
- Атакующий может менять IP

**Исходный файл:** `monitoring/security/LoginAttemptService.scala` (85 строк)

### 1.4 Авторизация — 4 уровня

#### Уровень 1: URL-паттерны (Spring Security XML)

```xml
<!-- Публичные (NOT authenticated) -->
permitAll: /extjs4.2.1/**, /login.html, /login.js, /localization/**, 
           /logos/**, /errorReporting, 
           /EDS/getobjectsdata, /EDS/getnotifications, /EDS/getPDF/**,
           /EDS/getgroups, /EDS/banned, /api/**

<!-- Только с localhost -->
/sessions/** → hasIpAddress('127.0.0.1')

<!-- Всё остальное → аутентификация обязательна -->
/** → isAuthenticated()

<!-- Billing — строже -->
/** → hasAnyRole('admin','superuser')  // ROLE_USER НЕ МОЖЕТ войти в billing
```

**Файлы:**
- `monitoring/security-app-context.xml` (107 строк)
- `billing/security-app-context.xml` (123 строки)

#### Уровень 2: Роли (иерархия)

| Роль | Что может | Комментарий |
|---|---|---|
| `admin` | Всё | Полный доступ ко всем операциям и всем сущностям |
| `servicer` | Обслуживающий | Та же модель проверки, что admin — через SecureInterceptor |
| `superuser` | Управляет **только своими** пользователями | Видит только созданных им пользователей |
| `ROLE_USER` | Минимум | Может менять только Object DataSet и User DataSet для собственных сущностей |

#### Уровень 3: Команды (Axon CQRS — SecureInterceptor)

`SecureInterceptor.scala` (110 строк) — перехватывает **ВСЕ** CQRS-команды перед выполнением:

```
Маршрут: Command → SecureInterceptor → проверка authority → разрешить/отклонить

22+ маппинга команд на authority:
  Account CRUD        → AccountCreate / AccountDataSet / AccountDelete
  TariffPlan CRUD     → TariffPlanCreate / TariffPlanDataSet / TariffPlanDelete  
  Equipment CRUD      → EquipmentCreate / EquipmentDataSet / EquipmentDelete + ObjectChange
  Object CRUD         → ObjectCreate / ObjectDataSet / ObjectDelete / ObjectRestore / ObjectRemove
  EquipmentTypes CRUD → EquipmentTypesCreate / DataSet / Delete
  User CRUD           → UserCreate / UserDataSet / UserDelete
  Permission CRUD     → ChangePermissions
  DealerTariffication → DealerTariffer
  Ticket CRUD         → Manager
```

**Логика проверки по ролям:**
- `admin` / `servicer` → проверяет только карту authority
- `superuser` → проверяет authority + может управлять только своими пользователями
- `ROLE_USER` → разрешены ТОЛЬКО: Object DataSet (свои объекты), User DataSet (свой профиль)

#### Уровень 4: Объектные permissions (ObjectsPermissionsChecker)

**11 гранулярных прав на каждый объект (= транспортное средство):**

| Код | Что разрешает |
|---|---|
| `FORBIDDEN` | Полный запрет доступа |
| `VIEW` | Просмотр информации |
| `CONTROL` | Управление (команды) |
| `BLOCK` | Блокировка двигателя |
| `GET_COORDS` | Получение координат |
| `RESTART_TERMINAL` | Перезагрузка трекера |
| `VIEW_SLEEPER` | Просмотр дремлющих |
| `VIEW_SETTINGS` | Просмотр настроек |
| `EDIT_SETTINGS` | Редактирование настроек |
| `EDIT_FUELSETTINGS` | Настройки топлива |
| `EDIT_SENSORS` | Настройки датчиков |

**Ключевые характеристики:**
- Хранятся в MongoDB (коллекция permissions)
- **Иерархические**: права на аккаунт каскадируются на все объекты внутри
- **Creator-based**: superuser может управлять пользователями, которых он создал
- **Кешированные**: Guava CacheBuilder с TTL
- **Инвалидация**: через Axon `@EventHandler` при изменении прав

**Исходные файлы:**
- `core/security/ObjectsPermissionsChecker.scala` (~100 строк)
- `core/security/PermissionsManager.scala` (301 строка)
- `core/security/PermissionValue.java` (23 строки)

### 1.5 Аудит входов

`AuthenticationListener.scala` записывает **все** auth-события в MongoDB `authlog`:

```json
{ 
  "login": "user1", 
  "event": "AuthenticationSuccessEvent",
  "date": ISODate("2024-01-15T10:30:00Z"), 
  "ip": "192.168.1.1"
}
```

- При успешном входе (не через backdoor) → обновляет `lastLoginDate` в `users`
- При завершении сессии → обновляет `lastAction` (время последней активности)
- Отдельная логика для Backdoor-аутентификации (не обновляет lastLoginDate)

### 1.6 Блокировка дилеров

```
DealerBlockingFilter (Servlet Filter)
├── Запрос к MongoDB коллекции "dealers"
├── Проверяет поля: blocked (boolean) + balance (число)
├── Guava cache с TTL 1 минута
├── Заблокирован → редирект на /EDS/banned
└── Показывает причину блокировки + остаток баланса
```

### 1.7 Биллинг-специфичная безопасность

```
RolesService (Ext Direct API):
├── 30+ authority-строк для гранулярного управления
├── Шаблоны ролей в MongoDB "billingRoles" (name + authorities array)
├── Назначение через MongoDB "billingPermissions"
├── Все операции требуют admin + ChangeRoles authority
└── Superuser видит только свои шаблоны ролей

Админ-пароли Billing:
├── InMemoryUserDetailsManager (Spring Security)
├── Из properties-файла: ${WAYRECALL_HOME}/conf/wrcinstances/${instance.name}/billingAdmins.properties
└── Отдельный от мониторинга провайдер: BillingAuthenticationProvider
```

---

## 2. Наш Wayrecall Tracker — текущее состояние

### 2.1 Что реализовано

| Компонент | Статус | Где |
|---|---|---|
| JWT аутентификация | ✅ MVP (хардкод-юзеры) | `API-Gateway/service/AuthService.scala` |
| JWT верификация | ✅ Работает | `API-Gateway/middleware/AuthMiddleware.scala` |
| CORS | ✅ Whitelist origins | `API-Gateway/middleware/CorsMiddleware.scala` |
| Прокси к бэкендам | ✅ Через ProxyService | `API-Gateway/service/ProxyService.scala` |
| Health check | ✅ Параллельный | `API-Gateway/service/HealthService.scala` |
| Логирование запросов | ✅ С request ID | `API-Gateway/middleware/LogMiddleware.scala` |
| Роли (enum) | ✅ Admin, User, Viewer, SuperAdmin | `API-Gateway/domain/Models.scala` |
| AppDomain (Billing/Monitoring) | ✅ Определение по Origin | `API-Gateway/middleware/AuthMiddleware.scala` |
| X-заголовки для бэкендов | ✅ X-User-Id, X-Company-Id, X-User-Roles | `API-Gateway/middleware/AuthMiddleware.scala` |

### 2.2 Что НЕ реализовано (критические дыры)

| Компонент | Статус | Приоритет | Что нужно |
|---|---|---|---|
| **User Service интеграция** | ❌ Хардкод 2 юзеров | P0 | Подключить к PostgreSQL через User Service |
| **Password hashing** | ❌ Plaintext сравнение | P0 | bcrypt/argon2 |
| **Refresh tokens** | ❌ Нет | P1 | Пара access+refresh токенов |
| **Rate limiting** | ❌ Нет | P1 | Token Bucket в Redis |
| **Brute force protection** | ❌ Нет | P1 | Redis-based счётчик по IP |
| **Гранулярные permissions** | ❌ Нет | P2 | Как в Stels: per-object permissions |
| **API key auth** | ❌ Нет | P2 | Для интеграций (Wialon, webhooks) |
| **Аудит** | ❌ Нет | P2 | Логгирование auth-событий в БД |
| **2FA** | ❌ Нет | P3 | TOTP для админов |
| **Session management** | ❌ Нет | P3 | Отзыв токенов, макс. сессий |
| **CSRF protection** | ⚠️ Не нужен (JWT) | — | JWT с Bearer token не подвержен CSRF |
| **HSTS** | ❌ Нет | P1 | Strict-Transport-Security header |

### 2.3 Текущая схема аутентификации

```
┌─────────────────────┐
│    Web Frontend      │ ← React + TypeScript
│  (localhost:3001)    │
│                      │
│  POST /api/v1/auth/login  ──────────────────────┐
│  { email, password }                              │
│                                                   ▼
│                                          ┌──────────────┐
│                                          │  API Gateway  │ :8080
│                                          │               │
│                                          │ AuthService   │
│                                          │  .login()     │
│                                          │               │
│                                          │ ⚠️ Хардкод:   │
│                                          │ admin/admin   │
│                                          │ user/user     │
│                                          │               │
│                                          │ → JWT (HS256) │
│                                          └───────────────┘
│                                                   │
│  🎫 { token, expiresAt, user }  ◄─────────────────┘
│                                                   
│  Далее: Authorization: Bearer <token>             
│  ─────────────────────────────────────────────────►
│                                          ┌───────────────┐
│                                          │  API Gateway   │
│  ANY /api/v1/devices/**                  │                │
│                                          │ 1. extractToken│
│                                          │ 2. verifyJWT   │
│                                          │ 3. enrichHeaders│
│                                          │    X-User-Id   │
│                                          │    X-Company-Id│
│                                          │    X-User-Roles│
│                                          │ 4. proxyForward│
│                                          │    → device-mgr│
│                                          └───────────────┘
```

---

## 3. Сравнительная таблица

| Аспект | Stels Legacy | Wayrecall Tracker | Комментарий |
|---|---|---|---|
| **Аутентификация** | Spring Security + MongoDB | JWT + хардкод (MVP) | Нужно подключить User Service |
| **Хеширование паролей** | Spring Security encoder | Нет (plaintext) | ⚠️ КРИТИЧНО |
| **Сессии** | HTTP Session + Cookie | Stateless JWT | ✅ Правильный подход для микросервисов |
| **Remember-Me** | Cookie с хардкод-ключом | JWT с TTL | ✅ Лучше |
| **Роли** | 4: admin, servicer, superuser, user | 4: Admin, SuperAdmin, User, Viewer | ✅ Есть |
| **Гранулярные права** | 11 типов per-object | Нет | ❌ Нужно реализовать |
| **Command-level auth** | SecureInterceptor (Axon) | Нет | ❌ В микросервисах — через API Gateway |
| **Brute force** | In-memory (5 попыток / мин) | Нет | ❌ Нужен Redis-based |
| **CSRF** | Отключен | Не нужен (JWT) | ✅ |
| **CORS** | Нет (монолит) | Whitelist origins | ✅ |
| **Аудит** | MongoDB authlog | Нет | ❌ Нужен |
| **Rate limiting** | Нет | Нет | ❌ Нужен |
| **Multi-tenant изоляция** | Частичная (через permissions) | По X-Company-Id header | ⚠️ Нужна проверка на уровне каждого сервиса |
| **API security** | BasicAuth (в WebApi.scala) | JWT Bearer | ✅ Лучше |
| **Блокировка дилеров** | DealerBlockingFilter | Нет аналога (пока) | P3 — для биллинга |
| **SSO между модулями** | Backdoor (UUID в MongoDB) | Единый JWT | ✅ Лучше |

---

## 4. Проблемы безопасности в Stels (что НЕ повторять)

### 4.1 Критические

| # | Проблема | Риск | Наше решение |
|---|---|---|---|
| 1 | **CSRF отключен** | Межсайтовая подделка запросов | JWT с Bearer token (не нужен CSRF) |
| 2 | **HSTS отключен** | MitM при HTTP→HTTPS | Включить HSTS в nginx/Gateway |
| 3 | **Захардкоженный Remember-Me ключ** | Компрометация → подделка токенов | JWT secret из env variables |
| 4 | **Backdoor через URL-параметр** | Ключ в логах, рефереров | Единый JWT для всех модулей |
| 5 | **Публичные endpoints** | `/EDS/getobjectsdata`, `/api/**` без auth | Всё через JWT, кроме /health и /login |

### 4.2 Средние

| # | Проблема | Риск | Наше решение |
|---|---|---|---|
| 6 | **Brute force в памяти** | Не работает за балансером | Redis-based rate limiter |
| 7 | **REST API без Spring Security** | BasicAuth, не стандартизирован | Единый JWT через API Gateway |
| 8 | **MongoDB permissions без шифрования** | Слабое хеширование паролей | bcrypt в PostgreSQL |
| 9 | **Нет multi-tenant на уровне auth** | Data leak между организациями | X-Company-Id + проверка в каждом сервисе |

### 4.3 Низкие

| # | Проблема | Риск | Наше решение |
|---|---|---|---|
| 10 | **Нет 2FA** | Перехват пароля = полный доступ | TOTP для админов (PostMVP) |
| 11 | **Нет session management** | Нельзя отозвать сессию | Refresh token blacklist в Redis |
| 12 | **InMemoryUserDetailsManager для billing** | Пароли в файле | Единый User Service для всех |

---

## 5. Хорошие идеи из Stels (что взять)

### 5.1 4-уровневая авторизация

Stels имеет зрелую модель авторизации, которую стоит адаптировать:

```
Stels:                          Wayrecall Tracker (план):
┌─────────────────┐             ┌─────────────────────────────┐
│ URL-level       │  ────►      │ API Gateway: маршруты       │
│ (XML-конфиг)    │             │ (publicRoutes / authenticated│
│                 │             │  / admin-only)              │
├─────────────────┤             ├─────────────────────────────┤
│ Role-level      │  ────►      │ JWT claims: roles           │
│ (admin/super/   │             │ (Admin/SuperAdmin/User/     │
│  user)          │             │  Viewer)                    │
├─────────────────┤             ├─────────────────────────────┤
│ Command-level   │  ────►      │ Authorization header checks │
│ (SecureIntercept│             │ в каждом сервисе            │
│  or)            │             │ (X-User-Roles проверка)     │
├─────────────────┤             ├─────────────────────────────┤
│ Object-level    │  ────►      │ Гранулярные permissions     │
│ (11 типов per   │             │ в User Service              │
│  vehicle)       │             │ (per-vehicle ACL в PostgreSQL│
└─────────────────┘             └─────────────────────────────┘
```

### 5.2 Аудит-лог

Обязательно реализовать:
- Все auth-события (login, logout, failed login, token refresh)
- IP-адрес клиента
- User-Agent
- Результат (успех/провал)
- Время последней активности

### 5.3 Блокировка пользователей

Как в Stels: поле `enabled` + `blockcause`:
- Деактивированный пользователь не может войти
- Причина блокировки отображается в UI
- Автоматическая блокировка при подозрительной активности

### 5.4 Кеширование прав

Stels использует Guava CacheBuilder — мы используем Redis:
- Кеш прав пользователя TTL 5 минут
- Инвалидация через Kafka-события при изменении прав
- Кеш на стороне API Gateway (не заставлять бэкенды проверять каждый раз)

---

## 6. План реализации безопасности в Wayrecall

### Фаза 1: MVP (текущий приоритет)

```
✅ Сделано:
   - JWT аутентификация в API Gateway
   - CORS whitelist
   - Роли (Admin, User, Viewer, SuperAdmin)
   - X-заголовки для бэкендов
   - Health check

📋 Нужно для MVP:
   1. Подключить AuthService к User Service (вместо хардкода)
   2. Добавить bcrypt хеширование паролей
   3. Добавить маршруты ко ВСЕМ 13 сервисам в API Gateway
   4. Добавить HSTS header
   5. Добавить базовый rate limiting (Redis Token Bucket)
   6. Добавить brute force protection (Redis: IP → counter)
```

### Фаза 2: Production-Ready

```
📋 Задачи:
   1. Refresh tokens (access 15 мин, refresh 7 дней)
   2. Token blacklist в Redis (при logout)
   3. Per-object permissions (как в Stels, но в PostgreSQL)
   4. Аудит-лог в PostgreSQL
   5. Автоматическая блокировка при 10+ неудачных попытках
   6. API key auth для интеграций
   7. RBAC: настраиваемые роли (как billing RolesService в Stels)
```

### Фаза 3: Enterprise

```
📋 Задачи:
   1. 2FA (TOTP) для админов
   2. OAuth2/OIDC для SSO
   3. IP whitelist для критичных операций
   4. Session management (макс. 5 сессий)
   5. Авторотация JWT secret
   6. Mutual TLS для inter-service communication
```

---

## 7. Матрица ролей и прав

### 7.1 Роли системы

| Роль | Описание | Аналог в Stels | Доступ |
|---|---|---|---|
| `SuperAdmin` | Системный администратор | `admin` | Всё + Admin Service |
| `Admin` | Администратор компании | `superuser` | Управление своей компанией |
| `User` | Оператор/диспетчер | `ROLE_USER` | Мониторинг + отчёты |
| `Viewer` | Наблюдатель | — (новое) | Только просмотр |

### 7.2 Матрица доступа к сервисам

| Сервис | SuperAdmin | Admin | User | Viewer | Публичный |
|---|---|---|---|---|---|
| **auth/login** | — | — | — | — | ✅ |
| **health** | — | — | — | — | ✅ |
| **device-manager** | CRUD + все устройства | CRUD своей компании | Просмотр | Просмотр | ❌ |
| **history-writer** | Все данные | Данные своей компании | Данные своей компании | Данные своей компании | ❌ |
| **rule-checker** | CRUD | CRUD | Просмотр | Просмотр | ❌ |
| **notification-service** | CRUD | CRUD | Просмотр + test-send | Просмотр | ❌ |
| **analytics-service** | Все отчёты | Все отчёты | Все отчёты | Только просмотр | ❌ |
| **user-service** | Все пользователи | Своя компания | Свой профиль | Свой профиль | ❌ |
| **admin-service** | ✅ Полный | ❌ | ❌ | ❌ | ❌ |
| **integration-service** | CRUD | CRUD | Просмотр | ❌ | ❌ |
| **maintenance-service** | CRUD | CRUD | Просмотр | Просмотр | ❌ |
| **sensors-service** | CRUD | CRUD | Просмотр | Просмотр | ❌ |
| **websocket-service** | ✅ | ✅ | ✅ | ✅ | ❌ (нужен JWT) |

### 7.3 Гранулярные права на объекты (план)

Адаптация из Stels для Wayrecall:

| Право | Описание | Кто может выдать |
|---|---|---|
| `vehicle:view` | Просмотр информации о ТС | Admin+ |
| `vehicle:control` | Отправка команд на трекер | Admin+ |
| `vehicle:block` | Блокировка двигателя | Admin+ |
| `vehicle:track` | Получение координат в реальном времени | Admin+ |
| `vehicle:settings:view` | Просмотр настроек ТС | Admin+ |
| `vehicle:settings:edit` | Редактирование настроек ТС | Admin+ |
| `vehicle:sensors:view` | Просмотр данных датчиков | Admin+ |
| `vehicle:sensors:edit` | Настройка калибровки датчиков | Admin+ |
| `vehicle:fuel:edit` | Настройки топлива | Admin+ |

---

## 8. Рекомендации по внедрению

### 8.1 JWT Secret Management

```
❌ Stels: захардкожен в XML-конфиге
✅ Wayrecall:
   - JWT_SECRET из env variable (Docker secret)
   - Минимум 256 бит (32 символа)
   - Ротация: новый секрет каждые 30 дней
   - Поддержка 2 активных секретов одновременно (для плавной ротации)
```

### 8.2 Межсервисная безопасность

```
Текущее: API Gateway прокидывает X-заголовки → бэкенды доверяют

Проблема: если бэкенд доступен напрямую (не через Gateway), 
          X-заголовки можно подделать

Решение (фаза 2):
   1. Docker network isolation (бэкенды не видны извне)
   2. Inter-service JWT (Gateway подписывает, бэкенды верифицируют)
   3. mTLS между сервисами (фаза 3)
```

### 8.3 Password Policy

```
Минимум:
   - 8 символов
   - Хотя бы 1 заглавная + 1 цифра
   - bcrypt cost factor = 12
   - Не совпадает с последними 3 паролями
```

### 8.4 Rate Limiting Strategy

```
Redis Token Bucket:
   - Login endpoint: 5 попыток / минута / IP
   - API endpoints: 100 запросов / минута / user
   - WebSocket: 10 подключений / минута / user
   - Admin endpoints: 30 запросов / минута / user
```

---

*Документ создан на основе полного анализа исходного кода legacy-stels (12+ файлов безопасности, 2 Spring Security XML-конфига) и текущего кода API Gateway Wayrecall Tracker (10 Scala-файлов).*
