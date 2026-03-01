> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-01` | Версия: `1.0`

# Анализ legacy протоколов GPS-трекеров для реимплементации в Scala 3 + ZIO

Исходный код: `legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/`

---

## Содержание

1. [GalileoskyServer — Galileosky tag-based binary](#1-galileoskyserver)
2. [GL06Server — Concox/GT06 binary](#2-gl06server)
3. [TK102Server — TK102 text](#3-tk102server)
4. [TK103Server — TK103 text](#4-tk103server)
5. [ArnaviServer — Arnavi CSV/text](#5-arnaviserver)
6. [ADM1_07Server — ADM binary](#6-adm1_07server)
7. [GTLT3MT1Server — GTLT text/CSV](#7-gtlt3mt1server)
8. [MicroMayakServer — MicroMayak binary](#8-micromayakserver)
9. [Сводная таблица портов](#9-сводная-таблица-портов)
10. [Общие утилиты](#10-общие-утилиты)

---

## 1. GalileoskyServer

**Класс:** `GalileoskyServer.scala`  
**TCP порт:** `9097` (default из Spring XML: `${packreceiver.galileosky.port:9097}`)  
**Byte order:** `LITTLE_ENDIAN`

### Frame Detection (GalileoskyMessageDecoder)

```
Протокол: Tag-based бинарный
Минимальный размер кадра: 3 байта
Структура:
  [header: 1 byte]
  [size: 2 bytes, LITTLE_ENDIAN, маска 0x7FFF] — размер payload
  [payload: size bytes]
  [checksum: 2 bytes]

Полный размер кадра = (size & 0x7FFF) + 5 (1 header + 2 size + 2 checksum)
```

### IMEI Parsing

```
Tag 0x03: IMEI — 15 байт ASCII строка
Парсится через readBytesAsString(15)
IMEI хранится в var info: Option[String] — устанавливается один раз при первом пакете с tag 0x03
```

### Data Parsing Logic

Пакет содержит произвольную последовательность тегов. Каждая GPS-точка начинается с тега `0x20` (datetime) — при появлении нового `0x20` предыдущая точка сохраняется.

```
ОБЯЗАТЕЛЬНЫЕ для GPS-точки:
  Tag 0x20: datetime — readUnsignedInt() * 1000 → unix timestamp в ms (Date)
  Tag 0x30: coordinates (9 bytes total)
    - firstByte: 1 byte
      - correctness = (firstByte & 0xF0) >> 4
      - sat = (firstByte & 0x0F)
      - Если correctness == 0 или 2:
        - lat = readInt() / 1_000_000 (float, знаковый)
        - lon = readInt() / 1_000_000 (float, знаковый)
        - Если sat == 0: lat=NaN, lon=NaN
      - Иначе: skip 8 bytes, lat=NaN, lon=NaN
  Tag 0x33: speed & direction (4 bytes)
    - speed = readUnsignedShort() * 0.1 (rounded)
    - direction = readUnsignedShort() * 0.1 (rounded)

ДОПОЛНИТЕЛЬНЫЕ теги:
  0x01: Device type — skip 1
  0x02: Firmware — skip 1
  0x04: Device num — skip 2
  0x05: Unknown — skip 1
  0x10: Archive num — skip 2
  0x34: height — readShort()
  0x35: HDOP — skip 1
  0x40: status — readShort() → binary string, ignition = bit(9)
  0x41: power — readUnsignedShort()
  0x42: acc (battery) — readUnsignedShort()
  0x43: temperature — readByte()
  0x44: acceleration (4 bytes) — x,y,z по 10 бит:
    x = acc4 & 0x3FF
    y = (acc4 & 0xFFC00) >> 10
    z = (acc4 & 0x3FF00000) >> 20
    acceleration = sqrt(x² + y² + z²)
  0x45: outputs — readUnsignedShort() → binary string
  0x46: inputs — readUnsignedShort() → binary string
  0x47: EcoDrive — 4 * readUnsignedByte() / 100.0
  0x48: Extended terminal status — skip 2
  0x50–0x57: Analog inputs in0–in7 — readUnsignedShort()
  0x58–0x59: RS232 — skip 2
  0x60–0x62: Fuel sensors — readUnsignedShort()
  0x63–0x6F: Fuel sensors (3 byte) — readMedium()
  0x70–0x77: Temperature sensors — readShort()
  0x80–0x87: DS1923 — readMedium()
  0x88–0xAF: RS232 — readByte()
  0x90: iButton — skip 4
  0xB0–0xB9: unknown — skip 2
  0xC0–0xC3: CAN 32-bit — readInt()
  0xC4–0xD2: CAN 8-bit — readByte()
  0xD3: iButton 2 — skip 4
  0xD4: Total mileage — skip 4
  0xD5: iButton state — skip 1
  0xD6–0xDA: CAN 16-bit — readShort()
  0xDB–0xDF: CAN 32-bit — readInt()
  0xE2–0xE9: User data — readInt()
  0xF0–0xF9: unknown — skip 4
```

### ACK Format

```
3 байта, LITTLE_ENDIAN:
  [0x02] [checksum: 2 bytes LE]

checksum = последние 2 байта оригинального пакета (readShort() после payload)
```

### Key Constants

```scala
header byte: первый байт пакета (не проверяется явно)
LITTLE_ENDIAN ordering
Tag-based парсинг, цикл while (msg.readableBytes() > 2)
```

---

## 2. GL06Server

**Класс:** `GL06Server.scala` (Concox/GT06 protocol)  
**TCP порт:** `9094` (default из Spring XML: `${packreceiver.gl06Server.port:9094}`)  
**Byte order:** `BIG_ENDIAN` (default)

### Frame Detection (GL06MessageDecoder)

```
Start bytes: 0x78 0x78 (2 bytes)
Length field: 1 byte (unsigned) — длина payload
Stop bytes: 0x0D 0x0A (2 bytes)

Минимальный кадр: 5 bytes (2 start + 1 length + 2 stop)
Полный кадр: 2 + 1 + length + 2 = length + 5

Декодер читает:
  require(byte0 == 0x78)
  require(byte1 == 0x78)
  length = readUnsignedByte()
  payload = readSlice(length)
  require(stop0 == 0x0D)
  require(stop1 == 0x0A)
```

### IMEI Parsing

```
Protocol 0x01 (Login packet):
  IMEI = 8 bytes → hex string (Utils.toHexString без разделителя) → dropWhile('0')
  Пример: [00 00 35 28 12 34 56 78] → "0000352812345678" → "352812345678"
```

### Data Parsing Logic

```
Protocol byte (первый байт payload) определяет тип:

0x01 — Login:
  imei = readBytesToArray(8) → hex → dropWhile('0')
  ACK: response(0x01, 0x01)

0x12 — Location Data:
  year = readUnsignedByte() + 2000
  month = readUnsignedByte()
  day = readUnsignedByte()
  hour = readUnsignedByte()
  minute = readUnsignedByte()
  second = readUnsignedByte()
  satellites = readUnsignedByte()
  lat = readUnsignedInt() / 30000.0 / 60.0
  lon = readUnsignedInt() / 30000.0 / 60.0
  speed = readUnsignedByte()
  course = readUnsignedShort() & 0x03FF  (10 бит)
  LBS data:
    MCC = readUnsignedShort()
    MNC = readUnsignedByte()
    LAC = readUnsignedShort()
    CID = readUnsignedMedium()  (3 bytes)
  serial = readShort()

0x13 — Status:
  skip 5 bytes (status info)
  serial = readShort()
  ACK: response(0x13, serial)
```

### ACK Format

```
Функция response(protocol, serial):

body (4 bytes):
  [0x05]           — length
  [protocol: 1]    — protocol number
  [serial: 2]      — serial number

checksum = CRC16_X25 от body.nioBuffer()

Полный ответ (10 bytes):
  [0x78] [0x78]    — start
  [body: 4 bytes]  — body (0x05, protocol, serial_hi, serial_lo)
  [checksum: 2]    — CRC16(X25)
  [0x0D] [0x0A]    — stop

Зависимость: org.traccar.helper.Checksum.crc16(CRC16_X25, ...)
```

### Key Constants

```
Start: 0x78 0x78
Stop: 0x0D 0x0A
Login protocol: 0x01
Location protocol: 0x12
Status protocol: 0x13
CRC: CRC16_X25
```

---

## 3. TK102Server

**Класс:** `TK102Server.scala`  
**TCP порт:** `9092` (default из Spring XML: `${packreceiver.tk102Server.port:9092}`)  
**Протокол:** Текстовый

### Frame Detection (TK102MessageDecoder)

```
Start marker: 0x28 '('
End marker: 0x29 ')'

Декодер ищет ')' в буфере (findByteInReadable) и вырезает кадр включительно.
Минимальный размер: > 0 bytes
```

### IMEI Parsing

```
Формат пакета: (SSSSSSSSSSSSCCCCBODY)
  Offset 0: '(' — skip 1
  serial = readBytesAsString(12)  — 12 символов серийного номера
  command = readBytesAsString(4)  — 4-символьный код команды

IMEI = "3528" + serial.dropWhile('0')
  Пример: serial="000123456789" → IMEI="3528123456789"
```

### Data Parsing Logic

```
Команды:

"BP00" — Handshake/login:
  ACK: "(" + serial + "AP01" + "HSO" + ")"

"BP05" — Heartbeat:
  ACK: "(" + serial + "AP05" + "HSO" + ")"

"BR00" — Location data:
  body содержит NMEA-подобные поля:
    date = 6 chars (yyMMdd) → LocalDate
    availability = 1 char (A/V)
    lat_str = 9 chars (DDMM.MMMM format)
      lat = degrees + minutes/60
    lat_letter = 1 char (N/S)
    lon_str = 10 chars (DDDMM.MMMM format)
      lon = degrees + minutes/60
    lon_letter = 1 char (E/W)
    speed = 5 chars → float (knots) → short
    time = 6 chars (HHmmss) → LocalTime
    direction = 6 chars → float → short

  Координаты:
    lat: первые 2 цифры = градусы, остальное = минуты/60
    lon: первые 3 цифры = градусы, остальное = минуты/60

  satellites: hardcoded 9
  ACK: "(" + serial + "AR03" + ")"
```

### ACK Format

```
Текстовый ASCII:
  Login: "({serial}AP01HSO)"
  Heartbeat: "({serial}AP05HSO)"
  Location: "({serial}AR03)"
```

### Key Constants

```
START_MARKER = 0x28 = '('
END_MARKER = 0x29 = ')'
IMEI prefix: "3528"
Date format: "yyMMdd"
Time format: "HHmmss"
Timezone: UTC
```

---

## 4. TK103Server

**Класс:** `TK103Server.scala`  
**TCP порт:** `9095` (default из Spring XML: `${packreceiver.tk103Server.port:9095}`)  
**Протокол:** Текстовый  
**Идентичен TK102**, за исключением protocol name = "TK103"

### Frame Detection

```
ИДЕНТИЧНО TK102: Start='(' End=')'
```

### IMEI/Data/ACK

```
ПОЛНОСТЬЮ ИДЕНТИЧЕН TK102.
serial → 12 chars, command → 4 chars
imei = "3528" + serial.dropWhile('0')

Команды те же: BP00, BP05, BR00
Формат координат тот же (NMEA degrees+minutes)
ACK тот же формат

Единственное отличие: gpsdata.data.put("protocol", "TK103")
```

> **Примечание для реализации:** TK102 и TK103 можно реализовать как один парсер с параметром protocol name.

---

## 5. ArnaviServer

**Класс:** `ArnaviServer.scala`  
**TCP порт:** `9091` (default из Spring XML: `${packreceiver.arnavi.port:9091}`)  
**Протокол:** CSV/Text

### Frame Detection

```
DelimiterBasedFrameDecoder:
  Max frame length: Short.MaxValue (32767)
  Delimiters: '\r\n' ИЛИ '\n' ИЛИ NULL byte (0x00)
  
Netty стандартный: Delimiters.lineDelimiter() ++ Delimiters.nulDelimiter()
```

### IMEI Parsing

```
Формат: $AV,{version},{trackerID},{serial},...
  trackerID = elems(2)
  serial = elems(3)
  
IMEI = trackerID + "-" + serial
```

### Data Parsing Logic

```
Сообщение делится по запятой: message.split(",").map(_.trim)
Первый элемент ОБЯЗАН быть "$AV"
Второй элемент — версия протокола: "V2" или "V3"

=== V2 (26 полей) ===
  [0]  "$AV"
  [1]  "V2"
  [2]  trackerID
  [3]  Serial
  [4]  VIN
  [5]  VBAT (напряжение батареи)
  [6]  FSDATA
  [7]  ISSTOP
  [8]  ISEGNITION
  [9]  D_STATE
  [10] FREQ1
  [11] COUNT1
  [12] FIX_TYPE
  [13] SAT_COUNT
  [14] TIME (HHmmss)
  [15] XCOORD (lon, NMEA: DDDMM.MMMM[E/N])
  [16] YCOORD (lat, NMEA: DDMM.MMMM[E/N])
  [17] SPEED
  [18] COURSE
  [19] DATE (ddMMyy)
  [20] checksum

=== V3 (26 полей) ===
  [0]  "$AV"
  [1]  "V3"
  [2]  trackerID
  [3]  Serial
  [4]  VIN
  [5]  VBAT
  [6]  FSDATA
  [7]  ISSTOP
  [8]  ISEGNITION
  [9]  D_STATE
  [10] FREQ1
  [11] COUNT1
  [12] FREQ2
  [13] COUNT2
  [14] FIX_TYPE
  [15] SAT_COUNT
  [16] TIME (HHmmss)
  [17] XCOORD (lon)
  [18] YCOORD (lat)
  [19] SPEED
  [20] COURSE
  [21] DATE (ddMMyy)
  [22] ADC1
  [23] COUNTER3
  [24] TS_TEMP
  [25] checksum

Координаты (coord функция):
  1. Убрать суффикс [E/N]: replaceAll("[EN]$", "")
  2. d = toDouble
  3. deg = d.toInt / 100  (целочисленное деление)
  4. min = d - deg * 100
  5. result = deg + min / 60

Date: "ddMMyy" + "HHmmss" → UTC
```

### ACK Format

```
Текст ASCII: "RCPTOK\r\n" (8 bytes фиксированных)
Отправляется при успехе для обеих версий V2 и V3.
При ошибке — ctx.close()
```

### Key Constants

```
Header: "$AV"
Versions: "V2", "V3"
Date format: "ddMMyy"
Time format: "HHmmss"
Timezone: UTC
ACK: "RCPTOK\r\n"
Frame delimiter: \r\n or \n or NUL
```

---

## 6. ADM1_07Server

**Класс:** `ADM1_07Server.scala`  
**TCP порт:** `9096` (default из Spring XML: `${packreceiver.adm1_07Server.port:9096}`)  
**Byte order:** `LITTLE_ENDIAN`

### Frame Detection (ADM1_07MessageDecoder)

```
Минимальный размер: 3 bytes
Size field: 3-й байт (index+2), unsigned byte
  → полный кадр = size байт (size включает всё)

Если readableBytes < size → ждём ещё данных
```

### IMEI Parsing

```
Заголовок каждого пакета:
  deviceId = readUnsignedShort() (2 bytes, LE)
  size = readUnsignedByte() (1 byte)
  typ = readByte() (1 byte)

typeBits = typ & 0x03

Если typeBits == 0x03 (IMEI-пакет):
  imei = readBytesAsString(15) — 15 ASCII символов
  hwType = readByte()
  replyEnabled = readByte()
  
Info сохраняется: Info(imei, hwType, replyEnabled)
```

### Data Parsing Logic

```
typeBits == 0x01 или 0x00 — пакет с данными:

  soft = readUnsignedByte()
  gpsPntr = readUnsignedShort()
  status = readUnsignedShort()
  lat = readFloat() (LE) — если 0.0 → NaN
  lon = readFloat() (LE) — если 0.0 → NaN
  course = readUnsignedShort() * 0.1 (rounded)
  speed = readUnsignedShort() * 0.1 (rounded)
  acc = readUnsignedByte()
  height = readUnsignedShort()
  hdop = readUnsignedByte()
  satellites = readUnsignedByte()
  seconds = readUnsignedInt() (LE) → Date(seconds * 1000)
  power = readUnsignedShort()
  battery = readUnsignedShort()

Опциональные данные на основе бит типа:
  bit(2): skip 4 — акселерометр, выходы, события
  bit(3): skip 12 — аналоговые входы
  bit(4): skip 8 — импульсные/дискретные входы
  bit(5): skip 9 — датчики уровня топлива и температуры

Координаты: IEEE 754 float, прямые градусы (НЕ NMEA формат!)
  lat/lon в float → toDouble
  (0.0f → Float.NaN)
Timestamp: unix seconds × 1000
```

### ACK Format

```
Отправляется ТОЛЬКО если info.replyEnabled == 0x02:

132 bytes total:
  [deviceId: 2 bytes]    — оригинальный deviceId
  [0x84: 1 byte]         — command code
  ["***1*": 5 bytes]     — ASCII
  [zeros: 124 bytes]     — writeZero(124)
```

### Key Constants

```
IMEI packet type: typeBits == 0x03
Data packet type: typeBits == 0x01 или 0x00
Reply enabled: replyEnabled == 0x02
ACK marker: 0x84
LITTLE_ENDIAN
Size field at offset 2 (3rd byte) covers entire packet
```

---

## 7. GTLT3MT1Server

**Класс:** `GTLT3MT1Server.scala`  
**TCP порт:** `9093` (default из Spring XML: `${packreceiver.gtlt3mt1.port:9093}`)  
**Протокол:** CSV/Text

### Frame Detection

```
DelimiterBasedFrameDecoder:
  Max frame length: Short.MaxValue (32767)
  Delimiter: '#' (0x23)
  
Единственный кастомный разделитель — символ '#'
```

### IMEI Parsing

```
Формат: serial,command,time,validity,lat,NS,lon,EW,speed,direction,date,status#
  serial = elems(1)

IMEI = serial (используется напрямую, без префикса)
```

### Data Parsing Logic

```
Сообщение делится по ',': message.split(",").map(_.trim)
Если message.isEmpty → return (пропуск пустых кадров после '#')

Индексы полей:
  [0]  — не используется (пустое, перед serial)
  [1]  serial (IMEI устройства)
  [2]  command
  [3]  time (HHmmss)
  [4]  validity (A=active, V=void)
  [5]  lat (DDMM.MMMM — NMEA формат)
  [6]  N/S
  [7]  lon (DDDMM.MMMM — NMEA формат)
  [8]  E/W
  [9]  speed
  [10] direction
  [11] date (ddMMyy)
  [12] status

Координаты NMEA:
  lat: первые 2 символа = градусы, остальное = минуты → deg + min/60
  lon: первые 3 символа = градусы, остальное = минуты → deg + min/60

Date: ddMMyy + HHmmss → UTC
satellites: hardcoded 0
```

### ACK Format

```
Текстовый ASCII: "{первые 4 элемента через ','}#"
  → elems.take(4).mkString(",") + "#"
  Пример: ",SERIAL,CMD,TIME#"

При ошибке — ctx.close()
```

### Key Constants

```
Frame delimiter: '#'
Date format: "ddMMyy"
Time format: "HHmmss"
Timezone: UTC
NMEA coordinate format
```

---

## 8. MicroMayakServer

**Класс:** `MicroMayakServer.scala`  
**TCP порт:** `9090` (default из Spring XML: `${packreceiver.micromayac.port:9090}`)  
**Byte order:** `BIG_ENDIAN` (по умолчанию), но GPS данные в `LITTLE_ENDIAN`  
**Протокол:** Бинарный, async/future-based

### Frame Detection

```
Кастомный протокол на основе маркеров:
  START_MARKER = 0x24 ('$')
  END_MARKER = 0x0D ('\r')

Формат пакета:
  [0x24]           — start marker
  [marker: 1 byte] — тип пакета
  [kvitok: 1 byte] — sequence number
  [body: N bytes]  — payload
  [CRC: 1 byte]    — checksum
  [0x0D]           — end marker

CRC: (~sum_of_all_bytes_in_body + 1) & 0xFF  (дополнение суммы до 0)
```

### IMEI Parsing (Authentication)

```
Packet type: AUTH_KEY = 0x02

Body: 8 bytes → readImei:
  Каждый байт → hex string "%02X" → concat → stripPrefix("0")
  Пример: [00 35 28 12 34 56 78 00] → "0035281234567800" → "35281234567800"

Ответ (AUTH_CONFIRMATION = 0x04):
  [0x24] [body] [CRC] [0x0D]
  body:
    [0x04]                — AUTH_CONFIRMATION
    [kvitok]              — echo sequence
    [timestamp: 4 bytes BE] — текущее время в секундах (unix)
    [0x00]                — COMPLETED_CORRECTLY
```

### Data Parsing Logic

```
После аутентификации — state machine с типами пакетов:

0x05 — Видимые соты (LBS):
  lbsArr = readByteBuf(11)
  numberOfBaseStations = readByte()
  baseStationsData = N × readByteBuf(9)
  → parseLBS → saveGPSbyLBS (конвертация через LBSConverter)

0x03 — Запрос стартовой точки по LBS:
  content = readByteBuf(10)
  → readLBS → saveGPSbyLBS

0x08 — Состояние блока:
  content = readByteBuf(14)
  → readUnsignedInt() × 1000 → Date (unix timestamp, LE)
  → обновляет state.time

0x09 — Сообщения из черного ящика (GPS):
  pointData = readByteBuf(14)
  additionalPoints = readByte()
  additionalPointsData = readByteBuf(additionalPoints × 5)
  → parseGPS()

0x0A — Состояние + упакованные координаты:
  firstBlock = readByteBuf(16)
  coordinates = readByteBuf(10)
  additionalPoints = readByte()
  additionalPointsData = readByteBuf(additionalPoints × 5)
  → просто ACK (не парсит координаты, только логирует error)

0x0C — Описание ПО:
  content = readByteBuf(5) → просто ACK

Events (0xE0–0xFE):
  date = readInt (BE) × 1000 → Date → просто ACK

=== parseGPS ===
Input: 14 bytes main + (additionalCount × 5) bytes additional, всё LITTLE_ENDIAN

Main point (14 bytes LE):
  date = readUnsignedInt() × 1000 → Date (unix timestamp)
  packed_long = readLong() (8 bytes):
    speed = long.ofShift(56, 8) = bits[63:56]
    lon = long.ofShift(28, 28) / 600000.0 = bits[55:28]
    lat = long.ofShift(0, 28) / 600000.0 = bits[27:0]
  dops = readUnsignedShort() (2 bytes):
    nglonass = dops.ofShift(12, 4)
    qGSM = dops.ofShift(8, 4)
    dop = dops.ofShift(4, 4)
    ngps = dops.ofShift(0, 4)
  satellites = nglonass + ngps

Additional points (каждый 5 bytes LE):
  timeShift = readByte()
  shifts = readInt():
    speed_delta = shifts.ofShift(24, 8)
    lon_delta = shifts.ofShift(12, 12) / 600000.0
    lat_delta = shifts.ofShift(0, 12) / 600000.0
  Дельты ПРИБАВЛЯЮТСЯ к предыдущей точке (iterate)
  course: всегда 0

=== readLBS ===
Input: 10 bytes, LITTLE_ENDIAN:
  mcc_mnc = readUnsignedMedium() (3 bytes):
    mnc = mcc_mnc.ofShift(12, 12)
    mcc = mcc_mnc.ofShift(0, 12)
  lac = readUnsignedShort()
  cid = readInt()
  → LBS(mcc, mnc, lac, cid)

Если MCC == 65535 → lon=NaN, lat=NaN (не конвертировать)
```

### ACK Format

```
Confirmation packet:
  [0x24]           — START_MARKER
  [body]           — varies
  [CRC: 1 byte]    — checksum of body
  [0x0D]           — END_MARKER

body для MonoConfirmation:
  [0x00]           — COMPLETED_CORRECTLY
  [kvitok << 2 | state & 0x03]  — packed kvitok + state
  [marker]         — original packet marker

body для auth:
  [0x04]           — AUTH_CONFIRMATION
  [kvitok]
  [timestamp: 4 BE]
  [0x00]

CRC = (~sum_bytes + 1) & 0xFF
```

### Key Constants

```scala
START_MARKER = 0x24 ('$')
END_MARKER = 0x0D ('\r')
AUTH_KEY = 0x02
AUTH_CONFIRMATION = 0x04
COMPLETED_CORRECTLY = 0x00
COMPLETED_INCORRECTLY = 0x01
Event codes: 0xE0..0xFE (включая 0xFA дважды — баг в оригинале)

ofShift(shift, bits): (value >> shift) & ((1 << bits) - 1)
```

---

## 9. Сводная таблица портов

| # | Протокол | Legacy класс | Legacy порт (default) | Тип | Frame Detection |
|---|---|---|---|---|---|
| 1 | Galileosky | `GalileoskyServer` | 9097 | Binary, LE | Size field (2 bytes LE, mask 0x7FFF) |
| 2 | Concox/GT06 | `GL06Server` | 9094 | Binary, BE | Start 0x7878, length byte, stop 0x0D0A |
| 3 | TK102 | `TK102Server` | 9092 | Text | Start '(' End ')' |
| 4 | TK103 | `TK103Server` | 9095 | Text | Start '(' End ')' |
| 5 | Arnavi | `ArnaviServer` | 9091 | CSV/Text | Line delimiter (\r\n, \n, NUL) |
| 6 | ADM 1.07 | `ADM1_07Server` | 9096 | Binary, LE | Size at offset 2 (1 byte) |
| 7 | GTLT3MT1 | `GTLT3MT1Server` | 9093 | CSV/Text | '#' delimiter |
| 8 | MicroMayak | `MicroMayakServer` | 9090 | Binary, mixed | Start 0x24 ('$'), end 0x0D, CRC |

### Уже реализованные протоколы (для справки)

| Протокол | Legacy класс | Legacy порт | Статус |
|---|---|---|---|
| Teltonika Codec 8/8E | `TeltonikaNettyServer.java` | 9088 | ✅ Реализован |
| Wialon IPS | `WialonNettyServer.java` | 9087 | ✅ Реализован |
| Ruptela | `RuptelaNettyServer.scala` | 9089 | ✅ Реализован |
| NavTelecom FLEX | `NavTelecomNettyServer.scala` | 9085 | ✅ Реализован |

### Прочие legacy протоколы (не запрошены)

| Протокол | Класс | Порт |
|---|---|---|
| GoSafe | `GosafeNettyServer` | 9086 |
| SkySim | `SkysimNettyServer` | 9084 |
| AutophoneMayak | `AutophoneMayakServer` | 9083 |
| DTM | `DTMServer` | 9082 |
| SkyPatrol | `SkyPatrolNettyServer` | ? |
| EgtsProxy | `EgtsProxyServer` | ? |
| Zudo | `ZudoServer` | ? |

---

## 10. Общие утилиты

### ByteBufOps (implicit class)

```scala
// Из ScalaNettyUtils.scala
readBytesAsString(length, charset = US_ASCII): String
readBytesToArray(length): Array[Byte]
findByteInReadable(byte): Int  // -1 если не найден
toHexString: String  // через Utils.toHexString(bytes, " ")
writeAndRelease(data: ByteBuf): ByteBuf
toIteratorReadable: Iterator[Byte]
```

### Bit Manipulation (implicit classes из package.scala)

```scala
// longBitReads
def ofShift(shift: Int, bits: Int): Long = (l >> shift) & ((1 << bits) - 1)

// intBitReads
def ofShift(shift: Int, bits: Int): Int = (l >> shift) & ((1 << bits) - 1)

// byteBitReads
def bit(i: Int): Boolean = (l & (1 << i)) > 0

// shortBitReads
def bit(i: Int): Boolean = (l & (1 << i)) > 0

// standalone
def bit(option: Boolean): Int = if (option) 1 else 0
```

### GPSData (Java class)

```java
public class GPSData {
    public String uid;           // null при приёме
    public String imei;          // идентификатор устройства
    public double lon, lat;      // координаты (NaN если нет)
    public Date time;            // timestamp
    public short speed;          // скорость
    public short course;         // курс/направление
    public byte satelliteNum;    // число спутников
    public Map<String, Object> data;  // доп. данные (protocol, ignition, power, etc.)
}
```

### Координатные системы

| Протокол | Формат координат | Пример преобразования |
|---|---|---|
| Galileosky | int / 1_000_000 (микроградусы) | `55123456 → 55.123456°` |
| GL06/Concox | uint / 30000 / 60 | `lat_raw / 30000.0 / 60.0` |
| TK102/TK103 | NMEA DDMM.MMMM | `5530.5000 → 55 + 30.5/60 = 55.508°` |
| Arnavi | NMEA DDDMM.MMMM + suffix E/N | strip suffix, deg=int/100, min=rest |
| ADM | IEEE 754 float (прямые градусы) | `55.123f → 55.123°` |
| GTLT3MT1 | NMEA DDMM.MMMM | same as TK102 |
| MicroMayak | packed bits / 600000.0 | `long.ofShift(0,28) / 600000.0` |

---

*Этот документ создан для целей реимплементации протоколов в Scala 3 + ZIO.*
