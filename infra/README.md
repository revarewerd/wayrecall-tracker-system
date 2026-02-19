# 🛠️ Инфраструктура Wayrecall Tracker

Централизованное управление инфраструктурой, схемами данных и сервисами.

## 📁 Структура

```
infra/
├── postgresql/                  # PostgreSQL / TimescaleDB
│   ├── SCHEMA.md                    # Описание всех таблиц, полей, типов (source of truth)
│   ├── init.sql                     # SQL-схема инициализации
│   └── init.sh                      # Скрипт запуска init.sql через Docker
│
├── redis/                       # Redis
│   └── KEYS.md                      # Все ключи Redis: структура, владение, TTL
│
├── kafka/                       # Apache Kafka
│   ├── TOPICS.md                    # Все топики, маршруты, форматы сообщений
│   └── create-topics.sh             # Скрипт создания топиков через Docker
│
├── scripts/                     # Общие скрипты управления
│   ├── init-all.sh                  # Полная инициализация системы (7 шагов)
│   ├── start-dev.sh                 # Запуск dev-окружения в tmux
│   ├── stop-all.sh                  # Остановка всех сервисов
│   └── health-check.sh             # Проверка здоровья всех сервисов
│
└── README.md                    # Этот файл
```

## 📚 Документация по инфраструктуре

| Файл | Что описывает |
|------|--------------|
| [postgresql/SCHEMA.md](postgresql/SCHEMA.md) | Все таблицы PostgreSQL/TimescaleDB: organizations, devices, vehicles, gps_positions (hypertable), geozones и др. |
| [redis/KEYS.md](redis/KEYS.md) | Все Redis ключи: `device:{imei}` HASH (кто какие поля пишет/читает), commands queue, pub/sub каналы |
| [kafka/TOPICS.md](kafka/TOPICS.md) | Все Kafka топики: gps-events, gps-events-rules, gps-events-retranslation, device-status и др. Матрица сервис→топик |

## 🚀 Быстрый старт

### 1. Инициализация всей системы

```bash
./infra/scripts/init-all.sh
```

**Что делает:**
1. Проверяет Docker и Docker Compose
2. Инициализирует git submodules
3. Создаёт директории для данных
4. Запускает инфраструктуру (Kafka, Redis, TimescaleDB)
5. Создаёт Kafka топики (7 топиков)
6. Инициализирует TimescaleDB (таблицы, hypertables, индексы, функции)
7. Компилирует все сервисы (SBT)

### 2. Запуск dev-окружения

```bash
./infra/scripts/start-dev.sh
```

Запускает tmux сессию с 6 окнами:
- **infra** — логи Docker Compose
- **conn-mgr** — Connection Manager (TCP сервер)
- **history** — History Writer (Kafka → TimescaleDB)
- **device-mgr** — Device Manager (REST API)
- **kafka-debug** — Kafka Console Consumer
- **redis-debug** — Redis CLI

### 3. Проверка здоровья

```bash
./infra/scripts/health-check.sh
```

### 4. Остановка

```bash
./infra/scripts/stop-all.sh
```

## 🔧 Отдельные операции

```bash
# Только Kafka топики
./infra/kafka/create-topics.sh

# Только TimescaleDB
./infra/postgresql/init.sh

# Подключиться к TimescaleDB вручную
docker exec -it tracker-timescaledb psql -U tracker -d tracker

# Подключиться к Redis
docker exec -it tracker-redis redis-cli

# Посмотреть логи Kafka
docker exec tracker-kafka kafka-console-consumer.sh \
  --bootstrap-server localhost:9092 \
  --topic gps-events \
  --property print.key=true
```

## 📊 Порты

| Сервис | Порт | Описание |
|--------|------|----------|
| Redis | 6379 | Cache + Pub/Sub |
| Kafka | 9092, 29092 | Message broker |
| Zookeeper | 2181 | Kafka coordinator |
| TimescaleDB | 5432 | PostgreSQL + TimeSeries |
| Prometheus | 9090 | Metrics |
| Grafana | 3000 | Dashboards |
| Connection Manager | 5001-5004 | TCP для трекеров |
| Device Manager | 8092 | REST API |
| History Writer | 8093 | Internal HTTP |

---

**Версия:** 2.0  
**Обновлено:** 11 февраля 2026
