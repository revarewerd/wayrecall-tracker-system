# Модуль 7: Netty TCP — сетевой уровень

> 📁 Файлы: `TcpServer.scala`, `ConnectionHandler.scala`, `RateLimiter.scala`

---

## 7.1 Зачем Netty?

GPS трекеры общаются по **бинарному TCP** протоколу. HTTP тут не подходит — нужен raw TCP.

**Netty** — это Java-фреймворк для высокопроизводительных сетевых приложений:
- Обрабатывает 10,000+ одновременных TCP соединений
- Non-blocking I/O (NIO) — один поток на тысячи соединений
- Pipeline архитектура — цепочка обработчиков

---

## 7.2 Архитектура Netty

```
                    ┌─────────────────────────┐
                    │     Boss EventLoop       │
                    │  (принимает соединения)  │
                    └──────────┬──────────────┘
                               │ accept
           ┌───────────────────┼───────────────────┐
           ↓                   ↓                   ↓
   Worker EventLoop    Worker EventLoop    Worker EventLoop
   (чтение/запись)     (чтение/запись)     (чтение/запись)
           ↓                   ↓                   ↓
    ┌──────────┐       ┌──────────┐       ┌──────────┐
    │ Pipeline │       │ Pipeline │       │ Pipeline │
    │ Handler1 │       │ Handler1 │       │ Handler1 │
    │ Handler2 │       │ Handler2 │       │ Handler2 │
    │ Handler3 │       │ Handler3 │       │ Handler3 │
    └──────────┘       └──────────┘       └──────────┘
```

- **Boss** — принимает новые TCP соединения (1-2 потока)
- **Worker** — обрабатывает данные (число потоков = CPU cores)
- **Pipeline** — цепочка обработчиков для каждого соединения

---

## 7.3 TcpServer.scala — запуск сервера

```scala
override def start(port: Int, handlerFactory: () => ChannelHandler): Task[Channel] =
  ZIO.asyncZIO { callback =>
    ZIO.attempt {
      val bootstrap = new ServerBootstrap()
      bootstrap.group(bossGroup, workerGroup)
        .channel(classOf[NioServerSocketChannel])
        .option(ChannelOption.SO_BACKLOG, Integer.valueOf(config.maxConnections))
        .childOption(ChannelOption.SO_KEEPALIVE, java.lang.Boolean.TRUE)
        .childOption(ChannelOption.TCP_NODELAY, java.lang.Boolean.TRUE)
        .childHandler(new ChannelInitializer[SocketChannel] {
          override def initChannel(ch: SocketChannel): Unit =
            val pipeline = ch.pipeline()
            pipeline.addLast("rateLimiter", new RateLimitHandler(limiter, runtime))
            pipeline.addLast("readTimeout", new ReadTimeoutHandler(30, SECONDS))
            pipeline.addLast("writeTimeout", new WriteTimeoutHandler(10, SECONDS))
            pipeline.addLast("handler", handlerFactory())
        })
      
      bootstrap.bind(port).addListener { (future: ChannelFuture) =>
        if future.isSuccess then callback(ZIO.succeed(future.channel()))
        else callback(ZIO.fail(new Exception(s"Порт $port занят")))
      }
    }
  }
```

### Pipeline для каждого соединения:

```
Трекер TCP пакет
  → [RateLimitHandler]     IP rate limiting
  → [ReadTimeoutHandler]   Отключить если молчит 30 сек
  → [WriteTimeoutHandler]  Timeout на запись 10 сек
  → [ConnectionHandler]    Наша бизнес-логика
```

---

## 7.4 ZIO.async + Netty listeners

Netty работает на callback'ах, ZIO — на эффектах. Мост:

```scala
// Запуск сервера — Netty callback → ZIO
ZIO.asyncZIO { callback =>
  bootstrap.bind(port).addListener { future =>
    if future.isSuccess then callback(ZIO.succeed(future.channel()))
    else callback(ZIO.fail(...))
  }
}

// Остановка — аналогично  
override def stop(channel: Channel): Task[Unit] =
  ZIO.async { callback =>
    channel.close().addListener { future =>
      if future.isSuccess then callback(ZIO.unit)
      else callback(ZIO.fail(...))
    }
  }
```

---

## 7.5 EventLoopGroup как ZIO ресурс

```scala
// Boss group — acquireRelease для graceful shutdown
bossGroup <- ZIO.acquireRelease(
  ZIO.attempt(new NioEventLoopGroup(config.bossThreads))
)(group => 
  ZIO.async[Any, Nothing, Unit] { callback =>
    group.shutdownGracefully().addListener(_ => callback(ZIO.unit))
  }
)
```

При `Ctrl+C`:
1. ZIO инициирует shutdown
2. `shutdownGracefully()` завершает все активные соединения
3. Netty callback → ZIO callback → ресурс освобождён

---

## 7.6 ConnectionHandler — бизнес-логика соединения

Жизненный цикл одного TCP соединения:

```
1. channelActive()   → Трекер подключился
2. channelRead()     → Первый пакет = IMEI (аутентификация)
3. channelRead()     → Последующие пакеты = GPS данные
4. channelInactive() → Трекер отключился
```

### Состояние через ZIO Ref:

```scala
final case class ConnectionState(
    imei: Option[String] = None,
    vehicleId: Option[Long] = None,
    connectedAt: Long = 0L,
    positionCache: Map[Long, GpsPoint] = Map.empty
)
```

### Иммутабельные обновления:

```scala
// Не мутация! Создаём новый объект:
def withImei(newImei: String, vid: Long, timestamp: Long): ConnectionState =
  copy(imei = Some(newImei), vehicleId = Some(vid), connectedAt = timestamp)
```

---

## 7.7 RateLimiter — защита от DDoS

```scala
// RateLimitHandler.scala — Netty handler
class RateLimitHandler(rateLimiter: RateLimiter, runtime: Runtime[Any])
  extends ChannelInboundHandlerAdapter:
  
  override def channelActive(ctx: ChannelHandlerContext): Unit =
    val ip = ctx.channel().remoteAddress().asInstanceOf[InetSocketAddress]
      .getAddress.getHostAddress
    
    val effect = rateLimiter.tryAcquire(ip).flatMap {
      case true  => ZIO.succeed(super.channelActive(ctx))  // Пропустить
      case false => ZIO.logWarning(s"Rate limit: $ip") *>   // Закрыть
                    ZIO.succeed(ctx.close())
    }
    
    Unsafe.unsafe { implicit u =>
      runtime.unsafe.run(effect).getOrThrowFiberFailure()
    }
```

### RateLimiter на ZIO Ref:

```scala
// Хранит количество соединений с каждого IP
// Ref[Map[String, ConnectionRecord]]
// Атомарное обновление, потокобезопасно без synchronized
```

---

## 7.8 Параллельный запуск серверов

```scala
// Main.scala — 4 протокола параллельно
_ <- ZIO.collectAllParDiscard(
  List(
    startServerIfEnabled("Teltonika", config.tcp.teltonika, server, teltonikaFactory),
    startServerIfEnabled("Wialon", config.tcp.wialon, server, wialonFactory),
    startServerIfEnabled("Ruptela", config.tcp.ruptela, server, ruptelaFactory),
    startServerIfEnabled("NavTelecom", config.tcp.navtelecom, server, navtelecomFactory)
  )
)
```

`ZIO.collectAllParDiscard` — запускает все параллельно, ждёт завершения всех.

---

## 📝 Упражнение

1. Открой `TcpServer.scala` — найди pipeline. В каком порядке проходят handlers?
2. Что произойдёт если трекер не отправит данные 30 секунд? (ReadTimeoutHandler)
3. В `RateLimitHandler` — зачем `Unsafe.unsafe`? Можно ли без него?
4. Почему `bossThreads = 1-2`, а `workerThreads = CPU cores`?
5. Что будет если один TCP сервер не запустится (порт занят)?

---

**→ Следующий: [08-TESTING.md](08-TESTING.md) — Тестирование ZIO**
