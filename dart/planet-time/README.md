# interplanet_time — Dart 3

Dart 3 port of the [InterPlanet Time](https://interplanet.live) planet-time library
(Story 18.12). Provides solar-day time, work-schedule, orbital mechanics, and
light-speed calculations for every planet in the solar system.

## Usage

```dart
import 'package:interplanet_time/interplanet_time.dart';

void main() {
  final now = DateTime.now().millisecondsSinceEpoch;

  // Get Mars local time (AMT+0)
  final mars = getPlanetTime(Planet.mars, now);
  print('Mars: ${mars.timeStr}');

  // Light travel time Earth → Mars
  final lt = lightTravelSeconds(Planet.earth, Planet.mars, now);
  print('Light travel: ${formatLightTime(lt)}');

  // Mars Coordinated Time
  final mtc = getMtc(now);
  print('MTC: ${mtc.mtcStr}');
}
```

## API

- `getPlanetTime(Planet planet, int utcMs, {double tzOffsetH = 0.0})` → `PlanetTime`
- `getMtc(int utcMs)` → `MtcResult`
- `helioPos(Planet planet, int utcMs)` → `HelioPos`
- `bodyDistanceAu(Planet a, Planet b, int utcMs)` → `double`
- `lightTravelSeconds(Planet from, Planet to, int utcMs)` → `double`
- `formatLightTime(double seconds)` → `String`
- `findMeetingWindows(Planet a, Planet b, {int earthDays, int startMs})` → `List<MeetingWindow>`

## Running tests

```
dart test
```

## Fixture validation

```
dart run bin/fixture_runner.dart ../../c/planet-time/fixtures/reference.json
```

## License

MIT
