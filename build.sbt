lazy val root = project
  .in(file("."))
  .aggregate(
    connectionManager,
    historyWriter,
    deviceManager,
    ruleChecker,
    notificationService,
    analyticsService,
    userService,
    adminService,
    integrationService,
    maintenanceService,
    sensorsService
  )
  .settings(
    name := "wayrecall-tracker-system",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Connection Manager - приём GPS данных
lazy val connectionManager = project
  .in(file("services/connection-manager"))
  .settings(
    name := "connection-manager",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// History Writer - сохранение в TimescaleDB
lazy val historyWriter = project
  .in(file("services/history-writer"))
  .settings(
    name := "history-writer",
    version := "0.1.0",
    scalaVersion := "3.4.0",
    libraryDependencies ++= Seq(
      "dev.zio" %% "zio" % "2.0.20",
      "dev.zio" %% "zio-kafka" % "2.2.0",
      "org.postgresql" % "postgresql" % "42.7.1",
      "com.zaxxer" % "HikariCP" % "5.1.0"
    )
  )
  .dependsOn(connectionManager % "test->test;compile->compile")

// Device Manager - управление командами и трекерами
lazy val deviceManager = project
  .in(file("services/device-manager"))
  .settings(
    name := "device-manager",
    version := "0.1.0",
    scalaVersion := "3.4.0",
    libraryDependencies ++= Seq(
      "dev.zio" %% "zio" % "2.0.20",
      "dev.zio" %% "zio-redis" % "0.2.0",
      "org.apache.kafka" % "kafka-clients" % "3.6.1"
    )
  )
  .dependsOn(connectionManager % "test->test;compile->compile")

// Rule Checker - проверка геозон и правил скорости
lazy val ruleChecker = project
  .in(file("services/rule-checker"))
  .settings(
    name := "rule-checker",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Notification Service - уведомления (email, SMS, push, Telegram, webhook)
lazy val notificationService = project
  .in(file("services/notification-service"))
  .settings(
    name := "notification-service",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Analytics Service - генерация отчётов, экспорт, планировщик
lazy val analyticsService = project
  .in(file("services/analytics-service"))
  .settings(
    name := "analytics-service",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// User Service - управление пользователями, ролями, компаниями
lazy val userService = project
  .in(file("services/user-service"))
  .settings(
    name := "user-service",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Admin Service - системное администрирование, мониторинг
lazy val adminService = project
  .in(file("services/admin-service"))
  .settings(
    name := "admin-service",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Integration Service - ретрансляция GPS (Wialon, Webhooks), Inbound API
lazy val integrationService = project
  .in(file("services/integration-service"))
  .settings(
    name := "integration-service",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Maintenance Service - плановое ТО, напоминания, пробег
lazy val maintenanceService = project
  .in(file("services/maintenance-service"))
  .settings(
    name := "maintenance-service",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Sensors Service - обработка датчиков, калибровка, события
lazy val sensorsService = project
  .in(file("services/sensors-service"))
  .settings(
    name := "sensors-service",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Общие настройки
inThisBuild(Seq(
  organization := "com.wayrecall",
  scalacOptions ++= Seq(
    "-encoding", "utf8",
    "-deprecation",
    "-unchecked",
    "-language:postfixOps",
    "-feature"
  ),
  resolvers ++= Seq(
    "Maven Central" at "https://repo1.maven.org/maven2/",
    Resolver.sonatypeRepo("releases")
  )
))
