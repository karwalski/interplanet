// constants.dart — LTX SDK constants

const String kVersion = '1.0.0';

const int kDefaultQuantum = 3;

const String kDefaultApiBase = 'https://interplanet.live/api/ltx.php';

const List<String> kSegTypes = [
  'PLAN_CONFIRM',
  'TX',
  'RX',
  'CAUCUS',
  'BUFFER',
  'MERGE',
];

const List<Map<String, dynamic>> kDefaultSegments = [
  {'type': 'PLAN_CONFIRM', 'q': 2},
  {'type': 'TX', 'q': 2},
  {'type': 'RX', 'q': 2},
  {'type': 'CAUCUS', 'q': 2},
  {'type': 'TX', 'q': 2},
  {'type': 'RX', 'q': 2},
  {'type': 'BUFFER', 'q': 1},
];

// ── Story 26.4 constants ───────────────────────────────────────────────────

const int kDefaultPlanLockTimeoutFactor = 2;
const int kDelayViolationWarnS = 120;
const int kDelayViolationDegradedS = 300;

const List<String> kSessionStates = [
  'INIT',
  'LOCKED',
  'RUNNING',
  'DEGRADED',
  'COMPLETE',
];
