<?php
declare(strict_types=1);

/**
 * MeetingWindowsTest.php: PHPUnit tests for the InterplanetTime PHP library.
 * Split out of the former multi-class tests/UnitTest.php so that
 * PHPUnit 10+ (one test class per file) discovers every test case.
 *
 * Run all unit tests: ./vendor/bin/phpunit   (uses phpunit.xml)
 */

require_once __DIR__ . '/../../src/autoload.php';

use PHPUnit\Framework\TestCase;
use InterplanetTime\Constants;
use InterplanetTime\Scheduling;

// ── 9. Meeting windows ────────────────────────────────────────────────────────

class MeetingWindowsTest extends TestCase
{
    public function testFindsMeetingWindowsEarthEarth(): void
    {
        $fromMs  = Constants::J2000_MS;
        $windows = Scheduling::findMeetingWindows('earth', 'earth', $fromMs, 1);
        // Earth and Earth always overlap
        $this->assertNotEmpty($windows);
    }

    public function testMeetingWindowsHavePositiveDuration(): void
    {
        $fromMs  = Constants::J2000_MS;
        $windows = Scheduling::findMeetingWindows('earth', 'mars', $fromMs, 7);
        // The list may legitimately be empty; assert its type so the test is never "risky".
        $this->assertIsArray($windows);
        foreach ($windows as $w) {
            $this->assertGreaterThan(0, $w->durationMinutes);
            $this->assertGreaterThan($w->startMs, $w->endMs);
        }
    }

    public function testMeetingWindowsArrayType(): void
    {
        $windows = Scheduling::findMeetingWindows('earth', 'mars', Constants::J2000_MS, 3);
        $this->assertIsArray($windows);
        foreach ($windows as $w) {
            $this->assertInstanceOf(\InterplanetTime\MeetingWindow::class, $w);
        }
    }
}
