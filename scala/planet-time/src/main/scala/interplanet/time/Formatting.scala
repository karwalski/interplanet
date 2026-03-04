package interplanet.time

import scala.math.*

/**
 * Formatting.scala — formatLightTime and other display utilities
 * Ported from planet-time.js v1.1.0
 */

/**
 * Format a light travel time (seconds) as a human-readable string.
 */
def formatLightTime(seconds: Double): String =
  if seconds < 0.001 then "<1ms"
  else if seconds < 1.0   then s"${(seconds * 1000).toInt}ms"
  else if seconds < 60.0  then f"$seconds%.1fs"
  else if seconds < 3600.0 then f"${seconds / 60.0}%.1fmin"
  else
    val h = floor(seconds / 3600.0).toInt
    val m = ((seconds % 3600.0) / 60.0 + 0.5).toInt
    s"${h}h ${m}m"
