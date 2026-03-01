# 📋 План ревью документации Wayrecall Tracker

> **Создано:** 1 марта 2026 | **Цель:** привести ВСЮ документацию к единому стандарту из copilot-instructions.md

---

## 📊 Текущее состояние

| Статус | Кол-во | Примечание |
|--------|--------|------------|
| ✅ Соответствует стандарту (тег + дата + версия) | 3 | CM, TOPICS.md, LEGACY_PROTOCOLS |
| ⚠️ Нет мета-блока / устарел | 25 | Основная масса документов |
| 🔴 Кандидаты на АРХИВ | 6 | Старые / дублирующие |
| **Всего документов** | **34** | **~33 900 строк** |

---

## 🗺️ Порядок чтения (от фундамента к деталям)

### Фаза 1: Фундамент (архитектура верхнего уровня)

Читай сверху вниз — от общей картины к блокам:

| # | Файл | Строк | Зачем читать | Приоритет |
|---|------|-------|-------------|-----------|
| 1 | [docs/ARCHITECTURE.md](ARCHITECTURE.md) | 251 | Общая архитектура, 3 блока, как всё связано | 🔴 Критично |
| 2 | [docs/blocks/ARCHITECTURE_BLOCK1.md](blocks/ARCHITECTURE_BLOCK1.md) | 787 | Block 1: CM + DM + HW — реализованный блок | 🔴 Критично |
| 3 | [docs/blocks/ARCHITECTURE_BLOCK2.md](blocks/ARCHITECTURE_BLOCK2.md) | 1251 | Block 2: Geozones, Notifications, Analytics и др. | 🔴 Критично |
| 4 | [docs/blocks/ARCHITECTURE_BLOCK3.md](blocks/ARCHITECTURE_BLOCK3.md) | 1520 | Block 3: API GW, Auth, Users, WebSocket, Frontend | 🔴 Критично |

### Фаза 2: Инфраструктура (общие ресурсы)

| # | Файл | Строк | Зачем читать | Приоритет |
|---|------|-------|-------------|-----------|
| 5 | [infra/kafka/TOPICS.md](../infra/kafka/TOPICS.md) | 457 | Все Kafka топики, маршруты, consumer groups | 🟡 Важно |
| 6 | [infra/redis/KEYS.md](../infra/redis/KEYS.md) | 184 | Все Redis ключи и структуры | 🟡 Важно |
| 7 | [infra/postgresql/SCHEMA.md](../infra/postgresql/SCHEMA.md) | 270 | Общие схемы PostgreSQL | 🟡 Важно |
| 8 | [docs/DATA_STORES.md](DATA_STORES.md) | 1718 | Хранилища данных (сводный) | 🟡 Важно |

### Фаза 3: Block 1 — Сервисы (реализованы)

| # | Файл | Строк | Зачем читать | Приоритет |
|---|------|-------|-------------|-----------|
| 9 | [docs/services/CONNECTION_MANAGER.md](services/CONNECTION_MANAGER.md) | 1149 | ✅ v4.0 — эталон формата | 🟢 Ок |
| 10 | [docs/services/DEVICE_MANAGER.md](services/DEVICE_MANAGER.md) | 1592 | REST API устройств, команды | 🟡 Важно |
| 11 | [docs/services/HISTORY_WRITER.md](services/HISTORY_WRITER.md) | 1160 | Запись GPS в TimescaleDB | 🟡 Важно |

### Фаза 4: Block 2 — Сервисы (спроектированы)

| # | Файл | Строк | Зачем читать | Приоритет |
|---|------|-------|-------------|-----------|
| 12 | [docs/services/GEOZONES_SERVICE.md](services/GEOZONES_SERVICE.md) | 1258 | Геозоны, enter/leave | 🟡 Важно |
| 13 | [docs/services/SENSORS_SERVICE.md](services/SENSORS_SERVICE.md) | 1334 | Датчики, калибровка топлива | 🟡 Важно |
| 14 | [docs/services/NOTIFICATIONS_SERVICE.md](services/NOTIFICATIONS_SERVICE.md) | 1515 | Уведомления: email, SMS, push | 🟡 Важно |
| 15 | [docs/services/ANALYTICS_SERVICE.md](services/ANALYTICS_SERVICE.md) | 1714 | Отчёты, агрегация | 🟡 Важно |
| 16 | [docs/services/INTEGRATION_SERVICE.md](services/INTEGRATION_SERVICE.md) | 1552 | Ретрансляция Wialon, webhooks | 🟡 Важно |
| 17 | [docs/services/MAINTENANCE_SERVICE.md](services/MAINTENANCE_SERVICE.md) | 1573 | Плановое ТО | 🟡 Важно |

### Фаза 5: Block 3 — Сервисы (планируются)

| # | Файл | Строк | Зачем читать | Приоритет |
|---|------|-------|-------------|-----------|
| 18 | [docs/services/API_GATEWAY.md](services/API_GATEWAY.md) | 1354 | REST API, маршрутизация, rate limiting | 🟡 Важно |
| 19 | [docs/services/AUTH_SERVICE.md](services/AUTH_SERVICE.md) | 1420 | JWT, OAuth, сессии | 🟡 Важно |
| 20 | [docs/services/USER_SERVICE.md](services/USER_SERVICE.md) | 1388 | Пользователи, роли, организации | 🟡 Важно |
| 21 | [docs/services/WEBSOCKET_SERVICE.md](services/WEBSOCKET_SERVICE.md) | 1469 | Real-time позиции и события | 🟡 Важно |
| 22 | [docs/services/ADMIN_SERVICE.md](services/ADMIN_SERVICE.md) | 861 | Панель управления системой | 🟢 PostMVP |
| 23 | [docs/services/WEB_FRONTEND.md](services/WEB_FRONTEND.md) | 1100 | React + Leaflet UI | 🔴 Критично* |

> *WEB_FRONTEND.md критичен — известны пробелы: нет resizable panels, нет floating windows, не учтён UX старой системы

### Фаза 6: Специализированные документы

| # | Файл | Строк | Зачем читать | Приоритет |
|---|------|-------|-------------|-----------|
| 24 | [docs/GEOZONES_SERVICE_DESIGN.md](GEOZONES_SERVICE_DESIGN.md) | 567 | Детальный дизайн геозон | 🟢 По желанию |
| 25 | [docs/GEOZONES_DETAILED_FAQ.md](GEOZONES_DETAILED_FAQ.md) | 720 | FAQ по геозонам | 🟢 По желанию |

### Фаза 7: Кандидаты на АРХИВ (определить судьбу)

| # | Файл | Строк | Вопрос | Решение |
|---|------|-------|--------|---------|
| 26 | [docs/ARCHITECTURE_OLD.md](ARCHITECTURE_OLD.md) | 456 | Старая архитектура | ❓ АРХИВ? |
| 27 | [docs/ARCHITECTURE_AUDIT.md](ARCHITECTURE_AUDIT.md) | 466 | Аудит (26 янв) | ❓ АРХИВ? |
| 28 | [docs/BLOCK1_COMPLETION_PLAN.md](BLOCK1_COMPLETION_PLAN.md) | 414 | План Block 1 (уже реализован) | ❓ АРХИВ? |
| 29 | [docs/CM_DATA_STORES.md](CM_DATA_STORES.md) | 192 | Дубль DATA_MODEL.md? | ❓ УДАЛИТЬ? |
| 30 | [docs/CM_FILE_MAP.md](CM_FILE_MAP.md) | 127 | Карта файлов CM | ❓ АРХИВ? |
| 31 | [docs/CM_STUDY_GUIDE.md](CM_STUDY_GUIDE.md) | 176 | Учебник CM | ❓ АРХИВ? |
| 32 | [docs/AI_ANSWERS_TO_YOUR_QUESTIONS.md](AI_ANSWERS_TO_YOUR_QUESTIONS.md) | 684 | Ответы AI (25 янв) | ❓ АРХИВ? |
| 33 | [docs/REPO_COMPARISON_ANALYSIS.md](REPO_COMPARISON_ANALYSIS.md) | 395 | Анализ репо | ❓ АРХИВ? |
| 34 | [docs/LEGACY_PROTOCOLS_ANALYSIS.md](LEGACY_PROTOCOLS_ANALYSIS.md) | 886 | Анализ протоколов legacy | ✅ Актуален |

---

## 📝 Стандарт качества (чеклист для каждого документа)

При чтении каждого документа проверяй:

- [ ] **Мета-блок** — есть тег (`АКТУАЛЬНО`/`УСТАРЕЛО`/`ЧЕРНОВИК`), дата, версия
- [ ] **Содержание** — есть TOC с якорными ссылками
- [ ] **Диаграммы** — Mermaid для потоков данных, архитектуры, sequence
- [ ] **Таблицы** — порты, Kafka топики, Redis ключи, API endpoints
- [ ] **Консистентность** — данные совпадают с другими документами (порты, топики, имена)
- [ ] **Актуальность** — отражает текущее состояние кода (не задуманное, а реализованное)
- [ ] **Нет дублирования** — ссылки на /infra/ вместо копирования
- [ ] **Комментарии на русском** — все пояснения на русском
- [ ] **Нет AI промптов** — убраны устаревшие секции с промптами для AI
- [ ] **Связи** — ссылки на связанные документы работают

---

## 🔄 Процесс работы

### Шаг 1: Чтение (ты)

Читаешь документы в порядке выше (фаза 1 → 7). Для каждого пишешь заметки в **[DOC_REVIEW_NOTES.md](DOC_REVIEW_NOTES.md)** (формат ниже).

### Шаг 2: Обсуждение (мы вместе)

Обсуждаем твои заметки. Я отвечаю на вопросы, уточняю контекст, помогаю принять решения.

### Шаг 3: Правка (я)

Я правлю документы по согласованным заметкам. Ты проверяешь результат.

### Шаг 4: Финальная проверка

- Все мета-блоки на месте
- Все ссылки работают
- Нет дублирования
- Данные консистентны между документами

---

## ⏱️ Оценка времени

| Фаза | Документов | Объём | Твоё время (чтение) |
|------|-----------|-------|---------------------|
| 1. Архитектура | 4 | ~3 800 строк | ~30-40 мин |
| 2. Инфра | 4 | ~2 600 строк | ~20 мин |
| 3. Block 1 | 3 | ~3 900 строк | ~25 мин |
| 4. Block 2 | 6 | ~8 950 строк | ~50 мин |
| 5. Block 3 | 6 | ~7 600 строк | ~45 мин |
| 6. Специальные | 2 | ~1 300 строк | ~10 мин |
| 7. Архив | 9 | ~3 800 строк | ~15 мин (скан) |
| **Итого** | **34** | **~32 000 строк** | **~3 часа** |

> Можно разбить на 2-3 дня: День 1 = Фазы 1-3, День 2 = Фазы 4-5, День 3 = Фазы 6-7 + обсуждение
