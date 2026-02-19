#!/bin/bash
# Инициализация TimescaleDB для Wayrecall Tracker
# Использование: ./infra/postgresql/init.sh
#
# Source of truth: infra/postgresql/SCHEMA.md + init.sql

set -e

echo "🐘 Инициализация TimescaleDB..."

# Переменные
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="tracker"
DB_USER="tracker"
DB_PASSWORD="tracker123"
CONTAINER_NAME="tracker-timescaledb"

# Ожидание готовности PostgreSQL
echo "⏳ Ожидание готовности TimescaleDB..."
until docker exec $CONTAINER_NAME pg_isready -U $DB_USER 2>/dev/null; do
  echo "  ...ещё не готова"
  sleep 2
done

echo "✅ TimescaleDB готова к работе"
echo ""

# Выполнение SQL скрипта инициализации
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "📝 Выполнение SQL скрипта: $SCRIPT_DIR/init.sql"
docker exec -i $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME < "$SCRIPT_DIR/init.sql"

echo ""
echo "✅ TimescaleDB инициализирована!"
echo ""
echo "Подключение:"
echo "  Host:     $DB_HOST:$DB_PORT"
echo "  Database: $DB_NAME"
echo "  User:     $DB_USER"
echo ""
echo "Подключиться вручную:"
echo "  docker exec -it $CONTAINER_NAME psql -U $DB_USER -d $DB_NAME"
