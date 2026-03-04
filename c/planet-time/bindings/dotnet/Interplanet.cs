/**
 * Interplanet.cs — C# P/Invoke bindings for libinterplanet
 *
 * Targets .NET 6+ (net6.0, net8.0).
 * Place the compiled libinterplanet shared library (.so / .dylib / .dll)
 * in the same directory as the assembly, or configure the runtime path.
 *
 * Usage:
 *   long utcMs = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
 *   var pt = Interplanet.GetPlanetTime(Planet.Mars, utcMs, 0);
 *   Console.WriteLine(pt.TimeStr);
 */

using System;
using System.Runtime.InteropServices;

namespace Interplanet
{
    /// <summary>Planet identifiers matching the C enum ipt_planet_t.</summary>
    public enum Planet : int
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

    /// <summary>Heliocentric position in the ecliptic plane (AU).</summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct HelioPos
    {
        public double X;
        public double Y;
        public double R;
        public double Lon;
    }

    /// <summary>
    /// Local time on a planet.
    /// Matches the C struct ipt_planet_time_t byte-for-byte.
    /// </summary>
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct PlanetTimeRaw
    {
        public int    Hour;
        public int    Minute;
        public int    Second;
        public double LocalHour;
        public double DayFraction;
        public int    DayNumber;
        public int    DayInYear;
        public int    YearNumber;
        public int    PeriodInWeek;
        public int    IsWorkPeriod;   /* C int bool */
        public int    IsWorkHour;     /* C int bool */
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 6)]
        public string TimeStr;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 9)]
        public string TimeStrFull;
        public int    SolInYear;
        public int    SolsPerYear;
    }

    /// <summary>Managed planet time result with bool properties.</summary>
    public sealed class PlanetTime
    {
        public int    Hour         { get; }
        public int    Minute       { get; }
        public int    Second       { get; }
        public double LocalHour    { get; }
        public double DayFraction  { get; }
        public int    DayNumber    { get; }
        public int    DayInYear    { get; }
        public int    YearNumber   { get; }
        public int    PeriodInWeek { get; }
        public bool   IsWorkPeriod { get; }
        public bool   IsWorkHour   { get; }
        public string TimeStr      { get; }
        public string TimeStrFull  { get; }
        public int    SolInYear    { get; }
        public int    SolsPerYear  { get; }

        internal PlanetTime(in PlanetTimeRaw r)
        {
            Hour         = r.Hour;
            Minute       = r.Minute;
            Second       = r.Second;
            LocalHour    = r.LocalHour;
            DayFraction  = r.DayFraction;
            DayNumber    = r.DayNumber;
            DayInYear    = r.DayInYear;
            YearNumber   = r.YearNumber;
            PeriodInWeek = r.PeriodInWeek;
            IsWorkPeriod = r.IsWorkPeriod != 0;
            IsWorkHour   = r.IsWorkHour   != 0;
            TimeStr      = r.TimeStr      ?? "";
            TimeStrFull  = r.TimeStrFull  ?? "";
            SolInYear    = r.SolInYear;
            SolsPerYear  = r.SolsPerYear;
        }

        public override string ToString() => TimeStr;
    }

    /// <summary>Mars Coordinated Time (MTC).</summary>
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct MTCRaw
    {
        public int Sol;
        public int Hour;
        public int Minute;
        public int Second;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 6)]
        public string MtcStr;
    }

    public sealed class MTC
    {
        public int    Sol    { get; }
        public int    Hour   { get; }
        public int    Minute { get; }
        public int    Second { get; }
        public string MtcStr { get; }
        internal MTC(in MTCRaw r) { Sol=r.Sol; Hour=r.Hour; Minute=r.Minute; Second=r.Second; MtcStr=r.MtcStr??""; }
        public override string ToString() => MtcStr;
    }

    /// <summary>Line-of-sight status.</summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct LineOfSight
    {
        private int    _clear, _blocked, _degraded;
        public double  ClosestSunAU;
        public double  ElongDeg;
        public bool Clear    => _clear    != 0;
        public bool Blocked  => _blocked  != 0;
        public bool Degraded => _degraded != 0;
    }

    /// <summary>A meeting window where both planets are in work hours.</summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct MeetingWindow
    {
        public long StartMs;
        public long EndMs;
        public int  DurationMin;

        public DateTimeOffset StartUtc =>
            DateTimeOffset.FromUnixTimeMilliseconds(StartMs);
        public DateTimeOffset EndUtc =>
            DateTimeOffset.FromUnixTimeMilliseconds(EndMs);
    }

    /// <summary>
    /// Static class exposing all libinterplanet functions via P/Invoke.
    /// </summary>
    public static class Native
    {
        private const string Lib = "interplanet";

        [DllImport(Lib, EntryPoint = "ipt_helio_pos")]
        public static extern int HelioPos(Planet p, long utc_ms, out HelioPos result);

        [DllImport(Lib, EntryPoint = "ipt_body_distance_au")]
        public static extern double BodyDistanceAU(Planet a, Planet b, long utc_ms);

        [DllImport(Lib, EntryPoint = "ipt_light_travel_s")]
        public static extern double LightTravelS(Planet from, Planet to, long utc_ms);

        [DllImport(Lib, EntryPoint = "ipt_get_planet_time")]
        public static extern int GetPlanetTime(Planet p, long utc_ms, int tz_h,
                                                out PlanetTimeRaw result);

        [DllImport(Lib, EntryPoint = "ipt_get_mtc")]
        public static extern int GetMTC(long utc_ms, out MTCRaw result);

        [DllImport(Lib, EntryPoint = "ipt_get_mars_time_at_offset")]
        public static extern int GetMarsTimeAtOffset(long utc_ms, int offset_h,
                                                      out PlanetTimeRaw result);

        [DllImport(Lib, EntryPoint = "ipt_check_los")]
        public static extern int CheckLOS(Planet a, Planet b, long utc_ms,
                                           out LineOfSight result);

        [DllImport(Lib, EntryPoint = "ipt_lower_quartile_light_time")]
        public static extern double LowerQuartileLightTime(Planet a, Planet b,
                                                            long ref_ms);

        [DllImport(Lib, EntryPoint = "ipt_find_windows")]
        public static extern int FindWindows(Planet a, Planet b,
                                              long from_ms, int earth_days,
                                              [Out] MeetingWindow[] output,
                                              int max_out);

        [DllImport(Lib, EntryPoint = "ipt_format_light_time",
                   CharSet = CharSet.Ansi)]
        public static extern void FormatLightTime(double seconds,
                                                   [Out, MarshalAs(UnmanagedType.LPStr)] System.Text.StringBuilder buf,
                                                   int buf_len);

        [DllImport(Lib, EntryPoint = "ipt_format_planet_time",
                   CharSet = CharSet.Ansi)]
        public static extern void FormatPlanetTime(Planet p,
                                                    in PlanetTimeRaw pt,
                                                    [Out, MarshalAs(UnmanagedType.LPStr)] System.Text.StringBuilder buf,
                                                    int buf_len);
    }

    /// <summary>
    /// High-level managed API over the P/Invoke layer.
    /// </summary>
    public static class Api
    {
        /// <summary>Current UTC timestamp in milliseconds.</summary>
        public static long NowMs() =>
            DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();

        public static PlanetTime GetPlanetTime(Planet p, long utc_ms, int tz_h = 0)
        {
            if (Native.GetPlanetTime(p, utc_ms, tz_h, out var raw) != 0)
                throw new ArgumentException($"Invalid planet: {p}");
            return new PlanetTime(raw);
        }

        public static MTC GetMTC(long utc_ms)
        {
            Native.GetMTC(utc_ms, out var raw);
            return new MTC(raw);
        }

        public static double LightTravelSeconds(Planet from, Planet to, long utc_ms)
        {
            double s = Native.LightTravelS(from, to, utc_ms);
            if (s < 0) throw new ArgumentException("Invalid planet");
            return s;
        }

        public static LineOfSight CheckLOS(Planet a, Planet b, long utc_ms)
        {
            if (Native.CheckLOS(a, b, utc_ms, out var result) != 0)
                throw new ArgumentException("Invalid planet");
            return result;
        }

        public static MeetingWindow[] FindWindows(Planet a, Planet b,
                                                   long from_ms,
                                                   int earth_days,
                                                   int max_windows = 64)
        {
            var buf = new MeetingWindow[max_windows];
            int n = Native.FindWindows(a, b, from_ms, earth_days, buf, max_windows);
            var result = new MeetingWindow[n];
            Array.Copy(buf, result, n);
            return result;
        }

        public static string FormatLightTime(double seconds)
        {
            var sb = new System.Text.StringBuilder(64);
            Native.FormatLightTime(seconds, sb, sb.Capacity);
            return sb.ToString();
        }
    }
}
