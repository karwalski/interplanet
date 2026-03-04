// scheduling.dart — findMeetingWindows
// Ported verbatim from planet-time.js (Story 18.12)

import 'constants.dart';
import 'models.dart';
import 'time_calc.dart';

/// Find overlapping work windows between two planets over [earthDays] Earth days.
///
/// Scans from [startMs] (UTC ms) in 15-minute steps.
/// Returns a list of [MeetingWindow] describing each overlap period.
List<MeetingWindow> findMeetingWindows(
  Planet planetA,
  Planet planetB, {
  int earthDays = 7,
  int? startMs,
}) {
  const stepMs = 15 * 60000; // 15 minutes
  final start = startMs ?? DateTime.now().millisecondsSinceEpoch;
  final endMs = start + earthDays * earthDayMs;

  final windows = <MeetingWindow>[];
  var inWindow = false;
  var windowStart = 0;

  for (var t = start; t < endMs; t += stepMs) {
    final ta = getPlanetTime(planetA, t);
    final tb = getPlanetTime(planetB, t);
    final overlap = ta.isWorkHour && tb.isWorkHour;

    if (overlap && !inWindow) {
      inWindow = true;
      windowStart = t;
    } else if (!overlap && inWindow) {
      inWindow = false;
      windows.add(MeetingWindow(
        startMs: windowStart,
        endMs: t,
        durationMin: (t - windowStart) ~/ 60000,
      ));
    }
  }

  if (inWindow) {
    windows.add(MeetingWindow(
      startMs: windowStart,
      endMs: endMs,
      durationMin: (endMs - windowStart) ~/ 60000,
    ));
  }

  return windows;
}
