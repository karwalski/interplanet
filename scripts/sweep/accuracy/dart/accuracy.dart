// Accuracy harness for dart/planet-time (see ../gen-cases-group2.js).
// Run from dart/planet-time after `dart pub get`:
//   dart --packages=.dart_tool/package_config.json \
//     ../../scripts/sweep/accuracy/dart/accuracy.dart ../../scripts/sweep/accuracy/instants-group2.txt
import 'dart:io';

import 'package:interplanet_time/interplanet_time.dart';

void main(List<String> args) {
  const bodies = [
    Planet.mercury, Planet.venus, Planet.earth, Planet.mars, Planet.jupiter,
    Planet.saturn, Planet.uranus, Planet.neptune, Planet.moon,
  ];
  int b(bool v) => v ? 1 : 0;
  final out = StringBuffer();
  for (final raw in File(args[0]).readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final ms = int.parse(line);
    for (final body in bodies) {
      try {
        final pt = getPlanetTime(body, ms);
        final lt = lightTravelSeconds(body, Planet.earth, ms);
        out.writeln([ms, body.name, pt.hour, pt.minute, pt.second, pt.dayNumber,
            pt.dayInYear, pt.yearNumber, pt.periodInWeek, b(pt.isWorkPeriod),
            b(pt.isWorkHour), lt.toStringAsFixed(6)].join('\t'));
      } catch (e) {
        stderr.writeln('$ms ${body.name}: $e');
      }
    }
    final m = getMtc(ms);
    out.writeln([ms, 'mtc', m.sol, m.hour, m.minute, m.second].join('\t'));
  }
  stdout.write(out);
}
