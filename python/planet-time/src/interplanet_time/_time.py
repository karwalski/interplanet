"""
_time.py — Planet time and MTC calculations.
Exact port of planet-time.js getPlanetTime / getMTC functions.
All functions accept utc_ms (int, milliseconds since Unix epoch).
"""

from __future__ import annotations
import math
from datetime import datetime, timezone

from ._constants import Planet, PLANETS, MARS_EPOCH_MS, MARS_SOL_MS
from ._models import PlanetTime, MTC

# Maps Planet enum → 3-letter timezone zone prefix (mirrors ZONE_PREFIXES in planet-time.js)
_ZONE_PREFIXES: dict[Planet, str] = {
    Planet.MARS:    "AMT",
    Planet.MOON:    "LMT",
    Planet.MERCURY: "MMT",
    Planet.VENUS:   "VMT",
    Planet.JUPITER: "JMT",
    Planet.SATURN:  "SMT",
    Planet.URANUS:  "UMT",
    Planet.NEPTUNE: "NMT",
}

__all__ = ["get_planet_time", "get_mtc", "get_mars_time_at_offset"]


def get_planet_time(
    planet: Planet,
    utc_ms: int,
    tz_offset_h: float = 0,
) -> PlanetTime:
    """Get the current time on a planet.

    Parameters
    ----------
    planet:      Planet enum member
    utc_ms:      UTC milliseconds since Unix epoch
    tz_offset_h: local-hour zone offset from planet prime meridian (default 0)

    Notes
    -----
    Moon maps to Earth's solar day (tidally locked; work schedules on Earth time).
    Mars populates sol_in_year / sols_per_year; all others get None.
    """
    # Moon uses Earth's planetary data
    key = Planet.EARTH if planet == Planet.MOON else planet
    p   = PLANETS[key]

    elapsed_ms  = utc_ms - p['epochMs'] + tz_offset_h / 24 * p['solarDayMs']
    total_days  = elapsed_ms / p['solarDayMs']
    day_number  = math.floor(total_days)
    day_frac    = total_days - day_number

    local_hour  = day_frac * 24
    h           = math.floor(local_hour)
    m           = math.floor((local_hour - h) * 60)
    s           = math.floor(((local_hour - h) * 60 - m) * 60)

    days_per    = p['daysPerPeriod']
    per_week    = p['periodsPerWeek']
    work_per    = p['workPeriodsPerWeek']

    if p.get('earthClockSched'):
        # Mercury and Venus: schedule on UTC Mon–Fri 09:00–17:00
        dt_utc = datetime.fromtimestamp(utc_ms / 1000, tz=timezone.utc)
        period_in_week = dt_utc.weekday()  # 0=Mon..6=Sun
        is_work_period = period_in_week < work_per
        utc_hour = dt_utc.hour + dt_utc.minute / 60.0 + dt_utc.second / 3600.0
        is_work_hour = is_work_period and p['workHoursStart'] <= utc_hour < p['workHoursEnd']
    else:
        total_periods = total_days / days_per
        period_in_week = (
            (math.floor(total_periods) % per_week) + per_week
        ) % per_week
        is_work_period = period_in_week < work_per
        is_work_hour   = (
            is_work_period
            and p['workHoursStart'] <= local_hour < p['workHoursEnd']
        )

    year_len    = p['siderealYrMs'] / p['solarDayMs']
    year_number = math.floor(total_days / year_len)
    day_in_year = total_days - year_number * year_len

    sol_in_year  = None
    sols_per_year = None
    if planet == Planet.MARS:
        sols_per_year_f = PLANETS[Planet.MARS]['siderealYrMs'] / PLANETS[Planet.MARS]['solarDayMs']
        sol_in_year   = math.floor(day_in_year)
        sols_per_year = round(sols_per_year_f)

    prefix = _ZONE_PREFIXES.get(planet)
    if prefix is not None:
        off_sign = "+" if tz_offset_h >= 0 else ""
        zone_id: str | None = f"{prefix}{off_sign}{math.trunc(tz_offset_h)}"
    else:
        zone_id = None

    return PlanetTime(
        hour=h, minute=m, second=s,
        local_hour=local_hour,
        day_fraction=day_frac,
        day_number=day_number,
        day_in_year=math.floor(day_in_year),
        year_number=year_number,
        period_in_week=int(period_in_week),
        is_work_period=bool(is_work_period),
        is_work_hour=bool(is_work_hour),
        time_str=f"{h:02d}:{m:02d}",
        time_str_full=f"{h:02d}:{m:02d}:{s:02d}",
        sol_in_year=sol_in_year,
        sols_per_year=sols_per_year,
        zone_id=zone_id,
    )


def get_mtc(utc_ms: int) -> MTC:
    """Get Mars Coordinated Time (MTC) — the Martian equivalent of UTC."""
    total_sols = (utc_ms - MARS_EPOCH_MS) / MARS_SOL_MS
    sol  = math.floor(total_sols)
    frac = total_sols - sol
    h    = math.floor(frac * 24)
    m    = math.floor((frac * 24 - h) * 60)
    s    = math.floor(((frac * 24 - h) * 60 - m) * 60)
    return MTC(
        sol=sol, hour=h, minute=m, second=s,
        mtc_str=f"{h:02d}:{m:02d}",
    )


def get_mars_time_at_offset(utc_ms: int, offset_h: float) -> PlanetTime:
    """Get Mars local time at a given zone offset (Mars local hours from AMT)."""
    return get_planet_time(Planet.MARS, utc_ms, tz_offset_h=offset_h)
