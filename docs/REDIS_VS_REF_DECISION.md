> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-02` | Версия: `1.0`

# 🔴 Redis vs ZIO Ref — Архитектурное решение

## Контекст проблемы

При компиляции сервисов обнаружилось, что **zio-redis** (обёртка Redis для ZIO) **несовместима** с нашим стеком (ZIO 2.0.20 + Scala 3.4.0). Вместо того чтобы использовать **lettuce** напрямую (как это уже сделано в Connection Manager), все сервисы были переведены на **ZIO `Ref`** (in-memory HashMap).

**Это решение было ошибочным.** В данном документе разбираем почему, и что с этим делать.

---

## Три варианта работы с Redis

### Вариант A: lettuce напрямую (✅ РЕКОМЕНДУЕМЫЙ)

Connection Manager уже использует **lettuce 6.3.2** — Java-клиент Redis, который отлично работает с Scala 3:

```scala
// Как устроено в Connection Manager:
import io.lettuce.core.{RedisClient => LettuceClient, RedisURI}

val uri = RedisURI.builder()
  .withHost(config.host)
  .withPort(config.port)
  .withDatabase(config.database)
  .build()

val client = LettuceClient.create(uri)
val connection = client.connect()
val commands = connection.async()   // Async API → Java CompletionStage

// Java CompletionStage → ZIO:
private def fromCompletionStage[A](cs: => CompletionStage[A]): Task[A] =
  ZIO.fromFuture(_ => cs.asScala)

// Использование:
fromCompletionStage(commands.hgetall("device:123456"))
  .map(_.asScala.toMap)
```

**Плюсы:**
- Проверенное решение — уже работает в CM (330 строк, 11 файлов используют)
- Настоящий Redis — данные персистентны, шарятся между инстансами
- Встроенная поддержка Pub/Sub, TTL, Sorted Sets, Streams
- Java-библиотека — нет проблем совместимости со Scala 3
- Async API — неблокирующий, идиоматичный для ZIO
- Connection pooling "из коробки"
- Lettuce 6.3.x — зрелая, стабильная библиотека (Pivotal/VMware)

**Минусы:**
- Нужно писать ZIO-обёртку вручную (но CM уже показывает паттерн)
- Императивный Java API (обёрнут в `fromCompletionStage`)
- Внешняя зависимость — требуется работающий Redis-сервер
- Больше кода чем Ref (~50-100 строк обёртки на сервис)

### Вариант B: ZIO `Ref` — in-memory (⚠️ ТЕКУЩЕЕ СОСТОЯНИЕ)

```scala
case class ThrottleService(
  throttleRef: Ref[Map[String, Instant]],
  rateRef: Ref[Map[String, Int]]
) { ... }
```

**Плюсы:**
- Zero зависимостей — ничего дополнительного не нужно
- Максимальная скорость — никаких сетевых вызовов
- Простота кода — 20-30 строк вместо 100
- Тестируемость — идеально для unit-тестов
- Хорошо для dev/test окружения

**Минусы (критичные для production):**
- 🚨 **Потеря данных при рестарте** — все кэши, очереди, состояния теряются
- 🚨 **Нет шаринга между инстансами** — при горизонтальном масштабировании каждый инстанс видит только свои данные
- 🚨 **Нет TTL** — нужно реализовывать вручную через фоновый fiber
- 🚨 **Нет Pub/Sub** — невозможна межсервисная коммуникация через Redis каналы
- 🚨 **Утечка памяти** — Map растёт бесконечно если не чистить
- ❌ **Не подходит для production** при >1 инстансе сервиса
- ❌ Круговая зависимость: Device Manager ↔ CM должны видеть одни и те же ключи Redis

### Вариант C: zio-redis (❌ НЕ РАБОТАЕТ)

```scala
// Не компилируется с ZIO 2.0.20 + Scala 3.4.0
import zio.redis._
```

**Статус:** Нет совместимой версии. Следить за обновлениями: https://github.com/zio/zio-redis

---

## Что используют наши сервисы и зачем

### Кому Redis КРИТИЧЕСКИ нужен

| Сервис | Компонент | Что хранит | Почему Ref — проблема |
|--------|-----------|------------|----------------------|
| **Connection Manager** | RedisClient | device:{imei}, pending_commands, Pub/Sub | ✅ Уже на lettuce — ОК |
| **Device Manager** | DeviceCache | Кэш устройств, IMEI↔VehicleId маппинг | Должен видеть те же ключи что и CM |
| **Rule Checker** | VehicleStateManager | Состояния "в каких геозонах" каждый vehicleId | При рестарте потеряем все состояния, ложные enter/leave |
| **Integration Service** | WialonSender, CircuitBreaker | Пулы соединений, circuit breaker state | При рестарте — дубли ретрансляций, потеря CB state |

### Кому Ref ДОПУСТИМ (может остаться)

| Сервис | Компонент | Что хранит | Почему Ref — ОК |
|--------|-----------|------------|-----------------|
| **Notification Service** | ThrottleService | Throttle counters, rate limits | Потеря при рестарте — допустима (пошлёт лишнее уведомление) |
| **Sensors Service** | SensorStateStore | Состояния датчиков | Восстанавливается из Kafka/DB |
| **Admin Service** | ConfigService | Конфигурации | Восстанавливается из DB при старте |
| **Analytics Service** | ReportCache | Кэш отчётов | Потеря — ОК (пересчитается) |
| **Maintenance Service** | MaintenanceCache | Кэш пробега | Восстанавливается из DB |

---

## Рекомендация

### Phase 1 (MVP — текущее состояние)

**Оставить Ref** где потеря данных при рестарте допустима:
- ✅ notification-service (ThrottleService)
- ✅ sensors-service (SensorStateStore)
- ✅ admin-service (ConfigService)
- ✅ analytics-service (ReportCache)
- ✅ maintenance-service (MaintenanceCache)

**Перевести на lettuce** где данные критичны:
- 🔄 rule-checker → VehicleStateManager (состояния геозон не должны теряться)
- 🔄 integration-service → CircuitBreaker, WialonSender pool (потеря = дубли)
- 🔄 device-manager → должен читать те же Redis ключи что и CM

### Phase 2 (Production-ready)

Создать **shared Redis client library** (`wayrecall-redis-client`) — общую обёртку lettuce для всех сервисов:

```
services/common/
└── redis-client/
    ├── build.sbt
    └── src/main/scala/com/wayrecall/tracker/redis/
        ├── WayrecallRedisClient.scala    // Trait + Live (lettuce)
        ├── WayrecallRedisConfig.scala    // Конфигурация
        └── WayrecallRedisCodecs.scala    // Сериализация
```

Все сервисы подключают эту библиотеку вместо дублирования lettuce-обёрток.

### Phase 3 (Оптимизация)

- Добавить Redis Cluster для HA
- Добавить Sentinel для failover
- Pipeline/batch операции для массовых запросов
- Redis Streams вместо Kafka для real-time events (оценить)

---

## Сравнительная таблица

| Критерий | lettuce (Redis) | ZIO Ref (in-memory) | Комментарий |
|----------|----------------|---------------------|-------------|
| **Персистентность** | ✅ Да (RDB/AOF) | ❌ Нет | Ref теряет всё при рестарте |
| **Шаринг между инстансами** | ✅ Да | ❌ Нет | Критично для горизонтального масштабирования |
| **TTL** | ✅ Встроенный | ❌ Нужен ручной fiber | Redis EXPIRE из коробки |
| **Pub/Sub** | ✅ Да | ❌ Нет | CM использует для команд/конфигов |
| **Latency** | ~0.1-1ms (сеть) | ~0.001ms (RAM) | Ref быстрее, но Redis достаточно быстр |
| **Масштабируемость** | ✅ Redis Cluster | ❌ Только 1 инстанс | Критично для production |
| **Сложность кода** | Средняя (~100 строк обёртки) | Минимальная (~20 строк) | Ref проще |
| **Тестируемость** | Средняя (testcontainers) | ✅ Отличная | Ref идеален для тестов |
| **Production-ready** | ✅ Да | ❌ Только для dev | Ref не для production |
| **Отладка** | ✅ redis-cli, RedisInsight | ❌ Только логи | Инструменты мониторинга |
| **Совместимость** | ✅ Java → работает | ✅ Чистый ZIO | Оба работают |

---

## Вывод

**Ref — это допустимый shortcut для MVP и dev-окружения**, но для production нужен Redis через lettuce. Паттерн уже есть в Connection Manager. На Phase 2 — создать shared library.

**Текущий план:**
1. MVP компилируется и работает с Ref — ✅ DONE
2. Перевод критичных сервисов на lettuce — TODO (после MVP)
3. Shared Redis client library — TODO (Phase 2)

---

*Версия: 1.0 | Обновлён: 2 марта 2026 | Тег: АКТУАЛЬНО*
