package interplanet.time

import scala.io.Source
import scala.math.abs
import ujson.*

/**
 * FixtureRunner.scala — Reads reference.json and validates 54 fixture entries.
 * Matches the pattern established in the Go fixture_test.go.
 *
 * Usage: sbt "run path/to/reference.json"
 */
@main def fixtureRunner(args: String*): Unit =
  val fixturePath = if args.nonEmpty then args(0) else "../../c/planet-time/fixtures/reference.json"
  val file = java.io.File(fixturePath)

  if !file.exists() then
    println(s"SKIP: fixture file not found at $fixturePath")
    println("0 passed  0 failed  (fixtures skipped)")
    System.exit(0)

  val jsonText = Source.fromFile(file).mkString
  val json = ujson.read(jsonText)
  val entries = json("entries").arr

  var passed = 0
  var failed = 0

  for entry <- entries do
    val utcMs = entry("utc_ms").num.toLong
    val planetStr = entry("planet").str
    val expectedHour = entry("hour").num.toInt
    val expectedMinute = entry("minute").num.toInt
    val lightTravelS = entry.obj.get("light_travel_s").flatMap {
      case ujson.Num(n) => Some(n)
      case _ => None
    }.getOrElse(0.0)

    val tag = s"$planetStr@$utcMs"
    val expectedPeriodInWeek = if entry.obj.contains("period_in_week") then entry("period_in_week").num.toInt else -1
    val expectedIsWorkPeriod = if entry.obj.contains("is_work_period") then entry("is_work_period").num.toInt else -1
    val expectedIsWorkHour   = if entry.obj.contains("is_work_hour")   then entry("is_work_hour").num.toInt   else -1

    val planet =
      try Planet.fromString(planetStr)
      catch
        case e: Exception =>
          println(s"FAIL: $tag — unknown planet '$planetStr'")
          failed += 1
          null

    if planet != null then
      val pt = getPlanetTime(planet, utcMs, 0.0)

      if pt.hour == expectedHour then
        passed += 1
      else
        failed += 1
        println(s"FAIL: $tag hour=$expectedHour (got ${pt.hour})")

      if pt.minute == expectedMinute then
        passed += 1
      else
        failed += 1
        println(s"FAIL: $tag minute=$expectedMinute (got ${pt.minute})")

      if lightTravelS != 0.0 && planetStr != "earth" && planetStr != "moon" then
        val lt = lightTravelSeconds(Planet.Earth, planet, utcMs)
        if abs(lt - lightTravelS) <= 2.0 then
          passed += 1
        else
          failed += 1
          println(f"FAIL: $tag lightTravel — expected $lightTravelS%.3f, got $lt%.3f")

      if expectedPeriodInWeek >= 0 then
        if pt.periodInWeek == expectedPeriodInWeek then
          passed += 1
        else
          failed += 1
          println(s"FAIL: $tag period_in_week=$expectedPeriodInWeek (got ${pt.periodInWeek})")

      if expectedIsWorkPeriod >= 0 then
        val got = if pt.isWorkPeriod then 1 else 0
        if got == expectedIsWorkPeriod then
          passed += 1
        else
          failed += 1
          println(s"FAIL: $tag is_work_period=$expectedIsWorkPeriod (got $got)")

      if expectedIsWorkHour >= 0 then
        val got = if pt.isWorkHour then 1 else 0
        if got == expectedIsWorkHour then
          passed += 1
        else
          failed += 1
          println(s"FAIL: $tag is_work_hour=$expectedIsWorkHour (got $got)")

  println(s"Fixture entries checked: ${entries.length}")
  println(s"$passed passed  $failed failed")
  if failed > 0 then System.exit(1)
