package interplanet.time

import kotlin.math.*

/**
 * TimeCalc.kt — getPlanetTime, getMtc, getMarsTimeAtOffset
 * Ported verbatim from planet-time.js v1.1.0
 */

/**
 * Get the local time on a planet.
 * @param planet  the planet
 * @param utcMs   UTC timestamp in milliseconds
 * @param tzOffsetH  timezone offset in local hours from planet prime meridian
 */
fun getPlanetTime(planet: Planet, utcMs: Long, tzOffsetH: Double = 0.0): PlanetTime {
    // Moon uses Earth's solar day (tidally locked; work schedules run on Earth time)
    val effective = if (planet == Planet.MOON) Planet.EARTH else planet
    val pd = PLANET_DATA[effective]!!
    val solarDay = pd.solarDayMs.toDouble()

    // tz offset applied as a fraction of one solar day (same as JS)
    val elapsedMs = (utcMs - pd.epochMs).toDouble() + tzOffsetH / 24.0 * solarDay
    val totalDays = elapsedMs / solarDay
    val dayNumber = floor(totalDays).toLong()
    val dayFrac = totalDays - dayNumber.toDouble()

    val localHour = dayFrac * 24.0
    val h = localHour.toInt()
    val minF = (localHour - h) * 60.0
    val m = minF.toInt()
    val s = ((minF - m) * 60.0).toInt()

    // Work period — positive modulo for pre-epoch dates
    val piw: Int
    val isWorkPeriod: Boolean
    val isWorkHour: Boolean
    if (pd.earthClockSched) {
        // Mercury/Venus: solar day >> circadian rhythm; use UTC Earth-clock scheduling
        // UTC day-of-week: ((floor(utcMs / 86400000) % 7 + 10) % 7 → Mon=0..Sun=6
        // (+7 before +3 ensures positive result for pre-1970 timestamps)
        val utcDay = floor(utcMs.toDouble() / 86400000.0).toLong()
        piw = ((utcDay % 7L + 10L) % 7L).toInt()
        isWorkPeriod = piw < pd.workPeriodsPerWeek
        // UTC hour within the day — positive modulo handles pre-1970 timestamps
        val msInDay = ((utcMs % 86400000L) + 86400000L) % 86400000L
        val utcHour = msInDay.toDouble() / 3600000.0
        isWorkHour = isWorkPeriod && utcHour >= pd.workStart.toDouble() && utcHour < pd.workEnd.toDouble()
    } else {
        val totalPeriods = totalDays / pd.daysPerPeriod
        piw = ((floor(totalPeriods).toInt() % pd.periodsPerWeek) + pd.periodsPerWeek) % pd.periodsPerWeek
        isWorkPeriod = piw < pd.workPeriodsPerWeek
        isWorkHour = isWorkPeriod && localHour >= pd.workStart.toDouble() && localHour < pd.workEnd.toDouble()
    }

    // Year / day-in-year
    val yearLenDays = pd.siderealYrMs.toDouble() / solarDay
    val yearNumber = floor(totalDays / yearLenDays).toLong()
    val dayInYear = floor(totalDays - yearNumber.toDouble() * yearLenDays).toLong()

    val solInYear: Int?
    val solsPerYear: Int?
    if (effective == Planet.MARS) {
        solInYear = dayInYear.toInt()
        solsPerYear = (pd.siderealYrMs.toDouble() / solarDay).roundToInt()
    } else {
        solInYear = null
        solsPerYear = null
    }

    // zoneId: null for Earth; "PREFIX+N" or "PREFIX-N" for all others
    val zonePrefix = ZONE_PREFIX[planet]
    val zoneId: String? = zonePrefix?.let { prefix ->
        val offsetInt = kotlin.math.round(tzOffsetH).toInt()
        prefix + (if (offsetInt >= 0) "+$offsetInt" else "-${-offsetInt}")
    }

    return PlanetTime(
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
        timeStr = "%02d:%02d".format(h, m),
        timeStrFull = "%02d:%02d:%02d".format(h, m, s),
        solInYear = solInYear,
        solsPerYear = solsPerYear,
        zoneId = zoneId
    )
}

private fun Double.roundToInt(): Int = (this + 0.5).toInt()

/**
 * Get Mars Coordinated Time (MTC) — the Martian equivalent of UTC.
 */
fun getMtc(utcMs: Long): MtcResult {
    val ms = (utcMs - MARS_EPOCH_MS).toDouble()
    val sol = floor(ms / MARS_SOL_MS.toDouble()).toLong()
    var fracMs = ms % MARS_SOL_MS.toDouble()
    if (fracMs < 0) fracMs += MARS_SOL_MS.toDouble()
    val totalSec = fracMs / 1000.0
    val h = (totalSec / 3600.0).toInt()
    val minute = ((totalSec % 3600.0) / 60.0).toInt()
    val second = (totalSec % 60.0).toInt()

    return MtcResult(
        sol = sol,
        hour = h,
        minute = minute,
        second = second,
        mtcStr = "%02d:%02d".format(h, minute)
    )
}

/**
 * Get Mars local time at a given zone offset (Mars local hours from AMT).
 */
data class MarsLocalTime(
    val sol: Long,
    val hour: Int,
    val minute: Int,
    val second: Int,
    val timeString: String,
    val offsetHours: Double
)

fun getMarsTimeAtOffset(utcMs: Long, offsetHours: Double): MarsLocalTime {
    val mtc = getMtc(utcMs)
    var h = mtc.hour.toDouble() + offsetHours
    var solDelta = 0L
    if (h >= 24.0) { h -= 24.0; solDelta = 1L }
    if (h < 0.0)   { h += 24.0; solDelta = -1L }
    return MarsLocalTime(
        sol = mtc.sol + solDelta,
        hour = h.toInt(),
        minute = mtc.minute,
        second = mtc.second,
        timeString = "%02d:%02d".format(h.toInt(), mtc.minute),
        offsetHours = offsetHours
    )
}
