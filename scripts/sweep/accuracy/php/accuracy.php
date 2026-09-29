<?php
// Accuracy harness for php/planet-time (see ../gen-cases-group2.js).
// Run from php/planet-time:
//   php ../../scripts/sweep/accuracy/php/accuracy.php ../../scripts/sweep/accuracy/instants-group2.txt
declare(strict_types=1);

require getcwd() . '/src/autoload.php';

use InterplanetTime\InterplanetTime;

$bodies = ['mercury', 'venus', 'earth', 'mars', 'jupiter', 'saturn', 'uranus', 'neptune', 'moon'];
$b = static fn(bool $v): int => $v ? 1 : 0;

foreach (file($argv[1], FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
    $ms = (int) trim($line);
    foreach ($bodies as $body) {
        try {
            $pt = InterplanetTime::getPlanetTime($body, $ms);
            $lt = InterplanetTime::lightTravelSeconds($body, 'earth', $ms);
        } catch (\Throwable $e) {
            fwrite(STDERR, "$ms $body: {$e->getMessage()}\n");
            continue;
        }
        echo implode("\t", [$ms, $body, $pt->hour, $pt->minute, $pt->second, $pt->dayNumber,
            $pt->dayInYear, $pt->yearNumber, $pt->periodInWeek, $b($pt->isWorkPeriod),
            $b($pt->isWorkHour), sprintf('%.6f', $lt)]), "\n";
    }
    $m = InterplanetTime::getMTC($ms);
    echo implode("\t", [$ms, 'mtc', $m->sol, $m->hour, $m->minute, $m->second]), "\n";
}
