#!/usr/bin/env python3
"""
GPS-симулятор трафика для тестового стенда Wayrecall Tracker.
Генерирует реалистичные GPS-точки по протоколу Wialon IPS и отправляет на CM.

Использование:
  python3 gps-simulator.py                     # Все 15 устройств, интервал 10с
  python3 gps-simulator.py --devices 5         # Первые 5 устройств
  python3 gps-simulator.py --interval 5        # Интервал 5 сек
  python3 gps-simulator.py --host 192.168.1.5  # Указать хост CM
  python3 gps-simulator.py --duration 300      # Работать 5 минут (0 = бесконечно)

Протокол: Wialon IPS v2.0
Порт: 5002 (Wialon)
"""

import socket
import time
import math
import random
import argparse
import signal
import sys
from datetime import datetime, timezone
from typing import List, Tuple, Optional

# ═══════════════════════════════════════════════════════════
# Зарегистрированные устройства (из БД tracker.devices)
# ═══════════════════════════════════════════════════════════
DEVICES = [
    {"id": 1,  "imei": "867236073419238", "name": "КАМАЗ-65115"},
    {"id": 2,  "imei": "863051067176403", "name": "ГАЗель NEXT"},
    {"id": 3,  "imei": "869132073749245", "name": "Toyota Hilux"},
    {"id": 4,  "imei": "862059067157274", "name": "MAN TGS 33.440"},
    {"id": 5,  "imei": "863051067096072", "name": "Hyundai Porter"},
    {"id": 6,  "imei": "863051067169127", "name": "УАЗ Патриот"},
    {"id": 7,  "imei": "867236077847459", "name": "Volvo FH 500"},
    {"id": 8,  "imei": "863051067176510", "name": "Ford Transit"},
    {"id": 9,  "imei": "869132073847874", "name": "Scania R450"},
    {"id": 10, "imei": "863051067087477", "name": "Skoda Octavia"},
    {"id": 11, "imei": "869132073688203", "name": "КАМАЗ-43118"},
    {"id": 12, "imei": "869132073706120", "name": "ГАЗ-3309"},
    {"id": 13, "imei": "863051067300599", "name": "Mercedes Sprinter"},
    {"id": 14, "imei": "863051067177047", "name": "Kia Sportage"},
    {"id": 15, "imei": "867236073432082", "name": "DAF XF 480"},
]

# ═══════════════════════════════════════════════════════════
# Маршруты (московский регион) — начальные точки и направления
# ═══════════════════════════════════════════════════════════
ROUTES = [
    # Маршрут 1: МКАД (кольцо)
    {"center": (55.7558, 37.6173), "radius_km": 15, "type": "circle"},
    # Маршрут 2: Ленинградское шоссе (Москва → Химки)
    {"start": (55.8050, 37.5100), "end": (55.9050, 37.4200), "type": "line"},
    # Маршрут 3: Каширское шоссе (юг)
    {"start": (55.6500, 37.6500), "end": (55.5500, 37.7000), "type": "line"},
    # Маршрут 4: Ярославское шоссе (северо-восток)
    {"start": (55.8200, 37.6800), "end": (55.9200, 37.8000), "type": "line"},
    # Маршрут 5: Минское шоссе (запад)
    {"start": (55.7200, 37.4000), "end": (55.7000, 37.1500), "type": "line"},
    # Маршрут 6: Горьковское шоссе (восток)
    {"start": (55.7400, 37.8000), "end": (55.7600, 38.0500), "type": "line"},
    # Маршрут 7: Новорязанское шоссе (юго-восток)
    {"start": (55.6800, 37.7500), "end": (55.6000, 38.0000), "type": "line"},
    # Маршрут 8: Дмитровское шоссе (север)
    {"start": (55.8700, 37.5300), "end": (55.9800, 37.5100), "type": "line"},
    # Маршрут 9: Варшавское шоссе (юг)
    {"start": (55.6300, 37.6200), "end": (55.5300, 37.5800), "type": "line"},
    # Маршрут 10: Кутузовский → Можайское (запад)
    {"start": (55.7400, 37.5000), "end": (55.7300, 37.2500), "type": "line"},
    # Маршрут 11: Щёлковское шоссе (восток)
    {"start": (55.8000, 37.7500), "end": (55.8400, 37.9500), "type": "line"},
    # Маршрут 12: Профсоюзная → Калужское (юго-запад)
    {"start": (55.6500, 37.5200), "end": (55.5500, 37.4500), "type": "line"},
    # Маршрут 13: Рублёвское шоссе (запад)
    {"start": (55.7500, 37.4200), "end": (55.7300, 37.2000), "type": "line"},
    # Маршрут 14: Балашиха (восток)
    {"start": (55.7950, 37.9500), "end": (55.8100, 38.0500), "type": "line"},
    # Маршрут 15: Ново-Рижское шоссе (запад)
    {"start": (55.7800, 37.3800), "end": (55.8200, 37.1500), "type": "line"},
]


class VehicleSimulator:
    """Симулятор одного транспортного средства."""

    def __init__(self, device: dict, route: dict, idx: int):
        self.device = device
        self.imei = device["imei"]
        self.name = device["name"]
        self.route = route
        self.idx = idx

        # Текущее положение
        if route["type"] == "circle":
            angle = random.uniform(0, 2 * math.pi)
            r_km = route["radius_km"]
            self.lat = route["center"][0] + (r_km / 111.0) * math.cos(angle)
            self.lon = route["center"][1] + (r_km / (111.0 * math.cos(math.radians(route["center"][0])))) * math.sin(angle)
            self.angle = angle
        else:
            # Линейный маршрут — начинаем с начала или конца (случайно)
            t = random.random()
            self.lat = route["start"][0] + t * (route["end"][0] - route["start"][0])
            self.lon = route["start"][1] + t * (route["end"][1] - route["start"][1])
            self.direction = 1 if random.random() > 0.5 else -1
            self.t = t

        # Скорость 30-80 км/ч
        self.speed = random.uniform(30, 80)
        self.altitude = random.uniform(120, 200)
        self.satellites = random.randint(8, 16)
        self.course = random.uniform(0, 360)
        self.hdop = round(random.uniform(0.8, 2.5), 1)

        # TCP соединение
        self.sock: Optional[socket.socket] = None
        self.connected = False

    def connect(self, host: str, port: int) -> bool:
        """Подключение к CM и авторизация по Wialon IPS."""
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.settimeout(10)
            self.sock.connect((host, port))

            # Wialon IPS авторизация: #L#imei;password\r\n
            login_msg = f"#L#{self.imei};NA\r\n"
            self.sock.sendall(login_msg.encode('ascii'))

            # Ожидаем ответ #AL#1\r\n (успех)
            response = self.sock.recv(256).decode('ascii', errors='ignore')
            if "#AL#1" in response:
                self.connected = True
                print(f"  ✅ {self.name} ({self.imei}) — подключён")
                return True
            else:
                print(f"  ❌ {self.name} ({self.imei}) — отклонён: {response.strip()}")
                self.disconnect()
                return False
        except Exception as e:
            print(f"  ❌ {self.name} ({self.imei}) — ошибка: {e}")
            self.disconnect()
            return False

    def disconnect(self):
        """Отключение."""
        if self.sock:
            try:
                self.sock.close()
            except:
                pass
        self.sock = None
        self.connected = False

    def step(self, interval_sec: float):
        """Сдвинуть позицию на один шаг."""
        # Расстояние в км за интервал
        dist_km = (self.speed / 3600) * interval_sec

        if self.route["type"] == "circle":
            # Движение по кругу (МКАД)
            r_km = self.route["radius_km"]
            circumference = 2 * math.pi * r_km
            self.angle += (dist_km / circumference) * 2 * math.pi
            self.lat = self.route["center"][0] + (r_km / 111.0) * math.cos(self.angle)
            self.lon = self.route["center"][1] + (r_km / (111.0 * math.cos(math.radians(self.route["center"][0])))) * math.sin(self.angle)
            # Курс — тангенциальное направление
            self.course = (math.degrees(self.angle) + 90) % 360
        else:
            # Линейный маршрут (туда-обратно)
            dlat = self.route["end"][0] - self.route["start"][0]
            dlon = self.route["end"][1] - self.route["start"][1]
            route_len_km = math.sqrt((dlat * 111) ** 2 + (dlon * 111 * math.cos(math.radians(self.lat))) ** 2)
            dt = dist_km / max(route_len_km, 0.1)
            self.t += dt * self.direction

            # Разворот на концах маршрута
            if self.t >= 1.0:
                self.t = 1.0
                self.direction = -1
            elif self.t <= 0.0:
                self.t = 0.0
                self.direction = 1

            self.lat = self.route["start"][0] + self.t * dlat
            self.lon = self.route["start"][1] + self.t * dlon

            # Курс
            self.course = math.degrees(math.atan2(dlon * self.direction, dlat * self.direction)) % 360

        # Лёгкий рандом — имитация реальности
        self.lat += random.gauss(0, 0.0001)
        self.lon += random.gauss(0, 0.0001)
        self.speed = max(5, min(120, self.speed + random.gauss(0, 5)))
        self.altitude += random.gauss(0, 1)
        self.satellites = max(4, min(20, self.satellites + random.choice([-1, 0, 0, 0, 1])))

    def send_position(self) -> bool:
        """Отправить текущую позицию по Wialon IPS."""
        if not self.connected or not self.sock:
            return False

        try:
            now = datetime.now(timezone.utc)
            date_str = now.strftime("%d%m%y")  # DDMMYY
            time_str = now.strftime("%H%M%S")  # HHMMSS

            # Wialon IPS формат координат: DDMM.MMMM
            lat_abs = abs(self.lat)
            lat_deg = int(lat_abs)
            lat_min = (lat_abs - lat_deg) * 60
            lat_str = f"{lat_deg:02d}{lat_min:07.4f}"
            lat_hem = "N" if self.lat >= 0 else "S"

            lon_abs = abs(self.lon)
            lon_deg = int(lon_abs)
            lon_min = (lon_abs - lon_deg) * 60
            lon_str = f"{lon_deg:03d}{lon_min:07.4f}"
            lon_hem = "E" if self.lon >= 0 else "W"

            speed_knots = self.speed * 0.539957  # км/ч → узлы

            # #D#date;time;lat1;lat2;lon1;lon2;speed;course;alt;sats;hdop;inputs;outputs;adc;ibutton;params\r\n
            msg = (
                f"#D#"
                f"{date_str};{time_str};"
                f"{lat_str};{lat_hem};"
                f"{lon_str};{lon_hem};"
                f"{speed_knots:.1f};{self.course:.1f};"
                f"{self.altitude:.1f};{self.satellites};"
                f"{self.hdop};0;0;;;"
                f"\r\n"
            )

            self.sock.sendall(msg.encode('ascii'))

            # Ожидаем подтверждение #AD#1\r\n
            self.sock.settimeout(5)
            response = self.sock.recv(256).decode('ascii', errors='ignore')
            return "#AD#1" in response

        except socket.timeout:
            return True  # Таймаут не критичен
        except Exception as e:
            print(f"  ⚠️  {self.name}: ошибка отправки — {e}")
            self.connected = False
            return False


def run_simulator(host: str, port: int, num_devices: int, interval: float, duration: float):
    """Запуск симулятора."""
    devices_to_use = DEVICES[:num_devices]
    simulators: List[VehicleSimulator] = []

    print(f"\n🚀 GPS-симулятор Wayrecall Tracker")
    print(f"   Хост: {host}:{port}")
    print(f"   Устройств: {num_devices}")
    print(f"   Интервал: {interval} сек")
    print(f"   Длительность: {'∞' if duration == 0 else f'{duration} сек'}")
    print(f"\n📡 Подключение устройств...")

    # Создаём и подключаем симуляторы
    for i, dev in enumerate(devices_to_use):
        route = ROUTES[i % len(ROUTES)]
        sim = VehicleSimulator(dev, route, i)
        if sim.connect(host, port):
            simulators.append(sim)
        time.sleep(0.3)  # Не спамить подключениями

    if not simulators:
        print("\n❌ Ни одно устройство не подключилось!")
        return

    print(f"\n🟢 Запущено {len(simulators)} из {num_devices} устройств")
    print(f"   Отправка точек каждые {interval} сек...\n")

    # Обработка Ctrl+C
    running = True
    def signal_handler(sig, frame):
        nonlocal running
        running = False
        print("\n\n⏹  Остановка...")
    signal.signal(signal.SIGINT, signal_handler)

    start_time = time.time()
    total_sent = 0
    total_errors = 0

    try:
        while running:
            if duration > 0 and (time.time() - start_time) >= duration:
                break

            cycle_start = time.time()

            for sim in simulators:
                if not sim.connected:
                    # Попытка переподключения
                    sim.connect(host, port)
                    continue

                sim.step(interval)
                if sim.send_position():
                    total_sent += 1
                else:
                    total_errors += 1

            elapsed = time.time() - start_time
            active = sum(1 for s in simulators if s.connected)

            # Статус каждые 10 циклов
            if total_sent % (num_devices * 10) < num_devices:
                print(
                    f"  📊 T+{elapsed:.0f}с | "
                    f"Отправлено: {total_sent} | "
                    f"Ошибки: {total_errors} | "
                    f"Активных: {active}/{len(simulators)}"
                )

            # Ждём до следующего цикла
            sleep_time = max(0, interval - (time.time() - cycle_start))
            if sleep_time > 0 and running:
                time.sleep(sleep_time)

    finally:
        print(f"\n📈 Итого:")
        print(f"   Отправлено точек: {total_sent}")
        print(f"   Ошибок: {total_errors}")
        print(f"   Время работы: {time.time() - start_time:.0f} сек")
        print(f"\n🔌 Отключение...")
        for sim in simulators:
            sim.disconnect()
        print("   Готово.\n")


def main():
    parser = argparse.ArgumentParser(description="GPS-симулятор Wayrecall Tracker (Wialon IPS)")
    parser.add_argument("--host", default="192.168.1.5", help="Хост CM (default: 192.168.1.5)")
    parser.add_argument("--port", type=int, default=5002, help="Порт Wialon IPS (default: 5002)")
    parser.add_argument("--devices", type=int, default=15, help="Количество устройств 1-15 (default: 15)")
    parser.add_argument("--interval", type=float, default=10, help="Интервал отправки в сек (default: 10)")
    parser.add_argument("--duration", type=float, default=0, help="Длительность в сек, 0=бесконечно (default: 0)")
    args = parser.parse_args()

    args.devices = max(1, min(15, args.devices))

    run_simulator(args.host, args.port, args.devices, args.interval, args.duration)


if __name__ == "__main__":
    main()
