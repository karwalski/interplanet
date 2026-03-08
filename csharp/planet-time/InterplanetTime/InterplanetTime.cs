// InterplanetTime.cs — Interplanetary Time Library for C# (.NET 6)
// Port of planet-time.js v1.1.0 — Story 18.11
//
// Provides time, calendar, orbital mechanics, and light-speed calculations
// for every planet in the solar system.
//
// Namespace: InterplanetTime
// Main API:  static class Ipt

using System;
using System.Collections.Generic;

namespace InterplanetTime
{
    // ── Planet enum ──────────────────────────────────────────────────────────────
    public enum Planet
    {
        Mercury = 0,
        Venus   = 1,
        Earth   = 2,
        Mars    = 3,
        Jupiter = 4,
        Saturn  = 5,
        Uranus  = 6,
        Neptune = 7,
        Moon    = 8,
    }

    // ── Result records ───────────────────────────────────────────────────────────

    public record PlanetTime(
        int     Hour,
        int     Minute,
        int     Second,
        double  LocalHour,
        double  DayFraction,
        long    DayNumber,
        long    DayInYear,
        long    YearNumber,
        int     PeriodInWeek,
        bool    IsWorkPeriod,
        bool    IsWorkHour,
        string  TimeStr,
        string  TimeStrFull,
        int?    SolInYear,
        int?    SolsPerYear,
        string? ZoneId
    );

    public record MtcResult(
        long   Sol,
        int    Hour,
        int    Minute,
        int    Second,
        string MtcStr
    );

    public record HelioPos(
        double X,
        double Y,
        double R,
        double Lon
    );

    // ── Internal planet data structure ───────────────────────────────────────────

    internal struct PlanetData
    {
        public long   SolarDayMs;
        public long   SiderealYrMs;
        public long   EpochMs;
        public int    WorkStart;
        public int    WorkEnd;
        public double DaysPerPeriod;
        public int    PeriodsPerWeek;
        public int    WorkPeriodsPerWeek;
        public bool   EarthClockSched;
    }

    internal struct OrbElems
    {
        public double L0;   // mean longitude at J2000 (deg)
        public double DL;   // rate (deg/Julian century)
        public double Om0;  // longitude of perihelion (deg)
        public double E0;   // eccentricity
        public double A;    // semi-major axis (AU)
    }

    // ── Main static API ──────────────────────────────────────────────────────────

    public static class Ipt
    {
        // ── Constants ────────────────────────────────────────────────────────────

        /// <summary>J2000.0 epoch as Unix timestamp (ms)</summary>
        public const long   J2000_MS       = 946_728_000_000L;  // Date.UTC(2000,0,1,12,0,0)

        /// <summary>Julian Day number of J2000.0</summary>
        public const double J2000_JD       = 2_451_545.0;

        /// <summary>Mars epoch (MY0) — Date.UTC(1953,4,24,9,3,58,464)</summary>
        public const long   MARS_EPOCH_MS  = -524_069_761_536L;

        /// <summary>Mars solar day in milliseconds (24h 39m 35.244s)</summary>
        public const long   MARS_SOL_MS    = 88_775_244L;

        /// <summary>1 AU in kilometres (IAU 2012)</summary>
        public const double AU_KM          = 149_597_870.7;

        /// <summary>Speed of light in km/s (SI definition)</summary>
        public const double C_KMS          = 299_792.458;

        /// <summary>Light travel time for 1 AU in seconds</summary>
        public const double AU_SECONDS     = AU_KM / C_KMS;  // ≈499.004 s

        // ── IERS Leap seconds ────────────────────────────────────────────────────
        // [utcMs, taiMinusUtc] — 28 entries, last: 2017-01-01

        private static readonly (long UtcMs, int Delta)[] LEAP_SECS = {
            (63_072_000_000L,   10), (78_796_800_000L,   11), (94_694_400_000L,   12),
            (126_230_400_000L,  13), (157_766_400_000L,  14), (189_302_400_000L,  15),
            (220_924_800_000L,  16), (252_460_800_000L,  17), (283_996_800_000L,  18),
            (315_532_800_000L,  19), (362_793_600_000L,  20), (394_329_600_000L,  21),
            (425_865_600_000L,  22), (489_024_000_000L,  23), (567_993_600_000L,  24),
            (631_152_000_000L,  25), (662_688_000_000L,  26), (709_948_800_000L,  27),
            (741_484_800_000L,  28), (773_020_800_000L,  29), (820_454_400_000L,  30),
            (867_715_200_000L,  31), (915_148_800_000L,  32), (1_136_073_600_000L, 33),
            (1_230_768_000_000L, 34), (1_341_100_800_000L, 35), (1_435_708_800_000L, 36),
            (1_483_228_800_000L, 37),
        };

        // ── Orbital elements (Meeus Table 31.a) ─────────────────────────────────

        private static readonly Dictionary<string, OrbElems> ORB_ELEMS = new()
        {
            ["mercury"] = new OrbElems { L0 = 252.2507, DL = 149_474.0722, Om0 =  77.4561, E0 = 0.20564, A =  0.38710 },
            ["venus"]   = new OrbElems { L0 = 181.9798, DL =  58_519.2130, Om0 = 131.5637, E0 = 0.00677, A =  0.72333 },
            ["earth"]   = new OrbElems { L0 = 100.4664, DL =  36_000.7698, Om0 = 102.9373, E0 = 0.01671, A =  1.00000 },
            ["mars"]    = new OrbElems { L0 = 355.4330, DL =  19_141.6964, Om0 = 336.0600, E0 = 0.09341, A =  1.52366 },
            ["jupiter"] = new OrbElems { L0 =  34.3515, DL =   3_036.3027, Om0 =  14.3320, E0 = 0.04849, A =  5.20336 },
            ["saturn"]  = new OrbElems { L0 =  50.0775, DL =   1_223.5093, Om0 =  93.0572, E0 = 0.05551, A =  9.53707 },
            ["uranus"]  = new OrbElems { L0 = 314.0550, DL =     429.8633, Om0 = 173.0052, E0 = 0.04630, A = 19.19126 },
            ["neptune"] = new OrbElems { L0 = 304.3480, DL =     219.8997, Om0 =  48.1234, E0 = 0.00899, A = 30.06900 },
            // Moon uses Earth's orbit for helio position
            ["moon"]    = new OrbElems { L0 = 100.4664, DL =  36_000.7698, Om0 = 102.9373, E0 = 0.01671, A =  1.00000 },
        };

        // ── Zone prefixes ────────────────────────────────────────────────────────

        private static readonly Dictionary<string, string> ZONE_PREFIX = new()
        {
            ["mars"]    = "AMT",
            ["moon"]    = "LMT",
            ["mercury"] = "MMT",
            ["venus"]   = "VMT",
            ["jupiter"] = "JMT",
            ["saturn"]  = "SMT",
            ["uranus"]  = "UMT",
            ["neptune"] = "NMT",
        };

        // ── Planet data table ────────────────────────────────────────────────────

        private const long EARTH_DAY_MS = 86_400_000L;

        private static readonly Dictionary<string, PlanetData> PLANET_DATA = new()
        {
            ["mercury"] = new PlanetData {
                SolarDayMs        = (long)Math.Round(175.9408 * EARTH_DAY_MS),
                SiderealYrMs      = (long)Math.Round(87.9691  * EARTH_DAY_MS),
                EpochMs           = J2000_MS,
                WorkStart = 9, WorkEnd = 17,
                DaysPerPeriod = 1.0, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
                EarthClockSched = true,
            },
            ["venus"] = new PlanetData {
                SolarDayMs        = (long)Math.Round(116.7500 * EARTH_DAY_MS),
                SiderealYrMs      = (long)Math.Round(224.701  * EARTH_DAY_MS),
                EpochMs           = J2000_MS,
                WorkStart = 9, WorkEnd = 17,
                DaysPerPeriod = 1.0, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
                EarthClockSched = true,
            },
            ["earth"] = new PlanetData {
                SolarDayMs        = EARTH_DAY_MS,
                SiderealYrMs      = (long)Math.Round(365.25636 * EARTH_DAY_MS),
                EpochMs           = J2000_MS,
                WorkStart = 9, WorkEnd = 17,
                DaysPerPeriod = 1.0, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
            },
            ["mars"] = new PlanetData {
                SolarDayMs        = MARS_SOL_MS,
                SiderealYrMs      = (long)Math.Round(686.9957 * EARTH_DAY_MS),
                EpochMs           = MARS_EPOCH_MS,
                WorkStart = 9, WorkEnd = 17,
                DaysPerPeriod = 1.0, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
            },
            ["jupiter"] = new PlanetData {
                SolarDayMs        = (long)Math.Round(9.9250 * 3_600_000.0),
                SiderealYrMs      = (long)Math.Round(4332.589 * EARTH_DAY_MS),
                EpochMs           = J2000_MS,
                WorkStart = 8, WorkEnd = 16,
                DaysPerPeriod = 2.5, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
            },
            ["saturn"] = new PlanetData {
                SolarDayMs        = (long)Math.Round(10.578 * 3_600_000.0),
                SiderealYrMs      = (long)Math.Round(10_759.22 * EARTH_DAY_MS),
                EpochMs           = J2000_MS,
                WorkStart = 8, WorkEnd = 16,
                DaysPerPeriod = 2.25, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
            },
            ["uranus"] = new PlanetData {
                SolarDayMs        = (long)Math.Round(17.2479 * 3_600_000.0),
                SiderealYrMs      = (long)Math.Round(30_688.5 * EARTH_DAY_MS),
                EpochMs           = J2000_MS,
                WorkStart = 8, WorkEnd = 16,
                DaysPerPeriod = 1.0, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
            },
            ["neptune"] = new PlanetData {
                SolarDayMs        = (long)Math.Round(16.1100 * 3_600_000.0),
                SiderealYrMs      = (long)Math.Round(60_195.0 * EARTH_DAY_MS),
                EpochMs           = J2000_MS,
                WorkStart = 8, WorkEnd = 16,
                DaysPerPeriod = 1.0, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
            },
            ["moon"] = new PlanetData {
                SolarDayMs        = EARTH_DAY_MS,
                SiderealYrMs      = (long)Math.Round(365.25636 * EARTH_DAY_MS),
                EpochMs           = J2000_MS,
                WorkStart = 9, WorkEnd = 17,
                DaysPerPeriod = 1.0, PeriodsPerWeek = 7, WorkPeriodsPerWeek = 5,
            },
        };

        // ── TT / JDE helpers ─────────────────────────────────────────────────────

        private static int GetTAIminusUTC(long utcMs)
        {
            int offset = 10;
            foreach (var (utcMs2, delta) in LEAP_SECS)
            {
                if (utcMs >= utcMs2) offset = delta;
                else break;
            }
            return offset;
        }

        private static double JDE(long utcMs)
        {
            double ttMs = (double)utcMs + (GetTAIminusUTC(utcMs) + 32.184) * 1000.0;
            return 2_440_587.5 + ttMs / 86_400_000.0;
        }

        private static double JulianCenturies(long utcMs)
        {
            return (JDE(utcMs) - J2000_JD) / 36_525.0;
        }

        // ── Kepler solver ────────────────────────────────────────────────────────

        private static double KeplerE(double M, double e)
        {
            double E = M;
            for (int i = 0; i < 50; i++)
            {
                double dE = (M - E + e * Math.Sin(E)) / (1.0 - e * Math.Cos(E));
                E += dE;
                if (Math.Abs(dE) < 1e-12) break;
            }
            return E;
        }

        // ── Heliocentric position ────────────────────────────────────────────────

        private static HelioPos GetHelioXY(string planet, long utcMs)
        {
            string key = (planet == "moon") ? "earth" : planet;
            if (!ORB_ELEMS.TryGetValue(key, out OrbElems el))
                el = ORB_ELEMS["earth"];

            double T   = JulianCenturies(utcMs);
            const double D2R = Math.PI / 180.0;
            const double TAU = 2.0 * Math.PI;

            double L   = ((el.L0 + el.DL * T) * D2R % TAU + TAU) % TAU;
            double om  = el.Om0 * D2R;
            double M   = ((L - om) % TAU + TAU) % TAU;
            double e   = el.E0;
            double a   = el.A;

            double E   = KeplerE(M, e);
            double nu  = 2.0 * Math.Atan2(
                Math.Sqrt(1.0 + e) * Math.Sin(E / 2.0),
                Math.Sqrt(1.0 - e) * Math.Cos(E / 2.0));
            double r   = a * (1.0 - e * Math.Cos(E));
            double lon = ((nu + om) % TAU + TAU) % TAU;

            return new HelioPos(r * Math.Cos(lon), r * Math.Sin(lon), r, lon);
        }

        // ── Public API ───────────────────────────────────────────────────────────

        /// <summary>
        /// Get the heliocentric position of a planet at the given UTC milliseconds.
        /// Moon uses Earth's orbital elements.
        /// </summary>
        public static HelioPos HelioPos(string planet, long utcMs)
        {
            return GetHelioXY(planet, utcMs);
        }

        /// <summary>
        /// Distance in AU between two solar system bodies.
        /// </summary>
        public static double BodyDistanceAu(string a, string b, long utcMs)
        {
            var pA = GetHelioXY(a, utcMs);
            var pB = GetHelioXY(b, utcMs);
            double dx = pA.X - pB.X;
            double dy = pA.Y - pB.Y;
            return Math.Sqrt(dx * dx + dy * dy);
        }

        /// <summary>
        /// One-way light travel time between two bodies (seconds).
        /// </summary>
        public static double LightTravelSeconds(string from, string to, long utcMs)
        {
            return BodyDistanceAu(from, to, utcMs) * AU_SECONDS;
        }

        /// <summary>
        /// Get Mars Coordinated Time (MTC) for the given UTC milliseconds.
        /// </summary>
        public static MtcResult GetMtc(long utcMs)
        {
            double ms  = (double)(utcMs - MARS_EPOCH_MS);
            double solD = ms / MARS_SOL_MS;
            long   sol  = (long)Math.Floor(solD);
            double frac = solD - Math.Floor(solD);

            int h = (int)(frac * 24.0);
            double mf = (frac * 24.0 - h) * 60.0;
            int m = (int)mf;
            int s = (int)((mf - m) * 60.0);

            return new MtcResult(
                Sol    : sol,
                Hour   : h,
                Minute : m,
                Second : s,
                MtcStr : $"{h:D2}:{m:D2}"
            );
        }

        /// <summary>
        /// Get the current local time on a planet.
        /// tzOffsetH is the optional zone offset in local hours from the planet prime meridian.
        /// For Moon, uses Earth solar day and epoch (tidally locked).
        /// </summary>
        public static PlanetTime GetPlanetTime(string planet, long utcMs, double tzOffsetH = 0.0)
        {
            string effective = (planet == "moon") ? "earth" : planet;
            if (!PLANET_DATA.TryGetValue(effective, out PlanetData pd))
                throw new ArgumentException($"Unknown planet: {planet}");

            double solarDay = (double)pd.SolarDayMs;

            // tz offset applied as fraction of solar day (matches JS exactly)
            double elapsedMs = (double)(utcMs - pd.EpochMs) + tzOffsetH / 24.0 * solarDay;
            double totalDays = elapsedMs / solarDay;
            long   dayNumber = (long)Math.Floor(totalDays);
            double dayFrac   = totalDays - (double)dayNumber;

            double localHour = dayFrac * 24.0;
            int h = (int)localHour;
            double mf = (localHour - h) * 60.0;
            int m = (int)mf;
            int s = (int)((mf - m) * 60.0);

            // Work period (positive modulo so pre-epoch dates give valid range)
            int  piw;
            bool isWorkPeriod;
            bool isWorkHour;
            if (pd.EarthClockSched)
            {
                // Mercury/Venus: solar day >> circadian rhythm; use UTC Earth-clock scheduling
                // UTC day-of-week: ((floor(utcMs / 86400000) % 7 + 10) % 7 → Mon=0..Sun=6
                // (+7 before +3 ensures positive result for pre-1970 timestamps)
                long utcDay = (long)Math.Floor((double)utcMs / 86_400_000.0);
                piw = (int)(((utcDay % 7L) + 10L) % 7L);
                isWorkPeriod = piw < pd.WorkPeriodsPerWeek;
                // UTC hour within the day — positive modulo handles pre-1970 timestamps
                long msInDay = ((utcMs % 86_400_000L) + 86_400_000L) % 86_400_000L;
                double utcHour = (double)msInDay / 3_600_000.0;
                isWorkHour = isWorkPeriod && utcHour >= pd.WorkStart && utcHour < pd.WorkEnd;
            }
            else
            {
                double totalPeriods = totalDays / pd.DaysPerPeriod;
                piw = ((int)Math.Floor(totalPeriods) % pd.PeriodsPerWeek + pd.PeriodsPerWeek) % pd.PeriodsPerWeek;
                isWorkPeriod = piw < pd.WorkPeriodsPerWeek;
                isWorkHour   = isWorkPeriod && localHour >= pd.WorkStart && localHour < pd.WorkEnd;
            }

            // Year / day-in-year
            double yearLenDays = (double)pd.SiderealYrMs / solarDay;
            long   yearNumber  = (long)Math.Floor(totalDays / yearLenDays);
            long   dayInYear   = (long)Math.Floor(totalDays - (double)yearNumber * yearLenDays);

            int? solInYear   = null;
            int? solsPerYear = null;
            if (effective == "mars")
            {
                solInYear   = (int)dayInYear;
                solsPerYear = (int)Math.Round((double)pd.SiderealYrMs / solarDay);
            }

            string? zoneId = null;
            if (planet != "earth" && ZONE_PREFIX.TryGetValue(planet, out string? prefix))
            {
                int off = (int)tzOffsetH;
                string sign = off < 0 ? "-" : "+";
                zoneId = $"{prefix}{sign}{Math.Abs(off)}";
            }

            return new PlanetTime(
                Hour         : h,
                Minute       : m,
                Second       : s,
                LocalHour    : localHour,
                DayFraction  : dayFrac,
                DayNumber    : dayNumber,
                DayInYear    : dayInYear,
                YearNumber   : yearNumber,
                PeriodInWeek : piw,
                IsWorkPeriod : isWorkPeriod,
                IsWorkHour   : isWorkHour,
                TimeStr      : $"{h:D2}:{m:D2}",
                TimeStrFull  : $"{h:D2}:{m:D2}:{s:D2}",
                SolInYear    : solInYear,
                SolsPerYear  : solsPerYear,
                ZoneId       : zoneId
            );
        }

        /// <summary>
        /// Format a light travel time (seconds) as a human-readable string.
        /// Mirrors formatLightTime() in planet-time.js.
        /// </summary>
        public static string FormatLightTime(double seconds)
        {
            if (seconds < 0.001) return "<1ms";
            if (seconds < 1.0)   return $"{(seconds * 1000.0):F0}ms";
            if (seconds < 60.0)  return $"{seconds:F1}s";
            if (seconds < 3600.0) return $"{(seconds / 60.0):F1}min";
            int hr = (int)(seconds / 3600.0);
            int mn = (int)Math.Round((seconds % 3600.0) / 60.0);
            return $"{hr}h {mn}m";
        }
    }
}
