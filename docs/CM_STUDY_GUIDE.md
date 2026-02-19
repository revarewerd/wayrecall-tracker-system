# 📖 Connection Manager — Порядок изучения

> Гайд для разработчика: в каком порядке читать код CM

## Уровень 1: Доменная модель (что мы обрабатываем)

Начни с понимания **данных**, которыми оперирует CM.

### 1.1 `domain/GpsPoint.scala` (~450 строк)
Самый важный файл. Все доменные типы:
- `GpsPoint` — валидированная GPS точка (8 полей)
- `GpsRawPoint` — сырая точка из протокола
- `DeviceData` — **единая структура из Redis HASH** (context + position + connection)
- `GpsEventMessage` — обогащённое сообщение для Kafka (с маршрутизационными флагами)
- `VehicleConfig` — маршрутизационные флаги (обратная совместимость)
- `DeviceStatus`, `DisconnectReason` — статус подключения
- `UnknownDeviceEvent`, `UnknownGpsPoint` — данные от незарегистрированных трекеров
- `DeviceEvent` — входящие события от Device Manager

### 1.2 `domain/Protocol.scala` (~71 строка)
Типизированные ошибки — sealed trait иерархии:
- `ProtocolError` — ошибки парсинга протокола
- `FilterError` — ошибки валидации точек
- `RedisError` — ошибки Redis
- `KafkaError` — ошибки Kafka

### 1.3 `domain/Command.scala` (~96 строк)
Система команд для трекеров (reboot, set interval и т.д.)

---

## Уровень 2: Конфигурация (как настраивается)

### 2.1 `config/AppConfig.scala` (~183 строки)
Все case class'ы конфигурации: TCP, Redis, Kafka, фильтры, HTTP.
Читай вместе с `src/main/resources/application.conf`.

### 2.2 `config/DynamicConfigService.scala` (~148 строк)
Динамическая конфигурация фильтров (in-memory Ref + Redis Pub/Sub).
Позволяет менять пороги Dead Reckoning без перезапуска.

---

## Уровень 3: Хранилище (куда пишем / откуда читаем)

### 3.1 `storage/RedisClient.scala` (~329 строк)
**Критически важный файл.** Redis клиент:
- Unified HASH `device:{imei}` — `getDeviceData`, `updateDevicePosition`, `setDeviceConnectionFields`, `clearDeviceConnectionFields`
- Legacy ключи — `getVehicleId`, `setPosition`
- Pub/Sub для команд и конфигурации
- ZLayer.scoped для управления ресурсами

### 3.2 `storage/KafkaProducer.scala` (~139 строк)
Публикация событий в 9 Kafka топиков.

### 3.3 `storage/VehicleLookupService.scala` (~138 строк)
Cache-Aside: Redis → PostgreSQL fallback для vehicleId по IMEI.

---

## Уровень 4: Протоколы (как парсим бинарные данные)

### 4.1 `protocol/ProtocolParser.scala` (~39 строк)
Базовый trait — контракт: `parseImei`, `parseData`, `ack`, `encodeCommand`.

### 4.2 `protocol/TeltonikaParser.scala` (~332 строки) ← ОСНОВНОЙ
Бинарный протокол Teltonika Codec 8/8E. Самый сложный парсер.
Парсит AVL-записи, IO-элементы, проверяет CRC-16-IBM.

### 4.3 Другие парсеры (WialonParser, RuptelaParser, NavTelecomParser)
Аналогичная логика для других протоколов.

---

## Уровень 5: Фильтрация (валидация GPS точек)

### 5.1 `filter/DeadReckoningFilter.scala` (~111 строк)
Отсеивает аномальные точки: невозможная скорость, телепортация,
будущие timestamps, невалидные координаты.

### 5.2 `filter/StationaryFilter.scala` (~69 строк)
Определяет движение/стоянку: публикуем в Kafka только при движении.

---

## Уровень 6: Обработка (ЯДРО СИСТЕМЫ)

### 6.1 `network/ConnectionHandler.scala` (~854 строки) ← САМЫЙ ВАЖНЫЙ
**Главный файл CM.** Два компонента:

1. **GpsProcessingService** (trait + Live) — чистая бизнес-логика:
   - `processImeiPacket` → HGETALL device:{imei} → аутентификация
   - `processDataPacket` → fresh HGETALL + фильтрация + обогащение
   - `processPoint` → Dead Reckoning → Stationary → HMSET Redis → Kafka
   - `onConnect` → HMSET connection полей + DeviceStatus
   - `onDisconnect` → HDEL connection полей + DeviceStatus

2. **ConnectionHandler** (Netty adapter) — мост Netty ↔ ZIO:
   - `channelRead` → IMEI пакет или DATA пакет
   - `handleImeiPacket` → аутентификация → ConnectionState
   - `handleDataPacket` → обработка → ACK
   - `channelInactive` → отключение → cleanup

3. **ConnectionState** — иммутабельное состояние TCP соединения:
   - IMEI, vehicleId, DeviceData, positionCache, connectedAt

### 6.2 `network/ConnectionRegistry.scala` (~201 строка)
In-memory реестр TCP соединений. ZIO Ref с Map[imei → ConnectionEntry].
Нужен для: отправки команд, idle timeout, мониторинга.

### 6.3 `network/TcpServer.scala` (~184 строки)
Netty TCP сервер. Создаёт Netty pipeline: RateLimiter → Timeout → ConnectionHandler.

---

## Уровень 7: Фоновые сервисы

### 7.1 `service/DeviceEventConsumer.scala` (~173 строки)
Kafka Consumer для `device-events`: обновляет маршрутизационные флаги в Redis HASH.

### 7.2 `service/CommandHandler.scala` (~302 строки)
Kafka Consumer для `device-commands`: отправляет команды на онлайн-трекеры.

### 7.3 `network/IdleConnectionWatcher.scala` (~159 строк)
Фоновый timer: отключает неактивные соединения каждые 30с.

### 7.4 `network/DeviceConfigListener.scala` (~116 строк)
Redis Pub/Sub: закрывает соединения заблокированных устройств.

### 7.5 `network/RateLimiter.scala` (~193 строки)
IP-based rate limiting со sliding window.

---

## Уровень 8: API и точка входа

### 8.1 `api/HttpApi.scala` (~181 строка)
REST API: health check, статистика, управление фильтрами, отправка команд.

### 8.2 `Main.scala` (~203 строки)
Точка входа. Композиция ВСЕХ ZIO Layers + запуск в правильном порядке.
Читай ПОСЛЕДНИМ — после понимания всех компонентов.

---

## 🗺️ Карта зависимостей (что от чего зависит)

```
Main
 ├── TcpServer ← ConnectionHandler ← GpsProcessingService
 │                                     ├── ProtocolParser (Teltonika/Wialon/...)
 │                                     ├── RedisClient
 │                                     ├── KafkaProducer
 │                                     ├── DeadReckoningFilter ← DynamicConfigService
 │                                     └── StationaryFilter ← DynamicConfigService
 ├── DeviceEventConsumer ← RedisClient
 ├── CommandHandler ← ConnectionRegistry, RedisClient
 ├── IdleConnectionWatcher ← ConnectionRegistry
 ├── DeviceConfigListener ← ConnectionRegistry, RedisClient
 ├── HttpApi ← ConnectionRegistry, DynamicConfigService, CommandService
 └── AppConfig (корневая конфигурация для всех)
```

## ⏱️ Примерное время изучения

| Уровень | Время | Файлов |
|---------|-------|--------|
| 1. Доменная модель | 1-2 часа | 3 |
| 2. Конфигурация | 30 мин | 2 |
| 3. Хранилище | 1-2 часа | 4 |
| 4. Протоколы | 2-3 часа | 5 |
| 5. Фильтрация | 30 мин | 2 |
| 6. Обработка (ядро) | 3-4 часа | 3 |
| 7. Фоновые сервисы | 1-2 часа | 5 |
| 8. API и Main | 1 час | 2 |
| **Итого** | **~12 часов** | **29** |
