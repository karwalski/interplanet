package interplanet.time

import org.json.JSONObject
import org.json.JSONArray
import java.io.File
import kotlin.math.abs

/**
 * FixtureRunner.kt — Reads reference.json and validates 54 fixture entries.
 * Matches the pattern established in the Go fixture_test.go.
 *
 * Usage: ./gradlew run --args="path/to/reference.json"
 */
fun main(args: Array<String>) {
    val fixturePath = if (args.isNotEmpty()) args[0] else "../../c/planet-time/fixtures/reference.json"
    val file = File(fixturePath)

    if (!file.exists()) {
        println("SKIP: fixture file not found at $fixturePath")
        println("0 passed  0 failed  (fixtures skipped)")
        return
    }

    val json = JSONObject(file.readText())
    val entries: JSONArray = json.getJSONArray("entries")

    var passed = 0
    var failed = 0

    for (i in 0 until entries.length()) {
        val entry = entries.getJSONObject(i)
        val utcMs = entry.getLong("utc_ms")
        val planetStr = entry.getString("planet")
        val expectedHour = entry.getInt("hour")
        val expectedMinute = entry.getInt("minute")
        val lightTravelS = if (entry.has("light_travel_s")) entry.getDouble("light_travel_s") else 0.0

        val tag = "$planetStr@$utcMs"
        val expectedPeriodInWeek = if (entry.has("period_in_week")) entry.getInt("period_in_week") else -1
        val expectedIsWorkPeriod = if (entry.has("is_work_period")) entry.getInt("is_work_period") else -1
        val expectedIsWorkHour   = if (entry.has("is_work_hour"))   entry.getInt("is_work_hour")   else -1

        val planet = try {
            Planet.fromString(planetStr)
        } catch (e: Exception) {
            println("FAIL: $tag — unknown planet '$planetStr'")
            failed++
            continue
        }

        val pt = getPlanetTime(planet, utcMs, 0.0)

        if (pt.hour == expectedHour) {
            passed++
        } else {
            failed++
            println("FAIL: $tag hour=$expectedHour (got ${pt.hour})")
        }

        if (pt.minute == expectedMinute) {
            passed++
        } else {
            failed++
            println("FAIL: $tag minute=$expectedMinute (got ${pt.minute})")
        }

        if (lightTravelS != 0.0 && planetStr != "earth" && planetStr != "moon") {
            val lt = lightTravelSeconds(Planet.EARTH, planet, utcMs)
            if (abs(lt - lightTravelS) <= 2.0) {
                passed++
            } else {
                failed++
                println("FAIL: $tag lightTravel — expected ${"%.3f".format(lightTravelS)}, got ${"%.3f".format(lt)}")
            }
        }

        if (expectedPeriodInWeek >= 0) {
            if (pt.periodInWeek == expectedPeriodInWeek) {
                passed++
            } else {
                failed++
                println("FAIL: $tag period_in_week=$expectedPeriodInWeek (got ${pt.periodInWeek})")
            }
        }

        if (expectedIsWorkPeriod >= 0) {
            val got = if (pt.isWorkPeriod) 1 else 0
            if (got == expectedIsWorkPeriod) {
                passed++
            } else {
                failed++
                println("FAIL: $tag is_work_period=$expectedIsWorkPeriod (got $got)")
            }
        }

        if (expectedIsWorkHour >= 0) {
            val got = if (pt.isWorkHour) 1 else 0
            if (got == expectedIsWorkHour) {
                passed++
            } else {
                failed++
                println("FAIL: $tag is_work_hour=$expectedIsWorkHour (got $got)")
            }
        }
    }

    println("Fixture entries checked: ${entries.length()}")
    println("$passed passed  $failed failed")
    if (failed > 0) {
        System.exit(1)
    }
}
