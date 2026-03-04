# libinterplanet

Native C port of [planet-time.js](https://github.com/karwalski/interplanet) v1.0.0.

Provides planetary local time, Mars Coordinated Time (MTC), heliocentric orbital
positions, one-way light travel times, line-of-sight checks, and meeting-window
scheduling for every planet in our solar system.

Includes:
- **C API** (`include/libinterplanet.h`)
- **C++17 header-only wrapper** (`bindings/cpp/interplanet.hpp`)
- **C# / .NET P/Invoke** (`bindings/dotnet/Interplanet.cs`)
- **Unity MonoBehaviour helpers** (`unity/InterplanetUnity.cs`)
- **C unit tests** (`tests/test_libinterplanet.c`)
- **Cross-language fixture harness** (`tests/generate_fixtures.js`)

---

## Quick start

### Build (macOS / Linux)

```bash
cd libinterplanet
make all        # generates fixtures, builds libraries, runs tests
```

Or manually with CMake:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build
cd build && ctest --output-on-failure
```

### macOS note

On macOS, `libm` is part of the system library; CMake's `-lm` link is a no-op and
harmless.  On Linux it links the math library explicitly.

---

## C API

All timestamps are `int64_t` milliseconds since the Unix epoch — identical to
JavaScript's `Date.getTime()`.

```c
#include "include/libinterplanet.h"

int64_t now_ms = /* your platform's UTC-ms timestamp */;

/* Local time on Mars */
ipt_planet_time_t pt;
ipt_get_planet_time(IPT_MARS, now_ms, 0 /* AMT+0 */, &pt);
printf("Mars time: %s\n", pt.time_str);          /* "HH:MM" */
printf("Work hour: %s\n", pt.is_work_hour ? "yes" : "no");

/* One-way light travel Earth → Mars */
double lt_s = ipt_light_travel_s(IPT_EARTH, IPT_MARS, now_ms);
char buf[32];
ipt_format_light_time(lt_s, buf, sizeof(buf));   /* "3.1min" */

/* Mars Coordinated Time */
ipt_mtc_t mtc;
ipt_get_mtc(now_ms, &mtc);
printf("MTC: %s  Sol %d\n", mtc.mtc_str, mtc.sol);

/* Line-of-sight check */
ipt_los_t los;
ipt_check_los(IPT_EARTH, IPT_MARS, now_ms, &los);
printf("LOS clear: %s\n", los.clear ? "yes" : "no");

/* Meeting windows (Earth work hours ∩ Mars work hours) */
ipt_window_t wins[16];
int n = ipt_find_windows(IPT_EARTH, IPT_MARS, now_ms, 14 /* days */, wins, 16);
for (int i = 0; i < n; i++)
    printf("Window: %d min\n", wins[i].duration_min);
```

### Timezone note

The C API uses **integer UTC offsets** (`int tz_h`) rather than IANA timezone
strings. This keeps the library self-contained (no timezone database needed).

| Planet | Prefix | Example |
|--------|--------|---------|
| Mars   | AMT    | AMT+4 → `tz_h = 4` |
| Earth  | UTC    | UTC-5 → `tz_h = -5` |
| Moon   | LMT    | LMT+2 → `tz_h = 2` |

The C++ and C# wrappers can add IANA string lookups via the host platform
(`std::chrono::zoned_time` / `TimeZoneInfo`).

---

## C++ API

```cpp
#include "bindings/cpp/interplanet.hpp"

auto pt = ipt::getPlanetTime(ipt::Planet::Mars, utc_ms, 4 /* AMT+4 */);
std::cout << pt.timeStr << (pt.isWorkHour ? " (work)" : " (rest)") << "\n";

double lt = ipt::lightTravelSeconds(ipt::Planet::Earth, ipt::Planet::Mars, utc_ms);
std::cout << ipt::formatLightTime(lt) << "\n";

auto los = ipt::checkLOS(ipt::Planet::Earth, ipt::Planet::Mars, utc_ms);
std::cout << (los.clear ? "clear" : "blocked") << "\n";

auto windows = ipt::findWindows(ipt::Planet::Earth, ipt::Planet::Mars, utc_ms, 14);
for (auto& w : windows)
    std::cout << w.durationMin << " min\n";
```

---

## C# / .NET API

Add `Interplanet.cs` to your project. Place `libinterplanet.dylib` / `.so` / `.dll`
in the output directory.

```csharp
using Interplanet;

long utcMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

// High-level API
var pt = Api.GetPlanetTime(Planet.Mars, utcMs, 0);
Console.WriteLine($"{pt.TimeStr}  work={pt.IsWorkHour}");

var mtc = Api.GetMTC(utcMs);
Console.WriteLine($"MTC {mtc.MtcStr}  Sol {mtc.Sol}");

double lt = Api.LightTravelSeconds(Planet.Earth, Planet.Mars, utcMs);
Console.WriteLine(Api.FormatLightTime(lt));

var los = Api.CheckLOS(Planet.Earth, Planet.Mars, utcMs);
Console.WriteLine(los.Clear ? "Clear LOS" : "Blocked");

var windows = Api.FindWindows(Planet.Earth, Planet.Mars, utcMs, 14);
foreach (var w in windows)
    Console.WriteLine($"{w.StartUtc:u}  +{w.DurationMin}min");
```

---

## Unity

1. Copy `unity/InterplanetUnity.cs` and `bindings/dotnet/Interplanet.cs` to
   `Assets/Scripts/Interplanet/`.
2. Place the compiled native library in `Assets/Plugins/<platform>/`.
3. Attach `InterplanetClock` to a GameObject; configure `planet` and
   `tzOffsetHours` in the Inspector.

```
[Inspector]
Planet:         Mars
TzOffsetHours:  -5    ← AMT-5 (Valles Marineris western)
Update Interval: 1.0

[Read-only]
LocalTime:      14:32
IsWorkHour:     true
```

---

## Cross-language fixture harness

```bash
# Generate reference fixtures from the JS library
make fixtures         # writes fixtures/reference.json (54 entries)

# Run C unit tests (includes fixture-based validation)
make test
```

`fixtures/reference.json` is auto-generated from `planet-time.js` and should
**not** be committed — it is re-generated on each build.

---

## File layout

```
libinterplanet/
├── include/libinterplanet.h       ← Public C API
├── src/libinterplanet.c           ← Implementation (~1600 lines, no malloc)
├── bindings/
│   ├── cpp/interplanet.hpp        ← C++17 header-only wrapper
│   └── dotnet/
│       ├── Interplanet.cs         ← C# P/Invoke (.NET 6+)
│       └── Interplanet.csproj
├── unity/InterplanetUnity.cs      ← Unity MonoBehaviour helpers
├── tests/
│   ├── test_libinterplanet.c      ← C unit tests (no external deps)
│   └── generate_fixtures.js       ← Node.js fixture generator
├── fixtures/reference.json        ← Auto-generated (not committed)
├── CMakeLists.txt
├── Makefile
└── README.md
```

---

## Constants

| Symbol | Value | Source |
|--------|-------|--------|
| `IPT_AU_KM` | 149 597 870.7 km | IAU 2012 Resolution B2 (exact) |
| `IPT_C_KMS` | 299 792.458 km/s | SI definition (exact) |
| `IPT_AU_SECONDS` | ≈ 499.004 s | Derived |
| `IPT_J2000_JD` | 2 451 545.0 | Standard J2000.0 epoch |
| `IPT_J2000_MS` | 946 728 000 000 | 2000-01-01T12:00:00Z in Unix ms |
| `IPT_MARS_SOL_MS` | 88 775 244 | Allison & McEwen 2000 |
| `IPT_MARS_EPOCH_MS` | −524 048 638 464 | MY0: 1953-05-24T09:03:58.464Z |

---

## License

MIT — same as the parent interplanet project.
