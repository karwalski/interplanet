<?php
declare(strict_types=1);

/**
 * FormattingTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Formatting;

// ── 10. Formatting ────────────────────────────────────────────────────────────

class FormattingTest extends TestCase
{
    public function testFormatLightTimeZero(): void
    {
        $this->assertSame('0 s', Formatting::formatLightTime(0.0));
    }

    public function testFormatLightTimeOneMinute(): void
    {
        $this->assertSame('1 min', Formatting::formatLightTime(60.0));
    }

    public function testFormatLightTimeOneHour(): void
    {
        $this->assertSame('1 h', Formatting::formatLightTime(3600.0));
    }

    public function testFormatLightTimeMixed(): void
    {
        $this->assertSame('2 min 30 s', Formatting::formatLightTime(150.0));
    }

    public function testFormatPlanetTimeIso(): void
    {
        $result = Formatting::formatPlanetTimeIso('mars', 14, 30, 0);
        $this->assertStringContainsString('14:30:00', $result);
        $this->assertStringContainsString('mars', $result);
    }
}
