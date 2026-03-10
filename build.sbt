lazy val root = project
  .in(file("."))
  .aggregate(
    historyWriter,
    ruleChecker,
    analyticsService,
    userService
  )
  .settings(
    name := "wayrecall-tracker-system",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Connection Manager - компилируется автономно из services/connection-manager/
// Device Manager - компилируется автономно из services/device-manager/

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

// Rule Checker - проверка геозон и правил скорости
lazy val ruleChecker = project
  .in(file("services/rule-checker"))
  .settings(
    name := "rule-checker",
    version := "0.1.0",
    scalaVersion := "3.4.0"
  )

// Остальные сервисы компилируются автономно из своих директорий (свои build.sbt):
// - services/notification-service/
// - services/admin-service/
// - services/integration-service/
// - services/maintenance-service/
// - services/sensors-service/

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

// Общие настройки
inThisBuild(Seq(
  organization := "com.wayrecall",
  resolvers ++= Seq(
    "Maven Central" at "https://repo1.maven.org/maven2/",
    Resolver.sonatypeRepo("releases")
  )
))
