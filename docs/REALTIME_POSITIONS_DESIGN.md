# 🗺️ Real-Time отображение позиций транспорта

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-02` | Версия: `1.0`

## Цель документа

Детальное описание: **как работает отрисовка позиций машин в реальном времени** — от GPS-трекера до маркера на карте в браузере пользователя.

---

## 📑 Содержание

1. [Обзор потока данных](#1-обзор-потока-данных)
2. [Путь GPS-пакета (End-to-End)](#2-путь-gps-пакета-end-to-end)
3. [Connection Manager → Kafka](#3-connection-manager--kafka)
4. [WebSocket Service: Kafka → Browser](#4-websocket-service-kafka--browser)
5. [Frontend: WebSocket → Карта Leaflet](#5-frontend-websocket--карта-leaflet)
6. [Первоначальная загрузка (Initial Load)](#6-первоначальная-загрузка-initial-load)
7. [Масштабирование и производительность](#7-масштабирование-и-производительность)
8. [Обработка отключений](#8-обработка-отключений)
9. [Протокол сообщений](#9-протокол-сообщений)
10. [Диаграммы всех сценариев](#10-диаграммы-всех-сценариев)
11. [Оптимизации](#11-оптимизации)
12. [Сравнение с Legacy Stels](#12-сравнение-с-legacy-stels)

---

## 1. Обзор потока данных

### Общая схема (ASCII)

```
 GPS Трекер                Connection Manager            Kafka              WebSocket Service           Browser
 ─────────                 ──────────────────            ─────              ─────────────────           ───────
     │                            │                        │                       │                      │
     │  TCP пакет (бинарный)      │                        │                       │                      │
     │ =========================> │                        │                       │                      │
     │                            │                        │                       │                      │
     │                    ┌──── Parse ────┐                │                       │                      │
     │                    │ Protocol      │                │                       │                      │
     │                    │ Filter DR     │                │                       │                      │
     │                    │ Enrich        │                │                       │                      │
     │                    └──────┬────────┘                │                       │                      │
     │                           │                        │                       │                      │
     │                           │ GpsEvent (JSON)        │                       │                      │
     │                           │ =====================> │                       │                      │
     │                           │                        │                       │                      │
     │                           │ Redis: SET pos:{imei}  │                       │                      │
     │                           │ ─────────────────────> │ (Redis)               │                      │
     │                           │                        │                       │                      │
     │                           │                        │  Consume gps-events   │                      │
     │                           │                        │ =====================>│                      │
     │                           │                        │                       │                      │
     │                           │                        │               ┌── Lookup ──┐                │
     │                           │                        │               │ device_id   │                │
     │                           │                        │               │ → org_id    │                │
     │                           │                        │               │ → room      │                │
     │                           │                        │               └──────┬──────┘                │
     │                           │                        │                      │                       │
     │                           │                        │                      │ WS frame (JSON)       │
     │                           │                        │                      │ =====================>│
     │                           │                        │                      │                       │
     │                           │                        │                      │              ┌── Leaflet ──┐
     │                           │                        │                      │              │ moveMarker  │
     │                           │                        │                      │              │ updatePanel │
     │                           │                        │                      │              └─────────────┘
```

### Latency Budget

| Этап | Время | Кумулятивно |
|------|-------|-------------|
| TCP пакет → Parse → Filter | ~5-10ms | 10ms |
| Publish в Kafka | ~5-15ms | 25ms |
| Kafka → WS Service consume | ~10-30ms | 55ms |
| Lookup device → org → room | ~1-3ms | 58ms |
| WebSocket frame → Browser | ~10-30ms | 88ms |
| React re-render → Leaflet | ~5-15ms | **~100ms** |
| **Итого (p99)** | | **< 150ms** |

---

## 2. Путь GPS-пакета (End-to-End)

### Полная Sequence Diagram

```mermaid
sequenceDiagram
    participant T as 🛰️ GPS Трекер
    participant CM as Connection Manager
    participant P as Protocol Parser
    participant F as Dead Reckoning Filter
    participant K as Kafka
    participant R as Redis
    participant WS as WebSocket Service
    participant B as 🌐 Browser (Leaflet)

    Note over T,B: === ЭТАП 1: TCP приём и парсинг ===

    T->>CM: TCP: binary GPS packet (Teltonika Codec 8E)
    CM->>CM: Определить IMEI → deviceId, orgId
    CM->>P: parse(ByteBuf)
    P->>P: Декодировать: lat, lon, speed, course, altitude, satellites, timestamp
    P-->>CM: List[GpsPoint]

    Note over CM,F: === ЭТАП 2: Фильтрация ===

    CM->>F: filter(points, lastKnownPosition)
    F->>F: Dead Reckoning: убрать дубли, проверить скорость, расстояние
    F-->>CM: List[GpsPoint] (filtered)

    Note over CM,K: === ЭТАП 3: Публикация ===

    par Параллельно
        CM->>K: Publish gps-events (key=deviceId)<br/>JSON: {deviceId, imei, orgId, lat, lon,<br/>speed, course, altitude, satellites, ts}
        CM->>R: SET pos:{imei} → JSON {lat, lon, speed, course, ts}<br/>TTL 3600s
    end

    T-->>CM: ACK (протокол-зависимый ответ)

    Note over K,WS: === ЭТАП 4: WebSocket маршрутизация ===

    K->>WS: Consume gps-events (consumer group: ws-positions)
    WS->>WS: Lookup: deviceId → orgId → rooms
    WS->>WS: Найти все WS-соединения в room "org:{orgId}"
    WS->>WS: Также room "device:{deviceId}" (если есть подписчики)

    Note over WS,B: === ЭТАП 5: Доставка в браузер ===

    WS->>B: WS Frame: {"type":"position","deviceId":456,<br/>"data":{"lat":55.7558,"lon":37.6173,<br/>"speed":45,"course":180,"ts":"..."}}

    Note over B: === ЭТАП 6: Отрисовка на карте ===

    B->>B: zustand: updateDevicePosition(deviceId, newPos)
    B->>B: Leaflet: marker.setLatLng([lat, lon])
    B->>B: Leaflet: marker.setRotationAngle(course)
    B->>B: UI: обновить панель устройства (скорость, время)
```

---

## 3. Connection Manager → Kafka

### Что публикуется в Kafka

**Топик:** `gps-events`  
**Ключ партиции:** `deviceId` (числовой) — гарантирует порядок точек одного устройства  
**Consumer groups:** `history-writer`, `rule-checker`, `ws-positions`, `sensors-processor`

### Формат сообщения (JSON)

```json
{
  "deviceId": 456,
  "imei": "352093089439473",
  "organizationId": 123,
  "timestamp": "2026-06-02T14:30:15.123Z",
  "latitude": 55.755826,
  "longitude": 37.617300,
  "altitude": 156.0,
  "speed": 45.2,
  "course": 180,
  "satellites": 12,
  "hdop": 0.9,
  "inputs": {
    "ignition": true,
    "door": false,
    "sos": false
  },
  "analogInputs": {
    "power": 13.8,
    "battery": 4.1,
    "fuel1": 342
  },
  "eventId": null,
  "valid": true
}
```

### Redis: Последняя позиция

CM также записывает позицию в Redis для быстрого доступа (initial load):

```
KEY:    pos:{imei}
VALUE:  {"lat":55.755826,"lon":37.617300,"speed":45.2,"course":180,
         "alt":156,"sat":12,"ts":"2026-06-02T14:30:15.123Z","ign":true}
TTL:    3600 (1 час — если не обновляется, значит устройство офлайн)
```

**Зачем Redis?** При открытии карты (initial load) нужны **последние позиции всех устройств** организации — читать из Redis быстрее, чем Kafka.

---

## 4. WebSocket Service: Kafka → Browser

### Архитектура WebSocket Service

```mermaid
flowchart TB
    subgraph Input["Источники данных"]
        KafkaGPS["Kafka Consumer\ngps-events\n(group: ws-positions)"]
        KafkaEvents["Kafka Consumer\ngeozone-events\nspeed-events\nsensor-events\n(group: ws-events)"]
    end

    subgraph WS["WebSocket Service"]
        DeviceRegistry["Device Registry\n(deviceId → orgId mapping)\n(ZIO Ref / Redis)"]
        
        subgraph ConnManager["Connection Manager"]
            AuthFilter["JWT Auth Filter"]
            ConnPool["Connection Pool\n(ConcurrentHashMap[UserId, WsConnection])"]
        end
        
        subgraph RoomManager["Room Manager"]
            OrgRooms["org:{orgId}\n→ Set[WsConnection]"]
            DevRooms["device:{deviceId}\n→ Set[WsConnection]"]
            AlertRooms["alerts:{orgId}\n→ Set[WsConnection]"]
        end
        
        MessageRouter["Message Router\n(event → rooms)"]
        Serializer["JSON Serializer\n(zio-json)"]
        Throttler["Position Throttler\n(max 1 msg/sec per device)"]
    end

    subgraph Output["Клиенты"]
        B1["Browser 1\nsubscribed: org:123"]
        B2["Browser 2\nsubscribed: device:456"]
        B3["Mobile\nsubscribed: alerts:123"]
    end

    KafkaGPS --> Throttler --> MessageRouter
    KafkaEvents --> MessageRouter
    
    MessageRouter --> DeviceRegistry
    DeviceRegistry --> RoomManager
    RoomManager --> Serializer
    Serializer --> |"WS frame"| B1 & B2 & B3
    
    AuthFilter --> ConnPool --> RoomManager
```

### Как WS Service определяет, кому отправить

```scala
// Псевдокод маршрутизации позиции
def routePosition(event: GpsEvent): Task[Unit] = for {
  // 1. Определяем org_id устройства (из кэша или Kafka сообщения)
  orgId     <- deviceRegistry.getOrgId(event.deviceId)
  
  // 2. Находим все room'ы, куда нужно отправить
  orgRoom   <- roomManager.getRoom(s"org:$orgId")      // все устройства организации
  devRoom   <- roomManager.getRoom(s"device:${event.deviceId}") // конкретное устройство
  
  // 3. Объединяем connection'ы (убираем дубли)
  allConns  = (orgRoom.connections ++ devRoom.connections).distinct
  
  // 4. Сериализуем и отправляем
  message   <- serializer.encode(PositionMessage(event))
  _         <- ZIO.foreachParDiscard(allConns)(conn => conn.send(message))
} yield ()
```

### Throttling позиций

Некоторые трекеры шлют данные каждую секунду. На карте обновлять маркер 60 раз в минуту избыточно.

**Стратегия:** WebSocket Service троттлит позиции:
- Максимум **1 обновление в секунду** на устройство для room `org:{id}`
- Максимум **2 обновления в секунду** для room `device:{id}` (фокус на конкретном устройстве)
- **События** (геозоны, алерты) — **без троттлинга**, доставляются немедленно

```scala
// Throttle: хранить timestamp последней отправки на устройство в комнату
val lastSentRef: Ref[Map[(DeviceId, RoomId), Instant]]

def shouldSend(deviceId: DeviceId, room: RoomId, now: Instant): Boolean = {
  val key = (deviceId, room)
  val lastSent = lastSentMap.getOrElse(key, Instant.MIN)
  now.toEpochMilli - lastSent.toEpochMilli >= 1000 // 1 секунда
}
```

---

## 5. Frontend: WebSocket → Карта Leaflet

### Архитектура фронтенда (real-time часть)

```mermaid
flowchart LR
    subgraph WS["WebSocket Layer"]
        WSClient["WebSocket Client\n(auto-reconnect)"]
        WSParser["Message Parser\n(JSON.parse)"]
    end

    subgraph State["State Management"]
        DevStore["Zustand:\ndevicesStore\n{deviceId → DeviceState}"]
        AlertStore["Zustand:\nalertsStore\n{alerts[]}"]
    end

    subgraph Map["Leaflet Map"]
        MarkerLayer["Marker Layer\n(React-Leaflet Marker)"]
        PopupLayer["Popup / Tooltip\n(speed, time)"]
        RotateIcon["Rotated Marker\n(course direction)"]
        TrailLine["Polyline Trail\n(последние N точек)"]
    end

    subgraph UI["UI Panels"]
        DevicePanel["Device Panel\n(sidebar)"]
        SpeedGauge["Speed Badge"]
        StatusDot["Online/Offline dot"]
    end

    WSClient --> WSParser
    WSParser --> |position| DevStore
    WSParser --> |alert| AlertStore
    
    DevStore --> MarkerLayer & PopupLayer & RotateIcon & TrailLine
    DevStore --> DevicePanel & SpeedGauge & StatusDot
    AlertStore --> UI
```

### React код: useWebSocket hook

```typescript
// hooks/useWebSocket.ts
import { useEffect, useRef, useCallback } from 'react';
import { useAuthStore } from '../stores/authStore';
import { useDevicesStore } from '../stores/devicesStore';
import { useAlertsStore } from '../stores/alertsStore';

interface WsMessage {
  type: 'position' | 'geozone_event' | 'alert' | 'connection_status' | 'pong' | 'subscribed';
  deviceId?: number;
  data?: unknown;
}

export function useWebSocket(orgId: number) {
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimer = useRef<ReturnType<typeof setTimeout>>();
  const token = useAuthStore(s => s.accessToken);
  const updatePosition = useDevicesStore(s => s.updatePosition);
  const updateStatus = useDevicesStore(s => s.updateStatus);
  const addAlert = useAlertsStore(s => s.addAlert);

  const connect = useCallback(() => {
    if (!token) return;
    
    const ws = new WebSocket(`wss://ws.wayrecall.com/ws?token=${token}`);
    wsRef.current = ws;

    ws.onopen = () => {
      // Подписка на все устройства организации
      ws.send(JSON.stringify({ type: 'subscribe', channel: `org:${orgId}` }));
      // Подписка на алерты
      ws.send(JSON.stringify({ type: 'subscribe', channel: `alerts:${orgId}` }));
    };

    ws.onmessage = (event) => {
      const msg: WsMessage = JSON.parse(event.data);

      switch (msg.type) {
        case 'position':
          // Обновить позицию устройства в Zustand store
          updatePosition(msg.deviceId!, msg.data as PositionData);
          break;
        case 'connection_status':
          updateStatus(msg.deviceId!, msg.data as StatusData);
          break;
        case 'alert':
        case 'geozone_event':
          addAlert(msg.data as AlertData);
          break;
        case 'pong':
          break; // heartbeat response
      }
    };

    ws.onclose = () => {
      // Экспоненциальный reconnect: 1s, 2s, 4s, 8s, max 30s
      reconnectTimer.current = setTimeout(connect, getBackoffDelay());
    };

    ws.onerror = () => ws.close();
  }, [token, orgId]);

  // Heartbeat: ping каждые 25 секунд
  useEffect(() => {
    const interval = setInterval(() => {
      if (wsRef.current?.readyState === WebSocket.OPEN) {
        wsRef.current.send(JSON.stringify({ type: 'ping' }));
      }
    }, 25_000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    connect();
    return () => {
      clearTimeout(reconnectTimer.current);
      wsRef.current?.close();
    };
  }, [connect]);

  return wsRef;
}
```

### Zustand Store: позиции устройств

```typescript
// stores/devicesStore.ts
import { create } from 'zustand';

interface PositionData {
  lat: number;
  lon: number;
  speed: number;
  course: number;
  altitude: number;
  satellites: number;
  timestamp: string;
  ignition: boolean;
}

interface DeviceState {
  deviceId: number;
  name: string;
  imei: string;
  position: PositionData | null;
  isOnline: boolean;
  lastUpdate: string | null;
  // Trail — последние N точек для отрисовки хвоста
  trail: [number, number][]; // [lat, lon][]
}

interface DevicesStore {
  devices: Map<number, DeviceState>;
  
  // Начальная загрузка (REST)
  setDevices: (devices: DeviceState[]) => void;
  
  // Real-time обновление (WebSocket)
  updatePosition: (deviceId: number, pos: PositionData) => void;
  updateStatus: (deviceId: number, status: { isOnline: boolean }) => void;
}

const MAX_TRAIL_POINTS = 20; // Последние 20 точек на карте

export const useDevicesStore = create<DevicesStore>((set) => ({
  devices: new Map(),

  setDevices: (devices) => set({
    devices: new Map(devices.map(d => [d.deviceId, d]))
  }),

  updatePosition: (deviceId, pos) => set((state) => {
    const device = state.devices.get(deviceId);
    if (!device) return state;

    const newTrail = [...device.trail, [pos.lat, pos.lon] as [number, number]]
      .slice(-MAX_TRAIL_POINTS); // Ограничиваем хвост

    const newDevice: DeviceState = {
      ...device,
      position: pos,
      isOnline: true,
      lastUpdate: pos.timestamp,
      trail: newTrail,
    };

    const newMap = new Map(state.devices);
    newMap.set(deviceId, newDevice);
    return { devices: newMap };
  }),

  updateStatus: (deviceId, status) => set((state) => {
    const device = state.devices.get(deviceId);
    if (!device) return state;
    
    const newMap = new Map(state.devices);
    newMap.set(deviceId, { ...device, isOnline: status.isOnline });
    return { devices: newMap };
  }),
}));
```

### Leaflet: Компонент карты с маркерами

```tsx
// components/map/VehicleMarkers.tsx
import { Marker, Popup, Polyline, useMap } from 'react-leaflet';
import { useDevicesStore } from '../../stores/devicesStore';
import { useMemo } from 'react';
import L from 'leaflet';

// Иконка с поворотом по курсу
function createVehicleIcon(course: number, isOnline: boolean, speed: number) {
  const color = !isOnline ? '#999' : speed > 0 ? '#22c55e' : '#3b82f6';
  
  return L.divIcon({
    className: 'vehicle-marker',
    html: `
      <div style="transform: rotate(${course}deg)">
        <svg width="24" height="24" viewBox="0 0 24 24">
          <path d="M12 2 L8 22 L12 18 L16 22 Z" fill="${color}" stroke="#fff" stroke-width="1.5"/>
        </svg>
      </div>
    `,
    iconSize: [24, 24],
    iconAnchor: [12, 12],
  });
}

export function VehicleMarkers() {
  const devices = useDevicesStore(s => s.devices);
  
  // Мемоизация: пересоздаём массив только при изменении positions
  const markers = useMemo(() => {
    const result: JSX.Element[] = [];
    
    devices.forEach((device) => {
      if (!device.position) return;
      const { lat, lon, speed, course } = device.position;
      
      result.push(
        <Marker
          key={device.deviceId}
          position={[lat, lon]}
          icon={createVehicleIcon(course, device.isOnline, speed)}
        >
          <Popup>
            <b>{device.name}</b><br/>
            Скорость: {speed.toFixed(1)} км/ч<br/>
            Курс: {course}°<br/>
            Спутники: {device.position.satellites}<br/>
            {new Date(device.position.timestamp).toLocaleTimeString()}
          </Popup>
        </Marker>
      );
      
      // Хвост (trail) — последние точки
      if (device.trail.length > 1) {
        result.push(
          <Polyline
            key={`trail-${device.deviceId}`}
            positions={device.trail}
            color={device.isOnline ? '#3b82f6' : '#999'}
            weight={2}
            opacity={0.6}
          />
        );
      }
    });
    
    return result;
  }, [devices]);
  
  return <>{markers}</>;
}
```

### Визуализация: что видит пользователь

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WayRecall Tracker    [🔍 Поиск...]              🔔 3  👤 Admin   ⚙️      │
├────────────────┬────────────────────────────────────────────────────────────┤
│                │                                                            │
│ 📋 Устройства │              ┌─────────────────────────┐                   │
│                │              │       КАРТА (Leaflet)    │                   │
│ ● Камаз 001   │              │                          │                   │
│   45 км/ч ▶   │              │    ▲ Камаз 001           │                   │
│   14:30:15     │              │    │ (45 км/ч, курс 180°)│                   │
│                │              │    │ trail ···            │                   │
│ ● Газель 015  │              │    │                      │                   │
│   0 км/ч ■    │              │                ◀ Газель   │                   │
│   14:28:42     │              │               (стоит)    │                   │
│                │              │                          │                   │
│ ○ МАЗ 042     │              │       [геозона А]        │                   │
│   offline      │              │       ╭─────────╮        │                   │
│   13:15:00     │              │       │  склад  │        │                   │
│                │              │       ╰─────────╯        │                   │
│                │              │                          │                   │
│ Всего: 3      │              └─────────────────────────┘                   │
│ Online: 2     │                                                            │
│ Offline: 1    │  ─────────────────────────────────                         │
│                │  🔔 14:29:01 Камаз 001 — покинул геозону "Склад"          │
│                │  🔔 14:25:33 Газель 015 — превышение 82 км/ч              │
├────────────────┴────────────────────────────────────────────────────────────┤
│  ● Online: 2   ○ Offline: 1   📡 WS: Connected   ⏱ Last: 0.1s ago        │
└─────────────────────────────────────────────────────────────────────────────┘

Легенда маркеров:
  ▲  — движется (зелёный, повёрнут по курсу)
  ■  — стоит (синий)
  ●  — онлайн
  ○  — офлайн (серый)
  ── — trail (хвост последних 20 точек)
```

---

## 6. Первоначальная загрузка (Initial Load)

При открытии карты нужно **сразу** показать все устройства. WebSocket даёт только **обновления**, а начальные позиции — через REST.

### Sequence Diagram: Initial Load + Real-time

```mermaid
sequenceDiagram
    participant B as 🌐 Browser
    participant GW as API Gateway :8080
    participant DM as Device Manager
    participant R as Redis
    participant WS as WebSocket Service :8081
    participant K as Kafka

    Note over B: Пользователь открывает карту

    B->>GW: GET /api/v1/devices?org_id=123
    GW->>DM: GET /devices?org_id=123
    DM-->>GW: [{id:456, name:"Камаз", imei:"352..."}]
    GW-->>B: Список устройств

    B->>GW: GET /api/v1/devices/positions?org_id=123
    GW->>DM: GET /devices/positions?org_id=123
    DM->>R: MGET pos:352... pos:861... pos:353...
    R-->>DM: [{lat,lon,speed,...}, {lat,lon,...}, null]
    DM-->>GW: [{deviceId:456, lat:55.75, lon:37.62, speed:45, ...}, ...]
    GW-->>B: Массив последних позиций

    Note over B: Отрисовать все маркеры на карте (initial state)

    B->>WS: ws://ws.wayrecall.com/ws?token=JWT
    WS-->>B: Connected ✓
    B->>WS: {"type":"subscribe","channel":"org:123"}
    WS-->>B: {"type":"subscribed","channel":"org:123"}

    Note over B,K: Теперь позиции обновляются через WebSocket

    loop Каждые 1-60 секунд (зависит от интервала трекера)
        K->>WS: GPS event (device 456)
        WS->>B: {"type":"position","deviceId":456,"data":{...}}
        B->>B: updatePosition(456, data) → moveMarker()
    end
```

### Код Initial Load

```typescript
// pages/MapPage.tsx
import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { MapContainer, TileLayer } from 'react-leaflet';
import { VehicleMarkers } from '../components/map/VehicleMarkers';
import { useWebSocket } from '../hooks/useWebSocket';
import { useDevicesStore } from '../stores/devicesStore';
import { useAuthStore } from '../stores/authStore';
import { api } from '../api/client';

export function MapPage() {
  const orgId = useAuthStore(s => s.user?.organizationId);
  const setDevices = useDevicesStore(s => s.setDevices);

  // 1. Загрузить список устройств
  const { data: devices } = useQuery({
    queryKey: ['devices', orgId],
    queryFn: () => api.get(`/api/v1/devices?org_id=${orgId}`),
    staleTime: 60_000, // Кэш 1 минуту
  });

  // 2. Загрузить последние позиции (bulk)
  const { data: positions } = useQuery({
    queryKey: ['positions', orgId],
    queryFn: () => api.get(`/api/v1/devices/positions?org_id=${orgId}`),
    staleTime: 10_000, // Кэш 10 секунд
  });

  // 3. Объединить devices + positions → store
  useEffect(() => {
    if (devices && positions) {
      const merged = devices.map((d: any) => ({
        ...d,
        position: positions.find((p: any) => p.deviceId === d.id)?.data ?? null,
        isOnline: positions.some((p: any) => p.deviceId === d.id),
        trail: [],
      }));
      setDevices(merged);
    }
  }, [devices, positions]);

  // 4. Подключить WebSocket для real-time обновлений
  useWebSocket(orgId!);

  return (
    <MapContainer center={[55.75, 37.62]} zoom={10} style={{ height: '100%' }}>
      <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
      <VehicleMarkers />
    </MapContainer>
  );
}
```

---

## 7. Масштабирование и производительность

### Расчёт нагрузки

| Параметр | Значение |
|----------|----------|
| Максимум устройств | 20 000 |
| Средний интервал отправки | 10 секунд |
| GPS events/sec в Kafka | ~2 000 |
| WS Service consume rate | ~2 000 msg/sec |
| Среднее кол-во WS-подключений | ~500 (диспетчеры) |
| Среднее устройств на организацию | 50 |
| Updates per WS connection/sec | ~5 (50 устройств / 10 сек) |

### Горизонтальное масштабирование WS Service

```mermaid
flowchart LR
    subgraph LB["Load Balancer (Nginx)"]
        NX["Sticky Sessions\n(по user_id cookie)"]
    end

    subgraph WS1["WS Node 1"]
        C1["200 connections"]
        R1["Rooms: org:1..50"]
    end
    
    subgraph WS2["WS Node 2"]
        C2["200 connections"]
        R2["Rooms: org:51..100"]
    end
    
    subgraph WS3["WS Node 3"]
        C3["100 connections"]
        R3["Rooms: org:101..150"]
    end

    subgraph Cross["Cross-node broadcast"]
        Redis["Redis Pub/Sub\nws:broadcast:org:{id}"]
    end

    NX --> WS1 & WS2 & WS3
    
    WS1 & WS2 & WS3 <--> Redis
```

**Как работает cross-node broadcast:**

1. WS Node 1 получает GPS event для org:75
2. org:75 имеет подписчиков на Node 1 и Node 2
3. Node 1 отправляет своим локальным подписчикам напрямую
4. Node 1 публикует в Redis Pub/Sub `ws:broadcast:org:75`
5. Node 2 получает из Redis → отправляет своим локальным подписчикам

### Kafka Consumer: параллелизм

```
Топик gps-events: 12 партиций
Consumer group ws-positions: 3 инстанса WS Service
→ Каждый инстанс обрабатывает 4 партиции
→ ~660 msg/sec на инстанс
```

---

## 8. Обработка отключений

### State Diagram: WebSocket Connection

```mermaid
stateDiagram-v2
    [*] --> Disconnected

    Disconnected --> Connecting: open()
    Connecting --> Connected: onopen
    Connecting --> Reconnecting: onerror/onclose

    Connected --> Subscribing: send subscribe
    Subscribing --> Active: "subscribed" received
    Subscribing --> Reconnecting: onclose

    Active --> Active: position/event messages
    Active --> Reconnecting: onclose/onerror

    Reconnecting --> Connecting: backoff timer expires
    Reconnecting --> Disconnected: max retries exceeded

    state Reconnecting {
        [*] --> Wait1s
        Wait1s --> Wait2s: retry failed
        Wait2s --> Wait4s: retry failed
        Wait4s --> Wait8s: retry failed
        Wait8s --> Wait16s: retry failed
        Wait16s --> Wait30s: retry failed
        Wait30s --> Wait30s: retry failed (cap)
    }
```

### Сценарии отключения

| Сценарий | Что происходит | Восстановление |
|----------|---------------|----------------|
| **Браузер закрыл** | WS close → очистка rooms | — |
| **Сеть пропала** | onclose через 30-60с | Reconnect с backoff |
| **WS Service рестарт** | Все connections разрываются | Клиент reconnect → re-subscribe → re-fetch positions |
| **JWT expired** | WS Service закрывает с code 4001 | Клиент refresh token → reconnect |
| **Kafka lag** | Позиции задерживаются | Отображается индикатор задержки "⏱ lag: 5s" |

### Гарантии при reconnect

```typescript
// При переподключении:
// 1. Re-subscribe на org и alert rooms
// 2. Запросить последние позиции через REST (для синхронизации пропущенных обновлений)
// 3. Показать пользователю "Соединение восстановлено"

ws.onopen = async () => {
  // Re-subscribe
  ws.send(JSON.stringify({ type: 'subscribe', channel: `org:${orgId}` }));
  ws.send(JSON.stringify({ type: 'subscribe', channel: `alerts:${orgId}` }));
  
  // Синхронизация — перезагружаем все позиции
  const freshPositions = await api.get(`/api/v1/devices/positions?org_id=${orgId}`);
  updateAllPositions(freshPositions);
  
  showToast('Соединение восстановлено', 'success');
};
```

---

## 9. Протокол сообщений

### Client → Server

```typescript
// Подписка на канал
{ "type": "subscribe", "channel": "org:123" }
{ "type": "subscribe", "channel": "device:456" }
{ "type": "subscribe", "channel": "alerts:123" }

// Отписка
{ "type": "unsubscribe", "channel": "org:123" }

// Heartbeat
{ "type": "ping" }
```

### Server → Client

```typescript
// Подтверждение подписки
{ "type": "subscribed", "channel": "org:123" }

// 📍 Позиция устройства
{
  "type": "position",
  "deviceId": 456,
  "data": {
    "lat": 55.755826,
    "lon": 37.617300,
    "speed": 45.2,
    "course": 180,
    "altitude": 156.0,
    "satellites": 12,
    "timestamp": "2026-06-02T14:30:15.123Z",
    "ignition": true
  }
}

// 📍 Событие геозоны
{
  "type": "geozone_event",
  "deviceId": 456,
  "data": {
    "eventType": "LEAVE",
    "geozoneName": "Склад",
    "geozoneId": 789,
    "timestamp": "2026-06-02T14:29:01.000Z",
    "lat": 55.755826,
    "lon": 37.617300
  }
}

// 🚨 Алерт (скорость, датчик, ТО)
{
  "type": "alert",
  "deviceId": 456,
  "data": {
    "alertType": "SPEED_VIOLATION",
    "message": "Превышение скорости: 82 км/ч (лимит 60)",
    "severity": "WARNING",
    "timestamp": "2026-06-02T14:25:33.000Z"
  }
}

// 🔌 Статус подключения
{
  "type": "connection_status",
  "deviceId": 456,
  "data": {
    "isOnline": false,
    "lastSeen": "2026-06-02T14:30:15.123Z"
  }
}

// Heartbeat ответ
{ "type": "pong" }

// Ошибка
{ "type": "error", "message": "Unauthorized", "code": 4001 }
```

---

## 10. Диаграммы всех сценариев

### Сценарий 1: Пользователь открывает карту

```mermaid
sequenceDiagram
    actor U as 👤 Диспетчер
    participant B as Browser
    participant GW as API Gateway
    participant DM as Device Manager
    participant R as Redis
    participant WS as WebSocket Service

    U->>B: Открывает /map
    B->>GW: GET /api/v1/devices?org_id=123
    GW->>DM: GET /devices?org_id=123
    DM-->>B: 50 устройств

    B->>GW: GET /api/v1/devices/positions?org_id=123
    GW->>DM: GET /positions bulk
    DM->>R: MGET pos:{imei1} pos:{imei2} ... pos:{imei50}
    R-->>DM: 48 позиций (2 устройства офлайн > 1ч — TTL expired)
    DM-->>B: 48 позиций

    B->>B: Отрисовать 48 маркеров + 2 серых (offline)
    B->>WS: ws://... connect + subscribe org:123
    
    Note over B: Карта готова за ~300ms
```

### Сценарий 2: Трекер появляется онлайн

```mermaid
sequenceDiagram
    participant T as 🛰️ Трекер (был offline)
    participant CM as Connection Manager
    participant K as Kafka
    participant WS as WebSocket Service
    participant B as 🌐 Browser

    T->>CM: TCP SYN → Handshake
    CM->>CM: IMEI auth → deviceId=456, orgId=123
    CM->>K: Publish device-status: {deviceId:456, status:"ONLINE"}
    
    K->>WS: Consume device-status
    WS->>B: {"type":"connection_status","deviceId":456,"data":{"isOnline":true}}
    B->>B: Маркер: серый → синий, sidebar: "● online"

    T->>CM: GPS пакет
    CM->>K: Publish gps-events
    K->>WS: Consume → route
    WS->>B: {"type":"position","deviceId":456,"data":{...}}
    B->>B: Маркер: показать позицию + зелёный (движется)
```

### Сценарий 3: Массовая подписка (50+ устройств)

```mermaid
flowchart TB
    subgraph Frontend
        MapPage["MapPage.tsx"]
        Hook["useWebSocket(orgId=123)"]
        Store["devicesStore\n50 devices"]
        Leaflet["Leaflet Map\n50 Markers"]
    end

    subgraph WSService["WS Service"]
        Room["Room: org:123\n1 connection (этот browser)"]
        Router["Message Router"]
    end

    subgraph Kafka
        Part1["Partition 0: devices 1-200"]
        Part2["Partition 1: devices 201-400"]
        Part3["Partition 2: devices 401-600"]
    end

    Part1 & Part2 & Part3 --> Router
    Router --> Room --> Hook
    Hook --> Store --> Leaflet

    Note1["~5 updates/sec\n(50 devices × 1/10sec)"]
```

---

## 11. Оптимизации

### 11.1 Batch updates (frontend)

Вместо обновления маркера на каждое WS-сообщение, собираем обновления в micro-batch:

```typescript
// Буферизация обновлений 100ms
const pendingUpdates = new Map<number, PositionData>();
let flushTimer: ReturnType<typeof setTimeout> | null = null;

function onWsMessage(msg: WsMessage) {
  if (msg.type === 'position') {
    pendingUpdates.set(msg.deviceId!, msg.data as PositionData);
    
    if (!flushTimer) {
      flushTimer = setTimeout(() => {
        // Один batch React re-render вместо N отдельных
        batchUpdatePositions(pendingUpdates);
        pendingUpdates.clear();
        flushTimer = null;
      }, 100); // 100ms = 10 FPS обновлений карты (достаточно для глаза)
    }
  }
}
```

### 11.2 Viewport filtering (отправлять только видимые)

Если пользователь увеличил карту — нет смысла отправлять позиции устройств вне видимой области:

```typescript
// Client сообщает серверу текущий viewport
ws.send(JSON.stringify({
  type: 'viewport',
  bounds: {
    north: 55.82,
    south: 55.70,
    east: 37.75,
    west: 37.50
  }
}));

// WS Service фильтрует: отправляет position только если
// point внутри bounds клиента
// → Снижает трафик для организаций с 1000+ устройств
```

**Примечание:** viewport filtering — оптимизация Phase 2. В MVP отправляем все позиции org.

### 11.3 Delta encoding

Для экономии трафика — отправлять только изменившиеся поля:

```json
// Полное обновление (первое после подписки)
{"type":"position","deviceId":456,"full":true,"data":{"lat":55.75,"lon":37.62,"speed":45,"course":180,"alt":156,"sat":12,"ts":"..."}}

// Delta (следующие обновления)
{"type":"position","deviceId":456,"data":{"lat":55.76,"lon":37.63,"speed":48,"ts":"..."}}
// course, alt, sat не изменились — не отправляем
```

**Примечание:** delta encoding — оптимизация Phase 3.

### 11.4 Leaflet: Canvas renderer

Для 500+ маркеров стандартный SVG renderer тормозит. Используем Canvas:

```typescript
<MapContainer
  center={[55.75, 37.62]}
  zoom={10}
  preferCanvas={true}  // Canvas вместо SVG для маркеров
>
```

---

## 12. Сравнение с Legacy Stels

| Аспект | Legacy Stels | Wayrecall Tracker |
|--------|-------------|-------------------|
| **Транспорт** | Long polling (HTTP, 2 сек) | WebSocket (persistent) |
| **Задержка** | 2-4 секунды | < 150ms (p99) |
| **Трафик** | Полный JSON каждые 2 сек | Только delta при изменении |
| **Масштаб** | ~1000 устройств | 20 000+ |
| **Reconnect** | Страница перезагружается | Автоматический с backoff |
| **Маршрутизация** | Все объекты в одном запросе | Room-based (org, device, alerts) |
| **Фронтенд** | ExtJS 4.2 + OpenLayers | React 19 + Leaflet |
| **Обновление карты** | Перерисовка всех маркеров | Точечное обновление одного маркера |
| **Офлайн** | Нет индикации | Real-time статус online/offline |
| **Trail** | Нет | Хвост последних 20 точек |

### Legacy API: Real-time (для справки)

```javascript
// Legacy: polling каждые 2 секунды
setInterval(() => {
  Ext.Direct.MapObjects.getUpdatedAfter(lastTimestamp, function(result) {
    // result = все объекты с обновлёнными позициями
    // Перерисовать ВСЕ маркеры на OpenLayers
    updateAllMarkers(result);
    lastTimestamp = Date.now();
  });
}, 2000);
```

### Новый подход: WebSocket

```typescript
// Новый: WebSocket + точечные обновления
useWebSocket(orgId); // Один раз подключился

// Zustand store автоматически обновляет только изменившийся маркер
// React re-render только для одного компонента Marker
// Leaflet: marker.setLatLng() — O(1) операция
```

---

## Итог

### Полный путь GPS-пакета: от спутника до пикселя на карте

```
🛰️ Спутник → 📡 GPS Трекер → 🔌 TCP:5001 → Connection Manager
  → Parse (5ms) → Filter (2ms) → Publish Kafka (10ms)
  → WebSocket Service consume (20ms) → Route to room (1ms)
  → WS frame → Network (20ms) → Browser
  → Zustand store.updatePosition → React re-render → Leaflet.setLatLng
  
  ИТОГО: < 100ms (идеально) / < 150ms (p99)
```

Ключевые технологические решения:
1. **WebSocket** вместо polling — экономия трафика, снижение задержки в 20x
2. **Kafka** как шина + **Redis** для initial load — разделение потоковых и snapshot данных
3. **Room-based routing** — подписка по организации или устройству
4. **Throttling** на WS Service — не более 1 msg/sec на устройство
5. **Zustand + React-Leaflet** — точечные обновления DOM, без перерисовки всей карты
6. **Canvas renderer** — производительность для 500+ маркеров

---

*Связанные документы:*
- [ARCHITECTURE_BLOCK1.md](./blocks/ARCHITECTURE_BLOCK1.md) — Connection Manager, парсинг GPS
- [ARCHITECTURE_BLOCK3.md](./blocks/ARCHITECTURE_BLOCK3.md) — WebSocket Service, Frontend
- [CONNECTION_MANAGER.md](./services/CONNECTION_MANAGER.md) — TCP, протоколы
