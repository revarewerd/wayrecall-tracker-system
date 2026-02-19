#!/bin/bash

# ============================================================
# Создание Kafka топиков для Wayrecall Tracker
# ============================================================
# 
# Запуск: ./create-kafka-topics.sh
# Предварительно должен быть запущен Kafka
# ============================================================

set -e

KAFKA_HOST="${KAFKA_HOST:-localhost:9092}"
REPLICATION_FACTOR="${REPLICATION_FACTOR:-1}"

echo "🚀 Создание Kafka топиков для Wayrecall Tracker..."
echo "   Kafka: $KAFKA_HOST"
echo "   Replication Factor: $REPLICATION_FACTOR"
echo ""

# Функция создания топика
create_topic() {
  local TOPIC=$1
  local PARTITIONS=$2
  local RETENTION_MS=$3
  
  echo "📝 Создание топика: $TOPIC (partitions=$PARTITIONS, retention=${RETENTION_MS}ms)"
  
  kafka-topics --create \
    --bootstrap-server "$KAFKA_HOST" \
    --topic "$TOPIC" \
    --partitions "$PARTITIONS" \
    --replication-factor "$REPLICATION_FACTOR" \
    --config retention.ms="$RETENTION_MS" \
    --config compression.type=snappy \
    --if-not-exists || echo "   ⚠️  Топик $TOPIC уже существует"
}

# ============================================================
# БЛОК 1: Connection Manager + History Writer + Device Manager
# ============================================================

# GPS события (основной поток данных)
# 12 партиций для высокой пропускной способности (10k+ точек/сек)
# 7 дней retention (604800000 ms)
create_topic "gps-events" 12 604800000

# GPS события с геозонами (для Rule Checker и Geozones Service)
# 6 партиций (меньше нагрузка, только точки с привязкой к геозонам)
# 7 дней retention
create_topic "gps-events-rules" 6 604800000

# GPS события для ретрансляции (Wialon, EGTS, HTTP)
# 6 партиций
# 7 дней retention
create_topic "gps-events-retranslation" 6 604800000

# Статусы устройств (online/offline)
# 6 партиций (по deviceId для ordering)
# 7 дней retention
create_topic "device-status" 6 604800000

# Команды для трекеров (Static Partition Assignment)
# 6 партиций (каждый CM instance читает свою партицию через assign())
# 7 дней retention
create_topic "device-commands" 6 604800000

# CRUD события устройств (для синхронизации)
# 3 партиции (низкая частота изменений)
# 30 дней retention (2592000000 ms)
create_topic "device-events" 3 2592000000

# Неизвестные устройства (авто-регистрация)
# 3 партиции
# 7 дней retention
create_topic "unknown-devices" 3 604800000

# GPS точки от незарегистрированных трекеров (для последующей регистрации)
# 6 партиций (partition key = imei)
# 30 дней retention (2592000000 ms)
create_topic "unknown-gps-events" 6 2592000000

# Аудит команд (логирование всех команд и результатов)
# 3 партиции (по deviceId для ordering)
# 90 дней retention (7776000000 ms)
create_topic "command-audit" 3 7776000000

# ============================================================
# БЛОК 2: Geozones Service (Post-MVP)
# ============================================================

# События геозон (вход/выход)
# 6 партиций (по vehicleId)
# 30 дней retention
create_topic "geozone-events" 6 2592000000

echo ""
echo "✅ Все топики созданы успешно!"
echo ""
echo "📋 Проверка топиков:"
kafka-topics --list --bootstrap-server "$KAFKA_HOST" | grep -E "(gps|device|command|geozone|unknown)" || true
echo ""
echo "🎯 Для просмотра конфигурации топика:"
echo "   kafka-topics --describe --bootstrap-server $KAFKA_HOST --topic gps-events"
