# 📊 Сравнительный анализ: GitHub-репозитории vs Монорепо

**Дата анализа:** 17 февраля 2026  
**Цель:** Найти потерянный код, выявить улучшения, зафиксировать изменения логики  

## Источники

| Сервис | GitHub | Монорепо |
|--------|--------|----------|
| Connection Manager | `dimasjanee11/connection-manager` | `services/connection-manager/` |
| Device Manager | `dimasjanee11/device-manager` | `services/device-manager/` |
| History Writer | `dimasjanee11/history-writer` | `services/history-writer/` |
| Web Frontend | `dimasjanee11/web-frontend` | `services/web-frontend/` |
| Web Billing | `dimasjanee11/web-billing` | `services/web-billing/` |

## Общий вердикт

| Сервис | Статус | Суть |
|--------|--------|------|
| **CM** | ⚠️ Потери + Улучшения | 6 стабов протоколов потеряно, но добавлено 5+ новых файлов |
| **DM** | ✅ Идентичен | Только фиксы деплоя |
| **HW** | 🔄 Архитектурная замена | ClickHouse → TimescaleDB (осознанное решение) |
| **Web Frontend** | ✅ Идентичен + Docker | Добавлены Dockerfile + nginx.conf |
| **Web Billing** | ✅ Идентичен + Docker | Добавлены Dockerfile + nginx.conf |

## Оглавление

1. [Connection Manager](#1-connection-manager)
2. [Device Manager](#2-device-manager)
3. [History Writer](#3-history-writer)
4. [Web Frontend](#4-web-frontend)
5. [Web Billing](#5-web-billing)
6. [Итоги и рекомендации](#6-итоги-и-рекомендации)
7. [Гайд по проверке тест-стенда](#7-гайд-по-проверке-тест-стенда)

---

## 1. Connection Manager

**Статус: ⚠️ Есть потери И улучшения**

### 1.1 Потерянные файлы (6 стабов протоколов)

В GitHub-репозитории было **10 протоколов** (4 рабочих + 6 стабов). В монорепо осталось **только 4 рабочих**:

| Файл | GitHub | Монорепо | Статус |
|------|--------|----------|--------|
| `TeltonikaParser.scala` | ✅ | ✅ | OK — MVP |
| `WialonParser.scala` | ✅ | ✅ | OK — MVP |
| `RuptelaParser.scala` | ✅ | ✅ | OK — MVP |
| `NavTelecomParser.scala` | ✅ | ✅ | OK — MVP |
| `EGTSParser.scala` | ✅ | ❌ | **ПОТЕРЯН** (стаб ~30 строк) |
| `GoSafeParser.scala` | ✅ | ❌ | **ПОТЕРЯН** (стаб ~30 строк) |
| `AutophonemayakParser.scala` | ✅ | ❌ | **ПОТЕРЯН** (стаб ~30 строк) |
| `DTMParser.scala` | ✅ | ❌ | **ПОТЕРЯН** (стаб ~30 строк) |
| `SkySimParser.scala` | ✅ | ❌ | **ПОТЕРЯН** (стаб ~30 строк) |
| `ZudoParser.scala` | ✅ | ❌ | **ПОТЕРЯН** (стаб ~30 строк) |

### 1.2 Баг в Protocol enum

- **GitHub** Protocol enum: `Teltonika, Wialon, Ruptela, NavTelecom, EGTS, GoSafe, Autophonemayak, DTM, SkySim, Zudo` (10 значений)
- **Монорепо** Protocol enum: `Teltonika, Wialon, NavTelecom` (только **3** значения!)
- **Баг:** `Ruptela` отсутствует в enum, хотя парсер `RuptelaParser.scala` есть

### 1.3 Потерянная документация

- `docs/RESILIENCE_AUDIT.md` — документ о устойчивости CM, есть в GitHub, нет в монорепо

### 1.4 Новые файлы в монорепо (улучшения)

Эти файлы добавлены при разработке в монорепо, их **нет** в GitHub:

| Файл | Строк | Назначение |
|------|-------|------------|
| `DynamicConfigService.scala` | ~120 | Динамическая конфигурация через Redis |
| `DeviceConfigListener.scala` | ~80 | Слушатель изменений конфигурации устройств |
| `CommandHandler.scala` | ~150 | Обработка команд из Kafka для устройств |
| `DeviceEventConsumer.scala` | ~100 | Потребитель событий устройств из Kafka |
| `VehicleLookupService.scala` | ~90 | Поиск информации о транспортных средствах |
| `ParseError.scala` | 206 | Типизированная ADT ошибок парсинга |
| `Vehicle.scala` | ~40 | Модель VehicleInfo |

### 1.5 Расширенная логика

**ConnectionHandler.scala:**
- GitHub: ~570 строк
- Монорепо: **854 строки** (+50%)
- Добавлено: unified Redis HASH паттерн (DeviceData), расширенная валидация, обработка команд

**KafkaProducer — топики:**
- GitHub: 4 топика (`gps-events`, `device-status`, `unknown-devices`, `unknown-gps-events`)
- Монорепо: **7 топиков** (+3: `gps-events-rules`, `gps-events-retranslation`, `device-events`)

**GpsPoint.scala:**
- GitHub: базовый case class GpsPoint
- Монорепо: **447 строк** — добавлены `DeviceData`, `GpsEventMessage`, `DeviceEvent`, `UnknownGpsPoint`

### 1.6 Тесты

GitHub и монорепо: **6 тестов** — одинаковые (`TeltonikaParserSpec`, `WialonParserSpec`, etc.)

---

## 2. Device Manager

**Статус: ✅ Практически идентичен**

### 2.1 Структура файлов

14 Scala-файлов + 1 тест — **полное совпадение** между GitHub и монорепо (2869 строк).

| Пакет | Файлы | Совпадение |
|-------|-------|------------|
| `api/` | DeviceRoutes (10 эндпоинтов), HealthRoutes | ✅ |
| `service/` | DeviceService (487 строк) | ✅ |
| `repository/` | DeviceRepository (417 строк, Doobie SQL) | ✅ |
| `consumer/` | UnknownDeviceConsumer | ✅ |
| `publisher/` | KafkaPublisher | ✅ |
| `infrastructure/` | RedisSyncService, TransactorLayer | ✅ |
| `config/` | AppConfig | ✅* |
| `domain/` | Entities, Errors, Events | ✅ |
| `Main.scala` | Точка входа | ✅* |

### 2.2 Отличия (только фиксы деплоя)

Все отличия — результат отладки при деплое на тест-стенд (192.168.1.5):

1. **AppConfig.scala** — добавлен `TypesafeConfigProvider.fromResourcePath().kebabCase` (фикс загрузки конфига ZIO)
2. **application.conf** — имена топиков выровнены с case class полями (kebab → camelCase маппинг)
3. **Main.scala** — добавлен debug `println` / `tapError` / `catchAll` (для отладки silent exit)

### 2.3 Потери

**Нет потерь.** Всё сохранено.

---

## 3. History Writer

**Статус: 🔄 Архитектурная замена БД (осознанное решение)**

### 3.1 Ключевое изменение: ClickHouse → TimescaleDB

| Аспект | GitHub (оригинал) | Монорепо (текущий) |
|--------|--------------------|--------------------|
| **БД** | ClickHouse | TimescaleDB (PostgreSQL) |
| **Драйвер** | clickhouse-jdbc 0.6.0 | postgresql + Doobie 1.0.0-RC4 |
| **Пул соединений** | HikariCP (inline) | HikariCP через TransactorLayer |
| **SQL** | Raw JDBC PreparedStatement | Doobie SQL fragments |
| **Конфиг** | ClickHouseConfig (socketTimeout, compression) | DatabaseConfig (connectionTimeout) |
| **zio-config** | 4.0.0-RC16 | 4.0.0 (стабильная) |
| **JAR имя** | history-writer-1.0.0.jar | history-writer.jar |

### 3.2 Что изменилось в коде

**TelemetryRepository.scala** — полностью переписан:
- GitHub: raw JDBC, `PreparedStatement`, batch INSERT в ClickHouse MergeTree таблицы
- Монорепо: Doobie, SQL fragments, `time_bucket()` для дневной статистики в TimescaleDB

**Новые файлы в монорепо:**
- `infrastructure/DoobieInstances.scala` — Meta/Read instances для маппинга типов
- `infrastructure/TransactorLayer.scala` — ZIO Layer с HikariCP + health check

**Удалённые концепции:**
- ClickHouse-специфичные настройки (socketTimeout, compression, lz4-java)
- Raw JDBC код заменён на типобезопасный Doobie DSL

### 3.3 Что осталось без изменений

- Domain модели: `Entities.scala`, `Errors.scala`, `Events.scala` — **идентичны**
- API: `HistoryRoutes.scala`, `HealthRoutes.scala` — **идентичны**
- Сервис: `HistoryService.scala` — **идентичен**
- Потребитель: `TelemetryConsumer.scala` — **идентичен** (только вызов repository поменялся)

### 3.4 Весталь (мусор)

- `db/clickhouse/V1__initial_schema.sql` — DDL для ClickHouse **всё ещё лежит** в монорепо, хотя ClickHouse больше не используется. Можно удалить.

### 3.5 Фиксы деплоя (как у DM)

- `AppConfig.scala` — `TypesafeConfigProvider.kebabCase`
- `Main.scala` — debug `println` / `tapError` / `catchAll`
- `application.conf` — выравнивание имён топиков

### 3.6 Потери

**Нет потерь.** Изменение ClickHouse → TimescaleDB — осознанное архитектурное решение, не случайная потеря кода.

---

## 4. Web Frontend

**Статус: ✅ Идентичен + добавлен Docker**

### 4.1 Исходный код

**22 файла** `.tsx` / `.ts` / `.css` — **полное совпадение** GitHub ↔ монорепо.

Стек: React 19 + TypeScript + Vite + TailwindCSS 4 + Zustand + TanStack Query + OpenLayers 10

Ключевые файлы: `AppLayout.tsx`, `MapView.tsx` (OpenLayers), `LeftPanel.tsx` (грид ТС), 11 модальных компонентов, mock API (805 строк).

### 4.2 Добавлено в монорепо

| Файл | Назначение |
|------|------------|
| `Dockerfile` | Multi-stage сборка: node 22 → nginx alpine |
| `docker/nginx.conf` | Nginx конфиг с динамическим resolver для websocket-service |

Этих файлов **нет** в GitHub-репозитории (они были созданы при деплое на тест-стенд).

### 4.3 Потери

**Нет потерь.**

---

## 5. Web Billing

**Статус: ✅ Идентичен + добавлен Docker**

### 5.1 Исходный код

**24 файла** `.tsx` / `.ts` / `.css` — **полное совпадение** GitHub ↔ монорепо.

Стек: React 19 + TypeScript + Vite + Zustand + vanilla CSS (ExtJS Gray Theme)

Ключевые файлы: `BillingApp.tsx` (13 панелей-вкладок), `GridPanel.tsx` (generic таблица), `AccountForm.tsx` (модальное окно), 4 файла API (~55 REST эндпоинтов).

### 5.2 Добавлено в монорепо

| Файл | Назначение |
|------|------------|
| `Dockerfile` | Multi-stage сборка: node 22 → nginx alpine |
| `docker/nginx.conf` | Nginx конфиг |

Этих файлов **нет** в GitHub-репозитории.

### 5.3 Потери

**Нет потерь.**

---

## 6. Итоги и рекомендации

### 6.1 Что потеряно при копировании

| # | Что | Где | Приоритет |
|---|-----|-----|-----------|
| 1 | 6 стабов протоколов (EGTS, GoSafe, Autophonemayak, DTM, SkySim, Zudo) | CM `protocol/` | 🟡 Средний — стабы, но полезны как каркас для будущих протоколов |
| 2 | Ruptela отсутствует в Protocol enum | CM `domain/Protocol.scala` | 🔴 Баг — парсер есть, enum нет |
| 3 | RESILIENCE_AUDIT.md | CM `docs/` | 🟢 Низкий — документация |

### 6.2 Что улучшено в монорепо

| # | Что | Где | Значимость |
|---|-----|-----|------------|
| 1 | Unified Redis HASH паттерн (DeviceData) | CM | 🔴 Критично — единый формат данных |
| 2 | 7 Kafka топиков (vs 4 в GitHub) | CM | 🔴 Критично — роутинг событий |
| 3 | ParseError ADT (206 строк) | CM | 🟡 Важно — типизированные ошибки |
| 4 | DynamicConfigService + DeviceConfigListener | CM | 🟡 Важно — горячая перезагрузка конфига |
| 5 | CommandHandler + DeviceEventConsumer | CM | 🟡 Важно — обработка команд через Kafka |
| 6 | ClickHouse → TimescaleDB/Doobie | HW | 🔴 Критично — типобезопасный SQL |
| 7 | TransactorLayer + DoobieInstances | HW | 🟡 Важно — правильная абстракция |
| 8 | Dockerfiles для web-сервисов | Web | 🟡 Важно — деплой на тест-стенд |

### 6.3 Рекомендации

**Срочно (перед следующим релизом):**
1. Добавить `Ruptela` обратно в Protocol enum
2. Восстановить 6 стабов протоколов из GitHub (скопировать файлы)

**Желательно:**
3. Удалить весталь `db/clickhouse/V1__initial_schema.sql` из HW
4. Восстановить `docs/RESILIENCE_AUDIT.md` из GitHub CM

**По желанию:**
5. Убрать debug `println` / `tapError` из Main.scala (DM, HW) перед продом

---

## 7. Гайд по проверке тест-стенда

**Сервер:** 192.168.1.5, SSH порт 2220, пользователь wogulis

### 7.1 Подключение к серверу

```bash
ssh -p 2220 wogulis@192.168.1.5
cd /opt/tracker
```

### 7.2 Статус всех контейнеров

```bash
docker compose -f docker-compose.prod.yml ps
```

Ожидается **16 контейнеров** со статусом `Up (healthy)` или `Up`.

### 7.3 Health-эндпоинты бэкенд-сервисов

```bash
# Device Manager (REST API)
curl -s http://localhost:8092/health | jq .

# History Writer
curl -s http://localhost:8093/health | jq .

# Connection Managers (4 протокола)
curl -s http://localhost:8081/health | jq .  # Teltonika
curl -s http://localhost:8082/health | jq .  # Wialon
curl -s http://localhost:8083/health | jq .  # Ruptela
curl -s http://localhost:8084/health | jq .  # NavTelecom
```

### 7.4 TCP-порты Connection Manager

```bash
# Проверка что TCP-порты слушают
nc -z localhost 5001 && echo "Teltonika OK"  || echo "Teltonika FAIL"
nc -z localhost 5002 && echo "Wialon OK"     || echo "Wialon FAIL"
nc -z localhost 5003 && echo "Ruptela OK"    || echo "Ruptela FAIL"
nc -z localhost 5004 && echo "NavTelecom OK" || echo "NavTelecom FAIL"
```

### 7.5 Инфраструктура

```bash
# Redis
docker exec tracker-redis redis-cli ping
# Ожидается: PONG

# TimescaleDB
docker exec tracker-timescaledb psql -U postgres -d tracker -c '\dt'
# Ожидается: список таблиц (devices, device_positions, etc.)

# Kafka — список топиков
docker exec tracker-kafka kafka-topics --bootstrap-server localhost:9092 --list
# Ожидается: gps-events, device-status, unknown-devices, etc.

# Kafka — проверка consumer groups
docker exec tracker-kafka kafka-consumer-groups --bootstrap-server localhost:9092 --list
```

### 7.6 Веб-интерфейсы (открыть в браузере)

| URL | Сервис |
|-----|--------|
| `http://192.168.1.5:3001` | Web Frontend (карта + мониторинг) |
| `http://192.168.1.5:3002` | Web Billing (админка) |
| `http://192.168.1.5:3000` | Grafana (логин: admin / admin123) |
| `http://192.168.1.5:9090` | Prometheus |

Через Nginx прокси:

| URL | Куда проксирует |
|-----|-----------------|
| `http://192.168.1.5/` | → Web Frontend |
| `http://192.168.1.5/admin/` | → Web Billing |
| `http://192.168.1.5/api/` | → Device Manager API |

### 7.7 Логи сервисов

```bash
# Все логи разом (последние 50 строк)
docker compose -f docker-compose.prod.yml logs --tail=50

# Конкретный сервис (следить в реальном времени)
docker compose -f docker-compose.prod.yml logs -f device-manager
docker compose -f docker-compose.prod.yml logs -f history-writer
docker compose -f docker-compose.prod.yml logs -f cm-teltonika

# Поиск ошибок
docker compose -f docker-compose.prod.yml logs | grep -i "error\|exception\|fail"
```

### 7.8 Перезапуск

```bash
# Перезапустить один сервис
docker compose -f docker-compose.prod.yml restart device-manager

# Пересобрать и перезапустить
docker compose -f docker-compose.prod.yml up -d --build device-manager

# Перезапустить всё
docker compose -f docker-compose.prod.yml down && docker compose -f docker-compose.prod.yml up -d
```

---

*Документ создан автоматически на основе сравнительного анализа 5 GitHub-репозиториев с монорепо wayrecall-tracker.*

