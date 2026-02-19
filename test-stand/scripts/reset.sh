#!/bin/bash
# ============================================================
# Полный сброс и обнуление тестового стенда
# Удаляет ВСЕ данные: контейнеры, volumes, БД, Kafka, Redis
# ============================================================

set -e

SERVER="wogulis@192.168.1.5"
SSH_PORT=2220
REMOTE_PATH="/home/wogulis/projects/wayrecall-tracker-system"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}========================================${NC}"
echo -e "${RED}  ⚠️  ПОЛНЫЙ СБРОС ТЕСТОВОГО СТЕНДА${NC}"
echo -e "${RED}========================================${NC}"
echo ""
echo -e "${YELLOW}Это удалит:${NC}"
echo "  - Все Docker контейнеры"
echo "  - Все Docker volumes (Redis, Kafka, PostgreSQL данные)"
echo "  - Все Docker images"
echo "  - Данные на /mnt/raid/docker-data/"
echo ""

read -p "Точно сбросить всё? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Отменено."
    exit 0
fi

echo ""
echo -e "${GREEN}[1/5]${NC} Остановка и удаление контейнеров..."
ssh -p $SSH_PORT $SERVER "cd $REMOTE_PATH && docker compose -f test-stand/docker-compose.prod.yml down -v --remove-orphans 2>/dev/null || true"

echo ""
echo -e "${GREEN}[2/5]${NC} Удаление всех Docker volumes..."
ssh -p $SSH_PORT $SERVER 'docker volume prune -af 2>/dev/null || true'

echo ""
echo -e "${GREEN}[3/5]${NC} Удаление всех Docker images..."
ssh -p $SSH_PORT $SERVER 'docker system prune -af 2>/dev/null || true'

echo ""
echo -e "${GREEN}[4/5]${NC} Очистка данных на RAID..."
ssh -p $SSH_PORT $SERVER << 'ENDSSH'
set -e
echo "Удаление директорий данных..."
sudo rm -rf /mnt/raid/docker-data/redis/* 2>/dev/null || true
sudo rm -rf /mnt/raid/docker-data/kafka/* 2>/dev/null || true
sudo rm -rf /mnt/raid/docker-data/postgres/* 2>/dev/null || true
sudo rm -rf /mnt/raid/docker-data/zookeeper/* 2>/dev/null || true
sudo rm -rf /mnt/raid/docker-data/prometheus/* 2>/dev/null || true
sudo rm -rf /mnt/raid/docker-data/grafana/* 2>/dev/null || true

# Пересоздаём пустые директории
sudo mkdir -p /mnt/raid/docker-data/{redis,kafka,postgres,zookeeper/data,zookeeper/logs,prometheus,grafana}
sudo chown -R wogulis:wogulis /mnt/raid/docker-data/
echo "✓ Директории очищены и пересозданы"
ENDSSH

echo ""
echo -e "${GREEN}[5/5]${NC} Проверка..."
ssh -p $SSH_PORT $SERVER 'docker ps -a; echo "---"; du -sh /mnt/raid/docker-data/*'

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  ✅ Тестовый стенд обнулён!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Для деплоя запустите: ${GREEN}./test-stand/scripts/deploy.sh${NC}"
