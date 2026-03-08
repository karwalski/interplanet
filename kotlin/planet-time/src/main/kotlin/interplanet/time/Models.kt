package interplanet.time

/**
 * Models.kt — Data classes for planet-time results
 * Ported from planet-time.js v1.1.0
 */

data class PlanetTime(
    val hour: Int,
    val minute: Int,
    val second: Int,
    val localHour: Double,
    val dayFraction: Double,
    val dayNumber: Long,
    val dayInYear: Long,
    val yearNumber: Long,
    val periodInWeek: Int,
    val isWorkPeriod: Boolean,
    val isWorkHour: Boolean,
    val timeStr: String,
    val timeStrFull: String,
    val solInYear: Int? = null,
    val solsPerYear: Int? = null,
    val zoneId: String? = null
)

data class MtcResult(
    val sol: Long,
    val hour: Int,
    val minute: Int,
    val second: Int,
    val mtcStr: String
)

data class HelioPos(
    val x: Double,
    val y: Double,
    val r: Double,
    val lon: Double
)

data class LineOfSight(
    val clear: Boolean,
    val blocked: Boolean,
    val degraded: Boolean,
    val closestSunAu: Double,
    val elongDeg: Double
)

data class MeetingWindow(
    val startMs: Long,
    val endMs: Long,
    val durationMin: Int
)
