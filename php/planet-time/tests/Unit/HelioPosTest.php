<?php
declare(strict_types=1);

/**
 * HelioPosTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Orbital;

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
