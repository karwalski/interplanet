// FixtureTest.cs — Standalone fixture runner for InterplanetTime C# library
// Story 18.11
//
// Usage: dotnet run --project FixtureTest [path/to/reference.json]
//
// Reads the 54-entry reference.json fixture, validates hour/minute and
// light-travel-seconds for each entry. Exits 0 on success, 1 on any failure.

using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using InterplanetTime;

// ── JSON types ────────────────────────────────────────────────────────────────

class FixtureEntry
{
    public long   utc_ms          { get; set; }
    public string planet          { get; set; } = "";
    public int    hour            { get; set; }
    public int    minute          { get; set; }
    public double light_travel_s  { get; set; }
    public int    period_in_week  { get; set; }
    public int    is_work_period  { get; set; }
    public int    is_work_hour    { get; set; }
}

class FixtureFile
{
    public List<FixtureEntry> entries { get; set; } = new();
}

// ── Program ───────────────────────────────────────────────────────────────────

static class Program
{
    static int Main(string[] args)
    {
        string fixturePath = args.Length > 0
            ? args[0]
            : Path.Combine(AppContext.BaseDirectory, "../../c/fixtures/reference.json");

        // Resolve relative paths against the assembly directory
        if (!Path.IsPathRooted(fixturePath))
        {
            string? src = Path.GetDirectoryName(
                System.Reflection.Assembly.GetExecutingAssembly().Location);
            fixturePath = Path.GetFullPath(Path.Combine(src ?? ".", fixturePath));
        }

        if (!File.Exists(fixturePath))
        {
            Console.WriteLine($"SKIP: fixture file not found at {fixturePath}");
            Console.WriteLine("0 passed  0 failed  (fixtures skipped)");
            return 0;
        }

        string json = File.ReadAllText(fixturePath);
        FixtureFile? fixture;
        try
        {
            fixture = JsonSerializer.Deserialize<FixtureFile>(json);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Failed to parse fixture: {ex.Message}");
            return 1;
        }

        if (fixture == null || fixture.entries.Count == 0)
        {
            Console.Error.WriteLine("Fixture file is empty or malformed.");
            return 1;
        }

        int passed = 0, failed = 0;

        foreach (var entry in fixture.entries)
        {
            string tag = $"{entry.planet}@{entry.utc_ms}";

            // Check hour and minute
            PlanetTime pt = Ipt.GetPlanetTime(entry.planet, entry.utc_ms, 0.0);

            if (pt.Hour == entry.hour)
                passed++;
            else
            {
                failed++;
                Console.WriteLine($"FAIL: {tag} hour={entry.hour} (got {pt.Hour})");
            }

            if (pt.Minute == entry.minute)
                passed++;
            else
            {
                failed++;
                Console.WriteLine($"FAIL: {tag} minute={entry.minute} (got {pt.Minute})");
            }

            // Check light travel (skip for earth and moon)
            if (entry.light_travel_s != 0
                && entry.planet != "earth"
                && entry.planet != "moon")
            {
                double lt = Ipt.LightTravelSeconds("earth", entry.planet, entry.utc_ms);
                if (Math.Abs(lt - entry.light_travel_s) <= 2.0)
                    passed++;
                else
                {
                    failed++;
                    Console.WriteLine(
                        $"FAIL: {tag} lightTravel — expected {entry.light_travel_s:F3}, got {lt:F3}");
                }
            }

            // Check period_in_week
            if (pt.PeriodInWeek == entry.period_in_week)
                passed++;
            else
            {
                failed++;
                Console.WriteLine($"FAIL: {tag} period_in_week={entry.period_in_week} (got {pt.PeriodInWeek})");
            }

            // Check is_work_period
            int gotWP = pt.IsWorkPeriod ? 1 : 0;
            if (gotWP == entry.is_work_period)
                passed++;
            else
            {
                failed++;
                Console.WriteLine($"FAIL: {tag} is_work_period={entry.is_work_period} (got {gotWP})");
            }

            // Check is_work_hour
            int gotWH = pt.IsWorkHour ? 1 : 0;
            if (gotWH == entry.is_work_hour)
                passed++;
            else
            {
                failed++;
                Console.WriteLine($"FAIL: {tag} is_work_hour={entry.is_work_hour} (got {gotWH})");
            }
        }

        Console.WriteLine($"Fixture entries checked: {fixture.entries.Count}");
        Console.WriteLine($"{passed} passed  {failed} failed");
        return failed > 0 ? 1 : 0;
    }
}
