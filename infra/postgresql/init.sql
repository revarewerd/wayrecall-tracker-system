-- ============================================================
-- Инициализация TimescaleDB для Wayrecall Tracker
-- Source of truth: infra/postgresql/SCHEMA.md
-- ============================================================

-- Расширения
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================
-- ORGANIZATIONS
-- ============================================================

CREATE TABLE IF NOT EXISTS organizations (
    id              BIGSERIAL PRIMARY KEY,
    name            VARCHAR(200) NOT NULL,
    inn             VARCHAR(20),
    email           VARCHAR(200) NOT NULL,
    phone           VARCHAR(50),
    address         TEXT,
    timezone        VARCHAR(50) NOT NULL DEFAULT 'Europe/Moscow',
    max_devices     INTEGER NOT NULL DEFAULT 100,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_organizations_email ON organizations (email);
CREATE INDEX IF NOT EXISTS idx_organizations_inn ON organizations (inn) WHERE inn IS NOT NULL;

-- ============================================================
-- VEHICLES
-- ============================================================

CREATE TABLE IF NOT EXISTS vehicles (
    id                  BIGSERIAL PRIMARY KEY,
    organization_id     BIGINT NOT NULL REFERENCES organizations(id),
    name                VARCHAR(200) NOT NULL,
    vehicle_type        VARCHAR(20) NOT NULL DEFAULT 'Car',
    license_plate       VARCHAR(20),
    vin                 VARCHAR(20),
    brand               VARCHAR(100),
    model               VARCHAR(100),
    year                INTEGER,
    color               VARCHAR(50),
    fuel_type           VARCHAR(30),
    fuel_tank_capacity  DOUBLE PRECISION,
    icon_url            VARCHAR(500),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_vehicles_org ON vehicles (organization_id);
CREATE INDEX IF NOT EXISTS idx_vehicles_plate ON vehicles (license_plate) WHERE license_plate IS NOT NULL;

-- ============================================================
-- SENSOR PROFILES
-- ============================================================

CREATE TABLE IF NOT EXISTS sensor_profiles (
    id              BIGSERIAL PRIMARY KEY,
    organization_id BIGINT NOT NULL REFERENCES organizations(id),
    name            VARCHAR(200) NOT NULL,
    description     TEXT,
    sensors         JSONB NOT NULL DEFAULT '[]',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sensor_profiles_org ON sensor_profiles (organization_id);

-- ============================================================
-- DEVICES
-- ============================================================

CREATE TABLE IF NOT EXISTS devices (
    id                  BIGSERIAL PRIMARY KEY,
    imei                VARCHAR(20) UNIQUE NOT NULL,
    name                VARCHAR(200),
    protocol            VARCHAR(20) NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'Active',
    organization_id     BIGINT NOT NULL REFERENCES organizations(id),
    vehicle_id          BIGINT REFERENCES vehicles(id),
    sensor_profile_id   BIGINT REFERENCES sensor_profiles(id),
    phone_number        VARCHAR(20),
    firmware_version    VARCHAR(50),
    last_seen_at        TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_devices_imei ON devices (imei);
CREATE INDEX IF NOT EXISTS idx_devices_org ON devices (organization_id);
CREATE INDEX IF NOT EXISTS idx_devices_vehicle ON devices (vehicle_id) WHERE vehicle_id IS NOT NULL;

-- ============================================================
-- GPS POSITIONS (Hypertable) — History Writer пишет
-- ============================================================

CREATE TABLE IF NOT EXISTS gps_positions (
    time                TIMESTAMPTZ NOT NULL,
    device_id           BIGINT NOT NULL,
    vehicle_id          BIGINT,
    organization_id     BIGINT NOT NULL,
    imei                VARCHAR(20) NOT NULL,
    latitude            DOUBLE PRECISION NOT NULL,
    longitude           DOUBLE PRECISION NOT NULL,
    altitude            DOUBLE PRECISION,
    speed               DOUBLE PRECISION NOT NULL,
    course              DOUBLE PRECISION,
    satellites          INTEGER,
    hdop                DOUBLE PRECISION,
    is_moving           BOOLEAN NOT NULL DEFAULT true,
    is_valid            BOOLEAN NOT NULL DEFAULT true,
    sensors             JSONB,
    protocol            VARCHAR(20),
    location            GEOGRAPHY(POINT, 4326)
);

SELECT create_hypertable('gps_positions', 'time',
    chunk_time_interval => INTERVAL '7 days',
    if_not_exists => TRUE
);

CREATE INDEX IF NOT EXISTS idx_gps_imei_time ON gps_positions (imei, time DESC);
CREATE INDEX IF NOT EXISTS idx_gps_vehicle_time ON gps_positions (vehicle_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_gps_org_time ON gps_positions (organization_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_gps_location ON gps_positions USING GIST (location);

ALTER TABLE gps_positions SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'imei',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('gps_positions', INTERVAL '7 days', if_not_exists => TRUE);
SELECT add_retention_policy('gps_positions', INTERVAL '1 year', if_not_exists => TRUE);

-- ============================================================
-- UNKNOWN DEVICE POSITIONS (Hypertable) — неизвестные трекеры
-- GPS данные от устройств, не зарегистрированных в системе.
-- Администратор видит их в веб-интерфейсе и может добавить.
-- Хранятся 30 дней, затем удаляются автоматически.
-- ============================================================

CREATE TABLE IF NOT EXISTS unknown_device_positions (
    time            TIMESTAMPTZ NOT NULL,
    imei            VARCHAR(15) NOT NULL,
    server_time     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL,
    speed           DOUBLE PRECISION NOT NULL,
    course          DOUBLE PRECISION NOT NULL,
    altitude        DOUBLE PRECISION,
    satellites      INTEGER,
    protocol        VARCHAR(30) NOT NULL,
    instance_id     VARCHAR(50)
);

SELECT create_hypertable('unknown_device_positions', 'time',
    chunk_time_interval => INTERVAL '1 day',
    if_not_exists => TRUE
);

-- Индексы
CREATE INDEX IF NOT EXISTS idx_unknown_imei_time ON unknown_device_positions (imei, time DESC);
CREATE INDEX IF NOT EXISTS idx_unknown_time ON unknown_device_positions (time DESC);

-- Сжатие (через 3 дня — данные неизвестных устройств менее важны)
ALTER TABLE unknown_device_positions SET (
    timescaledb.compress,
    timescaledb.compress_segmentby = 'imei',
    timescaledb.compress_orderby = 'time DESC'
);

SELECT add_compression_policy('unknown_device_positions', INTERVAL '3 days', if_not_exists => TRUE);
SELECT add_retention_policy('unknown_device_positions', INTERVAL '30 days', if_not_exists => TRUE);

-- ============================================================
-- DEVICE COMMANDS (Hypertable) — Device Manager пишет
-- ============================================================

CREATE TABLE IF NOT EXISTS device_commands (
    time            TIMESTAMPTZ NOT NULL,
    command_id      UUID NOT NULL,
    device_id       BIGINT NOT NULL,
    imei            VARCHAR(20) NOT NULL,
    command_type    VARCHAR(50) NOT NULL,
    command_data    JSONB,
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    sent_at         TIMESTAMPTZ,
    ack_at          TIMESTAMPTZ,
    error_message   TEXT
);

SELECT create_hypertable('device_commands', 'time',
    chunk_time_interval => INTERVAL '30 days',
    if_not_exists => TRUE
);

CREATE INDEX IF NOT EXISTS idx_commands_imei_time ON device_commands (imei, time DESC);
CREATE INDEX IF NOT EXISTS idx_commands_status ON device_commands (status);

SELECT add_retention_policy('device_commands', INTERVAL '90 days', if_not_exists => TRUE);

-- ============================================================
-- GEOZONES (Блок 2 — Geozones Service)
-- ============================================================

CREATE TABLE IF NOT EXISTS geozones (
    id              SERIAL PRIMARY KEY,
    organization_id BIGINT NOT NULL REFERENCES organizations(id),
    name            VARCHAR(200) NOT NULL,
    zone_type       VARCHAR(50),
    geometry        GEOGRAPHY(POLYGON, 4326) NOT NULL,
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_geozones_geometry ON geozones USING GIST (geometry);
CREATE INDEX IF NOT EXISTS idx_geozones_org ON geozones (organization_id);

-- ============================================================
-- GEOZONE EVENTS (Hypertable, Блок 2)
-- ============================================================

CREATE TABLE IF NOT EXISTS geozone_events (
    time            TIMESTAMPTZ NOT NULL,
    event_id        UUID NOT NULL,
    vehicle_id      BIGINT NOT NULL,
    organization_id BIGINT NOT NULL,
    geozone_id      INTEGER NOT NULL,
    event_type      VARCHAR(20) NOT NULL,
    latitude        DOUBLE PRECISION NOT NULL,
    longitude       DOUBLE PRECISION NOT NULL
);

SELECT create_hypertable('geozone_events', 'time',
    chunk_time_interval => INTERVAL '30 days',
    if_not_exists => TRUE
);

CREATE INDEX IF NOT EXISTS idx_geozone_events_vehicle ON geozone_events (vehicle_id, time DESC);
CREATE INDEX IF NOT EXISTS idx_geozone_events_zone ON geozone_events (geozone_id, time DESC);

SELECT add_retention_policy('geozone_events', INTERVAL '6 months', if_not_exists => TRUE);

-- ============================================================
-- CONTINUOUS AGGREGATE — суточная статистика
-- ============================================================

CREATE MATERIALIZED VIEW IF NOT EXISTS daily_device_stats
WITH (timescaledb.continuous) AS
SELECT
    time_bucket('1 day', time) AS day,
    imei,
    vehicle_id,
    COUNT(*)                                        AS position_count,
    AVG(speed)                                      AS avg_speed,
    MAX(speed)                                      AS max_speed,
    SUM(CASE WHEN is_moving THEN 1 ELSE 0 END)     AS moving_count
FROM gps_positions
GROUP BY day, imei, vehicle_id;

SELECT add_continuous_aggregate_policy('daily_device_stats',
    start_offset    => INTERVAL '3 days',
    end_offset      => INTERVAL '1 hour',
    schedule_interval => INTERVAL '1 hour',
    if_not_exists   => TRUE
);

-- ============================================================
-- ФУНКЦИИ
-- ============================================================

CREATE OR REPLACE FUNCTION get_last_position(device_imei VARCHAR)
RETURNS TABLE (
    time TIMESTAMPTZ,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    course DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT gp.time, gp.latitude, gp.longitude, gp.speed, gp.course
    FROM gps_positions gp
    WHERE gp.imei = device_imei
    ORDER BY gp.time DESC
    LIMIT 1;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION check_point_in_geozone(
    lat DOUBLE PRECISION,
    lon DOUBLE PRECISION,
    org_id BIGINT
)
RETURNS TABLE (
    geozone_id INTEGER,
    geozone_name VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT gz.id, gz.name::VARCHAR
    FROM geozones gz
    WHERE gz.is_active = true
      AND gz.organization_id = org_id
      AND ST_Contains(gz.geometry::geometry, ST_SetSRID(ST_MakePoint(lon, lat), 4326));
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- ТЕСТОВЫЕ ДАННЫЕ
-- ============================================================

INSERT INTO organizations (name, email, timezone, max_devices)
VALUES ('Test Organization', 'test@wayrecall.com', 'Europe/Moscow', 100)
ON CONFLICT DO NOTHING;

INSERT INTO vehicles (organization_id, name, vehicle_type, license_plate)
SELECT o.id, 'Test Vehicle', 'Truck', 'A123BC'
FROM organizations o WHERE o.email = 'test@wayrecall.com'
ON CONFLICT DO NOTHING;

INSERT INTO devices (imei, name, protocol, status, organization_id)
SELECT '123456789012345', 'Test Device 1', 'Teltonika', 'Active', o.id
FROM organizations o WHERE o.email = 'test@wayrecall.com'
ON CONFLICT (imei) DO NOTHING;

-- ============================================================
-- КОММЕНТАРИИ
-- ============================================================

COMMENT ON TABLE organizations IS 'Организации (клиенты системы)';
COMMENT ON TABLE vehicles IS 'Транспортные средства';
COMMENT ON TABLE devices IS 'GPS устройства (трекеры)';
COMMENT ON TABLE sensor_profiles IS 'Профили датчиков (IO-element mapping)';
COMMENT ON TABLE gps_positions IS 'GPS позиции (TimescaleDB Hypertable, 10K+ точек/сек)';
COMMENT ON TABLE unknown_device_positions IS 'GPS позиции от неизвестных трекеров (авто-удаление через 30 дней)';
COMMENT ON TABLE device_commands IS 'Команды отправленные на устройства';
COMMENT ON TABLE geozones IS 'Геозоны (PostGIS полигоны)';
COMMENT ON TABLE geozone_events IS 'События въезда/выезда из геозон';
