# Анализ потребления памяти и ресурсов

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-02` | Версия: `1.0`

## Прогнозные требования по сервисам

### JVM Heap (рекомендации)

| Сервис | Min Heap | Max Heap | Причина |
|--------|----------|----------|---------|
| Connection Manager | 256 MB | 1 GB | Netty buffer pool + device context кэш |
| History Writer | 128 MB | 512 MB | Batch accumulation GPS точек |
| Device Manager | 128 MB | 256 MB | Stateless REST |
| Rule Checker | 256 MB | 512 MB | SpatialGrid кэш + VehicleState |
| Analytics Service | 256 MB | 1 GB | Генерация отчётов, foreachPar |
| Notification Service | 128 MB | 256 MB | In-memory throttle counters |
| Integration Service | 128 MB | 512 MB | Wialon TCP connection pool |
| WebSocket Service | 256 MB | 1 GB | WS connection registry |
| Maintenance Service | 128 MB | 256 MB | Stateless с кэшем |
| User Service | 128 MB | 256 MB | Stateless REST |
| Admin Service | 128 MB | 256 MB | Stateless REST |
| Sensors Service | 128 MB | 256 MB | Processing pipeline |
| Auth Service | 128 MB | 256 MB | JWT + cache |
| API Gateway | 256 MB | 512 MB | HTTP proxy + JWT validation |

**Итого на dev стенд:** ~2 GB (все сервисы по min)
**Итого production (single node):** ~6-8 GB

---

## Структуры в памяти

### Connection Manager
- `deviceContextCache: Ref[Map[String, DeviceContext]]` — ~500 байт/устройство × 20K = 10 MB
- Netty ByteBuf pool — управляется Netty, ~64-128 MB
- ZIO fiber pool — минимальный overhead

### Rule Checker
- `VehicleState per device` — Map текущих геозон, pending enter/leave, speed violations
  - ~200 байт/устройство × 20K = 4 MB
- `SpatialGrid` — хранится в Redis, не в JVM
- `SpeedRules cache` — ~100 байт/правило × 1K = 100 KB

### WebSocket Service
- `ConnectionRegistry: Ref[Map[ConnectionId, WsConnection]]` — ~1 KB/соединение × 5K = 5 MB
- `Subscriptions: Map[VehicleId, Set[ConnectionId]]` — ~200 байт/подписка

### Notification Service
- `ThrottleService` — два `Ref[Map]`:
  - throttleRef: ~100 байт/запись × 10K = 1 MB
  - rateRef: ~100 байт/запись × 1K = 100 KB
  - ⚠️ Нет очистки старых записей! Может расти бесконечно.

### Analytics Service
- `ReportCache: Ref[Map[String, String]]` — JSON строки отчётов
  - ~10 KB/отчёт × 100 = 1 MB
  - ⚠️ Нет TTL / eviction! Потенциальная утечка памяти.

---

## Известные проблемы с памятью

### 🔴 Критичные
1. **ThrottleService (notification)** — Map растёт без bounds, старые записи не удаляются
2. **ReportCache (analytics)** — In-memory без TTL, потенциальный OOM при интенсивном использовании

### 🟡 Средние 
3. **WialonSender connection pool** — TCP сокеты не закрываются при длительном простое
4. **Kafka consumer offset cache** — ZIO-Kafka управляет, но при большом количестве партиций может расти

### 🟢 Рекомендации
5. Перевести ReportCache и ThrottleService на Redis (уже есть в production плане)
6. Добавить TTL-based eviction для in-memory кэшей
7. Мониторить JVM heap через Prometheus JMX exporter
8. Настроить GC: G1GC с `-XX:MaxGCPauseMillis=100`

---

## Docker ресурсы (рекомендации)

### Разработка (docker-compose)
```yaml
services:
  connection-manager:
    mem_limit: 1g
    cpus: 1.0
  history-writer:
    mem_limit: 512m
    cpus: 0.5
  device-manager:
    mem_limit: 256m
    cpus: 0.5
  # ... остальные по 256-512m
```

### Production (Kubernetes)
```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```
