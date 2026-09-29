<?php
declare(strict_types=1);

/**
 * LightTravelTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Orbital;
use InterplanetTime\Formatting;

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
