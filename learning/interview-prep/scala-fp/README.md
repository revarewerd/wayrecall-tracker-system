# 🎓 Вопросы по Scala и ФП для собеседований

> Типичные вопросы на Scala/FP позиции с ответами и примерами.

---

## Категория 1: Основы Scala

### Q1: В чём разница между val, var и def?
```scala
val x = 42        // Immutable, вычисляется ОДИН раз при инициализации
var y = 42        // Mutable (НИКОГДА не используем в FP)
def z = 42        // Вычисляется КАЖДЫЙ раз при вызове
lazy val w = 42   // Вычисляется ОДИН раз при ПЕРВОМ обращении
```

### Q2: Что такое case class и чем отличается от обычного class?
- Автоматические `equals`, `hashCode`, `toString`, `copy`
- Pattern matchable
- Companion object с `apply` и `unapply`
- Immutable по умолчанию (val параметры)

### Q3: Что такое sealed trait и зачем?
- Все наследники должны быть в том же файле
- Компилятор проверяет exhaustive matching
- Основа для ADT (Algebraic Data Types)

```scala
sealed trait DomainError
case class DeviceNotFound(id: UUID)     extends DomainError
case class ParseError(msg: String)      extends DomainError
case class Unauthorized(reason: String) extends DomainError
```

### Q4: Opaque types в Scala 3 — зачем?
```scala
// Type safety без runtime overhead
opaque type Imei = String
object Imei:
  def apply(s: String): Imei = s
  extension (i: Imei) def value: String = i
```

---

## Категория 2: ФП концепции

### Q5: Что такое referential transparency?
Выражение referentially transparent если его можно заменить результатом без изменения поведения программы.
```scala
// RT: val x = 2 + 3; (x, x) == (5, 5) ✅
// Не RT: val x = println("hi"); (x, x) — side effect!
```

### Q6: Что такое Monad? (простым языком)
Тип `M[A]` с операциями:
- `pure: A => M[A]` (обернуть значение)
- `flatMap: M[A] => (A => M[B]) => M[B]` (цепочка вычислений)

Примеры: `Option`, `Either`, `List`, `ZIO`, `IO`

Законы:
1. Left identity: `pure(a).flatMap(f) == f(a)`
2. Right identity: `m.flatMap(pure) == m`
3. Associativity: `m.flatMap(f).flatMap(g) == m.flatMap(a => f(a).flatMap(g))`

### Q7: Functor vs Applicative vs Monad?
```
Functor:     map     — преобразовать значение внутри контейнера
Applicative: ap/zip  — комбинировать независимые вычисления
Monad:       flatMap — цепочка ЗАВИСИМЫХ вычислений
```

### Q8: Что такое for-comprehension?
Синтаксический сахар для цепочки flatMap/map:
```scala
// Это:
for {
  a <- getUser(id)
  b <- getDevice(a.deviceId)
  c <- sendCommand(b, cmd)
} yield c

// Эквивалентно:
getUser(id).flatMap(a =>
  getDevice(a.deviceId).flatMap(b =>
    sendCommand(b, cmd).map(c => c)
  )
)
```

---

## Категория 3: ZIO

### Q9: Что означает ZIO[R, E, A]?
- `R` — Environment (зависимости), нужные для выполнения
- `E` — Error type (типизированная ошибка)
- `A` — Success type (результат)

Частные случаи:
- `Task[A]` = `ZIO[Any, Throwable, A]`
- `UIO[A]` = `ZIO[Any, Nothing, A]`
- `IO[E, A]` = `ZIO[Any, E, A]`

### Q10: Как работает ZLayer?
DI через типы:
```scala
// Определение слоя
val live: ZLayer[Database, Nothing, UserService] =
  ZLayer.fromFunction(UserServiceLive(_))

// Сборка приложения
val app = program.provide(
  UserServiceLive.layer,
  DatabaseLive.layer,
  ConfigLive.layer
)
```

### Q11: Fiber vs Thread?
- **Thread:** OS-level, тяжёлый (~1MB стека), ограничен (~10K)
- **Fiber:** ZIO runtime, лёгкий (~200 байт), масштабируется (~1M+)
- Fiber кооперативный (yield при эффектах), Thread — preemptive

### Q12: Как обрабатывать ошибки в ZIO?
```scala
effect
  .mapError(e => DomainError(e))     // преобразовать тип ошибки
  .catchAll(e => fallback)            // обработать все ошибки
  .catchSome { case NotFound => ... } // частичная обработка
  .retry(Schedule.exponential(1.second)) // повторить
  .orDie                              // превратить в defect (panic)
```

---

## Категория 4: Concurrency

### Q13: Как работает Ref в ZIO?
```scala
// Атомарная ссылка (аналог AtomicReference, но функциональная)
for {
  ref <- Ref.make(0)
  _   <- ref.update(_ + 1)  // атомарная модификация
  v   <- ref.get             // чтение
} yield v // 1
```

### Q14: Queue vs Hub в ZIO?
- **Queue:** MPSC/MPMC очередь. Каждое сообщение получает ОДИН consumer.
- **Hub:** Broadcast. Каждое сообщение получают ВСЕ subscribers.

### Q15: Как избежать deadlock в FP?
- Используй `Ref` вместо locks (lock-free)
- `STM` (Software Transactional Memory) для составных операций
- ZIO Fiber автоматически обрабатывает interruption

---

## Категория 5: Практические задачи (Live Coding)

### Задача 1: Реализуй простой LRU Cache на Scala (без var)
### Задача 2: Напиши парсер JSON числа (чисто функционально)
### Задача 3: Реализуй retry с exponential backoff через ZIO Schedule
### Задача 4: Конвертируй callback-based API в ZIO
### Задача 5: Реализуй простой producer/consumer через ZIO Queue

> Решения — в `exercises/` (будем добавлять по мере практики)

---

*Обновлён по мере пополнения вопросов*
