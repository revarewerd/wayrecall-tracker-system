#!/bin/sh
# ============================================================
# Redis: маппинги IMEI для 15 Wialon трекеров
# Unified HASH (device:{imei}) + Legacy SET (vehicle:{imei})
# ============================================================

REDIS_CLI="redis-cli -a WayrecallRedis2026!"

# --- Unified HASH: device:{imei} → DeviceData (vehicleId, organizationId, name) ---
$REDIS_CLI HSET "device:867236073419238" vehicleId 1  organizationId 1 name "Wialon-01"
$REDIS_CLI HSET "device:863051067176403" vehicleId 2  organizationId 1 name "Wialon-02"
$REDIS_CLI HSET "device:869132073749245" vehicleId 3  organizationId 1 name "Wialon-03"
$REDIS_CLI HSET "device:862059067157274" vehicleId 4  organizationId 1 name "Wialon-04"
$REDIS_CLI HSET "device:863051067096072" vehicleId 5  organizationId 1 name "Wialon-05"
$REDIS_CLI HSET "device:863051067169127" vehicleId 6  organizationId 1 name "Wialon-06"
$REDIS_CLI HSET "device:867236077847459" vehicleId 7  organizationId 1 name "Wialon-07"
$REDIS_CLI HSET "device:863051067176510" vehicleId 8  organizationId 1 name "Wialon-08"
$REDIS_CLI HSET "device:869132073847874" vehicleId 9  organizationId 1 name "Wialon-09"
$REDIS_CLI HSET "device:863051067087477" vehicleId 10 organizationId 1 name "Wialon-10"
$REDIS_CLI HSET "device:869132073688203" vehicleId 11 organizationId 1 name "Wialon-11"
$REDIS_CLI HSET "device:869132073706120" vehicleId 12 organizationId 1 name "Wialon-12"
$REDIS_CLI HSET "device:863051067300599" vehicleId 13 organizationId 1 name "Wialon-13"
$REDIS_CLI HSET "device:863051067177047" vehicleId 14 organizationId 1 name "Wialon-14"
$REDIS_CLI HSET "device:867236073432082" vehicleId 15 organizationId 1 name "Wialon-15"

# --- Legacy SET: vehicle:{imei} → vehicleId ---
$REDIS_CLI SET "vehicle:867236073419238" 1
$REDIS_CLI SET "vehicle:863051067176403" 2
$REDIS_CLI SET "vehicle:869132073749245" 3
$REDIS_CLI SET "vehicle:862059067157274" 4
$REDIS_CLI SET "vehicle:863051067096072" 5
$REDIS_CLI SET "vehicle:863051067169127" 6
$REDIS_CLI SET "vehicle:867236077847459" 7
$REDIS_CLI SET "vehicle:863051067176510" 8
$REDIS_CLI SET "vehicle:869132073847874" 9
$REDIS_CLI SET "vehicle:863051067087477" 10
$REDIS_CLI SET "vehicle:869132073688203" 11
$REDIS_CLI SET "vehicle:869132073706120" 12
$REDIS_CLI SET "vehicle:863051067300599" 13
$REDIS_CLI SET "vehicle:863051067177047" 14
$REDIS_CLI SET "vehicle:867236073432082" 15

echo "=== Проверка ==="
echo "--- Unified HASH (device:*) ---"
$REDIS_CLI KEYS "device:*" | sort
echo ""
echo "--- Legacy SET (vehicle:*) ---"
$REDIS_CLI KEYS "vehicle:*" | sort
echo ""
echo "--- Пример device:867236073419238 ---"
$REDIS_CLI HGETALL "device:867236073419238"
echo ""
echo "--- Пример vehicle:867236073419238 ---"
$REDIS_CLI GET "vehicle:867236073419238"
echo ""
echo "Готово: 15 IMEI в Redis (unified + legacy)"
