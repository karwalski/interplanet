package interplanet.time

import kotlin.test.*
import kotlin.math.abs

/**
 * InterplanetTimeTest.kt — Unit tests for planet-time Kotlin library
 * 100+ assertions covering all planets, orbital mechanics, MTC, formatting
 */
class InterplanetTimeTest {

    // ── Known UTC timestamps ───────────────────────────────────────────────────
    // 2024-01-15T12:00:00Z
    private val UTC_2024_01_15 = 1705320000000L
    // 2026-01-01T00:00:00Z
    private val UTC_2026_01_01 = 1767225600000L
    // 2000-01-01T12:00:00Z (J2000 epoch)
    private val UTC_J2000 = 946728000000L

    // ── Planet enum ───────────────────────────────────────────────────────────

    @Test fun `Planet fromString mercury`() = assertEquals(Planet.MERCURY, Planet.fromString("mercury"))
    @Test fun `Planet fromString Venus uppercase`() = assertEquals(Planet.VENUS, Planet.fromString("Venus"))
    @Test fun `Planet fromString EARTH uppercase`() = assertEquals(Planet.EARTH, Planet.fromString("EARTH"))
    @Test fun `Planet fromString mars`() = assertEquals(Planet.MARS, Planet.fromString("mars"))
    @Test fun `Planet fromString jupiter`() = assertEquals(Planet.JUPITER, Planet.fromString("jupiter"))
    @Test fun `Planet fromString saturn`() = assertEquals(Planet.SATURN, Planet.fromString("saturn"))
    @Test fun `Planet fromString uranus`() = assertEquals(Planet.URANUS, Planet.fromString("uranus"))
    @Test fun `Planet fromString neptune`() = assertEquals(Planet.NEPTUNE, Planet.fromString("neptune"))
    @Test fun `Planet fromString moon`() = assertEquals(Planet.MOON, Planet.fromString("moon"))
    @Test fun `Planet idx Mercury`() = assertEquals(0, Planet.MERCURY.idx)
    @Test fun `Planet idx Moon`() = assertEquals(8, Planet.MOON.idx)

    // ── Constants ─────────────────────────────────────────────────────────────

    @Test fun `J2000_MS correct`() = assertEquals(946728000000L, J2000_MS)
    @Test fun `MARS_EPOCH_MS correct`() = assertEquals(-524069761536L, MARS_EPOCH_MS)
    @Test fun `MARS_SOL_MS correct`() = assertEquals(88775244L, MARS_SOL_MS)
    @Test fun `AU_KM correct`() = assertEquals(149597870.7, AU_KM, 0.001)
    @Test fun `C_KMS correct`() = assertEquals(299792.458, C_KMS, 0.0001)
    @Test fun `AU_SECONDS approx 499`() = assertTrue(abs(AU_SECONDS - 499.004) < 0.01)
    @Test fun `J2000_JD correct`() = assertEquals(2451545.0, J2000_JD, 0.0001)
    @Test fun `LEAP_SECONDS has 28 entries`() = assertEquals(28, LEAP_SECONDS.size)
    @Test fun `LEAP_SECONDS first entry`() { assertEquals(63_072_000_000L, LEAP_SECONDS[0].utcMs); assertEquals(10, LEAP_SECONDS[0].delta) }
    @Test fun `LEAP_SECONDS last entry 2017`() { assertEquals(1_483_228_800_000L, LEAP_SECONDS[27].utcMs); assertEquals(37, LEAP_SECONDS[27].delta) }

    // ── Orbital elements ──────────────────────────────────────────────────────

    @Test fun `ORB_ELEMS has 9 entries`() = assertEquals(9, ORB_ELEMS.size)
    @Test fun `Earth semi-major axis is 1 AU`() = assertEquals(1.0, ORB_ELEMS[Planet.EARTH]!!.a, 0.0001)
    @Test fun `Mars a = 1.52366`() = assertEquals(1.52366, ORB_ELEMS[Planet.MARS]!!.a, 0.00001)
    @Test fun `Jupiter a = 5.20336`() = assertEquals(5.20336, ORB_ELEMS[Planet.JUPITER]!!.a, 0.00001)
    @Test fun `Moon uses Earth elements`() = assertEquals(ORB_ELEMS[Planet.EARTH], ORB_ELEMS[Planet.MOON])
    @Test fun `Mercury L0 = 252.2507`() = assertEquals(252.2507, ORB_ELEMS[Planet.MERCURY]!!.l0, 0.0001)
    @Test fun `Neptune dL = 219.8997`() = assertEquals(219.8997, ORB_ELEMS[Planet.NEPTUNE]!!.dL, 0.0001)

    // ── taiMinusUtc ───────────────────────────────────────────────────────────

    @Test fun `TAI offset before 1972 is 10`() = assertEquals(10, taiMinusUtc(0L))
    @Test fun `TAI offset in 2024 is 37`() = assertEquals(37, taiMinusUtc(UTC_2024_01_15))
    @Test fun `TAI offset at J2000 is 32`() = assertEquals(32, taiMinusUtc(UTC_J2000))

    // ── JDE / JC ─────────────────────────────────────────────────────────────

    @Test fun `JDE at J2000 epoch near 2451545`() {
        val j = jde(UTC_J2000)
        assertTrue(abs(j - 2451545.0) < 0.001, "Expected ~2451545 but got $j")
    }

    @Test fun `JC at J2000 is near 0`() {
        val c = jc(UTC_J2000)
        assertTrue(abs(c) < 0.001, "Expected ~0 but got $c")
    }

    // ── keplerE ───────────────────────────────────────────────────────────────

    @Test fun `keplerE M=0 e=0 gives 0`() = assertEquals(0.0, keplerE(0.0, 0.0), 1e-12)
    @Test fun `keplerE circular orbit E=M`() = assertEquals(1.0, keplerE(1.0, 0.0), 1e-10)
    @Test fun `keplerE converges for Mars eccentricity`() {
        val E = keplerE(1.5, 0.09341)
        assertTrue(abs(E - 1.5 + 0.09341 * Math.sin(E)) < 1e-10)
    }

    // ── helioPosOf ────────────────────────────────────────────────────────────

    @Test fun `Earth helio pos r near 1 AU at J2000`() {
        val p = helioPosOf(Planet.EARTH, UTC_J2000)
        assertTrue(abs(p.r - 1.0) < 0.02, "Earth r=${p.r} expected ~1 AU")
    }

    @Test fun `Mars helio pos r between 1.38 and 1.67 AU`() {
        val p = helioPosOf(Planet.MARS, UTC_2024_01_15)
        assertTrue(p.r in 1.38..1.67, "Mars r=${p.r}")
    }

    @Test fun `Jupiter helio pos r near 5.2 AU`() {
        val p = helioPosOf(Planet.JUPITER, UTC_2024_01_15)
        assertTrue(abs(p.r - 5.20336) < 0.5, "Jupiter r=${p.r}")
    }

    @Test fun `Moon helioPosOf same as Earth`() {
        val moon = helioPosOf(Planet.MOON, UTC_2024_01_15)
        val earth = helioPosOf(Planet.EARTH, UTC_2024_01_15)
        assertEquals(earth.r, moon.r, 1e-10)
    }

    @Test fun `helioPosOf lon is in 0-2pi`() {
        val p = helioPosOf(Planet.SATURN, UTC_2024_01_15)
        assertTrue(p.lon >= 0.0 && p.lon < 2 * Math.PI)
    }

    // ── bodyDistanceAu ────────────────────────────────────────────────────────

    @Test fun `Earth to Mars distance between 0.4 and 2.5 AU`() {
        val d = bodyDistanceAu(Planet.EARTH, Planet.MARS, UTC_2024_01_15)
        assertTrue(d in 0.4..2.5, "Earth-Mars=${d} AU")
    }

    @Test fun `Earth to Jupiter distance between 4.0 and 6.5 AU`() {
        val d = bodyDistanceAu(Planet.EARTH, Planet.JUPITER, UTC_2024_01_15)
        assertTrue(d in 4.0..6.5, "Earth-Jupiter=${d} AU")
    }

    @Test fun `Same planet distance is 0`() {
        val d = bodyDistanceAu(Planet.EARTH, Planet.EARTH, UTC_2024_01_15)
        assertEquals(0.0, d, 1e-10)
    }

    // ── lightTravelSeconds ────────────────────────────────────────────────────

    @Test fun `Light travel Earth-Mars between 200 and 1250 seconds`() {
        val lt = lightTravelSeconds(Planet.EARTH, Planet.MARS, UTC_2024_01_15)
        assertTrue(lt in 200.0..1250.0, "Light travel=${lt}s")
    }

    @Test fun `Light travel Earth-Neptune between 3600 and 16000 seconds`() {
        val lt = lightTravelSeconds(Planet.EARTH, Planet.NEPTUNE, UTC_2024_01_15)
        assertTrue(lt in 3600.0..16000.0, "Light travel=${lt}s")
    }

    @Test fun `Light travel Earth-same is 0`() {
        val lt = lightTravelSeconds(Planet.EARTH, Planet.EARTH, UTC_2024_01_15)
        assertEquals(0.0, lt, 1e-10)
    }

    // ── checkLineOfSight ──────────────────────────────────────────────────────

    @Test fun `Line of sight Earth-Mars has closestSunAu >= 0`() {
        val los = checkLineOfSight(Planet.EARTH, Planet.MARS, UTC_2024_01_15)
        assertTrue(los.closestSunAu >= 0.0)
    }

    @Test fun `Line of sight result has exactly one of clear blocked degraded`() {
        val los = checkLineOfSight(Planet.EARTH, Planet.JUPITER, UTC_2024_01_15)
        val count = listOf(los.clear, los.blocked, los.degraded).count { it }
        assertEquals(1, count)
    }

    // ── getPlanetTime — Earth ─────────────────────────────────────────────────

    @Test fun `Earth time hour in 0-23`() {
        val pt = getPlanetTime(Planet.EARTH, UTC_2024_01_15)
        assertTrue(pt.hour in 0..23)
    }

    @Test fun `Earth time minute in 0-59`() {
        val pt = getPlanetTime(Planet.EARTH, UTC_2024_01_15)
        assertTrue(pt.minute in 0..59)
    }

    @Test fun `Earth time second in 0-59`() {
        val pt = getPlanetTime(Planet.EARTH, UTC_2024_01_15)
        assertTrue(pt.second in 0..59)
    }

    @Test fun `Earth no solInYear`() {
        val pt = getPlanetTime(Planet.EARTH, UTC_2024_01_15)
        assertNull(pt.solInYear)
    }

    @Test fun `Earth work hours 9-17`() {
        // Midday UTC — check that work period logic is consistent
        val pt = getPlanetTime(Planet.EARTH, UTC_2024_01_15)
        if (pt.isWorkHour) {
            assertTrue(pt.localHour >= 9.0 && pt.localHour < 17.0)
        }
    }

    @Test fun `Earth timeStr format HH:MM`() {
        val pt = getPlanetTime(Planet.EARTH, UTC_2024_01_15)
        assertTrue(pt.timeStr.matches(Regex("\\d{2}:\\d{2}")))
    }

    @Test fun `Earth timeStrFull format HH:MM:SS`() {
        val pt = getPlanetTime(Planet.EARTH, UTC_2024_01_15)
        assertTrue(pt.timeStrFull.matches(Regex("\\d{2}:\\d{2}:\\d{2}")))
    }

    // ── getPlanetTime — Mars ───────────────────────────────────────────────────

    @Test fun `Mars has solInYear`() {
        val pt = getPlanetTime(Planet.MARS, UTC_2024_01_15)
        assertNotNull(pt.solInYear)
    }

    @Test fun `Mars has solsPerYear near 687`() {
        val pt = getPlanetTime(Planet.MARS, UTC_2024_01_15)
        assertNotNull(pt.solsPerYear)
        assertTrue(pt.solsPerYear!! in 686..688)
    }

    @Test fun `Mars solInYear in valid range`() {
        val pt = getPlanetTime(Planet.MARS, UTC_2024_01_15)
        assertTrue(pt.solInYear!! in 0..687)
    }

    @Test fun `Mars hour in 0-23`() {
        val pt = getPlanetTime(Planet.MARS, UTC_2024_01_15)
        assertTrue(pt.hour in 0..23)
    }

    @Test fun `Mars periodInWeek in 0-6`() {
        val pt = getPlanetTime(Planet.MARS, UTC_2024_01_15)
        assertTrue(pt.periodInWeek in 0..6)
    }

    // ── getPlanetTime — Moon ──────────────────────────────────────────────────

    @Test fun `Moon uses Earth solar day`() {
        val moon = getPlanetTime(Planet.MOON, UTC_2024_01_15)
        val earth = getPlanetTime(Planet.EARTH, UTC_2024_01_15)
        assertEquals(earth.hour, moon.hour)
        assertEquals(earth.minute, moon.minute)
    }

    @Test fun `Moon has no solInYear`() {
        val pt = getPlanetTime(Planet.MOON, UTC_2024_01_15)
        assertNull(pt.solInYear)
    }

    // ── getPlanetTime — Gas giants ────────────────────────────────────────────

    @Test fun `Jupiter time hour in 0-23`() {
        val pt = getPlanetTime(Planet.JUPITER, UTC_2024_01_15)
        assertTrue(pt.hour in 0..23)
    }

    @Test fun `Saturn time periodInWeek in 0-6`() {
        val pt = getPlanetTime(Planet.SATURN, UTC_2024_01_15)
        assertTrue(pt.periodInWeek in 0..6)
    }

    @Test fun `Uranus no solInYear`() {
        assertNull(getPlanetTime(Planet.URANUS, UTC_2024_01_15).solInYear)
    }

    @Test fun `Neptune no solInYear`() {
        assertNull(getPlanetTime(Planet.NEPTUNE, UTC_2024_01_15).solInYear)
    }

    // ── getPlanetTime — tz offset ─────────────────────────────────────────────

    @Test fun `Mars tz offset +1 shifts hour by 1`() {
        val base = getPlanetTime(Planet.MARS, UTC_2024_01_15, 0.0)
        val offset = getPlanetTime(Planet.MARS, UTC_2024_01_15, 1.0)
        val diff = (offset.hour - base.hour + 24) % 24
        assertEquals(1, diff)
    }

    @Test fun `Earth tz offset +5 shifts hour by 5`() {
        val base = getPlanetTime(Planet.EARTH, UTC_2024_01_15, 0.0)
        val offset = getPlanetTime(Planet.EARTH, UTC_2024_01_15, 5.0)
        val diff = (offset.hour - base.hour + 24) % 24
        assertEquals(5, diff)
    }

    // ── getMtc ────────────────────────────────────────────────────────────────

    @Test fun `getMtc hour in 0-23`() {
        val mtc = getMtc(UTC_2024_01_15)
        assertTrue(mtc.hour in 0..23)
    }

    @Test fun `getMtc minute in 0-59`() {
        val mtc = getMtc(UTC_2024_01_15)
        assertTrue(mtc.minute in 0..59)
    }

    @Test fun `getMtc second in 0-59`() {
        val mtc = getMtc(UTC_2024_01_15)
        assertTrue(mtc.second in 0..59)
    }

    @Test fun `getMtc sol positive after 1953`() {
        val mtc = getMtc(UTC_2024_01_15)
        assertTrue(mtc.sol > 0)
    }

    @Test fun `getMtc sol negative before 1953`() {
        val preEpoch = -600_000_000_000L // ~1950
        val mtc = getMtc(preEpoch)
        assertTrue(mtc.sol < 0)
    }

    @Test fun `getMtc mtcStr format HH:MM`() {
        val mtc = getMtc(UTC_2024_01_15)
        assertTrue(mtc.mtcStr.matches(Regex("\\d{2}:\\d{2}")))
    }

    @Test fun `getMtc at Mars epoch is sol 0`() {
        // Just at epoch: total sols = 0, so sol = 0
        val mtc = getMtc(MARS_EPOCH_MS)
        assertEquals(0L, mtc.sol)
        assertEquals(0, mtc.hour)
        assertEquals(0, mtc.minute)
    }

    @Test fun `getMtc matches getPlanetTime Mars hour`() {
        val mtc = getMtc(UTC_2024_01_15)
        val pt = getPlanetTime(Planet.MARS, UTC_2024_01_15)
        assertEquals(pt.hour, mtc.hour)
        assertEquals(pt.minute, mtc.minute)
    }

    // ── getMarsTimeAtOffset ───────────────────────────────────────────────────

    @Test fun `getMarsTimeAtOffset 0 matches MTC`() {
        val mtc = getMtc(UTC_2024_01_15)
        val local = getMarsTimeAtOffset(UTC_2024_01_15, 0.0)
        assertEquals(mtc.hour, local.hour)
        assertEquals(mtc.minute, local.minute)
    }

    @Test fun `getMarsTimeAtOffset wraps at 24`() {
        val local = getMarsTimeAtOffset(UTC_2024_01_15, 5.0)
        assertTrue(local.hour in 0..23)
    }

    // ── formatLightTime ───────────────────────────────────────────────────────

    @Test fun `formatLightTime less than 1ms`() = assertEquals("<1ms", formatLightTime(0.0))
    @Test fun `formatLightTime ms range`() = assertEquals("500ms", formatLightTime(0.5))
    @Test fun `formatLightTime seconds range`() = assertTrue(formatLightTime(30.0).endsWith("s"))
    @Test fun `formatLightTime minutes range`() = assertTrue(formatLightTime(120.0).endsWith("min"))
    @Test fun `formatLightTime hours range`() = assertTrue(formatLightTime(7200.0).contains("h"))
    @Test fun `formatLightTime 1 AU`() {
        val s = formatLightTime(AU_SECONDS)
        assertTrue(s.contains("min") || s.contains("s"), "Expected min or s, got $s")
    }

    // ── findMeetingWindows ────────────────────────────────────────────────────

    @Test fun `findMeetingWindows returns list`() {
        val windows = findMeetingWindows(Planet.EARTH, Planet.MARS, 7, UTC_2024_01_15)
        assertNotNull(windows)
    }

    @Test fun `findMeetingWindows durations are positive`() {
        val windows = findMeetingWindows(Planet.EARTH, Planet.MARS, 7, UTC_2024_01_15)
        windows.forEach { assertTrue(it.durationMin > 0) }
    }

    @Test fun `findMeetingWindows endMs greater than startMs`() {
        val windows = findMeetingWindows(Planet.EARTH, Planet.MARS, 7, UTC_2024_01_15)
        windows.forEach { assertTrue(it.endMs > it.startMs) }
    }

    @Test fun `findMeetingWindows same planet returns windows`() {
        // Earth-Earth should always have work windows
        val windows = findMeetingWindows(Planet.EARTH, Planet.EARTH, 2, UTC_2024_01_15)
        assertTrue(windows.isNotEmpty())
    }

    // ── lowerQuartileLightTime ────────────────────────────────────────────────

    @Test fun `lowerQuartileLightTime Earth-Mars in valid range`() {
        val lt = lowerQuartileLightTime(Planet.EARTH, Planet.MARS, UTC_2024_01_15)
        assertTrue(lt in 200.0..800.0, "p25 light time=${lt}")
    }

    // ── PLANET_DATA ───────────────────────────────────────────────────────────

    @Test fun `Mercury solar day is about 175 Earth days`() {
        val mercury = PLANET_DATA[Planet.MERCURY]!!
        val days = mercury.solarDayMs.toDouble() / EARTH_DAY_MS
        assertTrue(abs(days - 175.9408) < 1.0, "Mercury day=${days}")
    }

    @Test fun `Mars solar day is 88775244 ms`() {
        assertEquals(88775244L, PLANET_DATA[Planet.MARS]!!.solarDayMs)
    }

    @Test fun `Jupiter daysPerPeriod is 2.5`() {
        assertEquals(2.5, PLANET_DATA[Planet.JUPITER]!!.daysPerPeriod, 0.001)
    }

    @Test fun `Saturn daysPerPeriod is 2.25`() {
        assertEquals(2.25, PLANET_DATA[Planet.SATURN]!!.daysPerPeriod, 0.001)
    }

    @Test fun `All planets have periodsPerWeek 7`() {
        Planet.entries.filter { it != Planet.MOON }.forEach {
            assertEquals(7, PLANET_DATA[it]!!.periodsPerWeek, "Failed for $it")
        }
    }

    @Test fun `All planets have workPeriodsPerWeek 5`() {
        Planet.entries.filter { it != Planet.MOON }.forEach {
            assertEquals(5, PLANET_DATA[it]!!.workPeriodsPerWeek, "Failed for $it")
        }
    }

    // ── Consistency checks across planets ────────────────────────────────────

    @Test fun `All planets return valid hour at J2000`() {
        Planet.entries.forEach { p ->
            val pt = getPlanetTime(p, UTC_J2000)
            assertTrue(pt.hour in 0..23, "Hour ${pt.hour} for $p")
        }
    }

    @Test fun `All planets return valid minute at J2000`() {
        Planet.entries.forEach { p ->
            val pt = getPlanetTime(p, UTC_J2000)
            assertTrue(pt.minute in 0..59, "Minute ${pt.minute} for $p")
        }
    }

    @Test fun `All planets timeStr matches HH:MM pattern`() {
        Planet.entries.forEach { p ->
            val pt = getPlanetTime(p, UTC_2024_01_15)
            assertTrue(pt.timeStr.matches(Regex("\\d{2}:\\d{2}")), "timeStr=${pt.timeStr} for $p")
        }
    }

    @Test fun `dayFraction is in 0-1 for all planets`() {
        Planet.entries.forEach { p ->
            val pt = getPlanetTime(p, UTC_2024_01_15)
            assertTrue(pt.dayFraction in 0.0..1.0, "dayFraction=${pt.dayFraction} for $p")
        }
    }

    @Test fun `isWorkHour implies isWorkPeriod`() {
        Planet.entries.forEach { p ->
            val pt = getPlanetTime(p, UTC_2024_01_15)
            if (pt.isWorkHour) assertTrue(pt.isWorkPeriod, "isWorkHour but not isWorkPeriod for $p")
        }
    }

    @Test fun `yearNumber is non-negative for post-epoch dates`() {
        Planet.entries.forEach { p ->
            val pt = getPlanetTime(p, UTC_2024_01_15)
            assertTrue(pt.yearNumber >= 0 || p == Planet.MARS, "yearNumber=${pt.yearNumber} for $p")
        }
    }

    @Test fun `Light travel Earth to all outer planets is positive`() {
        listOf(Planet.MARS, Planet.JUPITER, Planet.SATURN, Planet.URANUS, Planet.NEPTUNE).forEach { p ->
            val lt = lightTravelSeconds(Planet.EARTH, p, UTC_2024_01_15)
            assertTrue(lt > 0.0, "Light travel to $p = $lt")
        }
    }

    // ── Edge cases ────────────────────────────────────────────────────────────

    @Test fun `getPlanetTime at Unix epoch 0`() {
        val pt = getPlanetTime(Planet.EARTH, 0L)
        assertTrue(pt.hour in 0..23)
        assertTrue(pt.minute in 0..59)
    }

    @Test fun `getMtc at Unix epoch 0`() {
        val mtc = getMtc(0L)
        assertTrue(mtc.hour in 0..23)
    }

    @Test fun `getPlanetTime negative utcMs Mercury`() {
        val pt = getPlanetTime(Planet.MERCURY, -1_000_000_000_000L)
        assertTrue(pt.hour in 0..23)
    }

    @Test fun `keplerE handles zero eccentricity`() {
        val E = keplerE(2.0, 0.0)
        assertEquals(2.0, E, 1e-10)
    }
}
