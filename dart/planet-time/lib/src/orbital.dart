// orbital.dart — Heliocentric position, distance, and light-travel calculations
// Ported verbatim from planet-time.js (Story 18.12)

import 'dart:math';
import 'constants.dart';
import 'models.dart';

// ── Leap seconds / TT ─────────────────────────────────────────────────────────

/// Returns TAI - UTC (leap seconds) for the given UTC milliseconds.
int taiMinusUtc(int utcMs) {
  int offset = 10;
  for (final (delta, tMs) in leapSecs) {
    if (utcMs >= tMs) {
      offset = delta;
    } else {
      break;
    }
  }
  return offset;
}

/// Returns the Julian Ephemeris Day (Terrestrial Time) from UTC milliseconds.
/// TT = UTC + (TAI−UTC) + 32.184 s
double jde(int utcMs) {
  final ttMs = utcMs + (taiMinusUtc(utcMs) + 32.184) * 1000;
  return 2440587.5 + ttMs / 86400000.0;
}

/// Returns Julian centuries from J2000.0 (TT).
double jc(int utcMs) {
  return (jde(utcMs) - j2000Jd) / 36525.0;
}

// ── Kepler solver ─────────────────────────────────────────────────────────────

/// Solve Kepler's equation M = E - e·sin(E) via Newton-Raphson (tol 1e-12).
double keplerE(double m, double e) {
  double bigE = m;
  for (int i = 0; i < 50; i++) {
    final dE = (m - bigE + e * sin(bigE)) / (1.0 - e * cos(bigE));
    bigE += dE;
    if (dE.abs() < 1e-12) break;
  }
  return bigE;
}

// ── Heliocentric position ─────────────────────────────────────────────────────

/// Compute the heliocentric ecliptic position of [planet] at [utcMs].
/// Moon uses Earth's orbital elements.
HelioPos helioPos(Planet planet, int utcMs) {
  // Moon uses Earth's orbital elements for heliocentric position
  final el = orbElems[planet] ?? orbElems[Planet.earth]!;

  final t = jc(utcMs);
  const d2r = pi / 180.0;
  const tau = 2 * pi;

  final l = ((el.l0 + el.dL * t) * d2r % tau + tau) % tau;
  final om = el.om0 * d2r;
  final bigM = ((l - om) % tau + tau) % tau;
  final e = el.e0;
  final a = el.a;

  final bigE = keplerE(bigM, e);
  final v = 2.0 * atan2(
    sqrt(1.0 + e) * sin(bigE / 2.0),
    sqrt(1.0 - e) * cos(bigE / 2.0),
  );
  final r = a * (1.0 - e * cos(bigE));
  final lon = ((v + om) % tau + tau) % tau;

  return HelioPos(
    x: r * cos(lon),
    y: r * sin(lon),
    r: r,
    lon: lon,
  );
}

// ── Distance & light travel ───────────────────────────────────────────────────

/// Returns the distance between two solar system bodies in AU.
double bodyDistanceAu(Planet a, Planet b, int utcMs) {
  final pa = helioPos(a, utcMs);
  final pb = helioPos(b, utcMs);
  final dx = pa.x - pb.x;
  final dy = pa.y - pb.y;
  return sqrt(dx * dx + dy * dy);
}

/// Returns one-way light travel time between two bodies in seconds.
double lightTravelSeconds(Planet from, Planet to, int utcMs) {
  return bodyDistanceAu(from, to, utcMs) * auSeconds;
}
