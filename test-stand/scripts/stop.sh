#!/bin/bash
# Остановка всех сервисов

SERVER="wogulis@192.168.1.5"
SSH_PORT=2220

echo "🛑 Остановка всех сервисов..."

ssh -p $SSH_PORT $SERVER "cd /home/wogulis/projects/wayrecall-tracker-system && docker compose -f test-stand/docker-compose.prod.yml down"

echo "✅ Все сервисы остановлены"
