<?php
declare(strict_types=1);

/**
 * JdeJcTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Orbital;

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
