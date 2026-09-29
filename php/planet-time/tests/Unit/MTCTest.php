<?php
declare(strict_types=1);

/**
 * MTCTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Constants;
use InterplanetTime\Time;

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
