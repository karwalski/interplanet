<?php
declare(strict_types=1);

/**
 * ConstantsTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Constants;

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
        $ls   = Constants::LEAP_SECONDS;
        $last = end($ls);
        $this->assertSame(37, $last[1]);
    }
}
