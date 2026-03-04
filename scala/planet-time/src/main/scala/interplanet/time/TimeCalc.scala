package interplanet.time

import scala.math.*

/**
 * TimeCalc.scala — getPlanetTime, getMtc, getMarsTimeAtOffset
 * Ported verbatim from planet-time.js v1.1.0
 */

/**
 * Get the local time on a planet.
 * @param planet      the planet
 * @param utcMs       UTC timestamp in milliseconds
 * @param tzOffsetH   timezone offset in local hours from planet prime meridian
 */
def getPlanetTime(planet: Planet, utcMs: Long, tzOffsetH: Double = 0.0): PlanetTime =
  // Moon uses Earth's solar day (tidally locked; work schedules run on Earth time)
  val effective = if planet == Planet.Moon then Planet.Earth else planet
  val pd = PLANET_DATA(effective)
  val solarDay = pd.solarDayMs.toDouble

  // tz offset applied as a fraction of one solar day (same as JS)
  val elapsedMs = (utcMs - pd.epochMs).toDouble + tzOffsetH / 24.0 * solarDay
  val totalDays = elapsedMs / solarDay
  val dayNumber = floor(totalDays).toLong
  val dayFrac = totalDays - dayNumber.toDouble

  val localHour = dayFrac * 24.0
  val h = localHour.toInt
  val minF = (localHour - h) * 60.0
  val m = minF.toInt
  val s = ((minF - m) * 60.0).toInt

  // Work period — positive modulo for pre-epoch dates
  val (piw, isWorkPeriod, isWorkHour) =
    if pd.earthClockSched then
      // Mercury/Venus: solar day >> circadian rhythm; use UTC Earth-clock scheduling
      // UTC day-of-week: ((floor(utcMs / 86400000) % 7 + 10) % 7 → Mon=0..Sun=6
      // (+7 before +3 ensures positive result for pre-1970 timestamps)
      val utcDay = floor(utcMs.toDouble / 86400000.0).toLong
      val p = (((utcDay % 7L) + 10L) % 7L).toInt
      val wp = p < pd.workPeriodsPerWeek
      // UTC hour within the day — positive modulo handles pre-1970 timestamps
      val msInDay = ((utcMs % 86400000L) + 86400000L) % 86400000L
      val utcHour = msInDay.toDouble / 3600000.0
      val wh = wp && utcHour >= pd.workStart.toDouble && utcHour < pd.workEnd.toDouble
      (p, wp, wh)
    else
      val totalPeriods = totalDays / pd.daysPerPeriod
      val p = ((floor(totalPeriods).toInt % pd.periodsPerWeek) + pd.periodsPerWeek) % pd.periodsPerWeek
      val wp = p < pd.workPeriodsPerWeek
      val wh = wp && localHour >= pd.workStart.toDouble && localHour < pd.workEnd.toDouble
      (p, wp, wh)

  // Year / day-in-year
  val yearLenDays = pd.siderealYrMs.toDouble / solarDay
  val yearNumber = floor(totalDays / yearLenDays).toLong
  val dayInYear = floor(totalDays - yearNumber.toDouble * yearLenDays).toLong

  val (solInYear, solsPerYear) =
    if effective == Planet.Mars then
      (Some(dayInYear.toInt), Some(math.round(pd.siderealYrMs.toDouble / solarDay).toInt))
    else
      (None, None)

  PlanetTime(
    hour = h,
    minute = m,
    second = s,
    localHour = localHour,
    dayFraction = dayFrac,
    dayNumber = dayNumber,
    dayInYear = dayInYear,
    yearNumber = yearNumber,
    periodInWeek = piw,
    isWorkPeriod = isWorkPeriod,
    isWorkHour = isWorkHour,
    timeStr = f"$h%02d:$m%02d",
    timeStrFull = f"$h%02d:$m%02d:$s%02d",
    solInYear = solInYear,
    solsPerYear = solsPerYear
  )

/**
 * Get Mars Coordinated Time (MTC) — the Martian equivalent of UTC.
 */
def getMtc(utcMs: Long): MtcResult =
  val totalSols = (utcMs - MARS_EPOCH_MS).toDouble / MARS_SOL_MS.toDouble
  val sol = floor(totalSols).toLong
  val frac = totalSols - sol.toDouble
  val h = (frac * 24.0).toInt
  val minute = ((frac * 24.0 - h.toDouble) * 60.0).toInt
  val second = (((frac * 24.0 - h.toDouble) * 60.0 - minute.toDouble) * 60.0).toInt

  MtcResult(
    sol = sol,
    hour = h,
    minute = minute,
    second = second,
    mtcStr = f"$h%02d:$minute%02d"
  )

/**
 * Get Mars local time at a given zone offset (Mars local hours from AMT).
 */
def getMarsTimeAtOffset(utcMs: Long, offsetHours: Double): MarsLocalTime =
  val mtc = getMtc(utcMs)
  var hd = mtc.hour.toDouble + offsetHours
  var solDelta = 0L
  if hd >= 24.0 then { hd -= 24.0; solDelta = 1L }
  if hd < 0.0   then { hd += 24.0; solDelta = -1L }
  val hInt = hd.toInt
  MarsLocalTime(
    sol = mtc.sol + solDelta,
    hour = hInt,
    minute = mtc.minute,
    second = mtc.second,
    timeString = f"$hInt%02d:${mtc.minute}%02d",
    offsetHours = offsetHours
  )
