<?php
declare(strict_types=1);

/**
 * TaiMinusUtcTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Orbital;

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
