<?php
declare(strict_types=1);

/**
 * UnitTest.php — PHPUnit tests for the InterplanetTime PHP library.
 *
 * Sections:
 *   1. Constants
 *   2. JDE / JC at J2000
 *   3. TAI-UTC leap seconds
 *   4. MTC at J2000
 *   5. Light travel Earth→Mars (reference dates)
 *   6. getPlanetTime — all 9 bodies
 *   7. Work-hour logic
 *   8. Line of sight
 *   9. Meeting windows
 *   10. Formatting
 *   11. Heliocentric position sanity
 *   12. Mars sol-in-year / sols-per-year
 *
 * Run: ./vendor/bin/phpunit tests/UnitTest.php
 */

require_once __DIR__ . '/../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Constants;
use InterplanetTime\Orbital;
use InterplanetTime\Time;
use InterplanetTime\Scheduling;
use InterplanetTime\Formatting;
use InterplanetTime\InterplanetTime;

// ── 1. Constants ─────────────────────────────────────────────────────────────

class ConstantsTest extends TestCase
{
    public function testJ2000Ms(): void
    {
        $this->assertSame(946728000000, Constants::J2000_MS);
    }

    public function testMarsEpochMs(): void
    {
        $this->assertSame(-524069761536, Constants::MARS_EPOCH_MS);
    }

    public function testMarsSOlMs(): void
    {
        $this->assertSame(88775244, Constants::MARS_SOL_MS);
    }

    public function testAuKm(): void
    {
        $this->assertEqualsWithDelta(149597870.7, Constants::AU_KM, 0.1);
    }

    public function testCKms(): void
    {
        $this->assertEqualsWithDelta(299792.458, Constants::C_KMS, 0.001);
    }

    public function testAuSeconds(): void
    {
        $expected = 149597870.7 / 299792.458;
        $this->assertEqualsWithDelta($expected, Constants::AU_SECONDS, 0.1);
    }

    public function testPlanetsArrayHasNineEntries(): void
    {
        $this->assertCount(9, Constants::PLANETS);
    }

    public function testOrbitalElementsHasNineKeys(): void
    {
        $this->assertCount(9, Constants::ORBITAL_ELEMENTS);
    }

    public function testLeapSecondsNonEmpty(): void
    {
        $this->assertNotEmpty(Constants::LEAP_SECONDS);
    }

    public function testLeapSecondsLast(): void
    {
        $last = end(Constants::LEAP_SECONDS);
        $this->assertSame(37, $last[1]);
    }
}

// ── 2. JDE / JC ──────────────────────────────────────────────────────────────

class JdeJcTest extends TestCase
{
    public function testJdeAtJ2000(): void
    {
        // At J2000 (946728000000 ms), JDE ≈ 2451545.0 (within rounding from TAI correction)
        $jde = Orbital::jde(946728000000);
        $this->assertEqualsWithDelta(2451545.0, $jde, 0.01);
    }

    public function testJcAtJ2000(): void
    {
        $jc = Orbital::jc(946728000000);
        $this->assertEqualsWithDelta(0.0, $jc, 0.01);
    }

    public function testJdeIncreases(): void
    {
        $a = Orbital::jde(946728000000);
        $b = Orbital::jde(946728000000 + 86400000);
        $this->assertGreaterThan($a, $b);
    }

    public function testJcAfterOneCentury(): void
    {
        $oneHundredYears = (int)(100 * 365.25 * 86400000);
        $jc = Orbital::jc(946728000000 + $oneHundredYears);
        $this->assertEqualsWithDelta(1.0, $jc, 0.01);
    }
}

// ── 3. TAI-UTC ────────────────────────────────────────────────────────────────

class TaiMinusUtcTest extends TestCase
{
    public function testAtJ2000(): void
    {
        // 2000-01-01: TAI-UTC = 32
        $this->assertSame(32, Orbital::taiMinusUtc(946728000000));
    }

    public function testAfterLastLeapSecond(): void
    {
        // After 2017-01-01: TAI-UTC = 37
        $this->assertSame(37, Orbital::taiMinusUtc(1483228800001));
    }

    public function testBeforeFirstLeapSecond(): void
    {
        // Before 1972-01-01: TAI-UTC = 10
        $this->assertSame(10, Orbital::taiMinusUtc(0));
    }
}

// ── 4. MTC ───────────────────────────────────────────────────────────────────

class MTCTest extends TestCase
{
    public function testMTCAtJ2000(): void
    {
        $mtc = Time::getMTC(946728000000);
        $this->assertGreaterThanOrEqual(0, $mtc->hour);
        $this->assertLessThan(24, $mtc->hour);
        $this->assertGreaterThanOrEqual(0, $mtc->minute);
        $this->assertLessThan(60, $mtc->minute);
    }

    public function testMTCStrFormat(): void
    {
        $mtc = Time::getMTC(946728000000);
        $this->assertMatchesRegularExpression('/^\d{2}:\d{2}$/', $mtc->mtcStr);
    }

    public function testMTCSolNonNegative(): void
    {
        $mtc = Time::getMTC(946728000000);
        $this->assertGreaterThanOrEqual(0, $mtc->sol);
    }

    public function testMTCSolAtMarsEpoch(): void
    {
        $mtc = Time::getMTC(Constants::MARS_EPOCH_MS);
        $this->assertSame(0, $mtc->sol);
    }
}

// ── 5. Light travel ───────────────────────────────────────────────────────────

class LightTravelTest extends TestCase
{
    public function testEarthMarsAtJ2000(): void
    {
        $lt = Orbital::lightTravelSeconds('earth', 'mars', 946728000000);
        $this->assertGreaterThan(100.0, $lt);
        $this->assertLessThan(2000.0, $lt);
    }

    public function testEarthMarsOppositionAug2003(): void
    {
        // 2003-08-27 ~ closest Mars approach — ~183 s
        $ms = 1061942400000;
        $lt = Orbital::lightTravelSeconds('earth', 'mars', $ms);
        $this->assertEqualsWithDelta(185.0, $lt, 30.0);
    }

    public function testEarthMarsConjunctionApr2019(): void
    {
        // Near superior conjunction — delay > 1200 s
        $ms = 1554681600000; // 2019-04-08
        $lt = Orbital::lightTravelSeconds('earth', 'mars', $ms);
        $this->assertGreaterThan(1000.0, $lt);
    }

    public function testEarthJupiter(): void
    {
        $lt = Orbital::lightTravelSeconds('earth', 'jupiter', 946728000000);
        $this->assertGreaterThan(1000.0, $lt);
        $this->assertLessThan(5000.0, $lt);
    }

    public function testSymmetric(): void
    {
        $ab = Orbital::lightTravelSeconds('earth', 'mars', 946728000000);
        $ba = Orbital::lightTravelSeconds('mars', 'earth', 946728000000);
        $this->assertEqualsWithDelta($ab, $ba, 0.001);
    }

    public function testFormatLightTime186(): void
    {
        $this->assertSame('3 min 6 s', Formatting::formatLightTime(186.0));
    }

    public function testFormatLightTimeSeconds(): void
    {
        $this->assertSame('45 s', Formatting::formatLightTime(45.0));
    }

    public function testFormatLightTimeHours(): void
    {
        $this->assertSame('1 h 1 min 40 s', Formatting::formatLightTime(3700.0));
    }
}

// ── 6. getPlanetTime ─────────────────────────────────────────────────────────

class PlanetTimeTest extends TestCase
{
    private const REF_MS = 946728000000; // J2000

    private function assertValidTime(string $planet): void
    {
        $pt = Time::getPlanetTime($planet, self::REF_MS);
        $this->assertGreaterThanOrEqual(0, $pt->hour);
        $this->assertLessThan(24, $pt->hour);
        $this->assertGreaterThanOrEqual(0, $pt->minute);
        $this->assertLessThan(60, $pt->minute);
        $this->assertGreaterThanOrEqual(0, $pt->second);
        $this->assertLessThan(60, $pt->second);
        $this->assertMatchesRegularExpression('/^\d{2}:\d{2}$/', $pt->timeStr);
        $this->assertMatchesRegularExpression('/^\d{2}:\d{2}:\d{2}$/', $pt->timeStrFull);
    }

    public function testMercury(): void { $this->assertValidTime('mercury'); }
    public function testVenus():   void { $this->assertValidTime('venus');   }
    public function testEarth():   void { $this->assertValidTime('earth');   }
    public function testMars():    void { $this->assertValidTime('mars');    }
    public function testJupiter(): void { $this->assertValidTime('jupiter'); }
    public function testSaturn():  void { $this->assertValidTime('saturn');  }
    public function testUranus():  void { $this->assertValidTime('uranus');  }
    public function testNeptune(): void { $this->assertValidTime('neptune'); }
    public function testMoon():    void { $this->assertValidTime('moon');    }

    public function testTzOffsetShiftsHour(): void
    {
        $base   = Time::getPlanetTime('mars', self::REF_MS, 0.0);
        $offset = Time::getPlanetTime('mars', self::REF_MS, 2.0);
        $diff   = ($offset->hour * 60 + $offset->minute) - ($base->hour * 60 + $base->minute);
        // Normalize to [-23*60, 23*60]
        if ($diff > 23 * 60) $diff -= 24 * 60;
        if ($diff < -23 * 60) $diff += 24 * 60;
        $this->assertEqualsWithDelta(120.0, (float)$diff, 1.0);
    }

    public function testMarsHasSolInYear(): void
    {
        $pt = Time::getPlanetTime('mars', self::REF_MS);
        $this->assertNotNull($pt->solInYear);
        $this->assertNotNull($pt->solsPerYear);
        $this->assertSame(669, $pt->solsPerYear);
    }

    public function testEarthHasNoSolInYear(): void
    {
        $pt = Time::getPlanetTime('earth', self::REF_MS);
        $this->assertNull($pt->solInYear);
        $this->assertNull($pt->solsPerYear);
    }

    public function testDayFractionInRange(): void
    {
        $pt = Time::getPlanetTime('mars', self::REF_MS);
        $this->assertGreaterThanOrEqual(0.0, $pt->dayFraction);
        $this->assertLessThan(1.0, $pt->dayFraction);
    }
}

// ── 7. Work-hour logic ───────────────────────────────────────────────────────

class WorkHourTest extends TestCase
{
    private const WORK_START_MS = 946728000000 + 9 * 3600000;  // J2000 + 9 h

    public function testWorkHourAtNine(): void
    {
        // At exactly J2000 Earth hour = 0 (epoch reset). Use 9h past epoch.
        // Construct a time where Earth's fractional day = 9/24.
        // J2000_MS is the epoch; add exactly 9 earth hours.
        $ms = Constants::J2000_MS + 9 * 3600000;
        $pt = Time::getPlanetTime('earth', $ms);
        $this->assertGreaterThanOrEqual(9, $pt->hour);
        $this->assertLessThan(17, $pt->hour);
        $this->assertTrue($pt->isWorkHour);
    }

    public function testRestHourAtMidnight(): void
    {
        // Hour 0 → rest
        $ms = Constants::J2000_MS; // hour = 0 for Earth
        $pt = Time::getPlanetTime('earth', $ms);
        $this->assertSame(0, $pt->hour);
        $this->assertFalse($pt->isWorkHour);
    }

    public function testRestHourAtTwentyThree(): void
    {
        $ms = Constants::J2000_MS + 23 * 3600000;
        $pt = Time::getPlanetTime('earth', $ms);
        $this->assertSame(23, $pt->hour);
        $this->assertFalse($pt->isWorkHour);
    }
}

// ── 8. Line of sight ─────────────────────────────────────────────────────────

class LineOfSightTest extends TestCase
{
    public function testEarthMarsAtJ2000(): void
    {
        $los = Orbital::checkLineOfSight('earth', 'mars', 946728000000);
        $this->assertIsBool($los->clear);
        $this->assertIsBool($los->blocked);
        $this->assertGreaterThan(0.0, $los->elongDeg);
    }

    public function testBlockedNearSuperiorConjunction(): void
    {
        // 2021-10-08: Mars near superior conjunction (behind Sun from Earth)
        $ms = 1633651200000;
        $los = Orbital::checkLineOfSight('earth', 'mars', $ms);
        $this->assertFalse($los->clear);
    }

    public function testClearNearOpposition(): void
    {
        // 2020-10-13: Mars opposition — clear path
        $ms = 1602547200000;
        $los = Orbital::checkLineOfSight('earth', 'mars', $ms);
        $this->assertTrue($los->clear);
    }

    public function testClosestSunAuIsPresentOrNull(): void
    {
        $los = Orbital::checkLineOfSight('earth', 'jupiter', 946728000000);
        // closestSunAu should be non-null for distinct bodies
        $this->assertNotNull($los->closestSunAu);
    }
}

// ── 9. Meeting windows ────────────────────────────────────────────────────────

class MeetingWindowsTest extends TestCase
{
    public function testFindsMeetingWindowsEarthEarth(): void
    {
        $fromMs  = Constants::J2000_MS;
        $windows = Scheduling::findMeetingWindows('earth', 'earth', $fromMs, 1);
        // Earth and Earth always overlap
        $this->assertNotEmpty($windows);
    }

    public function testMeetingWindowsHavePositiveDuration(): void
    {
        $fromMs  = Constants::J2000_MS;
        $windows = Scheduling::findMeetingWindows('earth', 'mars', $fromMs, 7);
        foreach ($windows as $w) {
            $this->assertGreaterThan(0, $w->durationMinutes);
            $this->assertGreaterThan($w->startMs, $w->endMs);
        }
    }

    public function testMeetingWindowsArrayType(): void
    {
        $windows = Scheduling::findMeetingWindows('earth', 'mars', Constants::J2000_MS, 3);
        foreach ($windows as $w) {
            $this->assertInstanceOf(\InterplanetTime\MeetingWindow::class, $w);
        }
    }
}

// ── 10. Formatting ────────────────────────────────────────────────────────────

class FormattingTest extends TestCase
{
    public function testFormatLightTimeZero(): void
    {
        $this->assertSame('0 s', Formatting::formatLightTime(0.0));
    }

    public function testFormatLightTimeOneMinute(): void
    {
        $this->assertSame('1 min', Formatting::formatLightTime(60.0));
    }

    public function testFormatLightTimeOneHour(): void
    {
        $this->assertSame('1 h', Formatting::formatLightTime(3600.0));
    }

    public function testFormatLightTimeMixed(): void
    {
        $this->assertSame('2 min 30 s', Formatting::formatLightTime(150.0));
    }

    public function testFormatPlanetTimeIso(): void
    {
        $result = Formatting::formatPlanetTimeIso('mars', 14, 30, 0);
        $this->assertStringContainsString('14:30:00', $result);
        $this->assertStringContainsString('mars', $result);
    }
}

// ── 11. Heliocentric position ─────────────────────────────────────────────────

class HelioPosTest extends TestCase
{
    public function testEarthDistanceNearOneAu(): void
    {
        $pos = Orbital::helioPos('earth', 946728000000);
        $this->assertEqualsWithDelta(1.0, $pos->r, 0.05);
    }

    public function testMarsDistanceInRange(): void
    {
        $pos = Orbital::helioPos('mars', 946728000000);
        $this->assertGreaterThan(1.3, $pos->r);
        $this->assertLessThan(1.7, $pos->r);
    }

    public function testJupiterDistanceInRange(): void
    {
        $pos = Orbital::helioPos('jupiter', 946728000000);
        $this->assertGreaterThan(4.0, $pos->r);
        $this->assertLessThan(6.5, $pos->r);
    }

    public function testXYConsistentWithR(): void
    {
        $pos = Orbital::helioPos('earth', 946728000000);
        $r = sqrt($pos->x ** 2 + $pos->y ** 2);
        $this->assertEqualsWithDelta($pos->r, $r, 0.001);
    }
}

// ── 12. Facade ───────────────────────────────────────────────────────────────

class FacadeTest extends TestCase
{
    public function testFacadePlanetTime(): void
    {
        $pt = InterplanetTime::getPlanetTime('mars', 946728000000);
        $this->assertGreaterThanOrEqual(0, $pt->hour);
        $this->assertLessThan(24, $pt->hour);
    }

    public function testFacadeLightTravel(): void
    {
        $lt = InterplanetTime::lightTravelSeconds('earth', 'mars', 946728000000);
        $this->assertGreaterThan(100.0, $lt);
    }

    public function testFacadeFormatLightTime(): void
    {
        $this->assertSame('3 min 6 s', InterplanetTime::formatLightTime(186.0));
    }

    public function testFacadeMTC(): void
    {
        $mtc = InterplanetTime::getMTC(946728000000);
        $this->assertMatchesRegularExpression('/^\d{2}:\d{2}$/', $mtc->mtcStr);
    }

    public function testFacadeVersion(): void
    {
        $this->assertNotEmpty(InterplanetTime::VERSION);
    }

    public function testFacadeHelioPos(): void
    {
        $pos = InterplanetTime::helioPos('earth', 946728000000);
        $this->assertEqualsWithDelta(1.0, $pos->r, 0.05);
    }
}
