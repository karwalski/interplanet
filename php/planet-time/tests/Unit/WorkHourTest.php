<?php
declare(strict_types=1);

/**
 * WorkHourTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Constants;
use InterplanetTime\Time;

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
