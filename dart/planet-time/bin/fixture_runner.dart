// fixture_runner.dart — standalone executable
// Reads reference.json and validates 54 cross-language fixture entries.
//
// Usage:
//   dart run bin/fixture_runner.dart ../../c/planet-time/fixtures/reference.json

import 'dart:convert';
import 'dart:io';
import 'package:interplanet_time/interplanet_time.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args[0]
      : '../../c/planet-time/fixtures/reference.json';

  final file = File(path);
  if (!file.existsSync()) {
    print('SKIP: fixture file not found at $path');
    print('0 passed  0 failed  (fixtures skipped)');
    exit(0);
  }

  final Map<String, dynamic> json;
  try {
    json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    stderr.writeln('Failed to parse fixture: $e');
    exit(1);
  }

  final entries = (json['entries'] as List<dynamic>).cast<Map<String, dynamic>>();

  int passed = 0;
  int failed = 0;

  for (final entry in entries) {
    final int utcMs = (entry['utc_ms'] as num).toInt();
    final String planetStr = entry['planet'] as String;
    final int expHour = (entry['hour'] as num).toInt();
    final int expMinute = (entry['minute'] as num).toInt();
    final double? expLightS = entry['light_travel_s'] != null
        ? (entry['light_travel_s'] as num).toDouble()
        : null;
    final int expPiw = entry['period_in_week'] != null
        ? (entry['period_in_week'] as num).toInt()
        : -1;
    final int expIsWorkPeriod = entry['is_work_period'] != null
        ? (entry['is_work_period'] as num).toInt()
        : -1;
    final int expIsWorkHour = entry['is_work_hour'] != null
        ? (entry['is_work_hour'] as num).toInt()
        : -1;

    final tag = '$planetStr@$utcMs';

    Planet planet;
    try {
      planet = Planet.fromString(planetStr);
    } catch (e) {
      failed++;
      print('FAIL: $tag unknown planet: $planetStr');
      continue;
    }

    final pt = getPlanetTime(planet, utcMs);

    if (pt.hour == expHour) {
      passed++;
    } else {
      failed++;
      print('FAIL: $tag hour=$expHour (got ${pt.hour})');
    }

    if (pt.minute == expMinute) {
      passed++;
    } else {
      failed++;
      print('FAIL: $tag minute=$expMinute (got ${pt.minute})');
    }

    if (expLightS != null && expLightS != 0.0 &&
        planetStr != 'earth' && planetStr != 'moon') {
      final lt = lightTravelSeconds(Planet.earth, planet, utcMs);
      if ((lt - expLightS).abs() <= 2.0) {
        passed++;
      } else {
        failed++;
        print('FAIL: $tag lightTravel — expected ${expLightS.toStringAsFixed(3)}, got ${lt.toStringAsFixed(3)}');
      }
    }

    if (expPiw >= 0) {
      if (pt.periodInWeek == expPiw) {
        passed++;
      } else {
        failed++;
        print('FAIL: $tag period_in_week=$expPiw (got ${pt.periodInWeek})');
      }
    }

    if (expIsWorkPeriod >= 0) {
      final got = pt.isWorkPeriod ? 1 : 0;
      if (got == expIsWorkPeriod) {
        passed++;
      } else {
        failed++;
        print('FAIL: $tag is_work_period=$expIsWorkPeriod (got $got)');
      }
    }

    if (expIsWorkHour >= 0) {
      final got = pt.isWorkHour ? 1 : 0;
      if (got == expIsWorkHour) {
        passed++;
      } else {
        failed++;
        print('FAIL: $tag is_work_hour=$expIsWorkHour (got $got)');
      }
    }
  }

  print('Fixture entries checked: ${entries.length}');
  print('$passed passed  $failed failed');

  if (failed > 0) {
    exit(1);
  }
}
