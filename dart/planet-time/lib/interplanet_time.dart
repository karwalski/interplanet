/// InterPlanet Time — Dart 3 port (Story 18.12)
///
/// Provides solar-day time, work-schedule, orbital mechanics, and
/// light-speed calculations for every planet in the solar system.
///
/// Usage:
/// ```dart
/// import 'package:interplanet_time/interplanet_time.dart';
///
/// final now = DateTime.now().millisecondsSinceEpoch;
/// final mars = getPlanetTime(Planet.mars, now);
/// print(mars.timeStr);
/// ```
library interplanet_time;

export 'src/constants.dart';
export 'src/models.dart';
export 'src/orbital.dart';
export 'src/time_calc.dart';
export 'src/scheduling.dart';
export 'src/formatting.dart';
