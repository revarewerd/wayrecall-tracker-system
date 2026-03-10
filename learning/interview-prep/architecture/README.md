# 🏗️ Архитектурные задачи для собеседований

> System Design Interview — проектирование распределённых систем.

## Прогресс

| # | Задача | Тема | Релевантность | Статус |
|---|--------|------|---------------|--------|
| 1 | Design GPS Tracking System | IoT, Real-time | 🔴 Наш проект! | ⬜ |
| 2 | Design Notification System | Pub/Sub, Queue | 🔴 Notification Service | ⬜ |
| 3 | Design Rate Limiter | Algorithm, Redis | 🔴 API Gateway | ⬜ |
| 4 | Design Chat Application | WebSocket, MQ | 🟡 WebSocket Service | ⬜ |
| 5 | Design URL Shortener | Storage, Hashing | 🟢 Классика | ⬜ |
| 6 | Design Twitter/News Feed | Fan-out, Cache | 🟢 Классика | ⬜ |
| 7 | Design Video Streaming | CDN, Encoding | 🟢 Классика | ⬜ |
| 8 | Design Uber/Ride-sharing | Geo, Real-time | 🔴 Геозоны, карта | ⬜ |
| 9 | Design Monitoring System | Metrics, Alerting | 🟡 Admin Service | ⬜ |
| 10 | Design Event-Driven Arch | Kafka, CQRS | 🔴 Вся система | ⬜ |

## Шаблон ответа (USADR)

```
1. Understand — уточняющие вопросы (5 мин)
2. Scope — определить границы (2 мин)
3. API Design — основные endpoints (3 мин)
4. Data Model — схема БД / хранилищ (5 мин)
5. High-Level Design — диаграмма компонентов (10 мин)
6. Deep Dive — масштабирование, edge cases (10 мин)
7. Review — подведение итогов (5 мин)
```

## Паттерны проектирования для IoT/GPS

| Паттерн | Описание | Где у нас |
|---------|----------|-----------|
| Event Sourcing | Все изменения как события | Kafka как event log |
| CQRS | Разделение чтения и записи | HW (write) vs DM (read) |
| Saga | Распределённые транзакции | Command → Execute → Confirm |
| Circuit Breaker | Защита от каскадных сбоев | Integration Service |
| Bulkhead | Изоляция ресурсов | Отдельные пулы по протоколам |
| Sidecar | Вспомогательный контейнер | Мониторинг, логирование |
| Gateway | Единая точка входа | API Gateway |
| Consumer Group | Масштабируемое потребление | Kafka consumers |

---

*Обновлён по мере решения задач*
