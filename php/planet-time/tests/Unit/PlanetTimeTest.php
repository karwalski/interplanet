<?php
declare(strict_types=1);

/**
 * PlanetTimeTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Time;

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
