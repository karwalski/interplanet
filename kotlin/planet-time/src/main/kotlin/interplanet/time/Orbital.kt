package interplanet.time

import kotlin.math.*

/**
 * Orbital.kt — Orbital mechanics: helio pos, distance, light travel, line of sight
 * Ported verbatim from planet-time.js v1.1.0
 */

// ── Leap second / TT helpers ──────────────────────────────────────────────────

/**
 * Returns TAI-UTC offset (leap seconds) for the given UTC milliseconds.
 */
fun taiMinusUtc(utcMs: Long): Int {
    var offset = 10
    for (ls in LEAP_SECONDS) {
        if (utcMs >= ls.utcMs) offset = ls.delta
        else break
    }
    return offset
}

/**
 * Convert UTC milliseconds to Julian Ephemeris Day (TT).
 * TT = UTC + (TAI-UTC) + 32.184 s
 */
fun jde(utcMs: Long): Double {
    val ttMs = utcMs.toDouble() + taiMinusUtc(utcMs).toDouble() * 1000.0 + 32184.0
    return 2440587.5 + ttMs / 86400000.0
}

/**
 * Julian centuries since J2000.0 from UTC milliseconds.
 */
fun jc(utcMs: Long): Double {
    return (jde(utcMs) - J2000_JD) / 36525.0
}

// ── Kepler solver ─────────────────────────────────────────────────────────────

/**
 * Solve Kepler's equation M = E - e*sin(E) via Newton-Raphson.
 * Tolerance: 1e-12
 */
fun keplerE(M: Double, e: Double): Double {
    var E = M
    for (i in 0 until 50) {
        val dE = (M - E + e * sin(E)) / (1.0 - e * cos(E))
        E += dE
        if (abs(dE) < 1e-12) break
    }
    return E
}

// ── Heliocentric position ─────────────────────────────────────────────────────

/**
 * Compute heliocentric ecliptic (x, y) position of a planet in AU.
 * Moon maps to Earth's orbital elements.
 */
fun helioPosOf(planet: Planet, utcMs: Long): HelioPos {
    val el = ORB_ELEMS[planet] ?: ORB_ELEMS[Planet.EARTH]!!
    val T = jc(utcMs)
    val TAU = 2.0 * PI
    val D2R = PI / 180.0

    val L = ((el.l0 + el.dL * T) * D2R % TAU + TAU) % TAU
    val om = el.om0 * D2R
    val M = ((L - om) % TAU + TAU) % TAU
    val e = el.e0
    val a = el.a

    val E = keplerE(M, e)
    val v = 2.0 * atan2(sqrt(1.0 + e) * sin(E / 2.0), sqrt(1.0 - e) * cos(E / 2.0))
    val r = a * (1.0 - e * cos(E))
    val lon = ((v + om) % TAU + TAU) % TAU

    return HelioPos(
        x = r * cos(lon),
        y = r * sin(lon),
        r = r,
        lon = lon
    )
}

// ── Distance & light travel ───────────────────────────────────────────────────

/**
 * Distance in AU between two solar system bodies.
 */
fun bodyDistanceAu(a: Planet, b: Planet, utcMs: Long): Double {
    val pA = helioPosOf(a, utcMs)
    val pB = helioPosOf(b, utcMs)
    val dx = pA.x - pB.x
    val dy = pA.y - pB.y
    return sqrt(dx * dx + dy * dy)
}

/**
 * One-way light travel time between two bodies (seconds).
 */
fun lightTravelSeconds(from: Planet, to: Planet, utcMs: Long): Double {
    return bodyDistanceAu(from, to, utcMs) * AU_SECONDS
}

// ── Line of sight ─────────────────────────────────────────────────────────────

/**
 * Check whether the line of sight between two bodies is obstructed by the Sun.
 * Blocked: < 0.1 AU; Degraded: < 0.25 AU or elongation < 5 deg.
 */
fun checkLineOfSight(a: Planet, b: Planet, utcMs: Long): LineOfSight {
    val pA = helioPosOf(a, utcMs)
    val pB = helioPosOf(b, utcMs)

    val abx = pB.x - pA.x
    val aby = pB.y - pA.y
    val d2 = abx * abx + aby * aby

    if (d2 < 1e-20) {
        return LineOfSight(clear = true, blocked = false, degraded = false,
            closestSunAu = -1.0, elongDeg = 0.0)
    }

    val t = max(0.0, min(1.0, -(pA.x * abx + pA.y * aby) / d2))
    val cx = pA.x + t * abx
    val cy = pA.y + t * aby
    val closest = sqrt(cx * cx + cy * cy)

    val dotAB = abx * pA.x + aby * pA.y
    val abMag = sqrt(d2)
    val aMag = sqrt(pA.x * pA.x + pA.y * pA.y)
    val cosEl = if (aMag > 1e-10 && abMag > 1e-10) -dotAB / (abMag * aMag) else 0.0
    val elongDeg = acos(max(-1.0, min(1.0, cosEl))) * 180.0 / PI

    val blocked = closest < 0.1
    val degraded = !blocked && (closest < 0.25 || elongDeg < 5.0)

    return LineOfSight(
        clear = !blocked && !degraded,
        blocked = blocked,
        degraded = degraded,
        closestSunAu = closest,
        elongDeg = elongDeg
    )
}

/**
 * Sample light travel time over one Earth year (360 steps) and return
 * the lower-quartile (p25) one-way light time in seconds.
 */
fun lowerQuartileLightTime(a: Planet, b: Planet, refMs: Long): Double {
    val yearMs = 365L * EARTH_DAY_MS
    val step = yearMs / 360L
    val samples = DoubleArray(360) { i -> lightTravelSeconds(a, b, refMs + i.toLong() * step) }
    samples.sort()
    return samples[(samples.size * 0.25).toInt()]
}
