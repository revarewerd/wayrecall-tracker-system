# 🎯 Подготовка к собеседованиям

> Тег: `АКТУАЛЬНО` | Обновлён: `2026-06-06` | Версия: `1.0`

## Структура

```
interview-prep/
├── README.md                    # ← этот файл
├── algorithms/                  # Алгоритмические задачи на Scala
│   ├── README.md               # Каталог задач, прогресс
│   ├── easy/                   # LeetCode Easy
│   ├── medium/                 # LeetCode Medium
│   └── hard/                   # LeetCode Hard
├── architecture/               # Архитектурные вопросы
│   ├── README.md               # Каталог тем
│   ├── system-design/          # System Design Interview
│   └── patterns/               # Паттерны проектирования
├── scala-fp/                   # Вопросы по Scala и ФП
│   ├── README.md               # Типовые вопросы на собесах
│   └── exercises/              # Практические задачи
└── behavioral/                 # Поведенческие вопросы
    └── README.md               # STAR метод, примеры ответов
```

## Ресурсы для подготовки

### Алгоритмы

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **LeetCode** | Практика | [leetcode.com](https://leetcode.com/) |
| **NeetCode 150** | Roadmap | [neetcode.io](https://neetcode.io/) |
| **Grokking Algorithms** | Книга | [Manning](https://www.manning.com/books/grokking-algorithms) |
| **CLRS (Introduction to Algorithms)** | Книга | [MIT Press](https://mitpress.mit.edu/9780262046305/) |

### System Design

| Ресурс | Тип | Ссылка |
|--------|-----|--------|
| **System Design Interview (Alex Xu)** | Книга | Vol 1 + Vol 2 |
| **Designing Data-Intensive Apps (Kleppmann)** | Книга | [O'Reilly](https://www.oreilly.com/library/view/designing-data-intensive-applications/9781491903063/) |
| **ByteByteGo** | YouTube | [youtube.com/@ByteByteGo](https://www.youtube.com/@ByteByteGo) |
| **System Design Primer** | GitHub | [donnemartin/system-design-primer](https://github.com/donnemartin/system-design-primer) |

### Scala-специфичные вопросы

| Тема | Что спрашивают |
|------|---------------|
| Immutability | Зачем? val vs var, persistent data structures |
| Pattern matching | Exhaustive, sealed traits, extractors |
| Higher-order functions | map/flatMap/filter, for-comprehension |
| Implicits / Givens | Как работает, когда применять |
| Type classes | Паттерн, примеры (Show, Eq, Codec) |
| ZIO | ZLayer, Fiber, error handling, Schedule |
| Cats | Monad, Functor, Traverse, EitherT |
| Concurrency | Fiber vs Thread, Ref, STM, Promise |
| Streams | ZIO Streams vs fs2, backpressure |

## План подготовки

### Фаза 1: Алгоритмы (4-6 недель)

```
Неделя 1-2: Массивы, строки, хеш-таблицы (15 задач)
Неделя 3:   Linked lists, стеки, очереди (10 задач)
Неделя 4:   Деревья, графы (10 задач)
Неделя 5:   DP (Dynamic Programming) (10 задач)
Неделя 6:   Сортировки, бинарный поиск (10 задач)
```

**Как решать:** сначала на Scala (идиоматично, с ФП), потом анализ O(n).

### Фаза 2: System Design (3-4 недели)

```
Неделя 1: Основы — CAP, шардинг, репликация, кэширование
Неделя 2: Дизайн систем — URL shortener, Twitter, Chat
Неделя 3: Real-time системы — GPS tracking (наш проект!), IoT
Неделя 4: Микросервисы — event-driven, CQRS, saga
```

### Фаза 3: Scala/FP Deep Dive (2-3 недели)

```
Неделя 1: Core Scala — ADT, pattern matching, type classes
Неделя 2: ZIO — layers, fibers, error handling, streams
Неделя 3: Практика — live coding, pair programming simulate
```

---

*Версия: 1.0 | Обновлён: 6 июня 2026 | Тег: АКТУАЛЬНО*
