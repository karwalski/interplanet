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
        System.exit(1)
    }

    val json = JSONObject(file.readText())
    val entries: JSONArray = json.getJSONArray("entries")

    var passed = 0
    var failed = 0

    // reference.json writes JSON null for fields that do not apply (for example
    // light_travel_s on Earth and Moon, mtc on non-Mars planets), so every
    // optional field is read through these null-safe helpers.
    fun JSONObject.optIntOrNull(key: String): Int? = if (has(key) && !isNull(key)) getInt(key) else null
    fun JSONObject.optDoubleOrNull(key: String): Double? = if (has(key) && !isNull(key)) getDouble(key) else null
    fun JSONObject.optObjectOrNull(key: String): JSONObject? = if (has(key) && !isNull(key)) getJSONObject(key) else null

    for (i in 0 until entries.length()) {
        val entry = entries.getJSONObject(i)
        val utcMs = entry.getLong("utc_ms")
        val planetStr = entry.getString("planet")
        val expectedHour = entry.getInt("hour")
        val expectedMinute = entry.getInt("minute")
        val lightTravelS = entry.optDoubleOrNull("light_travel_s")
        val expectedMtc = entry.optObjectOrNull("mtc")

        val tag = "$planetStr@$utcMs"
        val expectedPeriodInWeek = entry.optIntOrNull("period_in_week") ?: -1
        val expectedIsWorkPeriod = entry.optIntOrNull("is_work_period") ?: -1
        val expectedIsWorkHour   = entry.optIntOrNull("is_work_hour")   ?: -1

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

        if (lightTravelS != null && planetStr != "earth" && planetStr != "moon") {
            val lt = lightTravelSeconds(Planet.EARTH, planet, utcMs)
            if (abs(lt - lightTravelS) <= 2.0) {
                passed++
            } else {
                failed++
                println("FAIL: $tag lightTravel — expected ${"%.3f".format(lightTravelS)}, got ${"%.3f".format(lt)}")
            }
        }

        if (expectedMtc != null) {
            val mtc = getMtc(utcMs)
            for ((key, got) in listOf("sol" to mtc.sol, "hour" to mtc.hour.toLong(),
                                      "minute" to mtc.minute.toLong(), "second" to mtc.second.toLong())) {
                val want = expectedMtc.getLong(key)
                if (got == want) {
                    passed++
                } else {
                    failed++
                    println("FAIL: $tag mtc.$key=$want (got $got)")
                }
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
