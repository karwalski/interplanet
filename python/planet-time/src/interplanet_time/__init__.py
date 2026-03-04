"""
interplanet_time — Interplanetary Time Library (Python)

Pure-Python port of planet-time.js v0.1.0.
Provides time, calendar, work-schedule, orbital mechanics, and light-speed
calculations for every planet in the solar system.

All public functions accept utc_ms (int, milliseconds since Unix epoch),
matching the JS and C API conventions.

Quick start
-----------
>>> import interplanet_time as ipt
>>> pt = ipt.get_planet_time(ipt.Planet.MARS, 1061991060000)
>>> print(pt.time_str)
'21:03'
"""

from ._constants import Planet

from ._models import PlanetTime, MTC, LineOfSight, HelioPos, MeetingWindow

from ._orbital import (
    helio_pos,
    body_distance_au,
    light_travel_seconds,
    check_line_of_sight,
    lower_quartile_light_time,
)

from ._time import get_planet_time, get_mtc, get_mars_time_at_offset

from ._timezone import PlanetTimezone, PlanetDateTime

from ._scheduling import find_meeting_windows

from ._fairness import calculate_fairness_score

from ._formatting import format_light_time, format_planet_time_iso

__version__ = "0.1.0"

__all__ = [
    # Enum
    "Planet",
    # Models
    "PlanetTime", "MTC", "LineOfSight", "HelioPos", "MeetingWindow",
    # Orbital
    "helio_pos", "body_distance_au", "light_travel_seconds",
    "check_line_of_sight", "lower_quartile_light_time",
    # Time
    "get_planet_time", "get_mtc", "get_mars_time_at_offset",
    # Timezone helpers
    "PlanetTimezone", "PlanetDateTime",
    # Scheduling
    "find_meeting_windows",
    # Fairness
    "calculate_fairness_score",
    # Formatting
    "format_light_time", "format_planet_time_iso",
    # Version
    "__version__",
]
