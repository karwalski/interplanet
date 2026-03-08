"""
_models.py — Frozen dataclasses for interplanet_time public API.
"""

from __future__ import annotations
from dataclasses import dataclass

__all__ = ["PlanetTime", "MTC", "LineOfSight", "HelioPos", "MeetingWindow"]


@dataclass(frozen=True)
class PlanetTime:
    hour: int
    minute: int
    second: int
    local_hour: float
    day_fraction: float
    day_number: int
    day_in_year: int
    year_number: int
    period_in_week: int
    is_work_period: bool
    is_work_hour: bool
    time_str: str        # "HH:MM"
    time_str_full: str   # "HH:MM:SS"
    sol_in_year: int | None      # Mars only
    sols_per_year: int | None    # Mars only
    zone_id: str | None          # e.g. "AMT+0", "LMT-3"; None for Earth


@dataclass(frozen=True)
class MTC:
    sol: int
    hour: int
    minute: int
    second: int
    mtc_str: str  # "HH:MM"


@dataclass(frozen=True)
class LineOfSight:
    clear: bool
    blocked: bool
    degraded: bool
    closest_sun_au: float | None
    elong_deg: float


@dataclass(frozen=True)
class HelioPos:
    x: float    # AU, ecliptic plane
    y: float    # AU, ecliptic plane
    r: float    # AU, heliocentric distance
    lon: float  # radians, ecliptic longitude


@dataclass(frozen=True)
class MeetingWindow:
    start_ms: int
    end_ms: int
    duration_min: int
