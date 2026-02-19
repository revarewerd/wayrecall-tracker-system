# 🖥️ Тестовый стенд TrackerGPS на HP DL180 G6

## 📋 Информация о сервере

### Железо
- **Модель:** HP ProLiant DL180 G6 (2U rack server)
- **CPU:** Intel Xeon L5520 @ 2.27GHz (16 потоков)
- **RAM:** 7.7GB DDR3 ECC
- **Storage:**
  - Системный диск: 100GB (sda)
  - RAID0 массив: 8.2TB (md0) → `/mnt/raid`
- **Network:** 192.168.1.5 (локальная сеть)

### Доступ
- **Hostname:** freenaumen
- **SSH:** `wogulis@192.168.1.5`
- **SSH Port:** 2220
- **SSH Alias:** `ssh server` (порт 2220 настроен в ~/.ssh/config)
- **SSH Key:** id_ed25519 (настроен)

### Операционная система
- **ОС:** Ubuntu 24.04.3 LTS
- **Docker:** установлен
- **Docker Compose:** установлен

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

## 📊 Ресурсы сервера

### Использование памяти (планируемое)

| Компонент | RAM | CPU | Disk |
|-----------|-----|-----|------|
| Redis | 150MB | 5% | 1GB |
| Kafka + ZooKeeper | 1.5GB | 15% | 10GB |
| TimescaleDB | 600MB | 10% | 50GB+ |
| CM ×4 (Teltonika, Wialon, Ruptela, NavTelecom) | 4×512MB = 2GB | 20% | 1GB |
| History Writer | 512MB | 15% | 1GB |
| Device Manager | 512MB | 10% | 1GB |
| Web Frontend + Web Billing + Nginx Proxy | 320MB | 3% | 0.5GB |
| Prometheus | 200MB | 5% | 5GB |
| Grafana | 150MB | 5% | 1GB |
| **ИТОГО** | **~6GB** | **88%** | **70GB** |

**Остаток:** 3.7GB RAM, 15% CPU, 30GB системный диск, 8.2TB RAID массив

---

## 🔐 Безопасность

### Firewall (рекомендуется настроить)

```bash
# На сервере
sudo ufw allow 2220/tcp      # SSH (порт 2220)
sudo ufw allow 3000/tcp      # Grafana
sudo ufw allow 9090/tcp      # Prometheus
sudo ufw allow 5432/tcp      # PostgreSQL (только из локальной сети)
sudo ufw enable
```

### Пароли

Все пароли хранятся в `test-stand/.env` и `test-stand/credentials.md`.

**ВАЖНО:** Файл `.env` добавлен в `.gitignore` и не коммитится в репозиторий!

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

# Очистить неиспользуемые образы
ssh -p 2220 server 'docker system prune -a'
```

### RAID массив не смонтирован

```bash
ssh -p 2220 server 'sudo mount /dev/md0 /mnt/raid'
```

---

## 📞 Поддержка

- **Документация:** `/test-stand/*.md`
- **Логи:** `/mnt/raid/logs/`
- **Backups:** `/mnt/raid/backups/`
- **Мониторинг:** http://192.168.1.5:3000

---

## 🎯 Чеклист развертывания

- [ ] Сервер доступен по SSH
- [ ] RAID массив смонтирован
- [ ] Docker установлен и запущен
- [ ] Созданы директории для данных
- [ ] Файл `.env` настроен
- [ ] Запущен `initial-setup.sh`
- [ ] Запущен `deploy.sh`
- [ ] Все сервисы в статусе "Up"
- [ ] Grafana доступна
- [ ] Prometheus собирает метрики
- [ ] Настроен автозапуск (systemd)
- [ ] Настроен firewall
- [ ] Настроен backup
