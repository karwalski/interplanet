/// InterPlanet LTX SDK — Dart port (Story 33.11)
///
/// Provides a pure Dart 3 implementation of the LTX (Light-Time eXchange)
/// meeting protocol SDK. No external dependencies — stdlib only.
///
/// Usage:
/// ```dart
/// import 'package:interplanet_ltx/interplanet_ltx.dart';
///
/// final plan = createPlan(title: 'Mars Session', start: '2024-01-15T14:00:00Z');
/// print(makePlanId(plan));
/// print(generateIcs(plan));
/// ```
library interplanet_ltx;

export 'src/constants.dart';
export 'src/models.dart';
export 'src/core.dart';
export 'src/rest_client.dart';
export 'src/security.dart';
