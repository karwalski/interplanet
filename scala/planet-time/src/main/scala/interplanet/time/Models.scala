package interplanet.time

/**
 * Models.scala — Case classes for planet-time results
 * Ported from planet-time.js v1.1.0
 */

case class PlanetTime(
  hour: Int,
  minute: Int,
  second: Int,
  localHour: Double,
  dayFraction: Double,
  dayNumber: Long,
  dayInYear: Long,
  yearNumber: Long,
  periodInWeek: Int,
  isWorkPeriod: Boolean,
  isWorkHour: Boolean,
  timeStr: String,
  timeStrFull: String,
  solInYear: Option[Int] = None,
  solsPerYear: Option[Int] = None
)

case class MtcResult(
  sol: Long,
  hour: Int,
  minute: Int,
  second: Int,
  mtcStr: String
)

case class HelioPos(
  x: Double,
  y: Double,
  r: Double,
  lon: Double
)

case class LineOfSight(
  clear: Boolean,
  blocked: Boolean,
  degraded: Boolean,
  closestSunAu: Double,
  elongDeg: Double
)

case class MeetingWindow(
  startMs: Long,
  endMs: Long,
  durationMin: Int
)

case class MarsLocalTime(
  sol: Long,
  hour: Int,
  minute: Int,
  second: Int,
  timeString: String,
  offsetHours: Double
)
