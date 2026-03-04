"""Formatting utilities for LTX — Python port of ltx-sdk.js formatHMS/formatUTC."""

from datetime import datetime, timezone


def format_hms(sec: float) -> str:
    """Format seconds as HH:MM:SS or MM:SS."""
    if sec < 0:
        sec = 0
    sec = int(sec)
    h = sec // 3600
    m = (sec % 3600) // 60
    s = sec % 60
    if h > 0:
        return f'{h:02d}:{m:02d}:{s:02d}'
    return f'{m:02d}:{s:02d}'


def format_utc(dt) -> str:
    """Format a datetime or UTC millisecond timestamp as 'HH:MM:SS UTC'."""
    if isinstance(dt, (int, float)):
        dt = datetime.fromtimestamp(dt / 1000, tz=timezone.utc)
    elif isinstance(dt, str):
        dt = datetime.fromisoformat(dt.replace('Z', '+00:00'))
    return dt.strftime('%H:%M:%S') + ' UTC'
