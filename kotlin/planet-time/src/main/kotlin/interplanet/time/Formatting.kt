package interplanet.time

import kotlin.math.floor

/**
 * Formatting.kt — formatLightTime and other display utilities
 * Ported from planet-time.js v1.1.0
 */

/**
 * Format a light travel time (seconds) as a human-readable string.
 */
fun formatLightTime(seconds: Double): String {
    return when {
        seconds < 0.001 -> "<1ms"
        seconds < 1.0   -> "${(seconds * 1000).toInt()}ms"
        seconds < 60.0  -> "${"%.1f".format(seconds)}s"
        seconds < 3600.0 -> "${"%.1f".format(seconds / 60.0)}min"
        else -> {
            val h = floor(seconds / 3600.0).toInt()
            val m = ((seconds % 3600.0) / 60.0 + 0.5).toInt()
            "${h}h ${m}m"
        }
    }
}
