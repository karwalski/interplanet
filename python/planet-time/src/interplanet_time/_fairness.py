"""
_fairness.py — Scheduling fairness scoring for interplanet_time.
"""

from __future__ import annotations
import math
from zoneinfo import ZoneInfo

from ._models import MeetingWindow

__all__ = ["calculate_fairness_score"]


def calculate_fairness_score(
    windows: list[MeetingWindow],
    party_a_tz: str,
    party_b_tz: str,
) -> dict:
    """Calculate scheduling fairness across a list of meeting windows.

    For each window, checks whether the midpoint falls within standard
    working hours (09:00–17:00) for each party in their local timezone.
    Returns an overall fairness score (0–100) and per-party stats.

    Parameters
    ----------
    windows:     list[MeetingWindow] from find_meeting_windows()
    party_a_tz:  IANA timezone string for party A (e.g. "America/Chicago")
    party_b_tz:  IANA timezone string for party B (e.g. "Asia/Tokyo")

    Returns
    -------
    dict with keys:
        overall (int): 0–100 fairness score (100 = perfectly fair)
        per_party (list[dict]): per-party stats
        fairness (str): 'good' (≥75), 'ok' (≥40), or 'poor'
    """
    if not windows:
        return {"overall": 100, "per_party": [], "fairness": "good"}

    import datetime

    tzs = [ZoneInfo(party_a_tz), ZoneInfo(party_b_tz)]
    labels = [party_a_tz, party_b_tz]
    total = len(windows)

    per_party = []
    for tz, label in zip(tzs, labels):
        off_count = 0
        for w in windows:
            mid_ms = (w.start_ms + w.end_ms) // 2
            dt = datetime.datetime.fromtimestamp(mid_ms / 1000, tz=tz)
            h  = dt.hour
            wd = dt.weekday()  # 0=Mon … 6=Sun
            if not (0 <= wd <= 4 and 9 <= h < 17):
                off_count += 1
        per_party.append({
            "tz": label,
            "off_hour_count": off_count,
            "pct": off_count / total,
        })

    mean     = sum(p["pct"] for p in per_party) / len(per_party)
    variance = sum((p["pct"] - mean) ** 2 for p in per_party) / len(per_party)
    stddev   = math.sqrt(variance)
    overall  = max(0, round(100 * (1 - stddev * 2)))
    fairness = "good" if overall >= 75 else ("ok" if overall >= 40 else "poor")

    return {"overall": overall, "per_party": per_party, "fairness": fairness}
