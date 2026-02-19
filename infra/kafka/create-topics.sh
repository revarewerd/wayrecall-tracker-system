#!/bin/bash
# Создание Kafka топиков для Wayrecall Tracker
# Использование: ./infra/kafka/create-topics.sh
#
# Source of truth для списка топиков — TOPICS.md в этой же папке.
# При добавлении нового топика обновляй оба файла!

set -e

echo "📊 Создание Kafka топиков..."

# Переменные
KAFKA_CONTAINER="tracker-kafka"
REPLICATION_FACTOR=1

# Функция создания топика
create_topic() {
    local topic=$1
    local partitions=$2
    local retention_ms=$3
    local description=$4
    
    echo "  ├─ $topic (partitions=$partitions, retention=${retention_ms}ms) — $description"
    
    docker exec $KAFKA_CONTAINER kafka-topics.sh \
        --create \
        --if-not-exists \
        --bootstrap-server localhost:9092 \
        --topic "$topic" \
        --partitions "$partitions" \
        --replication-factor $REPLICATION_FACTOR \
        --config "retention.ms=$retention_ms" \
        --config compression.type=lz4
}

echo ""
echo "=== Блок 1: Core GPS Pipeline ==="

# 7 дней = 604800000 мс
# 1 день = 86400000 мс
# 30 дней = 2592000000 мс
# 90 дней = 7776000000 мс

create_topic "gps-events" 12 604800000 \
    "Все валидные GPS точки (CM → HW, WS, Analytics)"

create_topic "gps-events-rules" 6 86400000 \
    "GPS для проверки геозон/скоростей (CM → Geozones, RuleChecker)"

create_topic "gps-events-retranslation" 6 86400000 \
    "GPS для ретрансляции (CM → Integration Service)"

create_topic "device-status" 6 2592000000 \
    "Online/offline устройств (CM → Notifications, HW)"

create_topic "device-events" 3 2592000000 \
    "CRUD устройств (DM → CM, Integration Service)"

create_topic "unknown-devices" 3 604800000 \
    "Неизвестные IMEI (CM → DM auto-provisioning)"

create_topic "command-audit" 3 7776000000 \
    "Аудит команд (DM → аудит-лог)"

echo ""
echo "✅ Все топики созданы!"
echo ""
echo "Список топиков:"
docker exec $KAFKA_CONTAINER kafka-topics.sh \
    --list \
    --bootstrap-server localhost:9092
