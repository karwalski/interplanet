"""
_scheduling.py — Meeting window finder for interplanet_time.
Mirrors planet-time.js findMeetingWindows().
"""

from __future__ import annotations

from ._constants import Planet, EARTH_DAY_MS
from ._models import MeetingWindow
from ._time import get_planet_time

__all__ = ["find_meeting_windows"]


def find_meeting_windows(
    a: Planet,
    b: Planet,
    from_ms: int,
    earth_days: int = 30,
    step_min: int = 15,
) -> list[MeetingWindow]:
    """Find overlapping work windows between two planets over N Earth days.

    Scans in ``step_min``-minute steps and returns each contiguous block
    where both parties have ``is_work_hour=True``.

    Parameters
    ----------
    a, b:       Planet enum members to compare
    from_ms:    UTC milliseconds to start searching from
    earth_days: number of Earth days to scan (default 30)
    step_min:   time step in minutes (default 15)

    Returns
    -------
    list[MeetingWindow] sorted by start_ms ascending
    """
    step_ms = step_min * 60_000
    end_ms  = from_ms + earth_days * EARTH_DAY_MS
    windows: list[MeetingWindow] = []

    in_window   = False
    window_start = 0

    t = from_ms
    while t < end_ms:
        ta = get_planet_time(a, t)
        tb = get_planet_time(b, t)
        overlap = ta.is_work_hour and tb.is_work_hour

        if overlap and not in_window:
            in_window    = True
            window_start = t
        elif not overlap and in_window:
            in_window = False
            duration  = (t - window_start) // 60_000
            windows.append(MeetingWindow(
                start_ms=window_start,
                end_ms=t,
                duration_min=duration,
            ))
        t += step_ms

    # Close any open window at end of scan
    if in_window:
        duration = (end_ms - window_start) // 60_000
        windows.append(MeetingWindow(
            start_ms=window_start,
            end_ms=end_ms,
            duration_min=duration,
        ))

    return windows
