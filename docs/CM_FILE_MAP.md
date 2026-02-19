# 🗂️ Connection Manager — Карта файлов и ответственности

> 29 файлов, ~5900 строк Scala 3, организованы по пакетам

## Визуальная схема

```
src/main/scala/com/wayrecall/tracker/
│
├── Main.scala ·················· ТОЧКА ВХОДА: композиция Layers, запуск, graceful shutdown
│
├── api/
│   └── HttpApi.scala ··········· REST API: /health, /connections, /commands, /filters
│
├── config/
│   ├── AppConfig.scala ········· 15 case class конфигурации (TCP, Redis, Kafka, фильтры)
│   └── DynamicConfigService.scala  Динамическая конфигурация (Ref + Redis Pub/Sub)
│
├── domain/ ····················· ДОМЕННЫЕ ТИПЫ (case class + sealed trait)
│   ├── GpsPoint.scala ·········· GPS точка, DeviceData, GpsEventMessage, VehicleConfig,
│   │                             DeviceStatus, DisconnectReason, UnknownDevice*, DeviceEvent
│   ├── Protocol.scala ·········· Типизированные ошибки: Protocol/Filter/Redis/KafkaError
│   ├── ParseError.scala ········ 10 типов ошибок парсинга (CRC, IMEI, координаты)
│   ├── Command.scala ··········· Sealed-иерархия команд для трекеров (reboot, interval...)
│   └── Vehicle.scala ··········· VehicleInfo (id, imei, name, deviceType, isActive)
│
├── filter/ ····················· ФИЛЬТРАЦИЯ GPS ТОЧЕК
│   ├── DeadReckoningFilter.scala  Отсев аномалий (скорость, телепортация, будущие timestamp)
│   └── StationaryFilter.scala ·· Определение движения/стоянки (публикация только при движении)
│
├── network/ ···················· СЕТЕВОЙ СЛОЙ + БИЗНЕС-ЛОГИКА
│   ├── ConnectionHandler.scala · ★ ЯДРО: GpsProcessingService + Netty Handler + ConnectionState
│   │                             processImeiPacket → HGETALL | processDataPacket → fresh HGETALL
│   │                             processPoint → фильтры → HMSET → Kafka | onConnect/onDisconnect
│   ├── TcpServer.scala ········· Netty TCP сервер (EventLoop, pipeline, binding)
│   ├── ConnectionRegistry.scala  In-memory реестр соединений (ZIO Ref[Map[imei → Entry]])
│   ├── IdleConnectionWatcher.scala  Timer: отключение неактивных каждые 30с
│   ├── DeviceConfigListener.scala   Redis Pub/Sub: block/unblock устройств
│   ├── RateLimiter.scala ·········  IP rate limiting (sliding window)
│   └── CommandService.scala ······  Legacy: Redis Pub/Sub для ответов на команды
│
├── protocol/ ··················· ПАРСЕРЫ БИНАРНЫХ ПРОТОКОЛОВ
│   ├── ProtocolParser.scala ···· Базовый trait: parseImei, parseData, ack, encodeCommand
│   ├── TeltonikaParser.scala ··· Codec 8/8E: AVL записи, IO элементы, CRC-16-IBM
│   ├── WialonParser.scala ······ IPS: #L#, #D#, #SD#, DDMM.MMMM конвертация
│   ├── RuptelaParser.scala ····· Records, extended records, CRC-16
│   └── NavTelecomParser.scala ·· FLEX: "*>" сигнатура, CRC-16-CCITT
│
├── service/ ···················· KAFKA CONSUMERS (фоновые)
│   ├── DeviceEventConsumer.scala  device-events: обновление флагов в device:{imei} HASH
│   └── CommandHandler.scala ····  device-commands: отправка команд онлайн-трекерам
│
└── storage/ ···················· КЛИЕНТЫ ХРАНИЛИЩ
    ├── RedisClient.scala ······· Lettuce: unified HASH + legacy + Pub/Sub + ZSET
    ├── KafkaProducer.scala ····· zio-kafka: 8 методов публикации в 9 топиков
    ├── VehicleLookupService.scala  Cache-Aside: Redis → PostgreSQL fallback
    └── DeviceRepository.scala ·· PostgreSQL trait (Dummy impl для тестов)
```

## Ответственность по файлам

| Файл | Строк | Ключевая ответственность |
|------|-------|--------------------------|
| **Main.scala** | 203 | Композиция ZIO Layers, запуск 8 шагов, graceful shutdown |
| **HttpApi.scala** | 181 | 5 REST endpoints, health check, CORS |
| **AppConfig.scala** | 183 | 15 case class конфигурации, загрузка из HOCON |
| **DynamicConfigService.scala** | 148 | Hot-reload фильтров через Redis Pub/Sub |
| **GpsPoint.scala** | 446 | 14 доменных типов, DeviceData с fromRedisHash |
| **Protocol.scala** | 71 | 4 sealed trait иерархии ошибок |
| **ParseError.scala** | 205 | 10 типов ошибок парсинга |
| **Command.scala** | 96 | 5 типов команд, CommandStatus enum |
| **Vehicle.scala** | 14 | VehicleInfo (минимальный) |
| **DeadReckoningFilter.scala** | 111 | 4 проверки: скорость, координаты, время, телепортация |
| **StationaryFilter.scala** | 69 | Порог расстояния + скорости для shouldPublish |
| **ConnectionHandler.scala** | 854 | ★ ЯДРО: 3 компонента (Service + Handler + State) |
| **TcpServer.scala** | 184 | Netty bootstrap, pipeline, bind, shutdown |
| **ConnectionRegistry.scala** | 201 | CRUD соединений, поиск по IMEI, idle tracking |
| **IdleConnectionWatcher.scala** | 159 | Периодическая проверка + отключение |
| **DeviceConfigListener.scala** | 116 | Pub/Sub → закрытие заблокированных |
| **RateLimiter.scala** | 193 | Sliding window, cleanup, IP blacklist |
| **CommandService.scala** | 214 | Promise-based ожидание ответов на команды |
| **ProtocolParser.scala** | 39 | Контракт для всех парсеров |
| **TeltonikaParser.scala** | 332 | Codec 8/8E, AVL, IO, CRC |
| **WialonParser.scala** | 181 | IPS текстовый протокол |
| **RuptelaParser.scala** | 253 | Бинарный протокол Ruptela |
| **NavTelecomParser.scala** | 294 | FLEX бинарный протокол |
| **DeviceEventConsumer.scala** | 173 | Kafka → HMSET device:{imei} |
| **CommandHandler.scala** | 302 | Kafka → отправка команд на трекеры |
| **RedisClient.scala** | 329 | Unified HASH + Legacy + Pub/Sub |
| **KafkaProducer.scala** | 139 | 8 publish методов → 9 топиков |
| **VehicleLookupService.scala** | 138 | Redis cache + PostgreSQL fallback |
| **DeviceRepository.scala** | 91 | PostgreSQL trait (dummy для тестов) |

## Распределение кода по слоям

```
                    ┌─────────────────┐
                    │  Main.scala     │  Точка входа
                    └────────┬────────┘
                             │
     ┌───────────────────────┼───────────────────────┐
     │                       │                       │
┌────┴─────┐          ┌──────┴──────┐          ┌─────┴──────┐
│ api/     │          │ network/    │          │ service/   │
│ 181 стр  │          │ 1920 стр   │          │ 475 стр    │
│ HTTP API │          │ TCP+Logic   │          │ Kafka Cons │
└──────────┘          └──────┬──────┘          └─────┬──────┘
                             │                       │
              ┌──────────────┼──────────────┐        │
              │              │              │        │
         ┌────┴────┐   ┌────┴────┐    ┌────┴────┐   │
         │protocol/│   │filter/  │    │storage/ │◄──┘
         │1099 стр │   │180 стр  │    │697 стр  │
         │Парсеры  │   │Фильтры  │    │Redis    │
         └─────────┘   └─────────┘    │Kafka    │
                                      │Postgres │
              ┌────────────┐          └─────────┘
              │ domain/    │
              │ 832 стр    │ ← Используется ВСЕМИ
              │ Типы+Error │
              └────────────┘
              ┌────────────┐
              │ config/    │
              │ 331 стр    │ ← Используется ВСЕМИ
              │ Конфиги    │
              └────────────┘
```
