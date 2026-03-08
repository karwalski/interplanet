// models.dart — Data model classes for planet-time results

/// Result of getPlanetTime().
class PlanetTime {
  /// Hour component (0–23) in planet local time.
  final int hour;
  /// Minute component (0–59).
  final int minute;
  /// Second component (0–59).
  final int second;
  /// Fractional local hour (0.0–24.0).
  final double localHour;
  /// Fraction of the planet day elapsed (0.0–1.0).
  final double dayFraction;
  /// Total number of planet days since epoch.
  final int dayNumber;
  /// Day within the current planet year (integer).
  final int dayInYear;
  /// Number of full planet years since epoch.
  final int yearNumber;
  /// Work-period index within the current planet week (0-based).
  final int periodInWeek;
  /// Whether this time falls within a work period.
  final bool isWorkPeriod;
  /// Whether this time falls within a work hour.
  final bool isWorkHour;
  /// "HH:MM" formatted string.
  final String timeStr;
  /// "HH:MM:SS" formatted string.
  final String timeStrFull;
  /// Sol within the current Mars year (null for non-Mars planets).
  final int? solInYear;
  /// Total sols per Mars year (null for non-Mars planets).
  final int? solsPerYear;
  /// Interplanetary zone identifier, e.g. "AMT+4" (null for Earth).
  final String? zoneId;

  const PlanetTime({
    required this.hour,
    required this.minute,
    required this.second,
    required this.localHour,
    required this.dayFraction,
    required this.dayNumber,
    required this.dayInYear,
    required this.yearNumber,
    required this.periodInWeek,
    required this.isWorkPeriod,
    required this.isWorkHour,
    required this.timeStr,
    required this.timeStrFull,
    this.solInYear,
    this.solsPerYear,
    this.zoneId,
  });
}

/// Result of getMtc() — Mars Coordinated Time.
class MtcResult {
  /// Total Mars sols since MY0 epoch.
  final int sol;
  /// Hour component (0–23).
  final int hour;
  /// Minute component (0–59).
  final int minute;
  /// Second component (0–59).
  final int second;
  /// "HH:MM" formatted string.
  final String mtcStr;

  const MtcResult({
    required this.sol,
    required this.hour,
    required this.minute,
    required this.second,
    required this.mtcStr,
  });
}

/// Heliocentric ecliptic position of a planet.
class HelioPos {
  /// X coordinate (AU, ecliptic plane).
  final double x;
  /// Y coordinate (AU, ecliptic plane).
  final double y;
  /// Distance from Sun (AU).
  final double r;
  /// Ecliptic longitude (radians).
  final double lon;

  const HelioPos({
    required this.x,
    required this.y,
    required this.r,
    required this.lon,
  });
}

/// An overlapping work window between two planets.
class MeetingWindow {
  /// Start of overlap (UTC ms).
  final int startMs;
  /// End of overlap (UTC ms).
  final int endMs;
  /// Duration of the window in minutes.
  final int durationMin;

  const MeetingWindow({
    required this.startMs,
    required this.endMs,
    required this.durationMin,
  });
}
