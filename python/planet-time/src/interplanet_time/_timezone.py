"""
_timezone.py — Planet-aware tzinfo and datetime subclasses.
"""

from __future__ import annotations
import datetime

from ._constants import Planet
from ._models import PlanetTime
from ._time import get_planet_time

__all__ = ["PlanetTimezone", "PlanetDateTime"]


class PlanetTimezone(datetime.tzinfo):
    """Zero-UTC-offset tzinfo subclass that carries planet + local hour offset.

    utcoffset() always returns timedelta(0) — the library treats all planet
    times as offsets from UTC, computed externally via get_planet_time().
    """

    def __init__(self, planet: Planet, offset_h: float = 0.0) -> None:
        super().__init__()
        self._planet  = planet
        self._offset  = offset_h

    @property
    def planet(self) -> Planet:
        return self._planet

    @property
    def offset_h(self) -> float:
        return self._offset

    def utcoffset(self, dt: datetime.datetime | None) -> datetime.timedelta:
        return datetime.timedelta(0)

    def tzname(self, dt: datetime.datetime | None) -> str:
        sign = "+" if self._offset >= 0 else ""
        return f"{self._planet.name}{sign}{int(self._offset):d}h"

    def dst(self, dt: datetime.datetime | None) -> datetime.timedelta:
        return datetime.timedelta(0)

    def fromutc(self, dt: datetime.datetime) -> "PlanetDateTime":
        return PlanetDateTime._from_utc(dt, self)

    def __repr__(self) -> str:
        return f"PlanetTimezone({self._planet.name}, {self._offset:+g})"


class PlanetDateTime(datetime.datetime):
    """datetime subclass that exposes a .planet_time property.

    Construct via PlanetDateTime.from_utc_ms(utc_ms, planet, offset_h) or
    via a PlanetTimezone's fromutc() method.
    """

    _planet_tz: PlanetTimezone
    _planet_time_cache: PlanetTime | None

    def __new__(
        cls,
        year: int, month: int, day: int,
        hour: int = 0, minute: int = 0, second: int = 0,
        microsecond: int = 0,
        tzinfo: datetime.tzinfo | None = None,
        *,
        planet_tz: PlanetTimezone | None = None,
    ) -> "PlanetDateTime":
        obj = super().__new__(cls, year, month, day, hour, minute, second, microsecond, tzinfo)
        object.__setattr__(obj, '_planet_tz', planet_tz)
        object.__setattr__(obj, '_planet_time_cache', None)
        return obj

    @classmethod
    def from_utc_ms(cls, utc_ms: int, planet: Planet, offset_h: float = 0.0) -> "PlanetDateTime":
        """Build a PlanetDateTime from a UTC millisecond timestamp."""
        tz   = PlanetTimezone(planet, offset_h)
        dt   = datetime.datetime.fromtimestamp(utc_ms / 1000, tz=datetime.timezone.utc).replace(tzinfo=tz)
        obj  = cls(
            dt.year, dt.month, dt.day,
            dt.hour, dt.minute, dt.second, dt.microsecond,
            tzinfo=tz, planet_tz=tz,
        )
        return obj

    @classmethod
    def _from_utc(cls, dt: datetime.datetime, tz: PlanetTimezone) -> "PlanetDateTime":
        """Internal constructor used by PlanetTimezone.fromutc()."""
        return cls(
            dt.year, dt.month, dt.day,
            dt.hour, dt.minute, dt.second, dt.microsecond,
            tzinfo=tz, planet_tz=tz,
        )

    @property
    def planet_time(self) -> PlanetTime:
        """PlanetTime for this instant on the attached planet."""
        if self._planet_time_cache is None:
            tz = self._planet_tz
            if tz is None:
                raise ValueError("No PlanetTimezone attached to this PlanetDateTime")
            utc_ms = int(self.timestamp() * 1000)
            pt = get_planet_time(tz.planet, utc_ms, tz.offset_h)
            object.__setattr__(self, '_planet_time_cache', pt)
        return self._planet_time_cache

    def strftime(self, fmt: str) -> str:
        """Extends standard strftime with planet-specific format codes.

        %J — day_in_year (or sol for Mars)
        %T — planet local time "HH:MM"
        """
        result = fmt
        if '%J' in result or '%T' in result:
            pt = self.planet_time
            result = result.replace('%J', str(pt.day_in_year if pt.sol_in_year is None else pt.sol_in_year))
            result = result.replace('%T', pt.time_str)
        return super().strftime(result)
