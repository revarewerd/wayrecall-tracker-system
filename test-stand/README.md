# 🖥️ Тестовый стенд Wayrecall Tracker на HP DL180 G6

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-07` | Версия: `3.0`

## 📋 Информация о сервере

### Железо (настроено 2026-03-07)
- **Модель:** HP ProLiant DL180 G6 (2U rack server)
- **CPU:** 2× Intel Xeon L5520 @ 2.27GHz (4 ядра / 8 потоков каждый, HT) = **16 логических CPU**
- **RAM:** 20GB DDR3 ECC (5× 4GB: PROC1 слоты 3A/6B/9C + PROC2 слоты 6B/9C)
- **Storage:**
  - **SSD-1** (Kingston SV300S37A, 224GB, `/dev/sda`) → `/data` — Kafka, TimescaleDB, Redis, Docker
  - **SSD-2** (Kingston SA400S37, 224GB, `/dev/sdb`) → `/` — ОС Ubuntu 24.04 + swap 4GB
  - **HDD RAID1** (2× Seagate ST33000650NS, 2.73TB, `/dev/md0`) → `/mnt/storage` — Backups, Prometheus, Grafana
- **Network:** 192.168.1.5 (локальная сеть)

### Дисковая разметка

| Диск | Модель | Размер | Точка монтирования | UUID | Содержимое |
|------|--------|--------|-------------------|------|------------|
| SSD-2 (`/dev/sdb`) | Kingston SA400S37 | 224GB | `/` | `3c3ec19a-...` | ОС Ubuntu 24.04, swap 4GB |
| SSD-1 (`/dev/sda1`) | Kingston SV300S37A | 224GB | `/data` | `30fa3129-...` | Kafka, TimescaleDB, Redis, Docker data-root |
| HDD RAID1 (`/dev/md0`) | 2× Seagate ST33000650NS | 2.73TB | `/mnt/storage` | `d97062ce-...` | Backups, логи, Prometheus TSDB, Grafana |

**Почему RAID1 для HDD:** зеркало — если один HDD сдохнет, бэкапы и архивы целы. 2.73TB хватает с запасом.

**Почему SSD раздельные (не RAID):** для тестового стенда скорость важнее redundancy. При смерти SSD — переустановка ОС или пересоздание volumes занимает 30 минут.

### Каталоги данных на SSD-1 (`/data`)

```
/data/
├── docker/             # Docker data-root (images, containers, volumes)
├── kafka/              # Kafka broker logs (retention 7 дней)
│   └── kafka-logs/     # Топики и партиции
├── timescaledb/        # PostgreSQL + TimescaleDB
│   ├── pgdata/         # Основные данные
│   └── pgwal/          # Write-Ahead Log (отдельно для производительности)
├── postgres/           # PostgreSQL (master data: devices, users, orgs)
│   └── pgdata/
├── redis/              # Redis dump.rdb + appendonly.aof
└── zookeeper/          # ZooKeeper data + txn logs
    ├── data/
    └── datalog/
```

### Каталоги на HDD RAID1 (`/mnt/storage`)

```
/mnt/storage/
├── backups/            # Ежедневные pg_dump + Redis dump
│   ├── daily/          # Последние 7 дней
│   ├── weekly/         # Последние 4 недели
│   └── monthly/        # Последние 6 месяцев
├── logs/               # Docker logs (rotated, сжатые)
├── prometheus/         # Prometheus TSDB (retention 30 дней)
└── grafana/            # Grafana SQLite + dashboards
```

### Доступ
- **Hostname:** freenaumen
- **SSH:** `wogulis@192.168.1.5`
- **SSH Port:** 2220
- **SSH Alias:** `ssh server` (порт 2220 настроен в ~/.ssh/config)
- **SSH Key:** id_ed25519 (настроен, беспарольный вход)

### Операционная система
- **ОС:** Ubuntu 24.04.4 LTS (ядро 6.8.0-101-generic, установлена на SSD-2)
- **Docker:** 29.3.0 (data-root: `/data/docker`)
- **Docker Compose:** v5.1.0

---

## 🚀 Быстрый старт

### 1. Первоначальная настройка (один раз)

```bash
# Локально: подготовить конфигурацию
cd ~/repos/wayrecall-tracker-system-template
cp test-stand/.env.example test-stand/.env
nano test-stand/.env  # Настроить пароли

# Развернуть на сервере
./test-stand/scripts/initial-setup.sh
```

### 2. Деплой приложения

```bash
# Деплой одной командой
./test-stand/scripts/deploy.sh

# Проверить статус
./test-stand/scripts/status.sh
```

### 3. Доступ к сервисам

После развертывания доступны:

| Сервис | URL/Порт | Описание |
|--------|----------|----------|
| **Главная** | http://192.168.1.5 (порт 80) | Nginx reverse proxy |
| **Web Frontend** | http://192.168.1.5:3001 | Пользовательская панель |
| **Web Billing** | http://192.168.1.5:3002 | Админка |
| **Device Manager** | http://192.168.1.5:8092 | REST API |
| **History Writer** | http://192.168.1.5:8093 | Batch GPS writer |
| **CM Teltonika** | 192.168.1.5:5001 (TCP) | GPS протокол |
| **CM Wialon** | 192.168.1.5:5002 (TCP) | GPS протокол |
| **CM Ruptela** | 192.168.1.5:5003 (TCP) | GPS протокол |
| **CM NavTelecom** | 192.168.1.5:5004 (TCP) | GPS протокол |
| Grafana | http://192.168.1.5:3000 | Мониторинг |
| Prometheus | http://192.168.1.5:9090 | Метрики |
| PostgreSQL | 192.168.1.5:5432 | TimescaleDB |
| Redis | 192.168.1.5:6379 | Кэш/очереди |
| Kafka | 192.168.1.5:29092 | Внешний доступ |

---

## 📁 Структура папки test-stand

```
test-stand/
├── README.md                    # Этот файл
├── .env.example                 # Шаблон переменных окружения
├── .env                         # Реальные пароли (не коммитится!)
├── docker-compose.prod.yml      # Production конфигурация Docker
├── credentials.md               # Учетные данные и пароли
├── api-endpoints.md             # API эндпоинты всех сервисов
├── monitoring-guide.md          # Гайд по мониторингу
├── backup-strategy.md           # Стратегия резервного копирования
│
├── scripts/
│   ├── initial-setup.sh         # Первоначальная настройка сервера
│   ├── deploy.sh                # Деплой приложения
│   ├── rollback.sh              # Откат к предыдущей версии
│   ├── status.sh                # Статус всех сервисов
│   ├── backup.sh                # Создание backup
│   ├── restore.sh               # Восстановление из backup
│   ├── logs.sh                  # Просмотр логов
│   └── cleanup.sh               # Очистка старых данных
│
└── systemd/
    └── tracker-infra.service    # Systemd unit для автозапуска
```

---

## 📊 Ресурсы сервера (20GB RAM)

### Распределение RAM

#### Инфраструктура

| Компонент | JVM Heap / Config | mem_limit | IOPS | Диск |
|-----------|-------------------|-----------|------|------|
| **Kafka broker** | `-Xmx1g -Xms1g` | 2GB | ✅ | SSD-1 `/data/kafka/` |
| **ZooKeeper** | `-Xmx256m` | 512MB | — | SSD-1 `/data/zookeeper/` |
| **TimescaleDB** | `shared_buffers=2GB` | 4GB | ✅ | SSD-1 `/data/timescaledb/` |
| **Redis** | `maxmemory 512mb` | 768MB | — | SSD-1 `/data/redis/` |
| | | **Σ 7.3GB** | | |

#### Block 1 — Data Collection (6 контейнеров)

| Компонент | JVM Heap | mem_limit | Примечание |
|-----------|----------|-----------|------------|
| **CM Teltonika** | `-Xmx256m` | 384MB | TCP :5001, Netty |
| **CM Wialon** | `-Xmx256m` | 384MB | TCP :5002 |
| **CM Ruptela** | `-Xmx256m` | 384MB | TCP :5003 |
| **CM NavTelecom** | `-Xmx256m` | 384MB | TCP :5004 |
| **History Writer** | `-Xmx384m` | 512MB | Kafka → TimescaleDB batch |
| **Device Manager** | `-Xmx256m` | 384MB | REST API, PostgreSQL |
| | | **Σ 2.4GB** | |

#### Block 2 — Business Logic (11 контейнеров)

| Компонент | JVM Heap | mem_limit | Примечание |
|-----------|----------|-----------|------------|
| **Rule Checker** | `-Xmx256m` | 384MB | Геозоны, скорость, правила |
| **WebSocket Service** | `-Xmx256m` | 384MB | Kafka → WS, push позиций |
| **Notification Service** | `-Xmx192m` | 256MB | Email, SMS, Telegram |
| **Analytics Service** | `-Xmx192m` | 256MB | Отчёты, агрегация |
| **Integration Service** | `-Xmx192m` | 256MB | Wialon, webhooks |
| **Maintenance Service** | `-Xmx192m` | 256MB | ТО, пробег, напоминания |
| **User Service** | `-Xmx192m` | 256MB | Пользователи, роли |
| **Admin Service** | `-Xmx192m` | 256MB | Мониторинг системы |
| **Sensors Service** | `-Xmx192m` | 256MB | Датчики, калибровка |
| **Billing Service** | `-Xmx192m` | 256MB | Тарифы, оплата |
| **Ticket Service** | `-Xmx192m` | 256MB | Тикеты, техподдержка |
| | | **Σ 3.0GB** | |

#### Block 3 — Presentation (4 контейнера)

| Компонент | Config | mem_limit | Примечание |
|-----------|--------|-----------|------------|
| **API Gateway** | `-Xmx256m` | 384MB | Auth, routing, rate limit |
| **Web Frontend** | nginx | 64MB | React SPA |
| **Web Billing** | nginx | 64MB | Админка SPA |
| **Nginx reverse proxy** | nginx | 32MB | :80 → frontend/billing |
| | | **Σ 544MB** | |

#### Мониторинг (3 контейнера)

| Компонент | Config | mem_limit | Диск |
|-----------|--------|-----------|------|
| **Prometheus** | retention 30d | 512MB | HDD `/mnt/storage/prometheus/` |
| **Grafana** | — | 256MB | HDD `/mnt/storage/grafana/` |
| **Node Exporter** | — | 64MB | — |
| | | **Σ 832MB** | |

#### Итого: 28 контейнеров

| Группа | mem_limit | Контейнеров |
|--------|-----------|-------------|
| Инфраструктура | 7.3GB | 4 |
| Block 1 (CM ×4 + HW + DM) | 2.4GB | 6 |
| Block 2 (бизнес-логика) | 3.0GB | 11 |
| Block 3 (presentation) | 544MB | 4 |
| Мониторинг | 832MB | 3 |
| **ИТОГО mem_limit** | **~14.1GB** | **28** |
| **Linux + PageCache** | **~5.9GB** | — |

**PageCache (~6GB свободных) — скрытый бустер:** Linux использует свободную RAM как кэш файлового I/O. Kafka 99% reads из PageCache (не с диска). TimescaleDB тоже получает ускорение. Реальное потребление ~10-11GB, так что для PageCache будет ~9-10GB.

### Использование дисков (планируемое)

| Хранилище | Компонент | Объём | Retention |
|-----------|----------|-------|-----------|
| SSD-1 (224GB) | Kafka logs | ~60-80GB | 7 дней |
| SSD-1 (224GB) | TimescaleDB (data+WAL) | ~80-100GB | 90 дней (сжатие после 7) |
| SSD-1 (224GB) | Redis dump + ZooKeeper | ~2GB | — |
| SSD-1 (224GB) | Docker data-root | ~20-40GB | — |
| SSD-1 (224GB) | **Итого** | **~170GB** | запас ~50GB |
| HDD RAID1 (2.73TB) | Backups (daily/weekly/monthly) | ~50-100GB | 6 месяцев |
| HDD RAID1 (2.73TB) | Docker logs (rotated) | ~10GB | 30 дней |
| HDD RAID1 (2.73TB) | Prometheus TSDB | ~20GB | 30 дней |
| HDD RAID1 (2.73TB) | **Итого** | **~130GB** | запас ~2.5TB |

---

## 🔐 Безопасность

### Сетевая топология

```
Интернет
  │
  ├── Статический IP: 95.165.68.186 (твой домашний роутер)
  │
  └── Роутер (NAT + Port Forwarding)
      │
      ├── :2220  → 192.168.1.5:2220  (SSH)
      ├── :80    → 192.168.1.5:80    (Web UI — Nginx)
      ├── :443   → 192.168.1.5:443   (Web UI — HTTPS, будущее)
      ├── :5001  → 192.168.1.5:5001  (CM Teltonika)
      ├── :5002  → 192.168.1.5:5002  (CM Wialon)
      ├── :5003  → 192.168.1.5:5003  (CM Ruptela)
      └── :5004  → 192.168.1.5:5004  (CM NavTelecom)
      │
      └── LAN 192.168.1.0/24
          └── 192.168.1.5 (сервер freenaumen)
```

### Firewall (ufw) — правила

**Принцип:** минимум открытых портов. БД/Redis/Kafka НЕ открыты на хосте — только Docker internal network.

```bash
# === SSH — только ты (статический IP + LAN) ===
sudo ufw allow from 95.165.68.186 to any port 2220 proto tcp comment 'SSH external'
sudo ufw allow from 192.168.1.0/24 to any port 2220 proto tcp comment 'SSH LAN'

# === GPS протоколы (TCP) — открыты всем (трекеры подключаются с любых IP) ===
sudo ufw allow 5001:5004/tcp comment 'GPS protocols CM'

# === Web UI — открыт всем (заказчик смотрит демо) ===
sudo ufw allow 80/tcp comment 'HTTP Nginx proxy'
sudo ufw allow 443/tcp comment 'HTTPS future'

# === Мониторинг — только ты ===
sudo ufw allow from 95.165.68.186 to any port 3000 proto tcp comment 'Grafana external'
sudo ufw allow from 192.168.1.0/24 to any port 3000 proto tcp comment 'Grafana LAN'
sudo ufw allow from 95.165.68.186 to any port 9090 proto tcp comment 'Prometheus external'
sudo ufw allow from 192.168.1.0/24 to any port 9090 proto tcp comment 'Prometheus LAN'

# === Отладка БД — только LAN (не прокидывается на роутере) ===
sudo ufw allow from 192.168.1.0/24 to any port 5433 proto tcp comment 'TimescaleDB LAN'
sudo ufw allow from 192.168.1.0/24 to any port 6380 proto tcp comment 'Redis LAN'

# === Дефолт — запретить всё остальное ===
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw enable
```

**Что НЕ открыто снаружи (безопасно):**
- PostgreSQL/TimescaleDB (5433) — только LAN, роутер не прокидывает
- Redis (6380) — только LAN
- Kafka (9092/29092) — Docker internal только
- Prometheus (9090) — только твой IP + LAN
- Grafana (3000) — только твой IP + LAN
- API Gateway (8080), сервисы Block 2 — Docker internal, доступ через Nginx

**Что открыто снаружи:**
- SSH (2220) — **только с 95.165.68.186** (не со всего интернета!)
- GPS порты (5001-5004) — для трекеров (обязательно)
- HTTP/HTTPS (80/443) — для заказчика (демо Web UI)

### Пароли

Все пароли хранятся в `test-stand/.env` (не коммитится!).

**ВАЖНО:** Файл `.env` добавлен в `.gitignore`. Шаблон — `.env.example`.

---

## 🔧 Обслуживание

### Просмотр логов

```bash
# Все сервисы
./test-stand/scripts/logs.sh

# Конкретный сервис
./test-stand/scripts/logs.sh kafka

# Последние 100 строк с ошибками
./test-stand/scripts/logs.sh --tail 100 --filter error
```

### Backup

```bash
# Создать backup
./test-stand/scripts/backup.sh

# Восстановить из backup
./test-stand/scripts/restore.sh 2026-01-23_backup.tar.gz
```

### Обновление

```bash
# Обновить до последней версии из GitHub
./test-stand/scripts/deploy.sh

# Откат к предыдущей версии
./test-stand/scripts/rollback.sh
```

---

## 🐛 Troubleshooting

### Сервисы не запускаются

```bash
# Проверить статус Docker
ssh -p 2220 server 'sudo systemctl status docker'

# Проверить логи
./test-stand/scripts/logs.sh

# Перезапустить всё
ssh -p 2220 server 'cd projects/wayrecall-tracker-system && docker compose -f test-stand/docker-compose.prod.yml restart'
```

### Нехватка памяти

```bash
# Проверить использование
ssh -p 2220 server 'free -h'
ssh -p 2220 server 'docker stats --no-stream'

# Топ потребители
ssh -p 2220 server 'docker stats --no-stream --format "table {{.Name}}\t{{.MemUsage}}" | sort -k2 -h -r'

# Очистить неиспользуемые образы
ssh -p 2220 server 'docker system prune -a'
```

### SSD-2 (`/data`) заполняется

```bash
# Проверить использование /data
ssh -p 2220 server 'df -h /data'
ssh -p 2220 server 'du -sh /data/*'

# Kafka занимает много места — уменьшить retention
# В docker-compose: KAFKA_LOG_RETENTION_HOURS: 72  (3 дня вместо 7)

# TimescaleDB — принудительное сжатие
ssh -p 2220 server 'docker exec timescaledb psql -U postgres -c "SELECT compress_chunk(c) FROM show_chunks('\''gps_points'\'') c WHERE NOT is_compressed;"'
```

### HDD RAID1 не собран

```bash
# Проверить статус RAID
ssh -p 2220 server 'cat /proc/mdstat'

# Собрать RAID1 (первый раз)
ssh -p 2220 server 'sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdc /dev/sdd'
ssh -p 2220 server 'sudo mkfs.ext4 /dev/md0'
ssh -p 2220 server 'sudo mount /dev/md0 /mnt/storage'

# Добавить в fstab для автомонтирования
ssh -p 2220 server 'echo "/dev/md0 /mnt/storage ext4 defaults 0 2" | sudo tee -a /etc/fstab'
```

---

## 📞 Поддержка

- **Документация:** `/test-stand/*.md`
- **Логи:** `/mnt/storage/logs/`
- **Backups:** `/mnt/storage/backups/`
- **Мониторинг:** http://192.168.1.5:3000

---

## 🎯 Чеклист развертывания (после апгрейда)

### Этап 1: Железо и ОС
- [x] Установлены 5×4GB DDR3 ECC планки (20GB, 6-я была дефектная)
- [x] Установлены 2× SSD 240GB (Kingston SV300S37A + SA400S37)
- [x] BIOS: видит 20GB RAM и оба SSD
- [x] Установлена Ubuntu 24.04.4 LTS на SSD-2 (`/dev/sdb`)
- [x] SSD-1 отформатирован ext4 (LABEL=data), смонтирован в `/data`
- [x] HDD RAID1 собран (`mdadm --level=1`), отформатирован ext4, смонтирован в `/mnt/storage`
- [x] fstab настроен (автомонтирование `/data` и `/mnt/storage` по UUID)
- [x] Swap 4GB настроен (`/swap.img` на SSD-2)

### Этап 2: Базовое ПО
- [x] SSH настроен на порт 2220
- [x] SSH ключ скопирован (id_ed25519, беспарольный вход)
- [x] Docker 29.3.0 + Compose v5.1.0 установлены (data-root: `/data/docker`)
- [ ] Firewall (ufw) настроен
- [x] Каталоги созданы: `/data/kafka`, `/data/timescaledb`, `/data/redis`, `/data/zookeeper`, `/data/postgres`, `/data/docker`
- [x] Каталоги созданы: `/mnt/storage/backups`, `/mnt/storage/logs`, `/mnt/storage/prometheus`, `/mnt/storage/grafana`
- [x] Права доступа настроены (`chown` для Docker volumes)
- [x] Sysctl тюнинг (vm.swappiness=10, somaxconn=65535, file-max=2097152)
- [x] Ulimits настроены (nofile 65536)
- [x] mdadm.conf сохранён, initramfs обновлён

### Этап 3: Деплой
- [ ] `.env` файл настроен
- [ ] Запущен `initial-setup.sh`
- [ ] Запущен `deploy.sh`
- [ ] Все сервисы в статусе "Up"
- [ ] Grafana доступна — http://192.168.1.5:3000
- [ ] Prometheus собирает метрики — http://192.168.1.5:9090
- [ ] Настроен автозапуск (systemd)
- [ ] Настроен backup cron

---

## 🛠️ Пошаговая инструкция установки ОС

### 1. Подготовка загрузочной флешки

```bash
# На маке — скачать Ubuntu 24.04 Server
# Записать на USB через balenaEtcher или dd
sudo dd if=ubuntu-24.04-live-server-amd64.iso of=/dev/diskN bs=4M status=progress
```

### 2. Установка Ubuntu на SSD-1

В установщике Ubuntu:
- **Диск для ОС:** выбрать SSD-1 (240GB), `/` ext4
- **Swap:** 4GB раздел на SSD-1
- **НЕ трогать:** SSD-2 и оба HDD — настроим после
- **SSH Server:** включить при установке
- **Имя пользователя:** `wogulis`

### 3. Первый вход и базовая настройка

```bash
# Подключиться (первый раз по паролю, потом по ключу)
ssh wogulis@192.168.1.5

# Обновить систему
sudo apt update && sudo apt upgrade -y

# Сменить SSH порт на 2220
sudo sed -i 's/#Port 22/Port 2220/' /etc/ssh/sshd_config
sudo systemctl restart ssh

# Скопировать SSH ключ (с мака)
ssh-copy-id -p 2220 wogulis@192.168.1.5
```

### 4. Настройка SSD-2 (`/data`)

```bash
# Найти SSD-2
lsblk
# Допустим это /dev/sdb

# Создать раздел и файловую систему
sudo parted /dev/sdb mklabel gpt
sudo parted /dev/sdb mkpart primary ext4 0% 100%
sudo mkfs.ext4 -L data /dev/sdb1

# Создать точку монтирования
sudo mkdir -p /data
sudo mount /dev/sdb1 /data

# Добавить в fstab
echo "LABEL=data /data ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# Создать каталоги
sudo mkdir -p /data/{kafka/kafka-logs,timescaledb/{pgdata,pgwal},redis,zookeeper}
sudo chown -R 1001:1001 /data/kafka        # Kafka user
sudo chown -R 999:999 /data/timescaledb    # PostgreSQL user
sudo chown -R 999:999 /data/redis          # Redis user
```

### 5. Настройка HDD RAID1 (`/mnt/storage`)

```bash
# Установить mdadm
sudo apt install mdadm -y

# Найти HDD
lsblk
# Допустим /dev/sdc и /dev/sdd

# Создать RAID1 (зеркало)
sudo mdadm --create /dev/md0 --level=1 --raid-devices=2 /dev/sdc /dev/sdd

# Дождаться синхронизации (может занять несколько часов!)
cat /proc/mdstat

# Создать файловую систему
sudo mkfs.ext4 -L storage /dev/md0

# Смонтировать
sudo mkdir -p /mnt/storage
sudo mount /dev/md0 /mnt/storage

# Сохранить конфигурацию RAID
sudo mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf
sudo update-initramfs -u

# Добавить в fstab
echo "LABEL=storage /mnt/storage ext4 defaults,noatime 0 2" | sudo tee -a /etc/fstab

# Создать каталоги
sudo mkdir -p /mnt/storage/{backups/{daily,weekly,monthly},logs,prometheus,grafana}
```

### 6. Установка Docker

```bash
# Установить Docker
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker wogulis

# Docker data на SSD-1 (по умолчанию /var/lib/docker — уже на SSD-1)
# Перелогиниться чтобы группа подхватилась
exit
ssh -p 2220 server

# Проверить
docker run hello-world
docker compose version
```

### 7. Тюнинг системы

```bash
# Настройки ядра для Kafka и TimescaleDB
cat <<EOF | sudo tee /etc/sysctl.d/99-tracker.conf
# Увеличить лимиты для Kafka
vm.max_map_count = 262144
vm.swappiness = 10

# Увеличить сетевые буферы
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216

# Увеличить лимит открытых файлов
fs.file-max = 100000
EOF
sudo sysctl --system

# Лимиты для Docker процессов
cat <<EOF | sudo tee /etc/security/limits.d/99-tracker.conf
*    soft    nofile    65536
*    hard    nofile    65536
EOF
```

### 8. Деплой проекта

```bash
# Клонировать репозиторий
mkdir -p ~/projects && cd ~/projects
git clone https://github.com/revarewerd/wayrecall-tracker.git
cd wayrecall-tracker

# Настроить .env
cp test-stand/.env.example test-stand/.env
nano test-stand/.env

# Запустить
./test-stand/scripts/deploy.sh
```
