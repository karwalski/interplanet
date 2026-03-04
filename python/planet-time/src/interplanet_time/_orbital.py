"""
_orbital.py — Orbital mechanics for interplanet_time.
Exact port of planet-time.js orbital functions.
All functions accept utc_ms (int, milliseconds since Unix epoch).
"""

from __future__ import annotations
import math

from ._constants import (
    Planet, J2000_JD, AU_KM, C_KMS, AU_SECONDS, LEAP_SECS, ORB_ELEMS, EARTH_DAY_MS,
)
from ._models import HelioPos, LineOfSight

__all__ = [
    "helio_pos", "body_distance_au", "light_travel_seconds",
    "check_line_of_sight", "lower_quartile_light_time",
]

# Julian Day of the Unix epoch (1970-01-01 00:00:00 UTC)
_UNIX_EPOCH_JD = 2440587.5


def _tai_minus_utc(utc_ms: int) -> int:
    """TAI − UTC in seconds from the IERS leap-second table."""
    offset = 10
    for s, t_ms in LEAP_SECS:
        if utc_ms >= t_ms:
            offset = s
        else:
            break
    return offset


def _jde(utc_ms: int) -> float:
    """Convert UTC milliseconds to Terrestrial Time Julian Ephemeris Day.
    TT = UTC + (TAI−UTC) + 32.184 s
    """
    tt_ms = utc_ms + (_tai_minus_utc(utc_ms) + 32.184) * 1000
    return _UNIX_EPOCH_JD + tt_ms / 86400000


def _jc(utc_ms: int) -> float:
    """Julian centuries from J2000.0 for the given UTC millisecond timestamp."""
    return (_jde(utc_ms) - J2000_JD) / 36525


def _kepler_E(M: float, e: float) -> float:
    """Solve Kepler's equation M = E − e·sin(E) using Newton-Raphson.
    Tolerance: 1e-12 radians; max 50 iterations.
    """
    E = M
    for _ in range(50):
        dE = (M - E + e * math.sin(E)) / (1 - e * math.cos(E))
        E += dE
        if abs(dE) < 1e-12:
            break
    return E


def helio_pos(planet: Planet, utc_ms: int) -> HelioPos:
    """Heliocentric (x, y) position of a planet in AU (ecliptic plane).
    Moon uses Earth's orbital elements.
    """
    key = Planet.EARTH if planet == Planet.MOON else planet
    el = ORB_ELEMS[key]

    T   = _jc(utc_ms)
    TAU = 2 * math.pi
    D2R = math.pi / 180

    L   = ((el['L0'] + el['dL'] * T) * D2R % TAU + TAU) % TAU
    om  = el['om0'] * D2R
    M   = ((L - om) % TAU + TAU) % TAU
    e   = el['e0']
    a   = el['a']

    E   = _kepler_E(M, e)
    v   = 2 * math.atan2(
        math.sqrt(1 + e) * math.sin(E / 2),
        math.sqrt(1 - e) * math.cos(E / 2),
    )
    r   = a * (1 - e * math.cos(E))
    lon = ((v + om) % TAU + TAU) % TAU

    return HelioPos(
        x=r * math.cos(lon),
        y=r * math.sin(lon),
        r=r,
        lon=lon,
    )


def body_distance_au(a: Planet, b: Planet, utc_ms: int) -> float:
    """Distance in AU between two solar system bodies."""
    pA = helio_pos(a, utc_ms)
    pB = helio_pos(b, utc_ms)
    dx = pA.x - pB.x
    dy = pA.y - pB.y
    return math.sqrt(dx * dx + dy * dy)


def light_travel_seconds(a: Planet, b: Planet, utc_ms: int) -> float:
    """One-way light travel time between two bodies in seconds."""
    return body_distance_au(a, b, utc_ms) * AU_SECONDS


def check_line_of_sight(a: Planet, b: Planet, utc_ms: int) -> LineOfSight:
    """Check whether the line of sight between two bodies is obstructed by the Sun.
    Buffer zones: < 0.01 AU = blocked; < 0.05 AU = degraded.
    Guard: if bodies are co-located (Moon/Earth), d²≈0 → returns clear.
    """
    pA = helio_pos(a, utc_ms)
    pB = helio_pos(b, utc_ms)

    dx = pB.x - pA.x
    dy = pB.y - pA.y
    d2 = dx * dx + dy * dy

    # Guard: co-located bodies (e.g. Earth + Moon share orbital position)
    if d2 < 1e-12:
        return LineOfSight(
            clear=True, blocked=False, degraded=False,
            closest_sun_au=None, elong_deg=0.0,
        )

    dist = math.sqrt(d2)

    # Closest approach of segment A→B to the Sun (origin)
    t   = max(0.0, min(1.0, -(pA.x * dx + pA.y * dy) / d2))
    cx  = pA.x + t * dx
    cy  = pA.y + t * dy
    closest = math.sqrt(cx * cx + cy * cy)

    # Solar elongation at A
    cos_el  = (-pA.x * dx - pA.y * dy) / (pA.r * dist)
    elong   = math.degrees(math.acos(max(-1.0, min(1.0, cos_el))))

    blocked  = closest < 0.01
    degraded = (not blocked) and closest < 0.05

    return LineOfSight(
        clear=not blocked and not degraded,
        blocked=blocked,
        degraded=degraded,
        closest_sun_au=closest,
        elong_deg=elong,
    )


def lower_quartile_light_time(a: Planet, b: Planet, ref_ms: int) -> float:
    """Sample light travel time over one Earth year and return the 25th-percentile.
    Uses 360 samples. Good target for transmission window planning.
    """
    SAMPLES = 360
    step_ms = int(365.25 * EARTH_DAY_MS / SAMPLES)
    times   = [
        light_travel_seconds(a, b, ref_ms + i * step_ms)
        for i in range(SAMPLES)
    ]
    times.sort()
    return times[int(SAMPLES * 0.25)]
