-- ============================================================
-- Тестовые данные: организация, транспорт, 15 Wialon трекеров
-- ============================================================

BEGIN;

-- 1. Организация
INSERT INTO organizations (id, name, inn, email, phone, address, timezone, max_devices)
VALUES (1, 'Wayrecall Test', '7701234567', 'admin@wayrecall.ru', '+79161234567', 'Москва, ул. Тестовая 1', 'Europe/Moscow', 100)
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, updated_at = now();

SELECT setval('organizations_id_seq', (SELECT MAX(id) FROM organizations));

-- 2. Транспортные средства (15 штук)
INSERT INTO vehicles (id, organization_id, name, vehicle_type, license_plate) VALUES
  (1,  1, 'Трекер-01', 'Car', 'А001АА77'),
  (2,  1, 'Трекер-02', 'Car', 'А002АА77'),
  (3,  1, 'Трекер-03', 'Car', 'А003АА77'),
  (4,  1, 'Трекер-04', 'Car', 'А004АА77'),
  (5,  1, 'Трекер-05', 'Car', 'А005АА77'),
  (6,  1, 'Трекер-06', 'Car', 'А006АА77'),
  (7,  1, 'Трекер-07', 'Car', 'А007АА77'),
  (8,  1, 'Трекер-08', 'Car', 'А008АА77'),
  (9,  1, 'Трекер-09', 'Car', 'А009АА77'),
  (10, 1, 'Трекер-10', 'Car', 'А010АА77'),
  (11, 1, 'Трекер-11', 'Car', 'А011АА77'),
  (12, 1, 'Трекер-12', 'Car', 'А012АА77'),
  (13, 1, 'Трекер-13', 'Car', 'А013АА77'),
  (14, 1, 'Трекер-14', 'Car', 'А014АА77'),
  (15, 1, 'Трекер-15', 'Car', 'А015АА77')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, updated_at = now();

SELECT setval('vehicles_id_seq', (SELECT MAX(id) FROM vehicles));

-- 3. Устройства (15 Wialon IPS трекеров)
INSERT INTO devices (id, imei, name, protocol, status, organization_id, vehicle_id) VALUES
  (1,  '867236073419238', 'Wialon-01', 'wialon-ips', 'Active', 1, 1),
  (2,  '863051067176403', 'Wialon-02', 'wialon-ips', 'Active', 1, 2),
  (3,  '869132073749245', 'Wialon-03', 'wialon-ips', 'Active', 1, 3),
  (4,  '862059067157274', 'Wialon-04', 'wialon-ips', 'Active', 1, 4),
  (5,  '863051067096072', 'Wialon-05', 'wialon-ips', 'Active', 1, 5),
  (6,  '863051067169127', 'Wialon-06', 'wialon-ips', 'Active', 1, 6),
  (7,  '867236077847459', 'Wialon-07', 'wialon-ips', 'Active', 1, 7),
  (8,  '863051067176510', 'Wialon-08', 'wialon-ips', 'Active', 1, 8),
  (9,  '869132073847874', 'Wialon-09', 'wialon-ips', 'Active', 1, 9),
  (10, '863051067087477', 'Wialon-10', 'wialon-ips', 'Active', 1, 10),
  (11, '869132073688203', 'Wialon-11', 'wialon-ips', 'Active', 1, 11),
  (12, '869132073706120', 'Wialon-12', 'wialon-ips', 'Active', 1, 12),
  (13, '863051067300599', 'Wialon-13', 'wialon-ips', 'Active', 1, 13),
  (14, '863051067177047', 'Wialon-14', 'wialon-ips', 'Active', 1, 14),
  (15, '867236073432082', 'Wialon-15', 'wialon-ips', 'Active', 1, 15)
ON CONFLICT (imei) DO UPDATE SET
  name = EXCLUDED.name,
  protocol = EXCLUDED.protocol,
  status = EXCLUDED.status,
  organization_id = EXCLUDED.organization_id,
  vehicle_id = EXCLUDED.vehicle_id,
  updated_at = now();

SELECT setval('devices_id_seq', (SELECT MAX(id) FROM devices));

COMMIT;

-- Проверка
SELECT 'organizations' AS tbl, count(*) FROM organizations
UNION ALL
SELECT 'vehicles', count(*) FROM vehicles
UNION ALL
SELECT 'devices', count(*) FROM devices;

SELECT id, imei, name, protocol, status, vehicle_id FROM devices ORDER BY id;
