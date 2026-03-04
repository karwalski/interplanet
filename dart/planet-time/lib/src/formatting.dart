// formatting.dart — formatLightTime
// Ported verbatim from planet-time.js (Story 18.12)

/// Format a light travel time in seconds as a human-readable string.
///
/// Examples:
/// - 0.0001 → '<1ms'
/// - 0.5    → '500ms'
/// - 30.0   → '30.0s'
/// - 150.0  → '2.5min'
/// - 4000.0 → '1h 7m'
String formatLightTime(double seconds) {
  if (seconds < 0.001) return '<1ms';
  if (seconds < 1) return '${(seconds * 1000).toStringAsFixed(0)}ms';
  if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
  if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(1)}min';
  final h = (seconds / 3600).floor();
  final m = ((seconds % 3600) / 60).round();
  return '${h}h ${m}m';
}
