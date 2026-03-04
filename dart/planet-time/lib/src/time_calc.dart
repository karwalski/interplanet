// time_calc.dart — getPlanetTime and getMtc
// Ported verbatim from planet-time.js (Story 18.12)

import 'constants.dart';
import 'models.dart';

// ── Planet time ───────────────────────────────────────────────────────────────

/// Get the local time on [planet] at [utcMs].
///
/// [tzOffsetH] is the optional zone offset in planet local hours from the
/// planet's prime meridian (e.g. +4 for AMT+4 on Mars).
PlanetTime getPlanetTime(Planet planet, int utcMs, {double tzOffsetH = 0.0}) {
  // Moon uses Earth's solar day (tidally locked; work schedules run on Earth time)
  final effective = (planet == Planet.moon) ? Planet.earth : planet;
  final pd = planetDataMap[effective]!;

  final solarDay = pd.solarDayMs.toDouble();
  final elapsedMs = (utcMs - pd.epochMs).toDouble() + tzOffsetH / 24.0 * solarDay;
  final totalDays = elapsedMs / solarDay;
  final dayNumber = totalDays.floor();
  final dayFrac = totalDays - dayNumber;

  final localHour = dayFrac * 24.0;
  final h = localHour.floor();
  final minF = (localHour - h) * 60.0;
  final m = minF.floor();
  final s = ((minF - m) * 60.0).floor();

  // Work period (positive modulo so pre-epoch dates return valid range)
  final int piw;
  final bool isWorkPeriod;
  final bool isWorkHour;
  if (pd.earthClockSched) {
    // Mercury/Venus: solar day >> circadian rhythm; use UTC Earth-clock scheduling
    // UTC day-of-week: ((floor(utcMs / 86400000) % 7 + 10) % 7 → Mon=0..Sun=6
    // (+7 before +3 ensures positive result for pre-1970 timestamps)
    final utcDay = (utcMs / 86400000.0).floor();
    piw = ((utcDay % 7 + 10) % 7).toInt();
    isWorkPeriod = piw < pd.workPeriodsPerWeek;
    // UTC hour within the day — positive modulo handles pre-1970 timestamps
    final msInDay = ((utcMs % 86400000) + 86400000) % 86400000;
    final utcHour = msInDay / 3600000.0;
    isWorkHour = isWorkPeriod && utcHour >= pd.workStart && utcHour < pd.workEnd;
  } else {
    final totalPeriods = totalDays / pd.daysPerPeriod;
    piw = ((totalPeriods.floor() % pd.periodsPerWeek) + pd.periodsPerWeek) % pd.periodsPerWeek;
    isWorkPeriod = piw < pd.workPeriodsPerWeek;
    isWorkHour = isWorkPeriod && localHour >= pd.workStart && localHour < pd.workEnd;
  }

  final yearLenDays = pd.siderealYrMs / solarDay;
  final yearNumber = (totalDays / yearLenDays).floor();
  final dayInYear = (totalDays - yearNumber * yearLenDays).floor();

  int? solInYear;
  int? solsPerYear;
  if (effective == Planet.mars) {
    solInYear = dayInYear;
    solsPerYear = (pd.siderealYrMs / solarDay + 0.5).floor();
  }

  final hStr = h.toString().padLeft(2, '0');
  final mStr = m.toString().padLeft(2, '0');
  final sStr = s.toString().padLeft(2, '0');

  return PlanetTime(
    hour: h,
    minute: m,
    second: s,
    localHour: localHour,
    dayFraction: dayFrac,
    dayNumber: dayNumber,
    dayInYear: dayInYear,
    yearNumber: yearNumber,
    periodInWeek: piw,
    isWorkPeriod: isWorkPeriod,
    isWorkHour: isWorkHour,
    timeStr: '$hStr:$mStr',
    timeStrFull: '$hStr:$mStr:$sStr',
    solInYear: solInYear,
    solsPerYear: solsPerYear,
  );
}

// ── Mars Coordinated Time ─────────────────────────────────────────────────────

/// Get Mars Coordinated Time (MTC) — the Martian equivalent of UTC.
MtcResult getMtc(int utcMs) {
  final totalSols = (utcMs - marsEpochMs) / marsSolMs.toDouble();
  final sol = totalSols.floor();
  final frac = totalSols - sol;

  final h = (frac * 24).floor();
  final m = ((frac * 24 - h) * 60).floor();
  final s = (((frac * 24 - h) * 60 - m) * 60).floor();

  final hStr = h.toString().padLeft(2, '0');
  final mStr = m.toString().padLeft(2, '0');

  return MtcResult(
    sol: sol,
    hour: h,
    minute: m,
    second: s,
    mtcStr: '$hStr:$mStr',
  );
}
