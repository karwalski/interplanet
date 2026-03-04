<?php
/**
 * InterPlanet Time REST API — api/time.php
 *
 * GET  ?action=planet   &body=mars[&at=ISO][&tz_offset=N]
 * GET  ?action=distance &from=earth&to=mars[&at=ISO]
 * POST ?action=windows  body: {"locations":[...],"from_utc":"...","horizon_days":14}
 *
 * All timestamps are ISO 8601 UTC. All distances are AU. All delays are seconds.
 * Orbital mechanics port of planet-time.js (Meeus Table 31.a).
 */

declare(strict_types=1);

// ── CORS + helpers ────────────────────────────────────────────────────────────

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, Authorization');

if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') {
    http_response_code(204);
    exit;
}

function jsonOk(array $data): never {
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
    exit;
}

function jsonError(string $msg, int $code = 400): never {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode(['error' => $msg]);
    exit;
}

function parseAt(?string $s): float {
    if (!$s) return (float)time();
    try {
        $dt = new DateTimeImmutable($s, new DateTimeZone('UTC'));
        return (float)$dt->getTimestamp();
    } catch (Throwable) {
        jsonError("Invalid 'at' timestamp: $s");
    }
}

function parsedBody(): array {
    $raw = file_get_contents('php://input');
    if (!$raw) jsonError('Empty body');
    $data = json_decode($raw, true);
    if (!is_array($data)) jsonError('Invalid JSON body');
    return $data;
}

// ── Constants (from planet-time.js) ──────────────────────────────────────────

const J2000_UNIX   = 946728000.0;   // 2000-01-01T12:00:00 UTC as Unix seconds
const J2000_JD     = 2451545.0;     // Julian Day of J2000.0
const AU_KM        = 149597870.7;   // km per AU (IAU 2012 exact)
const C_KMS        = 299792.458;    // km/s (SI exact)
const AU_SECONDS   = 499.004784;    // AU_KM / C_KMS
const EARTH_DAY_S  = 86400.0;       // seconds in an Earth day
const TAI_UTC_2026 = 37;            // current TAI−UTC offset (seconds, since 2017-01-01)
const MARS_EPOCH   = -524559361.536;// Unix s: 1953-05-24 09:03:58.464 UTC (MY0)
const MARS_SOL_S   = 88775.244;     // seconds per Mars sol

// Orbital elements — Meeus Table 31.a (J2000.0 epoch)
// L0: mean longitude (deg), dL: rate (deg/Julian century), om0: perihelion longitude (deg)
// e0: eccentricity, a: semi-major axis (AU)
const ORBITAL_ELEMENTS = [
    'mercury' => ['L0' => 252.2507, 'dL' => 149474.0722, 'om0' =>  77.4561, 'e0' => 0.20564, 'a' => 0.38710],
    'venus'   => ['L0' => 181.9798, 'dL' =>  58519.2130, 'om0' => 131.5637, 'e0' => 0.00677, 'a' => 0.72333],
    'earth'   => ['L0' => 100.4664, 'dL' =>  36000.7698, 'om0' => 102.9373, 'e0' => 0.01671, 'a' => 1.00000],
    'mars'    => ['L0' => 355.4330, 'dL' =>  19141.6964, 'om0' => 336.0600, 'e0' => 0.09341, 'a' => 1.52366],
    'jupiter' => ['L0' =>  34.3515, 'dL' =>   3036.3027, 'om0' =>  14.3320, 'e0' => 0.04849, 'a' => 5.20336],
    'saturn'  => ['L0' =>  50.0775, 'dL' =>   1223.5093, 'om0' =>  93.0572, 'e0' => 0.05551, 'a' => 9.53707],
    'uranus'  => ['L0' => 314.0550, 'dL' =>    429.8633, 'om0' => 173.0052, 'e0' => 0.04630, 'a' => 19.1912],
    'neptune' => ['L0' => 304.3480, 'dL' =>    219.8997, 'om0' =>  48.1234, 'e0' => 0.00899, 'a' => 30.0690],
];

// Planet rotation and scheduling constants
// solarDay: seconds, siderealYr: seconds
// daysPerPeriod, periodsPerWeek, workPeriodsPerWeek: scheduling groups
// workStart, workEnd: local hours (0-23)
// epochUnix: planet local-time epoch as Unix seconds
const PLANETS = [
    'mercury' => ['name'=>'Mercury','solarDay'=>175.9408*EARTH_DAY_S,'siderealYr'=>87.9691*EARTH_DAY_S,
                  'dPP'=>1,'pPW'=>7,'wPPW'=>5,'wStart'=>9,'wEnd'=>17,'epoch'=>J2000_UNIX,'earthClockSched'=>true],
    'venus'   => ['name'=>'Venus',  'solarDay'=>116.7500*EARTH_DAY_S,'siderealYr'=>224.701*EARTH_DAY_S,
                  'dPP'=>1,'pPW'=>7,'wPPW'=>5,'wStart'=>9,'wEnd'=>17,'epoch'=>J2000_UNIX,'earthClockSched'=>true],
    'earth'   => ['name'=>'Earth',  'solarDay'=>EARTH_DAY_S,'siderealYr'=>365.25636*EARTH_DAY_S,
                  'dPP'=>1,'pPW'=>7,'wPPW'=>5,'wStart'=>9,'wEnd'=>17,'epoch'=>J2000_UNIX],
    'mars'    => ['name'=>'Mars',   'solarDay'=>MARS_SOL_S,'siderealYr'=>686.9957*EARTH_DAY_S,
                  'dPP'=>1,'pPW'=>7,'wPPW'=>5,'wStart'=>9,'wEnd'=>17,'epoch'=>MARS_EPOCH],
    'jupiter' => ['name'=>'Jupiter','solarDay'=>9.9250*3600,'siderealYr'=>4332.589*EARTH_DAY_S,
                  'dPP'=>2.5,'pPW'=>7,'wPPW'=>5,'wStart'=>8,'wEnd'=>16,'epoch'=>J2000_UNIX],
    'saturn'  => ['name'=>'Saturn', 'solarDay'=>10.5606*3600,'siderealYr'=>10759.22*EARTH_DAY_S,
                  'dPP'=>2.25,'pPW'=>7,'wPPW'=>5,'wStart'=>8,'wEnd'=>16,'epoch'=>J2000_UNIX],
    'uranus'  => ['name'=>'Uranus', 'solarDay'=>17.2479*3600,'siderealYr'=>30688.5*EARTH_DAY_S,
                  'dPP'=>1,'pPW'=>7,'wPPW'=>5,'wStart'=>8,'wEnd'=>16,'epoch'=>J2000_UNIX],
    'neptune' => ['name'=>'Neptune','solarDay'=>16.1100*3600,'siderealYr'=>60195.0*EARTH_DAY_S,
                  'dPP'=>1,'pPW'=>7,'wPPW'=>5,'wStart'=>8,'wEnd'=>16,'epoch'=>J2000_UNIX],
    'moon'    => ['name'=>'Moon',   'solarDay'=>EARTH_DAY_S,'siderealYr'=>365.25636*EARTH_DAY_S,
                  'dPP'=>1,'pPW'=>7,'wPPW'=>5,'wStart'=>9,'wEnd'=>17,'epoch'=>J2000_UNIX],
];

// ── Orbital mechanics ─────────────────────────────────────────────────────────

/** Julian centuries since J2000.0. Applies simplified TT correction (+69 s ≈ TAI-UTC+32.184). */
function julianCenturies(float $unixS): float {
    $ttS = $unixS + (TAI_UTC_2026 + 32.184);
    $jd  = 2440587.5 + $ttS / EARTH_DAY_S;
    return ($jd - J2000_JD) / 36525.0;
}

/** Solve Kepler's equation M = E − e·sin(E) via Newton's method (50 iterations). */
function keplerE(float $M_rad, float $e): float {
    $E = $M_rad;
    for ($i = 0; $i < 50; $i++) {
        $dE = ($M_rad - $E + $e * sin($E)) / (1.0 - $e * cos($E));
        $E += $dE;
        if (abs($dE) < 1e-12) break;
    }
    return $E;
}

/** Heliocentric (x, y) position in AU on the ecliptic plane. */
function planetHelioXY(string $body, float $unixS): array {
    $key = ($body === 'moon') ? 'earth' : $body;
    $el  = ORBITAL_ELEMENTS[$key] ?? null;
    if (!$el) jsonError("Unknown body: $body", 400);

    $T   = julianCenturies($unixS);
    $TAU = 2.0 * M_PI;
    $D2R = M_PI / 180.0;

    $L  = fmod($el['L0'] + $el['dL'] * $T, 360.0) * $D2R;
    $om = $el['om0'] * $D2R;
    $M  = fmod($L - $om, $TAU);
    if ($M < 0) $M += $TAU;
    $e  = $el['e0'];
    $a  = $el['a'];

    $E   = keplerE($M, $e);
    $v   = 2.0 * atan2(sqrt(1.0 + $e) * sin($E / 2.0), sqrt(1.0 - $e) * cos($E / 2.0));
    $r   = $a * (1.0 - $e * cos($E));
    $lon = fmod($v + $om, $TAU);
    if ($lon < 0) $lon += $TAU;

    return ['x' => $r * cos($lon), 'y' => $r * sin($lon), 'r' => $r, 'lon' => $lon];
}

/** Distance in AU between two bodies. */
function bodyDistanceAU(string $from, string $to, float $unixS): float {
    $a  = planetHelioXY($from, $unixS);
    $b  = planetHelioXY($to,   $unixS);
    $dx = $a['x'] - $b['x'];
    $dy = $a['y'] - $b['y'];
    return sqrt($dx * $dx + $dy * $dy);
}

/** One-way light travel in seconds. */
function lightTravelS(string $from, string $to, float $unixS): float {
    return bodyDistanceAU($from, $to, $unixS) * AU_SECONDS;
}

/** Conjunction countdown: days until Earth-body distance is maximised (superior conjunction proxy). */
function conjunctionInDays(string $body, float $unixS): float {
    $step  = 6.0 * 3600.0;
    $cur   = bodyDistanceAU('earth', $body, $unixS);
    for ($d = 1; $d <= 365; $d++) {
        $dist = bodyDistanceAU('earth', $body, $unixS + $d * $step);
        if ($dist < $cur) return $d * $step / EARTH_DAY_S;
        $cur = $dist;
    }
    return 365.0;
}

// ── Mars time ─────────────────────────────────────────────────────────────────

function getMTC(float $unixS): array {
    $totalSols = ($unixS - MARS_EPOCH) / MARS_SOL_S;
    $sol  = (int)floor($totalSols);
    $frac = $totalSols - $sol;
    $h = (int)floor($frac * 24);
    $m = (int)floor(($frac * 24 - $h) * 60);
    $s = (int)floor((($frac * 24 - $h) * 60 - $m) * 60);
    return ['sol' => $sol, 'hour' => $h, 'minute' => $m, 'second' => $s,
            'timeString' => sprintf('%02d:%02d', $h, $m)];
}

function getMarsLocalTime(float $unixS, float $tzOffsetHours): array {
    $mtc = getMTC($unixS);
    $h   = $mtc['hour'] + $tzOffsetHours;
    $solDelta = 0;
    if ($h >= 24) { $h -= 24; $solDelta =  1; }
    if ($h <   0) { $h += 24; $solDelta = -1; }
    return [
        'sol'        => $mtc['sol'] + $solDelta,
        'hour'       => (int)floor($h),
        'minute'     => $mtc['minute'],
        'second'     => $mtc['second'],
        'timeString' => sprintf('%02d:%02d', (int)floor($h), $mtc['minute']),
        'tzOffset'   => $tzOffsetHours,
    ];
}

// ── Planet / Earth work status ────────────────────────────────────────────────

function planetWorkStatus(string $body, float $unixS, float $tzOffset = 0.0): array {
    if ($body === 'moon') $body = 'earth';
    $p = PLANETS[$body] ?? null;
    if (!$p) jsonError("Unknown planet: $body", 400);

    $elapsed    = $unixS - $p['epoch'] + $tzOffset / 24.0 * $p['solarDay'];
    $totalDays  = $elapsed / $p['solarDay'];
    $dayFrac    = $totalDays - floor($totalDays);
    $localHour  = $dayFrac * 24.0;

    if (!empty($p['earthClockSched'])) {
        // Mercury/Venus: use Earth-standard work week (Mon–Fri UTC 09:00–17:00)
        $utcDt        = new DateTimeImmutable('@' . (int)$unixS, new DateTimeZone('UTC'));
        $utcDow       = (int)$utcDt->format('N'); // 1=Mon .. 7=Sun
        $utcHour      = (int)$utcDt->format('G') + (int)$utcDt->format('i') / 60.0;
        $periodInWeek = $utcDow - 1;              // 0=Mon .. 6=Sun
        $isWorkPeriod = $periodInWeek < $p['wPPW'];
        $isWorkHour   = $isWorkPeriod && $utcHour >= $p['wStart'] && $utcHour < $p['wEnd'];
    } else {
        $totalPeriods   = $totalDays / $p['dPP'];
        $periodInWeek   = ((int)floor($totalPeriods) % (int)$p['pPW'] + (int)$p['pPW']) % (int)$p['pPW'];
        $isWorkPeriod   = $periodInWeek < $p['wPPW'];
        $isWorkHour     = $isWorkPeriod && $localHour >= $p['wStart'] && $localHour < $p['wEnd'];
    }

    // For Mars, get sol-based time
    $solInfo = null;
    if ($body === 'mars') {
        $lt = getMarsLocalTime($unixS, $tzOffset);
        $solInfo = ['sol' => $lt['sol'], 'timeString' => $lt['timeString']];
    }

    return [
        'is_work_hour'   => $isWorkHour,
        'is_work_period' => $isWorkPeriod,
        'local_hour'     => round($localHour, 2),
        'period_in_week' => $periodInWeek,
        'sol_info'       => $solInfo,
    ];
}

const WORK_WEEK_DAYS = [
    'mon-fri' => [1, 2, 3, 4, 5],
    'sun-thu' => [0, 1, 2, 3, 4],
    'sat-wed' => [6, 0, 1, 2, 3],
    'tue-sat' => [2, 3, 4, 5, 6],
];

function earthWorkStatus(string $tz, string $workWeek, float $unixS): string {
    try {
        $dt    = (new DateTimeImmutable('@' . (int)$unixS))->setTimezone(new DateTimeZone($tz));
        $dow   = (int)$dt->format('w');   // 0=Sun, 6=Sat
        $hour  = (int)$dt->format('G');   // 0-23
        $min   = (int)$dt->format('i');
        $frac  = $hour + $min / 60.0;

        $days  = WORK_WEEK_DAYS[$workWeek] ?? [1, 2, 3, 4, 5];
        if (!in_array($dow, $days, true)) return 'rest';
        if ($frac >= 9.0 && $frac < 17.0)  return 'work';
        if (($frac >= 8.0 && $frac < 9.0) || ($frac >= 17.0 && $frac < 18.0)) return 'marginal';
        return 'rest';
    } catch (Throwable) {
        return 'rest';
    }
}

// ── Meeting window scanner ────────────────────────────────────────────────────

function checkLocationWork(array $loc, float $unixS): bool {
    $type = $loc['type'] ?? 'earth';
    if ($type === 'planet') {
        $info = planetWorkStatus($loc['planet'] ?? 'mars', $unixS, (float)($loc['tz_offset'] ?? 0));
        return $info['is_work_hour'];
    }
    return earthWorkStatus($loc['tz'] ?? 'UTC', $loc['work_week'] ?? 'mon-fri', $unixS) === 'work';
}

function findMeetingWindows(array $locations, float $fromS, int $horizonDays, int $minDurMin = 60): array {
    $STEP  = 15 * 60;  // 15-minute steps
    $endS  = $fromS + $horizonDays * EARTH_DAY_S;
    $windows = [];
    $winStart = null;

    for ($t = $fromS; $t < $endS; $t += $STEP) {
        $allWork = true;
        foreach ($locations as $loc) {
            if (!checkLocationWork($loc, $t)) { $allWork = false; break; }
        }
        if ($allWork && $winStart === null) {
            $winStart = $t;
        } elseif (!$allWork && $winStart !== null) {
            $durMin = (int)(($t - $winStart) / 60);
            if ($durMin >= $minDurMin) {
                $windows[] = makeWindow($winStart, $t, $locations);
            }
            $winStart = null;
        }
    }
    if ($winStart !== null) {
        $durMin = (int)(($endS - $winStart) / 60);
        if ($durMin >= $minDurMin) {
            $windows[] = makeWindow($winStart, $endS, $locations);
        }
    }
    return $windows;
}

function makeWindow(float $startS, float $endS, array $locations): array {
    $lightMin = 0.0;
    $planets  = array_filter($locations, fn($l) => ($l['type'] ?? 'earth') === 'planet');
    if (count($planets) > 0) {
        $body     = array_values($planets)[0]['planet'] ?? 'mars';
        $lightMin = round(lightTravelS('earth', $body, ($startS + $endS) / 2.0) / 60.0, 1);
    }
    return [
        'start_utc'          => gmdate('Y-m-d\TH:i:s\Z', (int)$startS),
        'end_utc'            => gmdate('Y-m-d\TH:i:s\Z', (int)$endS),
        'duration_minutes'   => (int)(($endS - $startS) / 60),
        'all_in_work_hours'  => true,
        'light_minutes'      => $lightMin,
    ];
}

// ── Route handlers ────────────────────────────────────────────────────────────

function handlePlanet(): void {
    $body     = strtolower(trim($_GET['body'] ?? ''));
    $tzOffset = (float)($_GET['tz_offset'] ?? 0);
    $atS      = parseAt($_GET['at'] ?? null);

    if (!$body) jsonError("'body' parameter required");

    if (($PLANETS[$body] ?? null) && ($body === 'earth' || !isset(ORBITAL_ELEMENTS[$body === 'moon' ? 'earth' : $body]))) {
        // planet without orbital elements (shouldn't happen with current set)
    }

    // Validate body
    if (!isset(PLANETS[$body])) jsonError("Unknown body: $body. Valid: " . implode(', ', array_keys(PLANETS)));

    $wk = planetWorkStatus($body, $atS, $tzOffset);

    // Light travel from Earth
    $earthBody = ($body === 'earth' || $body === 'moon') ? null : $body;
    $lightMin  = $earthBody ? round(lightTravelS('earth', $earthBody, $atS) / 60.0, 2) : 0.0;
    $conjDays  = $earthBody ? round(conjunctionInDays($earthBody, $atS), 1) : null;

    // Local time string
    $localTimeStr = null;
    if ($body === 'mars') {
        $lt = getMarsLocalTime($atS, $tzOffset);
        $localTimeStr = $lt['timeString'];
        $sol = $lt['sol'];
    } else {
        $p   = PLANETS[$body];
        $elapsed  = $atS - $p['epoch'] + $tzOffset / 24.0 * $p['solarDay'];
        $frac     = fmod($elapsed / $p['solarDay'], 1.0);
        if ($frac < 0) $frac += 1.0;
        $h = (int)floor($frac * 24);
        $m = (int)floor(($frac * 24 - $h) * 60);
        $localTimeStr = sprintf('%02d:%02d', $h, $m);
        $sol = null;
    }

    jsonOk([
        'body'              => $body,
        'at_utc'            => gmdate('Y-m-d\TH:i:s\Z', (int)$atS),
        'local_time'        => $localTimeStr,
        'sol'               => $sol ?? null,
        'is_work_hour'      => $wk['is_work_hour'],
        'is_work_period'    => $wk['is_work_period'],
        'light_minutes'     => $lightMin,
        'conjunction_in_days' => $conjDays,
        'tz_offset_hours'   => $tzOffset,
    ]);
}

function handleDistance(): void {
    $from = strtolower(trim($_GET['from'] ?? ''));
    $to   = strtolower(trim($_GET['to']   ?? ''));
    $atS  = parseAt($_GET['at'] ?? null);

    if (!$from || !$to) jsonError("'from' and 'to' parameters required");

    $distAU  = bodyDistanceAU($from, $to, $atS);
    $lightS  = $distAU * AU_SECONDS;

    jsonOk([
        'from'               => $from,
        'to'                 => $to,
        'at_utc'             => gmdate('Y-m-d\TH:i:s\Z', (int)$atS),
        'distance_au'        => round($distAU, 4),
        'distance_km'        => round($distAU * AU_KM, 0),
        'light_seconds'      => round($lightS, 1),
        'light_minutes'      => round($lightS / 60.0, 2),
        'round_trip_minutes' => round($lightS / 30.0, 2),
        'conjunction_in_days'=> round(conjunctionInDays($to !== 'earth' ? $to : $from, $atS), 1),
    ]);
}

function handleWindows(): void {
    if ($_SERVER['REQUEST_METHOD'] !== 'POST') jsonError('POST required', 405);

    $body = parsedBody();
    $locations   = $body['locations']    ?? [];
    $fromUtc     = $body['from_utc']     ?? null;
    $horizonDays = (int)($body['horizon_days']         ?? 14);
    $minDurMin   = (int)($body['min_duration_minutes'] ?? 60);

    if (!is_array($locations) || count($locations) < 1) jsonError("'locations' array required with at least 1 entry");
    if ($horizonDays < 1 || $horizonDays > 90)          jsonError("'horizon_days' must be 1–90");
    if ($minDurMin < 5 || $minDurMin > 480)             jsonError("'min_duration_minutes' must be 5–480");

    $fromS   = parseAt($fromUtc);
    $windows = findMeetingWindows($locations, $fromS, $horizonDays, $minDurMin);

    jsonOk([
        'windows'          => $windows,
        'windows_found'    => count($windows),
        'locations_count'  => count($locations),
        'scan_from_utc'    => gmdate('Y-m-d\TH:i:s\Z', (int)$fromS),
        'scan_horizon_days'=> $horizonDays,
        'min_duration_min' => $minDurMin,
    ]);
}

// ── Router ────────────────────────────────────────────────────────────────────

$action = strtolower(trim($_GET['action'] ?? ''));
match ($action) {
    'planet'   => handlePlanet(),
    'distance' => handleDistance(),
    'windows'  => handleWindows(),
    default    => jsonError("Unknown action '$action'. Valid: planet, distance, windows"),
};
