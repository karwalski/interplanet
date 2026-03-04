/**
 * Constants.scala - LTX SDK constants
 * Story 33.13 - Scala LTX library
 */

val VERSION: String = "1.0.0"

val DEFAULT_QUANTUM: Int = 3

val DEFAULT_API_BASE: String = "https://api.interplanet.app/ltx"

val SEG_TYPES: List[String] = List("PLAN_CONFIRM", "TX", "RX", "CAUCUS", "OPEN", "BUFFER")

val DEFAULT_SEGMENTS: List[LtxSegmentTemplate] = List(
  LtxSegmentTemplate("PLAN_CONFIRM", 2),
  LtxSegmentTemplate("TX",           2),
  LtxSegmentTemplate("RX",           2),
  LtxSegmentTemplate("CAUCUS",       2),
  LtxSegmentTemplate("TX",           2),
  LtxSegmentTemplate("RX",           2),
  LtxSegmentTemplate("BUFFER",       1)
)

// Story 26.4 constants
val DEFAULT_PLAN_LOCK_TIMEOUT_FACTOR: Int = 2
val DELAY_VIOLATION_WARN_S: Int = 120
val DELAY_VIOLATION_DEGRADED_S: Int = 300
val SESSION_STATES: List[String] = List("INIT", "LOCKED", "RUNNING", "DEGRADED", "COMPLETE")
