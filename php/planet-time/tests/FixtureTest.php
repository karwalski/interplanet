<?php
declare(strict_types=1);

/**
 * FixtureTest.php — Cross-language fixture validation for the PHP library.
 *
 * Reads interplanet-github/c/fixtures/reference.json and validates that
 * InterplanetTime::getPlanetTime() and lightTravelSeconds() match.
 *
 * Usage:
 *   php tests/FixtureTest.php [path/to/reference.json]
 *
 * If the fixture file is not found, the test exits 0 with a SKIP message.
 */

require_once __DIR__ . '/../src/autoload.php';

use InterplanetTime\InterplanetTime;

$fixturePath = $argv[1] ?? __DIR__ . '/../../c/fixtures/reference.json';

if (!file_exists($fixturePath)) {
    echo "SKIP: fixture file not found at $fixturePath\n";
    echo "0 passed  0 failed  (fixtures skipped)\n";
    exit(0);
}

$data    = json_decode(file_get_contents($fixturePath), true);
$entries = $data['entries'] ?? [];

$passed  = 0;
$failed  = 0;
$count   = 0;

function check(string $name, bool $cond): void
{
    global $passed, $failed;
    if ($cond) {
        $passed++;
    } else {
        $failed++;
        echo "FAIL: $name\n";
    }
}

function approx(string $name, float $actual, float $expected, float $delta): void
{
    global $passed, $failed;
    if (abs($actual - $expected) <= $delta) {
        $passed++;
    } else {
        $failed++;
        $a = number_format($actual, 3);
        $e = number_format($expected, 3);
        echo "FAIL: $name — expected $e, got $a\n";
    }
}

foreach ($entries as $entry) {
    $utcMs  = (int)$entry['utc_ms'];
    $planet = $entry['planet'];
    $expHr  = (int)$entry['hour'];
    $expMin = (int)$entry['minute'];
    $lt     = isset($entry['light_travel_s']) ? (float)$entry['light_travel_s'] : null;

    try {
        $pt  = InterplanetTime::getPlanetTime($planet, $utcMs);
        $tag = "{$planet}@{$utcMs}";

        check("$tag hour={$expHr}",   $pt->hour === $expHr);
        check("$tag minute={$expMin}", $pt->minute === $expMin);

        if ($lt !== null && $planet !== 'earth' && $planet !== 'moon') {
            $actLt = InterplanetTime::lightTravelSeconds('earth', $planet, $utcMs);
            approx("$tag lightTravel", $actLt, $lt, 2.0);
        }

        $count++;
    } catch (Throwable $e) {
        $failed++;
        echo "FAIL: {$planet}@{$utcMs} — {$e->getMessage()}\n";
    }
}

echo "Fixture entries checked: $count\n";
echo "$passed passed  $failed failed\n";

exit($failed > 0 ? 1 : 0);
