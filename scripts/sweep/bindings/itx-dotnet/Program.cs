// Smoke test of the libitx P/Invoke binding: the struct layouts must match
// libitx.h, or these calls return garbage or crash. Needs libitx.so on the
// library path (LD_LIBRARY_PATH=c/ltx/lib).
using System;
using InterPlanet;

int passed = 0, failed = 0;
void Check(string name, bool ok)
{
    if (ok) passed++; else { failed++; Console.WriteLine("FAIL: " + name); }
}

var plan = LtxPlan.Create("Binding check", "2026-03-15T14:00:00Z", 860);
Check("V == 2", plan.V == 2);
Check("title", plan.Title == "Binding check");
Check("2 nodes", plan.Nodes.Length == 2);
Check("7 segment templates", plan.SegmentTemplates.Length == 7);
var id = plan.MakePlanId();
Check("planId " + id, id.StartsWith("LTX-20260315-EARTHHQ-") && id.Contains("-v2-"));
var hash = plan.EncodeHash();
Check("hash starts with #l=", hash.StartsWith("#l="));
var urls = plan.BuildNodeUrls("https://interplanet.live/ltx.html");
Check("2 node URLs", urls.Length == 2);
Check("URL carries the whole hash", urls.Length == 2 && urls[1].Url.EndsWith(hash.Substring(1)));
Check("URL node id", urls.Length == 2 && urls[1].Url.Contains("?node=N1#"));
var ics = plan.GenerateICS();
Check("ICS complete", ics.TrimEnd().EndsWith("END:VCALENDAR") && ics.Contains("LTX-PLANID:" + id));
var back = LtxPlan.DecodeHash(hash);
Check("decode round trip", back.MakePlanId() == id);
Check("segments computed", plan.ComputeSegments().Length == 7 && plan.TotalMin() > 0);

Console.WriteLine($"{passed} passed  {failed} failed");
return failed == 0 ? 0 : 1;
