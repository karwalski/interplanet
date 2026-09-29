<?php
declare(strict_types=1);

/**
 * LineOfSightTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Orbital;

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
