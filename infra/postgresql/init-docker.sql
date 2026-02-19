-- ============================================================
-- WAYRECALL TRACKER - POSTGRESQL INITIALIZATION (DOCKER)
-- ============================================================

-- TimescaleDB extension (уже установлена в образе)
CREATE EXTENSION IF NOT EXISTS timescaledb;

-- Таблица для GPS позиций (hypertable)
CREATE TABLE IF NOT EXISTS gps_positions (
    id BIGSERIAL,
    vehicle_id BIGINT NOT NULL,
    device_id BIGINT NOT NULL,
    imei VARCHAR(15) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    server_time TIMESTAMPTZ NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    speed DOUBLE PRECISION NOT NULL,
    course DOUBLE PRECISION NOT NULL,
    altitude DOUBLE PRECISION,
    satellites INTEGER,
    hdop DOUBLE PRECISION,
    ignition BOOLEAN,
    PRIMARY KEY (vehicle_id, timestamp)
);

-- Создаём hypertable для timeseries данных
SELECT create_hypertable('gps_positions', 'timestamp', if_not_exists => TRUE);

-- Индексы для быстрого поиска
CREATE INDEX IF NOT EXISTS idx_gps_positions_vehicle_id ON gps_positions (vehicle_id);
CREATE INDEX IF NOT EXISTS idx_gps_positions_device_id ON gps_positions (device_id);
CREATE INDEX IF NOT EXISTS idx_gps_positions_imei ON gps_positions (imei);
CREATE INDEX IF NOT EXISTS idx_gps_positions_timestamp ON gps_positions (timestamp DESC);

\echo 'TimescaleDB hypertable gps_positions created successfully!'

-- ============================================================
-- Таблица для GPS позиций от неизвестных трекеров
-- Хранит данные от устройств, не зарегистрированных в системе,
-- чтобы администратор мог видеть их в веб-интерфейсе и добавить
-- ============================================================
CREATE TABLE IF NOT EXISTS unknown_device_positions (
    id BIGSERIAL,
    imei VARCHAR(15) NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL,
    server_time TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    speed DOUBLE PRECISION NOT NULL,
    course DOUBLE PRECISION NOT NULL,
    altitude DOUBLE PRECISION,
    satellites INTEGER,
    protocol VARCHAR(30) NOT NULL,
    instance_id VARCHAR(50),
    PRIMARY KEY (imei, timestamp)
);

-- Hypertable для timeseries данных неизвестных устройств
SELECT create_hypertable('unknown_device_positions', 'timestamp', if_not_exists => TRUE);

-- Индексы
CREATE INDEX IF NOT EXISTS idx_unknown_positions_imei ON unknown_device_positions (imei);
CREATE INDEX IF NOT EXISTS idx_unknown_positions_timestamp ON unknown_device_positions (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_unknown_positions_imei_time ON unknown_device_positions (imei, timestamp DESC);

-- Политика сжатия — данные неизвестных устройств храним 30 дней
SELECT add_retention_policy('unknown_device_positions', INTERVAL '30 days', if_not_exists => TRUE);

\echo 'TimescaleDB hypertable unknown_device_positions created successfully!'
