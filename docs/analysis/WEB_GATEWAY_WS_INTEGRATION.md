# Интеграция: Web Frontend + API Gateway + WebSocket Service

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-03-03` | Версия: `1.0`

## Обзор

Три сервиса образуют **презентационный слой** (Block 3) системы Wayrecall Tracker:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Браузер (React SPA)                          │
│                                                                 │
│  ┌─────────────┐  ┌───────────────────┐  ┌──────────────────┐  │
│  │ API Client  │  │ useWebSocket Hook │  │    Zustand Store  │  │
│  │ (fetch)     │  │ (WebSocket)       │  │    (state mgmt)  │  │
│  └──────┬──────┘  └────────┬──────────┘  └──────────────────┘  │
│         │                  │                                    │
└─────────┼──────────────────┼────────────────────────────────────┘
          │ HTTP             │ WebSocket
          ▼                  ▼
┌──────────────────────────────────────┐
│           nginx (порт 80)            │
│                                      │
│  /api/*  → api-gateway:8080          │
│  /ws/*   → websocket-service:8090    │
│  /*      → index.html (SPA)          │
└────┬──────────────────────┬──────────┘
     │ HTTP                 │ WS Upgrade
     ▼                      ▼
┌────────────┐    ┌──────────────────┐
│ API Gateway│    │ WebSocket Service│
│ :8080      │    │ :8090            │
│            │    │                  │
│ JWT verify │    │ orgId + token    │
│ Route → ↓  │    │ Kafka consumer   │
│ 24 routes  │    │ GPS → WS push   │
│ 13 backends│    │                  │
└────┬───────┘    └──────────────────┘
     │ HTTP прокси
     ▼
┌─────────────────────────────────┐
│ Block 1+2 микросервисы (13 шт) │
│ device-manager, history-writer, │
│ rule-checker, user-service ...  │
└─────────────────────────────────┘
```

## Потоки данных

### 1. REST API запросы (HTTP)

```
Браузер → [POST /api/v1/auth/login] → nginx → API Gateway → AuthService (JWT)
Браузер → [GET /api/v1/devices] → nginx → API Gateway (JWT verify) → device-manager :10092
Браузер → [GET /api/v1/history/telemetry/123] → nginx → API Gateway → history-writer :10091
Браузер → [GET /api/v1/geozones] → nginx → API Gateway → rule-checker :8093
```

**Важно:** Все REST запросы идут через API Gateway, который:
1. Проверяет JWT токен
2. Определяет домен (billing/monitoring) по Origin
3. Обогащает заголовки (X-User-Id, X-Company-Id, X-User-Roles)
4. Проксирует к нужному бэкенду
5. Логирует latency и результат

### 2. WebSocket (real-time GPS)

```
Браузер → [WS Upgrade: /ws?orgId=123&token=jwt] → nginx → WebSocket Service :8090

После подключения:
  Клиент → { type: "SubscribeOrg" }
  Сервер ← { type: "Subscribed", vehicleIds: [1,2,3,4,5] }

  Kafka (gps-events) → WebSocket Service → { type: "GpsPosition", vehicleId: 1, lat: 55.7, lon: 37.6, speed: 60 }
  Kafka (geozone-events) → WebSocket Service → { type: "GeozoneEvent", vehicleId: 1, geozoneId: 5, eventType: "enter" }
```

**Важно:** WS трафик идёт НАПРЯМУЮ к WebSocket Service (минуя API Gateway):
- WebSocket — долгоживущее соединение, не подходит для HTTP-прокси
- Аутентификация через query parameter `token` (JWT)
- nginx добавляет `Upgrade: websocket` и `Connection: upgrade` заголовки

### 3. Аутентификация

```
1. Пользователь вводит email + password
2. POST /api/v1/auth/login → API Gateway → AuthService
3. AuthService проверяет credentials → создаёт JWT
4. JWT возвращается клиенту → сохраняется в localStorage
5. Каждый HTTP запрос содержит: Authorization: Bearer <jwt>
6. WebSocket подключение содержит: ?token=<jwt>
```

## Файловая структура интеграции

### Web Frontend

```
src/
├── api/
│   ├── client.ts          ← HTTP-клиент (fetch + JWT + error handling)
│   └── mock.ts            ← Mock данные (для offline разработки)
├── hooks/
│   └── useWebSocket.ts    ← React-хук для WebSocket (auto-reconnect, ping/pong)
├── store/
│   └── appStore.ts        ← Zustand: vehicles[], geozones[], events[]
└── components/
    ├── MapView.tsx         ← OpenLayers карта (обновляет маркеры по WS)
    └── LeftPanel.tsx       ← Грид объектов (обновляет позиции по WS)
```

### API Gateway

```
src/.../gateway/
├── routing/ApiRouter.scala     ← 24 маршрута → 13 бэкендов
├── config/GatewayConfig.scala  ← ServicesConfig (13 endpoints)
├── middleware/
│   ├── AuthMiddleware.scala    ← JWT verify + X-headers enrichment
│   └── CorsMiddleware.scala    ← Whitelist origins (billing + monitoring)
├── service/
│   ├── ProxyService.scala      ← HTTP прокси к бэкендам
│   └── HealthService.scala     ← Health check 13 бэкендов
└── Main.scala                  ← Startup + DI + route listing
```

### WebSocket Service

```
src/.../websocket/
├── api/WebSocketHandler.scala  ← WS endpoint: /ws?orgId=...
├── consumer/
│   ├── GpsEventConsumer.scala  ← Kafka gps-events → WS push
│   └── EventConsumer.scala     ← Kafka geozone-events → WS push
├── registry/ConnectionRegistry.scala  ← Map[connId → WebSocket]
├── routing/MessageRouter.scala        ← vehicleId → Set[connId]
└── config/AppConfig.scala             ← Kafka + HTTP + throttle
```

## Конфигурация портов

| Компонент | Dev (localhost) | Docker Compose |
|---|---|---|
| Web Frontend (Vite) | :3001 | nginx :80 inside container |
| API Gateway | :8080 | api-gateway:8080 |
| WebSocket Service | :8090 | websocket-service:8090 |
| Device Manager | :10092 | device-manager:10092 |
| History Writer | :10091 | history-writer:10091 |
| Rule Checker | :8093 | rule-checker:8093 |
| Connection Manager | :10090 | connection-manager:10090 |

### Dev режим (localhost)

```bash
# Терминал 1: API Gateway
cd services/API-Gateway && sbt run
# → http://localhost:8080

# Терминал 2: WebSocket Service
cd services/websocket-service && sbt run
# → ws://localhost:8090

# Терминал 3: Device Manager (или другие нужные бэкенды)
cd services/device-manager && sbt run
# → http://localhost:10092

# Терминал 4: Web Frontend (Vite dev server)
cd services/web-frontend && npm run dev
# → http://localhost:3001
# Vite прокси: /api/* → localhost:8080, /ws/* → localhost:8090
```

### Docker Compose

```yaml
# nginx (web-frontend) проксирует:
#   /api/* → api-gateway:8080
#   /ws/*  → websocket-service:8090
#   /*     → SPA (index.html)
```

## Переход с Mock на реальные данные

### Этап 1: Аутентификация (MVP)

В `App.tsx` добавить проверку авторизации:

```tsx
import { isAuthenticated, login } from '@/api/client';

function App() {
  const [authenticated, setAuthenticated] = useState(isAuthenticated());

  if (!authenticated) {
    return <LoginForm onLogin={async (email, pass) => {
      await login(email, pass);
      setAuthenticated(true);
    }} />;
  }

  return <AppLayout />;
}
```

### Этап 2: Загрузка данных вместо mock

В `AppLayout.tsx` или `LeftPanel.tsx`:

```tsx
import { getDevices, getGeozones } from '@/api/client';
import { useQuery } from '@tanstack/react-query';

// Вместо mock данных — реальные запросы через TanStack Query
const { data: devices } = useQuery({
  queryKey: ['devices'],
  queryFn: getDevices,
  refetchInterval: 60_000,  // Рефетч каждую минуту (позиции придут через WS)
});
```

### Этап 3: WebSocket для real-time позиций

В `MapView.tsx`:

```tsx
import { useWebSocket, GpsPositionMessage } from '@/hooks/useWebSocket';

function MapView() {
  const store = useAppStore();

  const { status, subscribeOrg } = useWebSocket('org-uuid', {
    onGpsPosition: (pos: GpsPositionMessage) => {
      // Обновляем позицию ТС в Zustand store
      store.updateVehiclePosition(pos.vehicleId, {
        lat: pos.lat,
        lon: pos.lon,
        speed: pos.speed,
        course: pos.course,
        time: pos.timestamp,
      });
    },
    onGeozoneEvent: (evt) => {
      // Показываем уведомление на карте
      store.addEvent({
        vehicleId: evt.vehicleId,
        eventType: evt.eventType === 'enter' ? 'info' : 'warning',
        message: `${evt.eventType === 'enter' ? 'Вход' : 'Выход'}: ${evt.geozoneName}`,
        timestamp: evt.timestamp,
      });
    },
    onConnected: () => subscribeOrg(),
  });

  return (
    <div>
      <div className="ws-indicator">{status}</div>
      {/* ... OpenLayers карта ... */}
    </div>
  );
}
```

## Текущий статус и TODO

### Готово ✅

- [x] API Gateway: 24 маршрута → 13 бэкендов, JWT, CORS
- [x] WebSocket Service: WS handler, Kafka consumers, 60 тестов
- [x] Web Frontend: React SPA, карта, модальные окна, ExtJS-стиль
- [x] nginx.conf: правильные порты (api-gateway:8080, websocket-service:8090)
- [x] Vite dev proxy: /api → :8080, /ws → :8090
- [x] API Client (client.ts): JWT auth, HTTP methods, error handling
- [x] useWebSocket hook: auto-reconnect, ping/pong, typed messages
- [x] Dockerfile: правильные build-args

### Нужно сделать для полного MVP

- [ ] **LoginForm компонент** — страница логина (email + password)
- [ ] **Подключить TanStack Query** — заменить mock на реальные API вызовы
- [ ] **Подключить useWebSocket** в MapView — обновлять маркеры в реальном времени
- [ ] **updateVehiclePosition action** в Zustand — обновление одного ТС по WS
- [ ] **WebSocket Service: JWT аутентификация** — проверять token в query param (сейчас только orgId)
- [ ] **docker-compose.yml** — добавить web-frontend контейнер с правильными сетями
- [ ] **E2E тест** — запустить все 3 сервиса + отправить GPS пакет → увидеть на карте
