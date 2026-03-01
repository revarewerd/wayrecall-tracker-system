# Полный список GPS-протоколов в Legacy STELS

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-01` | Версия: `1.0`

## Сводная таблица

| # | Протокол | TCP-порт (legacy) | Формат | Netty Server | Выделенный парсер | В новом CM? |
|---|---|---|---|---|---|---|
| 1 | **Teltonika Codec 8/8E** | 9088 | Binary | `TeltonikaNettyServer.java` (Netty 3) | `avlprotocols/teltonika/TeltonikaParser.java` | ✅ Да |
| 2 | **Wialon IPS** (v1, бинарный) | 9087 | Binary (4B LE length + body) | `WialonNettyServer.java` (Netty 3) | `core/../wialonparser/WialonParser.java` | ✅ Да (WialonAdapterParser) |
| 3 | **Wialon IPS 2.0** (текстовый + deflate) | 20332 | Text (line-based) + zlib | `WialonIPS2Server.scala` (Netty 4) | Inline в `WialonIPS2Decoder` | ✅ Да (WialonAdapterParser) |
| 4 | **Ruptela** | 9089 | Binary (2B length + 8B IMEI long + cmd) | `RuptelaNettyServer.scala` (Netty 3) | `avlprotocols/ruptela/RuptelaParser.java` | ✅ Да |
| 5 | **NavTelecom FLEX** | 9085 | Binary (NTCB + FLEX протоколы) | `NavTelecomNettyServer.scala` (Netty 4) | `avlprotocols/navtelecom/NavtelecomParser.scala` + `FlexParser` | ✅ Да |
| 6 | **GoSafe** | 9086 | Binary (маркер 0xF8, escape-кодирование) | `GosafeNettyServer.scala` (Netty 3) | `avlprotocols/gosafe/GosafeParser.scala` | ✅ Да |
| 7 | **SkySim** | 9084 | Binary (0x5B..0x5D, tag-based) | `SkysimNettyServer.scala` (Netty 4) | `avlprotocols/skysim/Skysim.scala` | ✅ Да |
| 8 | **Autophone Mayak** | 9083 | Binary (0x10=auth, 0x11=work, 0x12=blackbox) | `AutophoneMayakServer.scala` (Netty 4) | `avlprotocols/autophonemayak/AutophoneMayak.scala` + `AutophoneMayak7.scala` | ✅ Да |
| 9 | **DTM** | 9082 | Binary (0x7B..0x7D маркеры) | `DTMServer.scala` (Netty 4) | `avlprotocols/dtm/DTM.scala` | ✅ Да |
| 10 | **Galileosky** | 9097 | Binary LE (tag-based, CRC) | `GalileoskyServer.scala` (Netty 4) | Inline в `GalileoskyAvlDataDecoder` | ❌ Нет |
| 11 | **GL06** (Concox/Queclink) | 9094 | Binary (0x78 0x78 start, 0x0D 0x0A stop) | `GL06Server.scala` (Netty 4) | Inline в `GL06AvlDataDecoder` | ❌ Нет |
| 12 | **TK102** | 9092 | Text/Binary (0x28..0x29 маркеры, '(' и ')') | `TK102Server.scala` (Netty 4) | Inline в `TK102rAvlDataDecoder` | ❌ Нет |
| 13 | **TK103** | 9095 | Text (0x28..0x29, CSV-like) | `TK103Server.scala` (Netty 4) | Inline в `TK103rAvlDataDecoder` | ❌ Нет |
| 14 | **Arnavi** | 9091 | Text (line/NUL-delimited, `$AV,V2/V3,...`) | `ArnaviServer.scala` (Netty 4) | Inline в `ArnaviAvlDataDecoder` | ❌ Нет |
| 15 | **ADM (ADM1_07)** | 9096 | Binary LE (2B deviceId + 1B size + body) | `ADM1_07Server.scala` (Netty 4) | Inline в `ADM1_07AvlDataDecoder` | ❌ Нет |
| 16 | **GTLT3MT1** (GlobusTracker) | 9093 | Text (CSV, '#'-delimited frames) | `GTLT3MT1Server.scala` (Netty 4) | Inline в `GTLT3MT1Decoder` | ❌ Нет |
| 17 | **SkyPatrol** | 9090 (UDP!) | Binary UDP (DatagramPacket) | `SkyPatrolNettyServer.scala` (Netty 4, UDP) | Inline в `SkyPatrolMessageReceiver` | ❌ Нет |
| 18 | **MicroMayak** | 9090 (по умолчанию) | Binary (0x24='$' start, async protocol) | `MicroMayakServer.scala` (Netty 4) | Inline (async state machine) | ❌ Нет |
| 19 | **Zudo** | 1081 (HTTP!) | HTTP POST (multipart, bin field) | `ZudoServer.scala` (Netty 4, HTTP) | `avlprotocols/zudo/ZudoParser.scala` | ❌ Нет |
| 20 | **EGTS** (proxy) | 7001 | Binary (EGTS Transport+AppData) | `EgtsProxyServer.scala` (Netty 4) | `avlprotocols/egts/TransportPackage.scala` | ❌ Нет |
| 21 | **BsonGPS** (internal) | 4511 | BSON/Wialon hybrid | blocking `BsonGPSPackReceiver.scala` | Использует `WialonParser` + `DboReader` | ❌ Нет |

---

## Детальное описание каждого протокола

### 1. Teltonika Codec 8/8E
- **Порт:** 9088
- **Формат:** Бинарный. Первый пакет — 2 байта длина IMEI + ASCII IMEI. Далее — [4B нули][4B size][codec_id][data][4B CRC16].
- **Server:** [TeltonikaNettyServer.java](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/TeltonikaNettyServer.java) (Netty 3, `LengthFieldBasedFrameDecoder`)
- **Parser:** [TeltonikaParser.java](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/teltonika/TeltonikaParser.java) (188 строк)
- **Blocking альтернатива:** `blocking/TeltonikaPackReceiver.scala` (устаревший)
- **В новом CM:** ✅ `TeltonikaParser.scala`

### 2. Wialon IPS (v1, бинарный)
- **Порт:** 9087
- **Формат:** Бинарный. 4 байта LE размер пакета, затем тело с блоками координат.
- **Server:** [WialonNettyServer.java](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/WialonNettyServer.java) (Netty 3, 692 строк, inline parsing)
- **Parser:** [WialonParser.java](../../legacy-stels/core/src/main/java/ru/sosgps/wayrecall/wialonparser/WialonParser.java) (153 строк, в core модуле)
- **Дополнительные файлы:** `WialonPackage.java`, `WialonCoordinatesBlock.java`, `WialonPackager.scala`
- **Blocking альтернатива:** `blocking/WialonPackReceiver.scala`
- **В новом CM:** ✅ `WialonAdapterParser.scala` + `WialonParser.scala` + `WialonBinaryParser.scala`

### 3. Wialon IPS 2.0 (текстовый + deflate сжатие)
- **Порт:** 20332
- **Формат:** Текстовый (line-based), поддержка zlib/deflate сжатия. Сообщения вида `#KEY#body`. Если первый байт 0xFF — включается zlib декомпрессия.
- **Server:** [WialonIPS2Server.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/WialonIPS2Server.scala) (Netty 4, 213 строк)
- **Parser:** Встроенный в `WialonIPS2Decoder` — regex-based парсинг текстовых сообщений, `#L#`, `#D#`, `#SD#`, `#B#`, `#P#`, `#M#`
- **В новом CM:** ✅ (вероятно через `WialonAdapterParser`)

### 4. Ruptela
- **Порт:** 9089
- **Формат:** Бинарный. [2B length][body (8B IMEI long + 1B commandId + data)][2B CRC16 Kermit].
- **Server:** [RuptelaNettyServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/RuptelaNettyServer.scala) (Netty 3, 101 строк)
- **Parser:** [RuptelaParser.java](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/ruptela/RuptelaParser.java) (293 строк)
- **Дополнительные:** `RuptelaPackProcessor.scala`, `RuptelaReconfigurator.scala`, `RuptelaStatePublisher.scala`, `RuptelaConfigParser.scala`
- **Blocking альтернатива:** `blocking/RuptelaPackReceiver.scala`
- **В новом CM:** ✅ `RuptelaParser.scala`

### 5. NavTelecom FLEX
- **Порт:** 9085
- **Формат:** Бинарный. Два подпротокола: NTCB (сигнатура `@NTC`, 16B header + body) и FLEX (сигнатура `*>FLEX`, динамическая битовая маска полей). LE byte order.
- **Server:** [NavTelecomNettyServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/NavTelecomNettyServer.scala) (Netty 4, 191 строк)
- **Parser:** [NavtelecomParser.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/navtelecom/NavtelecomParser.scala) (551 строк) — содержит `NavtelecomParser` + `FlexParser`
- **Дополнительные:** `NavtelecomConnectionProcessor.scala` (stateful обработка), `NavTelecomCommander.scala`
- **Поддержка команд:** Да (через `activeConnections`, `NavtelecomCommand`)
- **В новом CM:** ✅ `NavTelecomParser.scala`

### 6. GoSafe
- **Порт:** 9086
- **Формат:** Бинарный. Маркер начала 0xF8, escape-кодирование (0x1B). Поддержка LBS (tower data). Время от фиксированного startTime (2000-01-01 UTC).
- **Server:** [GosafeNettyServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/GosafeNettyServer.scala) (Netty 3, 175 строк)
- **Parser:** [GosafeParser.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/gosafe/GosafeParser.scala) (319 строк)
- **Дополнительные:** `GosafePacket.scala`, `GosafeLBSUpload.scala`
- **Blocking альтернатива:** `blocking/GosafePackReceiver.scala`
- **В новом CM:** ✅ `GoSafeParser.scala`

### 7. SkySim
- **Порт:** 9084
- **Формат:** Бинарный LE. Заголовок (версия 0x22 или 0x23), пакеты обрамлены 0x5B..0x5D. Tag-based поля. Поддержка разных версий header.
- **Server:** [SkysimNettyServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/SkysimNettyServer.scala) (Netty 4, 80 строк)
- **Parser:** [Skysim.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/skysim/Skysim.scala) (190 строк)
- **В новом CM:** ✅ `SkySimParser.scala`

### 8. Autophone Mayak
- **Порт:** 9083
- **Формат:** Бинарный. Фиксированные размеры пакетов: AUTH=12B (0x10), WORKING=78B (0x11), BLACKBOX=257B (0x12). Два подварианта: основной + версия 7 (с преамбулой `$`).
- **Server:** [AutophoneMayakServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/AutophoneMayakServer.scala) (Netty 4, 80 строк)
- **Parser:** [AutophoneMayak.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/autophonemayak/AutophoneMayak.scala) (302 строк) + [AutophoneMayak7.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/autophonemayak/AutophoneMayak7.scala) (313 строк)
- **В новом CM:** ✅ `AutophoneMayakParser.scala`

### 9. DTM
- **Порт:** 9082
- **Формат:** Бинарный. Маркеры: 0x7B ('{') — начало, 0x7D ('}') — конец. Поддержка I/O команд управления (блокировка двигателя и т.д.).
- **Server:** [DTMServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/DTMServer.scala) (Netty 4, 154 строк)
- **Parser:** [DTM.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/dtm/DTM.scala) (214 строк)
- **Поддержка команд:** Да (I/O switch commands через activeConnections)
- **В новом CM:** ✅ `DtmParser.scala`

---

### 10. Galileosky ❌
- **Порт:** 9097
- **Формат:** Бинарный LE. 1B header + 2B size (bit 15 = compressed flag) + tag-based payload + 2B CRC. Tag 0x03 = IMEI (15 байт ASCII). Множество тегов: 0x20=datetime, 0x30=coord, 0x33=speed, и т.д.
- **Server:** [GalileoskyServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/GalileoskyServer.scala) (Netty 4, 208 строк)
- **Parser:** Полностью inline в `GalileoskyAvlDataDecoder` — tag-switch парсинг
- **Особенности:** Tag-based протокол (аналог FLEX), поддержка множества дополнительных данных (температура, аналоговые входы, CAN-данные)
- **В новом CM:** ❌

### 11. GL06 (Concox / Queclink GT06) ❌
- **Порт:** 9094
- **Формат:** Бинарный. Начало: 0x78 0x78, размер: 1 байт unsigned, стоп-биты: 0x0D 0x0A. Многоступенчатый: сначала логин с IMEI, затем пакеты GPS.
- **Server:** [GL06Server.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/GL06Server.scala) (Netty 4, 137 строк)
- **Parser:** Inline в `GL06AvlDataDecoder`
- **В новом CM:** ❌

### 12. TK102 ❌
- **Порт:** 9092
- **Формат:** Text/Binary hybrid. Маркеры: `(` (0x28) — начало, `)` (0x29) — конец. Внутри: 12 байт serial + 4 байта command + body. NMEA-like координаты.
- **Server:** [TK102Server.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/TK102Server.scala) (Netty 4, 136 строк)
- **Parser:** Inline в `TK102rAvlDataDecoder`
- **Дата:** `yyMMdd` + `HHmmss`
- **В новом CM:** ❌

### 13. TK103 ❌
- **Порт:** 9095
- **Формат:** Text (аналогичен TK102). Маркеры: `(` / `)`. 12B serial + 4B command + CSV body. NMEA-координаты.
- **Server:** [TK103Server.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/TK103Server.scala) (Netty 4, 133 строк)
- **Parser:** Inline в `TK103rAvlDataDecoder`
- **В новом CM:** ❌

### 14. Arnavi ❌
- **Порт:** 9091
- **Формат:** Text ASCII. Line/NUL-delimited. Формат: `$AV,V2,...,#CRC` или `$AV,V3,...`. CSV с запятой. Ответ: `RCPTOK\r\n`.
- **Server:** [ArnaviServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/ArnaviServer.scala) (Netty 4, 163 строки)
- **Parser:** Inline в `ArnaviAvlDataDecoder` — поддержка V2 и V3 подварианта.
- **Дата:** `ddMMyy` + `HHmmss`, координаты в NMEA-формате (DDMM.MMMM)
- **В новом CM:** ❌

### 15. ADM (ADM1_07) ❌
- **Порт:** 9096
- **Формат:** Бинарный LE. 2B deviceId + 1B size + body. Дата: `yyMMdd` + `HHmmss` в ASCII внутри бинарного кадра. Поддержка битовых масок для I/O.
- **Server:** [ADM1_07Server.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/ADM1_07Server.scala) (Netty 4, 150 строк)
- **Parser:** Inline в `ADM1_07AvlDataDecoder`
- **В новом CM:** ❌

### 16. GTLT3MT1 (GlobusTracker LT-3 MT-1) ❌
- **Порт:** 9093
- **Формат:** Text ASCII. '#'-delimited frames, внутри CSV с запятой. Формат: `serial,command,time,validity,lat,N/S,lon,E/W,speed,direction,date,status#`.
- **Server:** [GTLT3MT1Server.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/GTLT3MT1Server.scala) (Netty 4, 97 строк)
- **Parser:** Inline в `GTLT3MT1Decoder`. Координаты NMEA (`DDMM.MMMM`).
- **В новом CM:** ❌

### 17. SkyPatrol ❌ (UDP!)
- **Порт:** 9090 (UDP, не TCP!)
- **Формат:** Бинарный UDP. DatagramPacket, бинарный парсинг через `RichDataInput`.
- **Server:** [SkyPatrolNettyServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/SkyPatrolNettyServer.scala) (Netty 4, 192 строки, `NioDatagramChannel`)
- **Parser:** Inline в `SkyPatrolMessageReceiver`
- **Особенности:** UDP-only! Не TCP. Использует `NioDatagramChannel`, `SO_BROADCAST`.
- **В новом CM:** ❌

### 18. MicroMayak ❌
- **Порт:** 9090 (Конфликт с SkyPatrol в config! Реально конфигурируется через `packreceiver.micromayac.port`)
- **Формат:** Бинарный. Асинхронный протокол. Start marker 0x24 ('$'). Auth (0x02), работа через `Connection` future-based state machine. Поддержка LBS, множество event-кодов (0xE0-0xFE). Использует `NavTelecom FlexParser` для парсинга тела сообщений.
- **Server:** [MicroMayakServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/MicroMayakServer.scala) (Netty 4, 344 строки, самый сложный inline парсер!)
- **Parser:** Inline, с использованием `NavTelecom.FlexParser` для данных
- **Особенности:** Асинхронная state-machine, LBS-поддержка, очень сложная логика
- **В новом CM:** ❌

### 19. Zudo ❌ (HTTP!)
- **Порт:** 1081 (HTTP, не TCP!)
- **Формат:** HTTP POST multipart/form-data. Поле `id` = IMEI, поле `bin` = бинарные GPS-данные. Время: Unix epoch + 10 лет и 5 дней сдвиг.
- **Server:** [ZudoServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/ZudoServer.scala) (Netty 4, HTTP pipeline: `HttpServerCodec` + `HttpObjectAggregator` + `HttpServerHandler`)
- **Parser:** [ZudoParser.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/avlprotocols/zudo/ZudoParser.scala) (211 строк)
- **Дополнительно:** Кастомный `ZudoPostRequestDecoder` (целиком скопированный Netty HTTP multipart с модификациями, 21 Java файл!)
- **В новом CM:** ❌

### 20. EGTS (proxy только) ❌
- **Порт:** 7001 (proxy)
- **Формат:** Бинарный LE. ГОСТ Р 56360-2015. Transport layer (headerLength + frameLength) + AppData frames + TermIdentity subrecords.
- **Server:** [EgtsProxyServer.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/EgtsProxyServer.scala) (Netty 4, 86 строк). **Это ПРОКСИ, а не полноценный receiver!** Проксирует данные на внешний EGTS-сервер с подменой IMEI.
- **Parser:** `avlprotocols/egts/` — `TransportPackage.scala`, `AppDataFrame.scala`, `Frame.scala`, `Package.scala`
- **Особенности:** Только проксирование! Не сохраняет данные в свою БД.
- **В новом CM:** ❌

### 21. BsonGPS (internal) ❌
- **Порт:** 4511
- **Формат:** Гибрид. Принимает BSON-объекты или Wialon-пакеты. Использует `DboReader` для чтения BSON, и `WialonParser` для чтения Wialon-формата. Blocking IO.
- **Server:** [BsonGPSPackReceiver.scala](../../legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/blocking/BsonGPSPackReceiver.scala) (blocking, 76 строк)
- **Особенности:** Внутренний протокол для передачи данных между сервисами. Не GPS-трекерский протокол.
- **В новом CM:** ❌ (вероятно не нужен — Kafka заменяет)

---

## Статистика

| Метрика | Значение |
|---|---|
| **Всего протоколов** | **21** |
| **Реализовано в новом CM** | **9** (только дедицированные парсеры через `MultiProtocolParser`) |
| **Не реализовано** | **12** |
| **TCP-протоколов** | 17 |
| **UDP-протоколов** | 1 (SkyPatrol) |
| **HTTP-протоколов** | 1 (Zudo) |
| **Proxy-only** | 1 (EGTS) |
| **Internal** | 1 (BsonGPS) |

## Категоризация НЕ реализованных

### Приоритет 1 — Реальные GPS-протоколы от трекеров
| Протокол | Сложность | Примечание |
|---|---|---|
| Galileosky | Средняя | Tag-based, хорошо документирован |
| GL06 (Concox/GT06) | Средняя | Очень популярный в Китае |
| TK102 | Низкая | Простой текстовый |
| TK103 | Низкая | Аналогичен TK102 |
| Arnavi | Низкая | Простой CSV |
| ADM1_07 | Средняя | Бинарный LE |
| GTLT3MT1 | Низкая | Простой CSV |
| MicroMayak | Высокая | Сложная async state machine + FlexParser |

### Приоритет 2 — Нестандартный транспорт
| Протокол | Сложность | Примечание |
|---|---|---|
| SkyPatrol | Средняя | UDP — нужен отдельный UDP listener |
| Zudo | Средняя | HTTP — нужен HTTP pipeline |

### Приоритет 3 — Специальные
| Протокол | Сложность | Примечание |
|---|---|---|
| EGTS (proxy) | Высокая | Российский ГОСТ, только проксирование |
| BsonGPS | Не нужна | Внутренний протокол, заменён Kafka |

---

## Дерево файлов

```
legacy-stels/
├── packreceiver/src/main/java/ru/sosgps/wayrecall/
│   ├── avlprotocols/                          # Выделенные парсеры
│   │   ├── autophonemayak/
│   │   │   ├── AutophoneMayak.scala          # Основной парсер (302 строк)
│   │   │   └── AutophoneMayak7.scala         # Версия 7 (313 строк)
│   │   ├── common/
│   │   │   ├── ConnectedDevicesWatcher.scala  # Менеджер активных соединений
│   │   │   ├── DeviceCommander.scala          # Интерфейс для отправки команд
│   │   │   ├── StoredDeviceCommand.scala      # Модель команды
│   │   │   └── StoredDeviceCommandsQueue.scala
│   │   ├── dtm/
│   │   │   └── DTM.scala                     # Парсер + команды (214 строк)
│   │   ├── egts/
│   │   │   ├── AppDataFrame.scala            # EGTS application data
│   │   │   ├── Frame.scala                   # EGTS frame
│   │   │   ├── Package.scala                 # EGTS package
│   │   │   └── TransportPackage.scala        # EGTS transport layer
│   │   ├── gosafe/
│   │   │   ├── GosafeParser.scala            # Основной парсер (319 строк)
│   │   │   ├── GosafePacket.scala            # Модель пакета
│   │   │   └── GosafeLBSUpload.scala         # LBS (tower data)
│   │   ├── navtelecom/
│   │   │   ├── NavtelecomParser.scala        # NTCB + FLEX парсер (551 строк!)
│   │   │   ├── NavtelecomConnectionProcessor.scala  # Stateful обработка
│   │   │   └── NavTelecomCommander.scala     # Отправка команд
│   │   ├── ruptela/
│   │   │   ├── RuptelaParser.java            # Парсер (293 строк)
│   │   │   ├── RuptelaIncomingPackage.java   # Модель пакета
│   │   │   ├── RuptelaPackProcessor.scala    # Обработка
│   │   │   ├── RuptelaReconfigurator.scala   # Переконфигурация трекеров
│   │   │   ├── RuptelaConfigParser.scala     # Парсер конфигов
│   │   │   └── RuptelaStatePublisher.scala   # Публикация состояния
│   │   ├── skysim/
│   │   │   └── Skysim.scala                  # Парсер (190 строк)
│   │   ├── teltonika/
│   │   │   └── TeltonikaParser.java          # Парсер (188 строк)
│   │   └── zudo/
│   │       ├── ZudoParser.scala              # HTTP body парсер (211 строк)
│   │       └── multipart/                    # 21 Java файл — кастомный HTTP decoder
│   │
│   └── packreceiver/
│       ├── netty/                             # Netty серверы (TCP/UDP/HTTP)
│       │   ├── TeltonikaNettyServer.java      # ✅ Netty 3
│       │   ├── WialonNettyServer.java         # ✅ Netty 3 (692 строк!)
│       │   ├── WialonIPS2Server.scala         # ✅ Netty 4
│       │   ├── RuptelaNettyServer.scala       # ✅ Netty 3
│       │   ├── NavTelecomNettyServer.scala    # ✅ Netty 4
│       │   ├── GosafeNettyServer.scala        # ✅ Netty 3
│       │   ├── SkysimNettyServer.scala        # ✅ Netty 4
│       │   ├── AutophoneMayakServer.scala     # ✅ Netty 4
│       │   ├── DTMServer.scala                # ✅ Netty 4
│       │   ├── GalileoskyServer.scala         # ❌ Netty 4 (inline)
│       │   ├── GL06Server.scala               # ❌ Netty 4 (inline)
│       │   ├── TK102Server.scala              # ❌ Netty 4 (inline)
│       │   ├── TK103Server.scala              # ❌ Netty 4 (inline)
│       │   ├── ArnaviServer.scala             # ❌ Netty 4 (inline)
│       │   ├── ADM1_07Server.scala            # ❌ Netty 4 (inline)
│       │   ├── GTLT3MT1Server.scala           # ❌ Netty 4 (inline)
│       │   ├── SkyPatrolNettyServer.scala     # ❌ Netty 4 (UDP)
│       │   ├── MicroMayakServer.scala         # ❌ Netty 4 (inline 344 строк)
│       │   ├── ZudoServer.scala               # ❌ Netty 4 (HTTP)
│       │   ├── EgtsProxyServer.scala          # ❌ Netty 4 (proxy)
│       │   ├── PackProcessorWriterHandler.scala  # Общий trait
│       │   └── ProxiedHandler.scala           # TCP proxy handler
│       │
│       └── blocking/                          # Устаревшие blocking серверы
│           ├── TeltonikaPackReceiver.scala    # Legacy blocking Teltonika
│           ├── WialonPackReceiver.scala       # Legacy blocking Wialon
│           ├── RuptelaPackReceiver.scala      # Legacy blocking Ruptela
│           ├── GosafePackReceiver.scala       # Legacy blocking GoSafe
│           ├── BsonGPSPackReceiver.scala      # Internal BSON/Wialon
│           ├── SimpleServer.scala             # Базовый blocking сервер
│           └── Proxy.scala                    # TCP proxy
│
└── core/src/main/java/ru/sosgps/wayrecall/
    └── wialonparser/                          # Wialon парсер (в отдельном core модуле!)
        ├── WialonParser.java                 # Бинарный парсер (153 строк)
        ├── WialonPackage.java                # Модель пакета
        ├── WialonPackageBlock.java           # Блок пакета
        ├── WialonCoordinatesBlock.java       # Блок координат
        ├── WialonPackager.scala              # Упаковщик (для ретрансляции)
        └── WialonRetranslatorEmulator.java   # Эмулятор
```

---

## Примечания

1. **Netty 3 vs Netty 4:** Legacy использует ОБОИХ. Teltonika/Wialon/Ruptela/GoSafe — Netty 3 (`org.jboss.netty`). Остальные — Netty 4 (`io.netty`). Новый CM использует только Netty 4.

2. **Inline parsers:** Протоколы #10-18 не имеют отдельных парсеров — вся логика внутри Netty handler'ов. При миграции нужно извлечь парсинг в чистые функции.

3. **Команды на трекер:** Поддерживают: NavTelecom (NavtelecomCommand), DTM (IOSwitch), Ruptela (конфигурация). В остальных — только приём данных.

4. **SkyPatrol — UDP!** Это единственный UDP протокол. Требует `NioDatagramChannel`, не может использовать текущий TCP pipeline.

5. **Zudo — HTTP!** Использует HTTP POST с multipart-формой. Не может использовать текущий TCP pipeline.

6. **MicroMayak — самый сложный.** 344 строки async state machine, использует FlexParser от NavTelecom для парсинга тела, LBS-поддержка. Потребует значительных усилий.

7. **EGTS — только прокси.** Не парсит GPS данные сам, проксирует на внешний сервер с подменой IMEI. Сомнительная ценность для нового CM.

8. **BsonGPS — внутренний.** Использовался для передачи данных между инстансами. В новой архитектуре заменён Kafka.
