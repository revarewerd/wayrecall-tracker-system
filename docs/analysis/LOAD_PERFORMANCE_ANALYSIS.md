# Анализ нагрузки и производительности

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-02` | Версия: `1.0`

## Целевые показатели (SLA)

| Метрика | Цель | Текущее состояние |
|---------|------|-------------------|
| GPS packet latency (p99) | < 100ms | ✅ Достижимо (Parse → Kafka) |
| REST API latency (p99) | < 200ms | ✅ Достижимо (lightweight endpoints) |
| Concurrent GPS trackers | 20,000+ | ⚠️ Не проверено нагрузочным тестом |
| GPS points/sec | 20,000+ | ⚠️ Не проверено нагрузочным тестом |
| History write latency | < 10 сек | ✅ Batch insert + TimescaleDB |
| Redis ops latency | < 1ms | ✅ In-memory |

---

## Узкие места (Bottlenecks)

### 1. Connection Manager — TCP парсинг
- **Текущее:** Netty event loop + ZIO fibers для парсинга
- **Оптимизация:** Binary parsing без аллокаций (ByteBuf direct access)
- **Риск:** Overflow Kafka producer при burst трафике
- **Рекомендация:** Token Bucket rate limiting на уровне TCP handler

### 2. History Writer — Batch Insert
- **Текущее:** Batch INSERT в TimescaleDB через Doobie
- **Оптимизация:** 
  - COPY protocol вместо INSERT (~10x быстрее)
  - Настройка chunk_time_interval (1 день)
  - Compression для данных > 7 дней
- **Риск:** При лаге Kafka consumer — рост latency записи

### 3. Rule Checker — SpatialGrid + PostGIS
- **Текущее:** 
  - SpatialGrid (Redis) → O(1) поиск кандидатов
  - PostGIS ST_Contains → O(log n) проверка
- **Оптимизация:**
  - Cache геозон в памяти (для малых развёртываний)
  - Anti-bounce фильтрует ~30% ложных срабатываний
- **Риск:** Большое количество геозон (>10K) замедлит PostGIS

### 4. Analytics Service — Тяжёлые отчёты
- **Текущее:** Запросы к continuous aggregates TimescaleDB
- **Оптимизация:**
  - Hourly/Daily materialized views
  - Фоновый экспорт (S3 + presigned URLs)
- **Риск:** Сводный отчёт по 1000+ ТС может занять >30 секунд

### 5. WebSocket Service — Fan-out
- **Текущее:** Kafka → in-memory registry → WS clients
- **Оптимизация:** Parallelism=10 для отправки
- **Риск:** 1000+ WS клиентов на одном инстансе → memory pressure

---

## Масштабирование

### Горизонтальное
| Сервис | Масштабируется? | Как |
|--------|----------------|-----|
| Connection Manager | ✅ | Несколько инстансов за TCP load balancer |
| History Writer | ✅ | Kafka partition = parallelism |
| Rule Checker | ✅ | Kafka partition per device |
| Analytics Service | ✅ | Stateless, за HTTP LB |
| WebSocket Service | ⚠️ | Нужен sticky sessions или Redis pub/sub |
| Device Manager | ✅ | Stateless REST |

### Вертикальное
- TimescaleDB: больше CPU/RAM для аналитических запросов
- Redis: RAM для кэша устройств и state

---

## Нагрузочное тестирование (план)

### Сценарии
1. **GPS flood:** 20K точек/сек через TCP на 30 минут
2. **REST burst:** 1000 RPS на Device Manager REST API
3. **Report storm:** 50 параллельных сводных отчётов
4. **WS connections:** 5000 одновременных WS клиентов

### Инструменты
- **gatling** для HTTP/WS нагрузки
- **Кастомный TCP клиент** (Scala + Netty) для GPS потока
- **Prometheus + Grafana** для мониторинга

### Метрики для сбора
- Latency (p50, p95, p99)
- Throughput (events/sec)
- Error rate
- JVM heap, GC pauses
- Kafka consumer lag
- DB connections in use
- CPU / Memory per service
