// Accuracy harness for csharp/planet-time (see ../gen-cases-group2.js).
//   dotnet run --project scripts/sweep/accuracy/csharp -- scripts/sweep/accuracy/instants-group2.txt
using System.Globalization;
using InterplanetTime;

string[] bodies = { "mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune", "moon" };
var inv = CultureInfo.InvariantCulture;
static int B(bool v) => v ? 1 : 0;

foreach (var raw in File.ReadAllLines(args[0]))
{
    var line = raw.Trim();
    if (line.Length == 0) continue;
    long ms = long.Parse(line, inv);
    foreach (var body in bodies)
    {
        PlanetTime pt; double lt;
        try
        {
            pt = Ipt.GetPlanetTime(body, ms);
            lt = Ipt.LightTravelSeconds(body, "earth", ms);
        }
        catch (Exception e) { Console.Error.WriteLine($"{ms} {body}: {e.Message}"); continue; }
        Console.WriteLine(string.Join("\t", ms, body, pt.Hour, pt.Minute, pt.Second, pt.DayNumber,
            pt.DayInYear, pt.YearNumber, pt.PeriodInWeek, B(pt.IsWorkPeriod), B(pt.IsWorkHour),
            lt.ToString("F6", inv)));
    }
    var m = Ipt.GetMtc(ms);
    Console.WriteLine(string.Join("\t", ms, "mtc", m.Sol, m.Hour, m.Minute, m.Second));
}
