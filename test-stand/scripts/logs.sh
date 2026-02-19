#!/bin/bash
# Просмотр логов сервисов

SERVER="wogulis@192.168.1.5"
SSH_PORT=2220
SERVICE=${1:-all}
LINES=${2:-50}

if [ "$SERVICE" == "all" ]; then
    ssh -p $SSH_PORT $SERVER "cd /home/wogulis/projects/wayrecall-tracker-system && docker compose -f test-stand/docker-compose.prod.yml logs --tail=$LINES -f"
else
    ssh -p $SSH_PORT $SERVER "cd /home/wogulis/projects/wayrecall-tracker-system && docker compose -f test-stand/docker-compose.prod.yml logs --tail=$LINES -f $SERVICE"
fi
