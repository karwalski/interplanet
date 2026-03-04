package interplanet.time

import munit.FunSuite
import scala.math.abs

/**
 * InterplanetTimeSuite.scala — munit tests for planet-time Scala library
 * 100+ assertions covering all planets, orbital mechanics, MTC, formatting
 */
class InterplanetTimeSuite extends FunSuite:

  // ── Known UTC timestamps ───────────────────────────────────────────────────
  // 2024-01-15T12:00:00Z
  val UTC_2024_01_15: Long = 1705320000000L
  // 2026-01-01T00:00:00Z
  val UTC_2026_01_01: Long = 1767225600000L
  // 2000-01-01T12:00:00Z (J2000 epoch)
  val UTC_J2000: Long = 946728000000L

  // ── Planet enum ───────────────────────────────────────────────────────────

  test("Planet.fromString mercury") { assertEquals(Planet.fromString("mercury"), Planet.Mercury) }
  test("Planet.fromString Venus uppercase") { assertEquals(Planet.fromString("Venus"), Planet.Venus) }
  test("Planet.fromString EARTH uppercase") { assertEquals(Planet.fromString("EARTH"), Planet.Earth) }
  test("Planet.fromString mars") { assertEquals(Planet.fromString("mars"), Planet.Mars) }
  test("Planet.fromString jupiter") { assertEquals(Planet.fromString("jupiter"), Planet.Jupiter) }
  test("Planet.fromString saturn") { assertEquals(Planet.fromString("saturn"), Planet.Saturn) }
  test("Planet.fromString uranus") { assertEquals(Planet.fromString("uranus"), Planet.Uranus) }
  test("Planet.fromString neptune") { assertEquals(Planet.fromString("neptune"), Planet.Neptune) }
  test("Planet.fromString moon") { assertEquals(Planet.fromString("moon"), Planet.Moon) }
  test("Planet.Mercury idx") { assertEquals(Planet.Mercury.idx, 0) }
  test("Planet.Moon idx") { assertEquals(Planet.Moon.idx, 8) }

  // ── Constants ─────────────────────────────────────────────────────────────

  test("J2000_MS correct") { assertEquals(J2000_MS, 946728000000L) }
  test("MARS_EPOCH_MS correct") { assertEquals(MARS_EPOCH_MS, -524069761536L) }
  test("MARS_SOL_MS correct") { assertEquals(MARS_SOL_MS, 88775244L) }
  test("AU_KM correct") { assertEqualsDouble(AU_KM, 149597870.7, 0.001) }
  test("C_KMS correct") { assertEqualsDouble(C_KMS, 299792.458, 0.0001) }
  test("AU_SECONDS approx 499") { assert(abs(AU_SECONDS - 499.004) < 0.01) }
  test("J2000_JD correct") { assertEqualsDouble(J2000_JD, 2451545.0, 0.0001) }
  test("LEAP_SECONDS has 28 entries") { assertEquals(LEAP_SECONDS.length, 28) }
  test("LEAP_SECONDS first entry") {
    assertEquals(LEAP_SECONDS.head.utcMs, 63_072_000_000L)
    assertEquals(LEAP_SECONDS.head.delta, 10)
  }
  test("LEAP_SECONDS last entry 2017") {
    assertEquals(LEAP_SECONDS.last.utcMs, 1_483_228_800_000L)
    assertEquals(LEAP_SECONDS.last.delta, 37)
  }

  // ── Orbital elements ──────────────────────────────────────────────────────

  test("ORB_ELEMS has 9 entries") { assertEquals(ORB_ELEMS.size, 9) }
  test("Earth semi-major axis 1 AU") { assertEqualsDouble(ORB_ELEMS(Planet.Earth).a, 1.0, 0.0001) }
  test("Mars a = 1.52366") { assertEqualsDouble(ORB_ELEMS(Planet.Mars).a, 1.52366, 0.00001) }
  test("Jupiter a = 5.20336") { assertEqualsDouble(ORB_ELEMS(Planet.Jupiter).a, 5.20336, 0.00001) }
  test("Moon uses Earth elements") { assertEquals(ORB_ELEMS(Planet.Moon), ORB_ELEMS(Planet.Earth)) }
  test("Mercury L0 = 252.2507") { assertEqualsDouble(ORB_ELEMS(Planet.Mercury).l0, 252.2507, 0.0001) }
  test("Neptune dL = 219.8997") { assertEqualsDouble(ORB_ELEMS(Planet.Neptune).dL, 219.8997, 0.0001) }

  // ── taiMinusUtc ───────────────────────────────────────────────────────────

  test("TAI offset before 1972 is 10") { assertEquals(taiMinusUtc(0L), 10) }
  test("TAI offset in 2024 is 37") { assertEquals(taiMinusUtc(UTC_2024_01_15), 37) }
  test("TAI offset at J2000 is 32") { assertEquals(taiMinusUtc(UTC_J2000), 32) }

  // ── JDE / JC ─────────────────────────────────────────────────────────────

  test("JDE at J2000 epoch near 2451545") {
    val j = jde(UTC_J2000)
    assert(abs(j - 2451545.0) < 0.001, s"Expected ~2451545 but got $j")
  }

  test("JC at J2000 is near 0") {
    val c = jc(UTC_J2000)
    assert(abs(c) < 0.001, s"Expected ~0 but got $c")
  }

  // ── keplerE ───────────────────────────────────────────────────────────────

  test("keplerE M=0 e=0 gives 0") { assertEqualsDouble(keplerE(0.0, 0.0), 0.0, 1e-12) }
  test("keplerE circular orbit E=M") { assertEqualsDouble(keplerE(1.0, 0.0), 1.0, 1e-10) }
  test("keplerE converges for Mars eccentricity") {
    val E = keplerE(1.5, 0.09341)
    assert(abs(E - 1.5 - 0.09341 * math.sin(E)) < 1e-10)
  }

  // ── helioPosOf ────────────────────────────────────────────────────────────

  test("Earth helio r near 1 AU at J2000") {
    val p = helioPosOf(Planet.Earth, UTC_J2000)
    assert(abs(p.r - 1.0) < 0.02, s"Earth r=${p.r}")
  }

  test("Mars helio r between 1.38 and 1.67 AU") {
    val p = helioPosOf(Planet.Mars, UTC_2024_01_15)
    assert(p.r >= 1.38 && p.r <= 1.67, s"Mars r=${p.r}")
  }

  test("Jupiter helio r near 5.2 AU") {
    val p = helioPosOf(Planet.Jupiter, UTC_2024_01_15)
    assert(abs(p.r - 5.20336) < 0.5, s"Jupiter r=${p.r}")
  }

  test("Moon helioPosOf same as Earth") {
    val moon = helioPosOf(Planet.Moon, UTC_2024_01_15)
    val earth = helioPosOf(Planet.Earth, UTC_2024_01_15)
    assertEqualsDouble(earth.r, moon.r, 1e-10)
  }

  test("helioPosOf lon is in 0-2pi") {
    val p = helioPosOf(Planet.Saturn, UTC_2024_01_15)
    assert(p.lon >= 0.0 && p.lon < 2 * math.Pi)
  }

  // ── bodyDistanceAu ────────────────────────────────────────────────────────

  test("Earth-Mars distance between 0.4 and 2.5 AU") {
    val d = bodyDistanceAu(Planet.Earth, Planet.Mars, UTC_2024_01_15)
    assert(d >= 0.4 && d <= 2.5, s"Earth-Mars=${d} AU")
  }

  test("Earth-Jupiter distance between 4.0 and 6.5 AU") {
    val d = bodyDistanceAu(Planet.Earth, Planet.Jupiter, UTC_2024_01_15)
    assert(d >= 4.0 && d <= 6.5, s"Earth-Jupiter=${d} AU")
  }

  test("Same planet distance is 0") {
    val d = bodyDistanceAu(Planet.Earth, Planet.Earth, UTC_2024_01_15)
    assertEqualsDouble(d, 0.0, 1e-10)
  }

  // ── lightTravelSeconds ────────────────────────────────────────────────────

  test("Light travel Earth-Mars between 200 and 1250 s") {
    val lt = lightTravelSeconds(Planet.Earth, Planet.Mars, UTC_2024_01_15)
    assert(lt >= 200.0 && lt <= 1250.0, s"Light travel=${lt}s")
  }

  test("Light travel Earth-Neptune between 3600 and 16000 s") {
    val lt = lightTravelSeconds(Planet.Earth, Planet.Neptune, UTC_2024_01_15)
    assert(lt >= 3600.0 && lt <= 16000.0, s"Light travel=${lt}s")
  }

  test("Light travel same body is 0") {
    assertEqualsDouble(lightTravelSeconds(Planet.Earth, Planet.Earth, UTC_2024_01_15), 0.0, 1e-10)
  }

  // ── checkLineOfSight ──────────────────────────────────────────────────────

  test("Line of sight Earth-Mars closestSunAu >= 0") {
    val los = checkLineOfSight(Planet.Earth, Planet.Mars, UTC_2024_01_15)
    assert(los.closestSunAu >= 0.0)
  }

  test("Line of sight has exactly one flag set") {
    val los = checkLineOfSight(Planet.Earth, Planet.Jupiter, UTC_2024_01_15)
    val count = List(los.clear, los.blocked, los.degraded).count(identity)
    assertEquals(count, 1)
  }

  // ── getPlanetTime — Earth ─────────────────────────────────────────────────

  test("Earth time hour in 0-23") {
    val pt = getPlanetTime(Planet.Earth, UTC_2024_01_15)
    assert(pt.hour >= 0 && pt.hour <= 23)
  }

  test("Earth time minute in 0-59") {
    val pt = getPlanetTime(Planet.Earth, UTC_2024_01_15)
    assert(pt.minute >= 0 && pt.minute <= 59)
  }

  test("Earth time second in 0-59") {
    val pt = getPlanetTime(Planet.Earth, UTC_2024_01_15)
    assert(pt.second >= 0 && pt.second <= 59)
  }

  test("Earth no solInYear") {
    assertEquals(getPlanetTime(Planet.Earth, UTC_2024_01_15).solInYear, None)
  }

  test("Earth timeStr matches HH:MM") {
    val pt = getPlanetTime(Planet.Earth, UTC_2024_01_15)
    assert(pt.timeStr.matches("\\d{2}:\\d{2}"))
  }

  test("Earth timeStrFull matches HH:MM:SS") {
    val pt = getPlanetTime(Planet.Earth, UTC_2024_01_15)
    assert(pt.timeStrFull.matches("\\d{2}:\\d{2}:\\d{2}"))
  }

  // ── getPlanetTime — Mars ───────────────────────────────────────────────────

  test("Mars has solInYear") {
    assert(getPlanetTime(Planet.Mars, UTC_2024_01_15).solInYear.isDefined)
  }

  test("Mars has solsPerYear near 687") {
    val spy = getPlanetTime(Planet.Mars, UTC_2024_01_15).solsPerYear
    assert(spy.isDefined && spy.get >= 668 && spy.get <= 670)
  }

  test("Mars solInYear in valid range") {
    val siy = getPlanetTime(Planet.Mars, UTC_2024_01_15).solInYear.get
    assert(siy >= 0 && siy <= 687)
  }

  test("Mars hour in 0-23") {
    assert(getPlanetTime(Planet.Mars, UTC_2024_01_15).hour <= 23)
  }

  test("Mars periodInWeek in 0-6") {
    val piw = getPlanetTime(Planet.Mars, UTC_2024_01_15).periodInWeek
    assert(piw >= 0 && piw <= 6)
  }

  // ── getPlanetTime — Moon ──────────────────────────────────────────────────

  test("Moon uses Earth solar day") {
    val moon = getPlanetTime(Planet.Moon, UTC_2024_01_15)
    val earth = getPlanetTime(Planet.Earth, UTC_2024_01_15)
    assertEquals(moon.hour, earth.hour)
    assertEquals(moon.minute, earth.minute)
  }

  test("Moon has no solInYear") {
    assertEquals(getPlanetTime(Planet.Moon, UTC_2024_01_15).solInYear, None)
  }

  // ── getPlanetTime — Gas giants ────────────────────────────────────────────

  test("Jupiter time hour in 0-23") {
    assert(getPlanetTime(Planet.Jupiter, UTC_2024_01_15).hour <= 23)
  }

  test("Saturn periodInWeek in 0-6") {
    val piw = getPlanetTime(Planet.Saturn, UTC_2024_01_15).periodInWeek
    assert(piw >= 0 && piw <= 6)
  }

  test("Uranus no solInYear") {
    assertEquals(getPlanetTime(Planet.Uranus, UTC_2024_01_15).solInYear, None)
  }

  test("Neptune no solInYear") {
    assertEquals(getPlanetTime(Planet.Neptune, UTC_2024_01_15).solInYear, None)
  }

  // ── getPlanetTime — tz offset ─────────────────────────────────────────────

  test("Mars tz offset +1 shifts hour by 1") {
    val base = getPlanetTime(Planet.Mars, UTC_2024_01_15, 0.0)
    val offset = getPlanetTime(Planet.Mars, UTC_2024_01_15, 1.0)
    val diff = (offset.hour - base.hour + 24) % 24
    assertEquals(diff, 1)
  }

  test("Earth tz offset +5 shifts hour by 5") {
    val base = getPlanetTime(Planet.Earth, UTC_2024_01_15, 0.0)
    val offset = getPlanetTime(Planet.Earth, UTC_2024_01_15, 5.0)
    val diff = (offset.hour - base.hour + 24) % 24
    assertEquals(diff, 5)
  }

  // ── getMtc ────────────────────────────────────────────────────────────────

  test("getMtc hour in 0-23") { assert(getMtc(UTC_2024_01_15).hour <= 23) }
  test("getMtc minute in 0-59") { assert(getMtc(UTC_2024_01_15).minute <= 59) }
  test("getMtc second in 0-59") { assert(getMtc(UTC_2024_01_15).second <= 59) }

  test("getMtc sol positive after 1953") {
    assert(getMtc(UTC_2024_01_15).sol > 0)
  }

  test("getMtc sol negative before 1953") {
    val mtc = getMtc(-600_000_000_000L)
    assert(mtc.sol < 0)
  }

  test("getMtc mtcStr matches HH:MM") {
    assert(getMtc(UTC_2024_01_15).mtcStr.matches("\\d{2}:\\d{2}"))
  }

  test("getMtc at Mars epoch is sol 0") {
    val mtc = getMtc(MARS_EPOCH_MS)
    assertEquals(mtc.sol, 0L)
    assertEquals(mtc.hour, 0)
    assertEquals(mtc.minute, 0)
  }

  test("getMtc matches getPlanetTime Mars hour") {
    val mtc = getMtc(UTC_2024_01_15)
    val pt = getPlanetTime(Planet.Mars, UTC_2024_01_15)
    assertEquals(mtc.hour, pt.hour)
    assertEquals(mtc.minute, pt.minute)
  }

  // ── getMarsTimeAtOffset ───────────────────────────────────────────────────

  test("getMarsTimeAtOffset 0 matches MTC") {
    val mtc = getMtc(UTC_2024_01_15)
    val local = getMarsTimeAtOffset(UTC_2024_01_15, 0.0)
    assertEquals(local.hour, mtc.hour)
    assertEquals(local.minute, mtc.minute)
  }

  test("getMarsTimeAtOffset wraps at 24") {
    val local = getMarsTimeAtOffset(UTC_2024_01_15, 5.0)
    assert(local.hour >= 0 && local.hour <= 23)
  }

  // ── formatLightTime ───────────────────────────────────────────────────────

  test("formatLightTime less than 1ms") { assertEquals(formatLightTime(0.0), "<1ms") }
  test("formatLightTime ms range") { assertEquals(formatLightTime(0.5), "500ms") }
  test("formatLightTime seconds range") { assert(formatLightTime(30.0).endsWith("s")) }
  test("formatLightTime minutes range") { assert(formatLightTime(120.0).endsWith("min")) }
  test("formatLightTime hours range") { assert(formatLightTime(7200.0).contains("h")) }
  test("formatLightTime 1 AU") {
    val s = formatLightTime(AU_SECONDS)
    assert(s.contains("min") || s.contains("s"), s"Expected min or s, got $s")
  }

  // ── findMeetingWindows ────────────────────────────────────────────────────

  test("findMeetingWindows returns list") {
    val windows = findMeetingWindows(Planet.Earth, Planet.Mars, 7, UTC_2024_01_15)
    assert(windows != null)
  }

  test("findMeetingWindows durations positive") {
    val windows = findMeetingWindows(Planet.Earth, Planet.Mars, 7, UTC_2024_01_15)
    windows.foreach(w => assert(w.durationMin > 0))
  }

  test("findMeetingWindows endMs > startMs") {
    val windows = findMeetingWindows(Planet.Earth, Planet.Mars, 7, UTC_2024_01_15)
    windows.foreach(w => assert(w.endMs > w.startMs))
  }

  test("findMeetingWindows same planet returns windows") {
    val windows = findMeetingWindows(Planet.Earth, Planet.Earth, 2, UTC_2024_01_15)
    assert(windows.nonEmpty)
  }

  // ── lowerQuartileLightTime ────────────────────────────────────────────────

  test("lowerQuartileLightTime Earth-Mars in valid range") {
    val lt = lowerQuartileLightTime(Planet.Earth, Planet.Mars, UTC_2024_01_15)
    assert(lt >= 200.0 && lt <= 800.0, s"p25 light time=${lt}")
  }

  // ── PLANET_DATA ───────────────────────────────────────────────────────────

  test("Mercury solar day is about 175 Earth days") {
    val days = PLANET_DATA(Planet.Mercury).solarDayMs.toDouble / EARTH_DAY_MS
    assert(abs(days - 175.9408) < 1.0, s"Mercury day=${days}")
  }

  test("Mars solar day is 88775244 ms") {
    assertEquals(PLANET_DATA(Planet.Mars).solarDayMs, 88775244L)
  }

  test("Jupiter daysPerPeriod is 2.5") {
    assertEqualsDouble(PLANET_DATA(Planet.Jupiter).daysPerPeriod, 2.5, 0.001)
  }

  test("Saturn daysPerPeriod is 2.25") {
    assertEqualsDouble(PLANET_DATA(Planet.Saturn).daysPerPeriod, 2.25, 0.001)
  }

  test("All planets have periodsPerWeek 7") {
    Planet.values.filter(_ != Planet.Moon).foreach { p =>
      assertEquals(PLANET_DATA(p).periodsPerWeek, 7, s"Failed for $p")
    }
  }

  test("All planets have workPeriodsPerWeek 5") {
    Planet.values.filter(_ != Planet.Moon).foreach { p =>
      assertEquals(PLANET_DATA(p).workPeriodsPerWeek, 5, s"Failed for $p")
    }
  }

  // ── Consistency checks across planets ────────────────────────────────────

  test("All planets return valid hour at J2000") {
    Planet.values.foreach { p =>
      val pt = getPlanetTime(p, UTC_J2000)
      assert(pt.hour >= 0 && pt.hour <= 23, s"Hour ${pt.hour} for $p")
    }
  }

  test("All planets return valid minute at J2000") {
    Planet.values.foreach { p =>
      val pt = getPlanetTime(p, UTC_J2000)
      assert(pt.minute >= 0 && pt.minute <= 59, s"Minute ${pt.minute} for $p")
    }
  }

  test("All planets timeStr HH:MM pattern") {
    Planet.values.foreach { p =>
      val pt = getPlanetTime(p, UTC_2024_01_15)
      assert(pt.timeStr.matches("\\d{2}:\\d{2}"), s"timeStr=${pt.timeStr} for $p")
    }
  }

  test("dayFraction is in 0-1 for all planets") {
    Planet.values.foreach { p =>
      val pt = getPlanetTime(p, UTC_2024_01_15)
      assert(pt.dayFraction >= 0.0 && pt.dayFraction <= 1.0, s"dayFraction=${pt.dayFraction} for $p")
    }
  }

  test("isWorkHour implies isWorkPeriod") {
    Planet.values.foreach { p =>
      val pt = getPlanetTime(p, UTC_2024_01_15)
      if pt.isWorkHour then assert(pt.isWorkPeriod, s"isWorkHour but not isWorkPeriod for $p")
    }
  }

  test("Light travel to outer planets is positive") {
    List(Planet.Mars, Planet.Jupiter, Planet.Saturn, Planet.Uranus, Planet.Neptune).foreach { p =>
      val lt = lightTravelSeconds(Planet.Earth, p, UTC_2024_01_15)
      assert(lt > 0.0, s"Light travel to $p = $lt")
    }
  }

  // ── Edge cases ────────────────────────────────────────────────────────────

  test("getPlanetTime at Unix epoch 0") {
    val pt = getPlanetTime(Planet.Earth, 0L)
    assert(pt.hour >= 0 && pt.hour <= 23)
    assert(pt.minute >= 0 && pt.minute <= 59)
  }

  test("getMtc at Unix epoch 0") {
    val mtc = getMtc(0L)
    assert(mtc.hour >= 0 && mtc.hour <= 23)
  }

  test("getPlanetTime negative utcMs Mercury") {
    val pt = getPlanetTime(Planet.Mercury, -1_000_000_000_000L)
    assert(pt.hour >= 0 && pt.hour <= 23)
  }

  test("keplerE zero eccentricity E=M") {
    assertEqualsDouble(keplerE(2.0, 0.0), 2.0, 1e-10)
  }
