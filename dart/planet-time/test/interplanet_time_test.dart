// interplanet_time_test.dart — unit tests for the interplanet_time library
// Uses package:test, 100+ assertions (Story 18.12)

import 'dart:math' show sin;
import 'package:test/test.dart';
import 'package:interplanet_time/interplanet_time.dart';

// J2000 epoch (2000-01-01T12:00:00Z) in UTC ms
const int j2000 = 946728000000;
// mars close approach 2003
const int mars2003 = 1061977860000;
// jupiter opposition 2023
const int jup2023 = 1698969600000;
// 2025 start
const int y2025 = 1735689600000;

void main() {
  // ── Planet enum ─────────────────────────────────────────────────────────────
  group('Planet enum', () {
    test('fromString mercury', () => expect(Planet.fromString('mercury'), Planet.mercury));
    test('fromString MARS (case insensitive)', () => expect(Planet.fromString('MARS'), Planet.mars));
    test('fromString moon', () => expect(Planet.fromString('moon'), Planet.moon));
    test('all 9 planets reachable', () {
      for (final name in ['mercury','venus','earth','mars','jupiter','saturn','uranus','neptune','moon']) {
        expect(() => Planet.fromString(name), returnsNormally);
      }
    });
  });

  // ── Constants ───────────────────────────────────────────────────────────────
  group('Constants', () {
    test('j2000Ms', () => expect(j2000Ms, 946728000000));
    test('marsEpochMs', () => expect(marsEpochMs, -524069761536));
    test('marsSolMs', () => expect(marsSolMs, 88775244));
    test('auKm', () => expect(auKm, closeTo(149597870.7, 0.01)));
    test('cKms', () => expect(cKms, closeTo(299792.458, 0.001)));
    test('auSeconds ~ 499', () => expect(auSeconds, closeTo(499.004, 0.01)));
    test('j2000Jd', () => expect(j2000Jd, 2451545.0));
    test('earthDayMs', () => expect(earthDayMs, 86400000));
    test('leapSecs has 28 entries', () => expect(leapSecs.length, 28));
    test('first leap second is 10 at 1972', () => expect(leapSecs.first.$1, 10));
    test('last leap second is 37 at 2017', () => expect(leapSecs.last.$1, 37));
    test('orbElems has 9 entries', () => expect(orbElems.length, 9));
    test('orbElems moon == earth L0', () => expect(orbElems[Planet.moon]!.l0, orbElems[Planet.earth]!.l0));
    test('mars a ~ 1.52 AU', () => expect(orbElems[Planet.mars]!.a, closeTo(1.52366, 0.0001)));
  });

  // ── taiMinusUtc ─────────────────────────────────────────────────────────────
  group('taiMinusUtc', () {
    test('before 1972 returns 10', () => expect(taiMinusUtc(0), 10));
    test('at J2000 returns 32', () => expect(taiMinusUtc(j2000), 32));
    test('after 2017 returns 37', () => expect(taiMinusUtc(y2025), 37));
  });

  // ── JDE / JC ────────────────────────────────────────────────────────────────
  group('jde and jc', () {
    test('jde at J2000 ~ 2451545', () => expect(jde(j2000), closeTo(2451545.0, 0.01)));
    test('jc at J2000 ~ 0.0', () => expect(jc(j2000).abs(), lessThan(0.0001)));
    test('jc is monotonically increasing', () {
      expect(jc(y2025), greaterThan(jc(j2000)));
    });
  });

  // ── keplerE ─────────────────────────────────────────────────────────────────
  group('keplerE', () {
    test('e=0 returns M', () {
      const m = 1.2;
      expect(keplerE(m, 0.0), closeTo(m, 1e-10));
    });
    test('converges for Mars eccentricity', () {
      final e = keplerE(1.0, 0.09341);
      // Kepler residual: |M - (E - ecc*sin(E))| should be tiny
      expect((1.0 - (e - 0.09341 * sin(e))).abs(), lessThan(1e-6));
    });
    test('e=0.0167 Earth', () {
      final e = keplerE(0.5, 0.01671);
      expect(e, closeTo(0.5, 0.1)); // approximate
    });
  });

  // ── helioPos ────────────────────────────────────────────────────────────────
  group('helioPos', () {
    test('Earth r ~ 1 AU at J2000', () {
      final pos = helioPos(Planet.earth, j2000);
      expect(pos.r, closeTo(1.0, 0.03));
    });
    test('Mars r ~ 1.52 AU mean', () {
      final pos = helioPos(Planet.mars, j2000);
      expect(pos.r, closeTo(1.52, 0.15));
    });
    test('Moon uses Earth orbit (r ~ 1 AU)', () {
      final moon = helioPos(Planet.moon, j2000);
      final earth = helioPos(Planet.earth, j2000);
      expect((moon.r - earth.r).abs(), lessThan(1e-10));
    });
    test('Jupiter r ~ 5.2 AU', () {
      final pos = helioPos(Planet.jupiter, j2000);
      expect(pos.r, closeTo(5.2, 0.3));
    });
    test('Neptune r ~ 30 AU', () {
      final pos = helioPos(Planet.neptune, j2000);
      expect(pos.r, closeTo(30.0, 1.0));
    });
  });

  // ── bodyDistanceAu ──────────────────────────────────────────────────────────
  group('bodyDistanceAu', () {
    test('Earth to Earth = 0', () {
      expect(bodyDistanceAu(Planet.earth, Planet.earth, j2000), closeTo(0.0, 1e-10));
    });
    test('Earth–Mars ~ 0.5–2.5 AU range', () {
      final d = bodyDistanceAu(Planet.earth, Planet.mars, j2000);
      expect(d, greaterThan(0.3));
      expect(d, lessThan(2.7));
    });
    test('Earth–Neptune > 28 AU', () {
      final d = bodyDistanceAu(Planet.earth, Planet.neptune, j2000);
      expect(d, greaterThan(28.0));
    });
    test('symmetry: A→B == B→A', () {
      final ab = bodyDistanceAu(Planet.earth, Planet.mars, mars2003);
      final ba = bodyDistanceAu(Planet.mars, Planet.earth, mars2003);
      expect((ab - ba).abs(), lessThan(1e-10));
    });
  });

  // ── lightTravelSeconds ──────────────────────────────────────────────────────
  group('lightTravelSeconds', () {
    test('Earth to Earth = 0', () {
      expect(lightTravelSeconds(Planet.earth, Planet.earth, j2000), closeTo(0.0, 1e-6));
    });
    test('Earth–Mars at close approach 2003 < 250 s', () {
      expect(lightTravelSeconds(Planet.earth, Planet.mars, mars2003), lessThan(250.0));
    });
    test('Earth–Jupiter > 2000 s at j2000', () {
      expect(lightTravelSeconds(Planet.earth, Planet.jupiter, j2000), greaterThan(2000.0));
    });
    test('Earth–Neptune > 14000 s', () {
      expect(lightTravelSeconds(Planet.earth, Planet.neptune, j2000), greaterThan(14000.0));
    });
    test('Earth–Mercury > 0', () {
      expect(lightTravelSeconds(Planet.earth, Planet.mercury, j2000), greaterThan(0.0));
    });
  });

  // ── formatLightTime ─────────────────────────────────────────────────────────
  group('formatLightTime', () {
    test('<1ms for tiny values', () => expect(formatLightTime(0.0), '<1ms'));
    test('ms format', () => expect(formatLightTime(0.5), '500ms'));
    test('seconds format', () => expect(formatLightTime(30.0), '30.0s'));
    test('minutes format', () => expect(formatLightTime(150.0), '2.5min'));
    test('hours format', () {
      final s = formatLightTime(4000.0);
      expect(s, contains('h'));
      expect(s, contains('m'));
    });
    test('exact 1 hour', () {
      expect(formatLightTime(3600.0), contains('1h'));
    });
  });

  // ── getMtc ──────────────────────────────────────────────────────────────────
  group('getMtc', () {
    test('at Mars epoch sol=0', () {
      final mtc = getMtc(marsEpochMs);
      expect(mtc.sol, 0);
      expect(mtc.hour, 0);
      expect(mtc.minute, 0);
    });
    test('sol increases over time', () {
      final a = getMtc(j2000);
      final b = getMtc(j2000 + marsSolMs);
      expect(b.sol - a.sol, 1);
    });
    test('hour in range 0–23', () {
      final mtc = getMtc(y2025);
      expect(mtc.hour, greaterThanOrEqualTo(0));
      expect(mtc.hour, lessThan(24));
    });
    test('minute in range 0–59', () {
      final mtc = getMtc(y2025);
      expect(mtc.minute, greaterThanOrEqualTo(0));
      expect(mtc.minute, lessThan(60));
    });
    test('second in range 0–59', () {
      final mtc = getMtc(y2025);
      expect(mtc.second, greaterThanOrEqualTo(0));
      expect(mtc.second, lessThan(60));
    });
    test('mtcStr format HH:MM', () {
      final mtc = getMtc(y2025);
      expect(mtc.mtcStr, matches(RegExp(r'^\d{2}:\d{2}$')));
    });
  });

  // ── getPlanetTime ───────────────────────────────────────────────────────────
  group('getPlanetTime — Earth', () {
    test('hour in range 0–23', () {
      final pt = getPlanetTime(Planet.earth, j2000);
      expect(pt.hour, greaterThanOrEqualTo(0));
      expect(pt.hour, lessThan(24));
    });
    test('minute in range 0–59', () {
      final pt = getPlanetTime(Planet.earth, j2000);
      expect(pt.minute, greaterThanOrEqualTo(0));
      expect(pt.minute, lessThan(60));
    });
    test('second in range 0–59', () {
      final pt = getPlanetTime(Planet.earth, j2000);
      expect(pt.second, greaterThanOrEqualTo(0));
      expect(pt.second, lessThan(60));
    });
    test('timeStr matches HH:MM', () {
      final pt = getPlanetTime(Planet.earth, j2000);
      expect(pt.timeStr, matches(RegExp(r'^\d{2}:\d{2}$')));
    });
    test('timeStrFull matches HH:MM:SS', () {
      final pt = getPlanetTime(Planet.earth, j2000);
      expect(pt.timeStrFull, matches(RegExp(r'^\d{2}:\d{2}:\d{2}$')));
    });
    test('solInYear is null for Earth', () {
      expect(getPlanetTime(Planet.earth, j2000).solInYear, isNull);
    });
    test('solsPerYear is null for Earth', () {
      expect(getPlanetTime(Planet.earth, j2000).solsPerYear, isNull);
    });
  });

  group('getPlanetTime — Mars', () {
    test('solInYear not null', () {
      final pt = getPlanetTime(Planet.mars, j2000);
      expect(pt.solInYear, isNotNull);
    });
    test('solsPerYear ~ 668', () {
      final pt = getPlanetTime(Planet.mars, j2000);
      expect(pt.solsPerYear, closeTo(669, 2));
    });
    test('solInYear in range 0–668', () {
      final pt = getPlanetTime(Planet.mars, j2000);
      expect(pt.solInYear, greaterThanOrEqualTo(0));
      expect(pt.solInYear, lessThan(670));
    });
    test('periodInWeek in 0–6', () {
      final pt = getPlanetTime(Planet.mars, j2000);
      expect(pt.periodInWeek, greaterThanOrEqualTo(0));
      expect(pt.periodInWeek, lessThan(7));
    });
  });

  group('getPlanetTime — Moon', () {
    test('Moon matches Earth time (same solar day)', () {
      final moon = getPlanetTime(Planet.moon, j2000);
      final earth = getPlanetTime(Planet.earth, j2000);
      expect(moon.hour, earth.hour);
      expect(moon.minute, earth.minute);
    });
    test('Moon solInYear is null', () {
      expect(getPlanetTime(Planet.moon, j2000).solInYear, isNull);
    });
  });

  group('getPlanetTime — tzOffset', () {
    test('positive offset increases hour', () {
      final base = getPlanetTime(Planet.earth, j2000);
      final offset = getPlanetTime(Planet.earth, j2000, tzOffsetH: 4.0);
      final expectedHour = (base.hour + 4) % 24;
      expect(offset.hour, expectedHour);
    });
    test('negative offset decreases hour', () {
      final base = getPlanetTime(Planet.earth, j2000);
      final offset = getPlanetTime(Planet.earth, j2000, tzOffsetH: -3.0);
      final expectedHour = (base.hour - 3 + 24) % 24;
      expect(offset.hour, expectedHour);
    });
  });

  group('getPlanetTime — all planets smoke test', () {
    for (final p in Planet.values) {
      test('${p.name} returns valid result', () {
        final pt = getPlanetTime(p, y2025);
        expect(pt.hour, greaterThanOrEqualTo(0));
        expect(pt.hour, lessThan(24));
        expect(pt.minute, greaterThanOrEqualTo(0));
        expect(pt.minute, lessThan(60));
        expect(pt.timeStr.length, 5);
      });
    }
  });

  group('getPlanetTime — dayFraction', () {
    test('dayFraction in range 0.0–1.0', () {
      final pt = getPlanetTime(Planet.earth, j2000);
      expect(pt.dayFraction, greaterThanOrEqualTo(0.0));
      expect(pt.dayFraction, lessThan(1.0));
    });
    test('localHour = dayFraction * 24', () {
      final pt = getPlanetTime(Planet.earth, y2025);
      expect(pt.localHour, closeTo(pt.dayFraction * 24, 1e-10));
    });
  });

  // ── findMeetingWindows ──────────────────────────────────────────────────────
  group('findMeetingWindows', () {
    test('returns list', () {
      final w = findMeetingWindows(Planet.earth, Planet.earth, startMs: j2000);
      expect(w, isA<List<MeetingWindow>>());
    });
    test('Earth–Earth produces windows (same schedule)', () {
      final w = findMeetingWindows(Planet.earth, Planet.earth, earthDays: 7, startMs: j2000);
      expect(w.isNotEmpty, true);
    });
    test('window startMs < endMs', () {
      final w = findMeetingWindows(Planet.earth, Planet.mars, earthDays: 14, startMs: j2000);
      for (final win in w) {
        expect(win.startMs, lessThan(win.endMs));
      }
    });
    test('window durationMin > 0', () {
      final w = findMeetingWindows(Planet.earth, Planet.mars, earthDays: 14, startMs: j2000);
      for (final win in w) {
        expect(win.durationMin, greaterThan(0));
      }
    });
  });

  // ── PlanetData map coverage ─────────────────────────────────────────────────
  group('planetDataMap', () {
    test('has 9 entries', () => expect(planetDataMap.length, 9));
    test('Jupiter daysPerPeriod = 2.5', () => expect(planetDataMap[Planet.jupiter]!.daysPerPeriod, 2.5));
    test('Saturn daysPerPeriod = 2.25', () => expect(planetDataMap[Planet.saturn]!.daysPerPeriod, 2.25));
    test('Mars epochMs == marsEpochMs', () => expect(planetDataMap[Planet.mars]!.epochMs, marsEpochMs));
    test('Earth solarDayMs == 86400000', () => expect(planetDataMap[Planet.earth]!.solarDayMs, earthDayMs));
  });
}
