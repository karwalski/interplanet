<?php
declare(strict_types=1);

/**
 * FacadeTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\InterplanetTime;

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
