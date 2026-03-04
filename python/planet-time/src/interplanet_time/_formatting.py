"""
_formatting.py — Human-readable format utilities for interplanet_time.
Mirrors planet-time.js formatLightTime() and formatPlanetTimeISO().
"""

from __future__ import annotations
import math

from ._constants import Planet
from ._models import PlanetTime

__all__ = ["format_light_time", "format_planet_time_iso"]

# Maps Planet enum → 3-letter timezone zone prefix
_ZONE_PREFIXES: dict[int, str] = {
    Planet.MARS:    "AMT",
    Planet.MOON:    "LMT",
    Planet.MERCURY: "MMT",
    Planet.VENUS:   "VMT",
    Planet.JUPITER: "JMT",
    Planet.SATURN:  "SMT",
    Planet.URANUS:  "UMT",
    Planet.NEPTUNE: "NMT",
    Planet.EARTH:   "EAT",
}


def format_light_time(seconds: float) -> str:
    """Format a light travel time (seconds) as a human-readable string.

    Examples: '<1ms', '500ms', '4.2s', '3.1min', '1h 22m'
    """
    if seconds < 0.001:
        return "<1ms"
    if seconds < 1:
        return f"{seconds * 1000:.0f}ms"
    if seconds < 60:
        return f"{seconds:.1f}s"
    if seconds < 3600:
        return f"{seconds / 60:.1f}min"
    h = math.floor(seconds / 3600)
    m = round((seconds % 3600) / 60)
    return f"{h}h {m}m"


def format_planet_time_iso(
    pt: PlanetTime,
    planet: Planet,
    offset_hours: float,
    utc_ms: int,
) -> str:
    """Format a planet time as a machine-parseable timestamp per
    draft-watt-interplanetary-timezones-00 §5.

    Mars:  "MY43-221T14:32:07/2026-02-19T09:15:23Z[Mars/AMT+4]"
    Other: "2026-02-19T14:32:07/2026-02-19T14:32:07Z[Moon/LMT+1]"

    The '/' separator embeds the UTC instant for minimum interoperability.
    """
    import datetime

    prefix   = _ZONE_PREFIXES.get(planet, planet.name[:3].upper() + "T")
    off_sign = "+" if offset_hours >= 0 else ""
    off_int  = int(offset_hours)
    tz_id    = f"{prefix}+0" if offset_hours == 0 else f"{prefix}{off_sign}{off_int}"
    body     = planet.name.capitalize() if planet != Planet.MOON else "Moon"

    hh = f"{pt.hour:02d}"
    mm = f"{pt.minute:02d}"
    ss = f"{pt.second:02d}"

    # Date component
    if planet == Planet.MARS and pt.sol_in_year is not None:
        date_str = f"MY{pt.year_number}-{pt.sol_in_year:03d}"
    else:
        dt = datetime.datetime.fromtimestamp(utc_ms / 1000, tz=datetime.timezone.utc)
        date_str = dt.strftime("%Y-%m-%d")

    # UTC reference
    dt_utc  = datetime.datetime.fromtimestamp(utc_ms / 1000, tz=datetime.timezone.utc)
    utc_ref = "/" + dt_utc.strftime("%Y-%m-%dT%H:%M:%SZ")

    return f"{date_str}T{hh}:{mm}:{ss}{utc_ref}[{body}/{tz_id}]"
