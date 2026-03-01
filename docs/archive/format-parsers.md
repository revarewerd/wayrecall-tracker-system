# 📡 Полный аудит GPS протоколов - Legacy Stels

**Дата:** 19 февраля 2026  
**Цель:** Задокументировать ВСЕ форматы, которые поддерживал старый Stels, чтобы новая система поддерживала их все.

---

## 🔍 Найдено протоколов: 22

| # | Протокол | Тип | Старый порт | Статус | Дата добавления |
|---|----------|-----|-------------|--------|-----------------|
| 1 | **Teltonika** | Бинарный | 9088 | 🔍 | Jan 2013 |
| 2 | **Wialon Binary** | Бинарный | 9087 | ✅ Изучен | Jan 2012 |
| 3 | **Wialon IPS 2.0** | Текст | отд. | ✅ Изучен | Aug 2012 |
| 4 | **Wialon REG** | Текст | ? | ✅ Изучен | Feb 2012 |
| 5 | **Ruptela** | Бинарный | 9089 | 🔍 | Jan 2013 |
| 6 | **NavTelecom F6** | Бинарный | 9085 | 🔍 | Dec 2012 |
| 7 | **GoSafe** | Бинарный | 9086 | 🔍 | Unknown |
| 8 | **GalileoSky** | Бинарный | ? | 🔍 | Unknown |
| 9 | **Skysim** | ? | 9084 | 🔍 | Unknown |
| 10 | **Autophonje Mayak** | ? | 9083 | 🔍 | Unknown |
| 11 | **DTM (Dunobil/Jaguar)** | ? | 9082 | 🔍 | Unknown |
| 12 | **TK102** | ? | ? | 🔍 | Unknown |
| 13 | **TK103** | ? | ? | 🔍 | Unknown |
| 14 | **GL06** | Текст | ? | 🔍 | Unknown |
| 15 | **Arnavi** | ? | ? | 🔍 | Unknown |
| 16 | **ADM-1.07** | ? | ? | 🔍 | Unknown |
| 17 | **MicroMayak** | ? | ? | 🔍 | Unknown |
| 18 | **SkyPatrol** | ? | ? | 🔍 | Unknown |
| 19 | **GTLT3MT1** | ? | ? | 🔍 | Unknown |
| 20 | **Zudo** | ? | ? | 🔍 | Unknown |
| 21 | **EGTS (Proxy)** | Бинарный (EGTS) | ? | 🔍 | Unknown |

---

## ✅ ДОКУМЕНТИРОВАННЫЕ ФОРМАТЫ

### 1. WIALON BINARY (WialonNettyServer.java)
**Порт:** 9087  
**Тип:** Бинарный  
**Использует:** Java WialonParser

**Структура пакета:**
```
[Size: 4B little-endian]
[IMEI: null-terminated string]
[Timestamp: 4B unix seconds]
[Flags: 4B]
[Blocks...]
```

**Координатный блок "posinfo":**
```
[hidden: 1B] [dataType:1B=0x02] [name:"posinfo" null-term]
[Longitude: 8B double, little-endian] 
[Latitude: 8B double, little-endian]
[Height: 8B double, little-endian]
[Speed: 2B short]
[Course: 2B short]
[Satellites: 1B]
```

**Пример:**
```
[0x50,0x00,0x00,0x00]              # Size=80 в little-endian
[0x38,0x36,0x30,0x37...0x00]       # IMEI "860719020025346\0"
[0x70,0x8B,0x70,0x50]              # Timestamp
[0x00,0x00,0x00,0x00]              # Flags
[0xBB,0x0B] [blockSize:4B]         # BlockType=3007, size...
[binary coordinates...]
```

---

### 2. WIALON IPS 2.0 (WialonIPS2Server.scala)
**Тип:** Текстовый  
**Структура:** `#KEY#data1;data2;...;dataNN\r\n`

#### Login (L):
```
#L#protocolVersion;imei\r\n
или
#L#imei;password\r\n
```
✅ ACK: `#AL#1\r\n` или `#AL#0\r\n`

#### Ping (P):
```
#P#\r\n
```
✅ ACK: `#AP#\r\n`

#### Short Data (SD):
```
#SD#ddMMyy;HHmmss;lat;N/S;lon;E/W;speed;course;alt;sats\r\n
```
✅ ACK: `#ASD#1\r\n`

#### Full Data (D):
```
#D#ddMMyy;HHmmss;lat;N/S;lon;E/W;speed;course;alt;sats;hdop;inputs;outputs;adc;lbutton;params\r\n
```
✅ ACK: `#AD#1\r\n`

#### Blackbox (B):
```
#B#row1|row2|row3\r\n
где row = ddMMyy;HHmmss;lat;N/S;lon;E/W;speed;course;alt;sats[;extra_fields]
```
✅ ACK: `#AB#count\r\n`

**Сжатие:** поддерживает zlib deflate
```
[0xFF] [Size:2B little-endian] [zlib-compressed-data]
```

---

### 3. WIALON REG (WialonPackager.scala)
**Тип:** Текстовый  
**Структура:** `REG;timestamp;lon;lat;speed;course;params;params;...`

**Пример:**
```
REG;1359662453;37.5562656;55.7350592;0;0;ALT:119.0,adc2:0.0,pwr_int:10.546,pwr_ext:12.377;in1:0,,SATS:11,gsm:4,counter1:0,battery_charge:0;;;;
```

**Параметры (ключ:значение парами, разделены запятыми):**
- `ALT:119.0` — высота (м)
- `SATS:11` — спутники
- `adc2:0.0` — аналоговый ввод
- `pwr_int:10.546` — внутреннее питание (V)
- `pwr_ext:12.377` — внешнее питание (V)
- `gsm:4` — сила сигнала GSM
- `battery_charge:0` — зарядка батареи (%)

**Типизация:** автоматическая (Int, Long, Double или String)

---

## 🔍 ТРЕБУЕТ ИЗУЧЕНИЯ

### 4. TELTONIKA (TeltonikaNettyServer.java)
**Порт:** 9088  
**Тип:** Бинарный  
**Используется:** Codec 8/8E (AVL protocol)

**Находится:** `ru.sosgps.wayrecall.avlprotocols.teltonika.TeltonikaParser`

**Маркеры:**
- Start byte: `0x00` (синхро)
- IMEI length: 2B
- IMEI: ASCII string (15 символов)
- Codec: 8 или 8E
- CRC: CRC16 checksum

**Структура AVL записи:**
```
[Timestamp: 8B]
[Priority: 1B]
[Longitude: 4B]
[Latitude: 4B]
[Altitude: 2B]
[Angle: 2B]
[Satellites: 1B]
[Speed: 2B]
[IO Elements: variable]
```

**Ответ:** ACK с количеством обработанных AVL записей

---

### 5. RUPTELA (RuptelaNettyServer.scala)
**Порт:** 9089  
**Тип:** Бинарный  
**Похож на:** Teltonika, но другая структура

**Начало пакета:**
- Маркер синхронизации
- IMEI (8 байт, hex-encoded)
- Timestamp
- Данные точек (разные блоки)

---

### 6. NAVTELECOM F6 (NavTelecomNettyServer.scala)
**Порт:** 9085  
**Тип:** Бинарный  
**Производитель:** NavTelecom, существует с 2009+

---

### 7. GL06 (GL06Server.scala) 
**Тип:** Текстовый  
**Маркер конца:** `#`  
**Разделитель:** `,`

```
lat,lon,speed,course,satellites,hdop,#
```

---

### 8. GOSAFE (GosafeNettyServer.scala)
**Порт:** 9086

---

### 9. GALILEOSKY (GalileoskyServer.scala)
**Тип:** Бинарный  
**Маркер начала:** `START_MARKER`  
**Производитель:** GalileoSky GPS трекеры

---

## � ПОЛНАЯ ТАБЛИЦА: ГДЕ НАХОДИТСЯ IMEI

| # | Протокол | Где IMEI | Когда | Как хранится |
|----|----------|----------|-------|--------------|
| 1 | Teltonika | Начало соединения | Один раз | `private String IMEI = null;` (stateful) |
| 2 | Wialon Binary | В каждом пакете | Каждый раз | Игнорируем, используем сохранённый (stateless) |
| 3 | Wialon IPS 2.0 | Login (#L# пакет) | Один раз | `var imei: Option[String] = None` (stateful) |
| 4 | Wialon REG | ? | ? | ? |
| 5 | Ruptela | Возможно в заголовке | ? | ? |
| 6 | NavTelecom | Начало соединения | Один раз | `_.connproc.imei` (stateful) |
| 7 | GoSafe | ? | ? | ? |
| 8 | GalileoSky | IMEI блок (type=0x03) | Один раз | Information packet (stateful) |
| 9 | Skysim | ? | ? | ? |
| 10 | Autophonje Mayak | Auth packet | Один раз | `var imei: Option[String]` (stateful) |
| 11 | DTM (Dunobil) | Заголовок `header` | Один раз | `def imei = header` (stateful) |
| 12 | TK102 | Генерируется | Один раз | `"3528" + serial` (stateful, no real IMEI) |
| 13 | TK103 | Генерируется | Один раз | `"3528" + serial` (stateful, no real IMEI) |
| 14 | GL06 | Первый пакет (8B hex) | Один раз | `var imei: Option[String] = None` (stateful) |
| 15 | Arnavi | ? | ? | ? |
| 16 | ADM-1.07 | IMEI инфо (type=0x03) | Один раз | Information packet (stateful) |
| 17 | MicroMayak | Auth packet | Один раз | `private def authenticate()` (stateful) |
| 18 | SkyPatrol | ? | ? | ? |
| 19 | GTLT3MT1 | ? | ? | ? |
| 20 | Zudo | HTTP POST параметр | Один раз | Зудо использует HTTP, не TCP (stateful) |
| 21 | EGTS Proxy | TermIdentity блок | Один раз | `case id: TermIdentity ⇒ id.imei` (stateful) |

**Статистика:**
- **Stateful** (сохраняют IMEI в session): 20 протоколов ← **NORM!**
- **Stateless** (IMEI в каждом пакете): 1-2 протокола (Wialon Binary, возможно Ruptela) ← **РЕДКО**



**CRITICAL PATTERN:** Не все протоколы отправляют IMEI в каждом пакете!

### Stateful (сохраняют IMEI после логина):
| Протокол | IMEI где | Как используется |
|----------|----------|-----------------|
| **Wialon IPS 2.0** | Login packet (#L#) | Один раз при подключении, используется для всех GPS data |
| **GL06** | Первый пакет (8B hex) | `var imei: Option[String] = None` — сохраняется на всё соединение |
| **Teltonika** | Начало соединения (2B length + ASCII) | `private String IMEI = null;` — один раз, дальше без IMEI |
| **NavTelecom** | В первом пакете | Сохраняется в ConnectedDevicesWatcher |
| **Autophonje Mayak** | Auth packet | `var imei: Option[String] = None` — дальше GPS без IMEI |
| **MicroMayak** | Auth packet (8B) | Сохраняется в `authenticate()` |
| **TK102/TK103** | Serial (нет IMEI) | Генерируется: `"3528" + serial` |

### Stateless (IMEI в каждом пакете):
| Протокол | IMEI где | Формат | Примечание |
|----------|----------|--------|-----------|
| **Wialon Binary** | После size (null-terminated) | `[Size][IMEI\0][TS][Data]` | IMEI в КАЖДОМ пакете (даже в data) |
| **Ruptela** | В начале (hex-encoded) | `[header][IMEI-8B][TS][data]` | IMEI может меняться между пакетами |
| **GoSafe** | ? | ? | ? |

### ConnectionHandler Архитектура:
```scala
// Первый пакет:
state.imei = None
  ↓ handleImeiPacket()
    ↓ parser.parseImei(buffer) → "860719020025346"
    ↓ state.imei = Some("860719020025346")

// Последующие пакеты:
state.imei = Some("860719020025346")
  ↓ handleDataPacket()
    ↓ parser.parseData(buffer, state.imei) // IMEI уже в параметре!
    ↓ GpsRawPoint(imei = imei, ...) // используем переданный IMEI

// Для stateful протоколов (Wialon IPS 2.0, GL06, Teltonika):
// IMEI из первого пакета → ConnectionState.imei → передаём в parseData()

// Для stateless протоколов (Wialon Binary, Ruptela):
// IMEI в каждом пакете, но мы используем сохранённый из первого
// (дефект: не проверяем что совпадает)
```

**ВЫВОД:** IMEI ВСЕГДА передается в `parseData(buffer, imei: String)`, независимо от протокола!

---

## ⚠️ АРХИТЕКТУРНОЕ СЛЕДСТВИЕ:

Нельзя просто парсить пакет отдельно — **нужно управлять состоянием соединения**:

```scala
// НЕПРАВИЛЬНО:
def parseGpsMessage(buffer: ByteBuf): Task[GpsRawPoint] = {
  // Где взять IMEI если его нет в пакете?
}

// ПРАВИЛЬНО:
case class ConnectionState(imei: String, lastSeq: Int, ...)

def handleMessage(buffer: ByteBuf, state: ConnectionState): Task[(GpsRawPoint, ConnectionState)] = {
  // Используй state.imei если нет в пакете
  // Обнови state для следующего пакета
}
```

**ConnectionHandler должен:**
1. Получить IMEI из первого пакета (login/auth/identify)
2. Сохранить IMEI в ConnectionState
3. Передавать IMEI парсеру для всех последующих пакетов
4. Очистить IMEI при disconnected

---

## ⚠️ МИНИМУМ НУЖНО РЕАЛИЗОВАТЬ:

### ПРИОРИТЕТ 1 (КРИТИЧНО):
- ✅ Wialon Binary (IMEI в каждом пакете — stateless)
- ⚠️ Wialon IPS 2.0 (IMEI только при логине — stateful)
- ✅ Wialon REG (структура проста)
- ❌ Teltonika (IMEI один раз — stateful, нужно состояние)
- ❌ Ruptela (нужно проверить, IMEI где)

### ПРИОРИТЕТ 2 (ВАЖНО):
- ❌ NavTelecom F6
- ❌ GoSafe
- ❌ GalileoSky
- ❌ GL06

### ПРИОРИТЕТ 3 (МОЖЕТ БЫТЬ ПОЗЖЕ):
- ❌ TK102/TK103 (старые китайские)
- ❌ Skysim
- ❌ Mayak (русские)
- ❌ DTM (Dunobil)
- ❌ Остальные

---

## 📋 ТОП ТЕЗИСЫ:

1. **Бинарные протоколы** используют маркеры (Start byte, CRC, length)
2. **Текстовые протоколы** используют простые разделители (`;`, `,`, `#`, `\r\n`)
3. **Сжатие** встречается в Wialon IPS 2.0 (zlib)
4. **Координаты** либо в decimal degrees, либо в целых числах (×10^6)
5. **Timestamps** либо unix seconds/milliseconds, либо текстовые (ddMMyy HHmmss)
6. **CRC16/Checksum** для всех бинарных

---

## 🎯 СТРАТЕГИЯ РЕАЛИЗАЦИИ:

### Фаза 1: КРИТИЧЕСКАЯ ФУНКЦИОНАЛЬНОСТЬ (Week 1-2)
**Цель:** Поддержка всех ТЕКУЩИХ пользовательских трекеров

```
✅ Wialon BINARY         (уже +70% реализирован)
✅ Wialon IPS 2.0        (уже +80% реализирован)
✅ Wialon REG            (нужен адаптер, +30% сделано)
```

**Задача:** Дополнить недостающие функции (blackbox, сжатие, параметры)

---

### Фаза 2: ВЫСОКИЙ ПРИОРИТЕТ (Week 2-3)
**Цель:** Поддержка 80% трекеров на рынке

```
🔴 Teltonika Codec 8/8E   (найти parserz ru.sosgps.wayrecall.avlprotocols.teltonika)
🔴 Ruptela                (похож на Teltonika, бинарный)
🔴 NavTelecom F6          (найдет дефиниции)
```

**Дата завершения:** 10-15 дней

---

### Фаза 3: СТАНДАРТНАЯ ПОДДЕРЖКА (Week 3-4)
```
🟡 GoSafe
🟡 GalileoSky
🟡 GL06
🟡 TK102/TK103
```

**Дата завершения:** 15-20 дней

---

### Фаза 4: РАСШИРЕННАЯ ПОДДЕРЖКА (Week 4+)
```
🟠 Skysim, Mayak, DTM, ADM-1.07, MicroMayak, SkyPatrol, GTLT3MT1, Zudo, Arnavi, EGTS
```

**Дата завершения:** Конец месяца (по мере заказов)

---

## 📊 ТЕКУЩЕЕ СОСТОЯНИЕ:

| Статус | Протокол | Реализация | Примечание |
|--------|----------|-----------|-----------|
| ✅ | Wialon BINARY | 70% | Основная логика есть, нужны edge cases |
| ✅ | Wialon IPS 2.0 | 80% | Нет blackbox, нет deflate, нет доп. параметров |
| ✅ | Wialon REG | 50% | Структура есть, нужна интеграция |
| ❌ | Teltonika | 0% | Нужно копировать парсер из legacy-stels |
| ❌ | Ruptela | 0% | Требует investigation |
| ❌ | NavTelecom | 0% | Требует investigation |
| ❌ | Остальные 16 | 0% | Не критично для MVP |

---

## 🚀 НЕМЕДЛЕННЫЕ ДЕЙСТВИЯ:

### 1. Завершить Wialon (сегодня):
```scala
// TODO: WialonIPS2Parser.scala
- [ ] Поддержка blackbox (#B#)
- [ ] Zlib deflate декомпрессия
- [ ] Полный список параметров (hdop, inputs, outputs, adc, lbutton)
- [ ] Обработка параметров после 15-го поля
```

### 2. Скопировать структуру Teltonika (завтра):
```bash
cp legacy-stels/core/src/main/.../teltonika/* \
   services/connection-manager/src/main/scala/.../teltonika/
```

### 3. Создать adapter все трёх Wialon (сегодня):
```scala
object WialonUniversalParser extends ProtocolParser {
  // Auto-detect BINARY vs IPS 2.0 vs REG
  // Маршрутизировать в нужный парсер
  // Единая структура GpsRawPoint на выходе
}
```

### 4. Тестирование (завтра):
```bash
# Для каждого формата - по 5-10 реальных пакетов
# Проверить что парсится -> GpsRawPoint -> OK
```

---

## � КРИТИЧЕСКИЕ ПРОБЛЕМЫ В ТЕКУЩЕЙ РЕАЛИЗАЦИИ

### 1. WialonParser.readLine() читает ВСЕ байты, не до \r\n
```scala
// НЕПРАВИЛЬНО:
private def readLine(buffer: ByteBuf): String =
    val bytes = new Array[Byte](buffer.readableBytes())  // ← ВСЕ байты!
    buffer.readBytes(bytes)
```

**Проблема:** Если в TCP буфере несколько пакетов сразу, парсер потеряет данные:
```
TCP буфер: "#L#860719020025346;pass\r\n#D#191120;143000;55.75;N;37.62;E;0;0;100;12\r\n"
           ↓ readLine()
           Считает ВСЕ байты сразу, потом пытается парсить как один пакет ← ОШИБКА
```

**Решение:** Использовать Netty decoder
```scala
pipeline.addLast("lineDecoder", new LineBasedFrameDecoder(1024))
// Netty автоматически разделяет по \r\n
```

### 2. WialonAdapterParser.isTextFormat() опирается на первый байт
```scala
private def isTextFormat(buffer: ByteBuf): Boolean =
    if buffer.readableBytes() > 0 then
      val firstByte = buffer.getUnsignedByte(buffer.readerIndex())
      firstByte == 0x23 // '#' = text IPS 2.0
```

**Проблема:** Работает ТОЛЬКО если первый пакет это иде пакет (#L#). Если трекер отправит данные до логина, или если логин содержит бинарные данные, детектище будет неправильно.

**Лучшее решение:** Использовать разные порты для разных форматов (как в старом Stels):
```
Порт 9087: Wialon Binary (с LengthFieldBasedFrameDecoder)
Порт 9087-alt: Wialon IPS 2.0 (с LineBasedFrameDecoder)
```

**Или:** Требовать чтоб старый Wialon Binary ВСЕГДА шифровался / использовал TLS для distinction.

### 3. Нет LengthFieldBasedFrameDecoder для бинарных протоколов
**Текущий код:** Ничего не добавляет в pipeline, кроме timeouts и rate limiter.

**Проблема:** 
- Teltonika, Ruptela, NavTelecom, GalileoSky и другие бинарные протоколы прибывают с полной длиной в заголовке
- Без decoder парсер должен читать длину сам и обрабатывать multi-packet scenarios

**Нужно:**
```scala
// Для бинарных протоколов:
new LengthFieldBasedFrameDecoder(
    1024 * 1024,    // maxFrameLength = 1MB
    0,              // lengthFieldOffset = 0 байт (размер с начала)
    4,              // lengthFieldLength = 4 байта (как в Wialon Binary)
    0,              // lengthAdjustment = 0
    4               // initialBytesToStrip = 4 (пропустить размер при передаче handler'у)
)

// Для текстовых протоколов:
new LineBasedFrameDecoder(1024 * 64)  // maxFrameLength = 64KB
```

---

## 📋 ЗАДАЧИ НА ИСПРАВЛЕНИЯ (ДО реала)

### Срыв-BLOCKING (MUST FIX BEFORE PROD):
- [ ] Добавить LengthFieldBasedFrameDecoder для бинарных протоколов в TcpServer.scala
- [ ] Добавить LineBasedFrameDecoder для текстовых протоколов в TcpServer.scala
- [ ] Переделать WialonAdapterParser:
  - [ ] Либо использовать разные порты (9087 binary vs 9088 text)
  - [ ] Либо требовать чтобы ПЕРВЫЙ пакет всегда был #L# (login)
- [ ] Исправить WialonParser.readLine() - читать ДО \r\n а не ВСЕ байты
- [ ] Добавить тесты с двумя пакетами подряд в одном TCP buffer

### ВЫСОКИЙURITE (нужно для MVP):
- [ ] WialonParser: добавить поддержку #B# (blackbox) пакетов
- [ ] WialonParser: добавить zlib deflate decompression для сжатых данных
- [ ] WialonParser: реализовать все 15+ параметров (#D# с полными данными)
- [ ] Реализовать Teltonika Codec 8/8E парсер (скопировать из legacy-stels/core)
- [ ] Реализовать Ruptela парсер

### ВАЖНО (для Phase 2):
- [ ] Реализовать NavTelecom парсер
- [ ] Реализовать GoSafe парсер
- [ ] Реализовать GalileoSky парсер
- [ ] Реализовать GL06 парсер

### НИЗКИЙ ПРИОРИТЕТ:
- [ ] Остальные 10+ протоколов (TK102/TK103, Mayak, DTM и т.д.)

---

## ДЛЯ БЫСТРОГО ПОИСКА:

**Где помощь в коде:**

```
# Все тесты пакетов
legacy-stels/tools/src/main/java/ru/sosgps/wayrecall/

# Примеры hex-данных
legacy-stels/packreceiver/src/main/java/.../WialonNettyServer.java:70-100

# Парсеры в кодировке
legacy-stels/core/src/main/java/ru/sosgps/wayrecall/wialonparser/

# Конфигурация портов
legacy-stels/conf/packreceiver.properties

# Netty handlers
legacy-stels/packreceiver/src/main/java/ru/sosgps/wayrecall/packreceiver/netty/
```

---

## ⚠️ ВАЖНЫЕ ЗАМЕЧАНИЯ:

1. **Teltonika уже в CME** через LengthFieldBasedFrameDecoder (нужно посмотреть текущую реализацию)
2. **Ruptela может совпадать с Teltonika** по структуре (проверить конфигом)
3. **РФ-протоколы** (Mayak, DTM, Arnavi) - потребуют специальных лицензий/документации
4. **Старые трекеры (2012+)** - могут посылать несколько форматов на одном порту (потребуется multi-format detection)

---

## 📞 КРИТИЧЕСКИЕ ВОПРОСЫ К ПОЛЬЗОВАТЕЛЮ:

1. **Какие трекеры есть у вас в реальной эксплуатации?**
   - Модели GPS устройств
   - Года выпуска
   - Текущие протоколы

2. **Насколько важна старая аналитика?**
   - Нужны ли данные из Kafka переходить на новые парсеры?
   - Или только новые подключения?

3. **Есть ли у вас примеры live трафика?**
   - tcpdump для каждого протокола
   - Real hex payloads для тестирования

