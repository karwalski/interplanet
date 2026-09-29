#!/usr/bin/env python3
"""Check the toke build against the shared fixtures.

  1. c/planet-time/fixtures/reference.json: every entry (planet x instant) is
     run through `interplanet time <planet> --at <utc_ms>` and each field the
     CLI prints is compared with the planet-time.js reference values.
  2. spec/golden/plan-ids.json: every v2 vector is run through
     `interplanet planid <JSON.stringify(plan)>` (v3 vectors are reported as
     skipped: the port does not implement SHA-256 / RFC 8785).
  3. `interplanet ltx` must rebuild the v2-createPlan-default vector.
  4. spec/golden/plan-id-prefixes.json: every v2 vector through `planid`,
     compared byte for byte (WTF-8, as the id can hold a lone surrogate).

Usage: python3 toke/verify.py [path/to/interplanet]
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BIN = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "interplanet")


def run(*args):
    r = subprocess.run([BIN, *args], capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def fields(out):
    d = {}
    for line in out.splitlines():
        if ":" in line and line.startswith("  "):
            k, v = line.strip().split(":", 1)
            d[k.strip()] = v.strip()
    return d


fails = 0
checks = 0


def check(label, ok, detail=""):
    global fails, checks
    checks += 1
    if not ok:
        fails += 1
        print("FAIL", label, detail)


ref = json.load(open(os.path.join(ROOT, "c/planet-time/fixtures/reference.json")))
for e in ref["entries"]:
    tag = "%s@%s" % (e["planet"], e["date_label"])
    rc, out = run("time", e["planet"], "--at", str(e["utc_ms"]))
    check(tag + " rc", rc == 0, out)
    f = fields(out)
    check(tag + " time", f.get("Time") == e["time_str_full"], (f.get("Time"), e["time_str_full"]))
    check(tag + " day_number", int(f["Day number"]) == e["day_number"])
    check(tag + " year_number", int(f["Year"]) == e["year_number"])
    check(tag + " day_in_year", int(f["Day in year"]) == e["day_in_year"])
    check(tag + " period_in_week", int(f["Period in week"]) == e["period_in_week"])
    check(tag + " is_work_period", (f["Work period"] == "yes") == bool(e["is_work_period"]))
    check(tag + " is_work_hour", (f["Work hour"] == "yes") == bool(e["is_work_hour"]))
    check(tag + " local_hour", abs(float(f["Local hour"]) - e["local_hour"]) < 1e-9,
          (f["Local hour"], e["local_hour"]))
    check(tag + " day_fraction", abs(float(f["Day fraction"]) - e["day_fraction"]) < 1e-11,
          (f["Day fraction"], e["day_fraction"]))
    check(tag + " helio_r_au", abs(float(f["Helio r"].split()[0]) - e["helio_r_au"]) < 1e-8,
          (f["Helio r"], e["helio_r_au"]))
    if e["light_travel_s"] is None:
        check(tag + " light absent", "Light (Earth)" not in f)
    else:
        check(tag + " light_travel_s", abs(float(f["Light (Earth)"].split()[0]) - e["light_travel_s"]) < 1e-5,
              (f.get("Light (Earth)"), e["light_travel_s"]))
    if e["sol_in_year"] is not None:
        check(tag + " sol_in_year", int(f["Sol in year"]) == e["sol_in_year"])
        check(tag + " sols_per_year", int(f["Sols/year"]) == e["sols_per_year"])
    if e["mtc"] is not None:
        m = e["mtc"]
        check(tag + " mtc", f["MTC"] == "%02d:%02d" % (m["hour"], m["minute"]), (f["MTC"], m))
        rc, out = run("mtc", "--at", str(e["utc_ms"]))
        mf = fields(out)
        check(tag + " mtc sol", int(mf["Sol"]) == m["sol"])
        check(tag + " mtc time", mf["Time"] == "%02d:%02d:%02d" % (m["hour"], m["minute"], m["second"]))
print("reference.json: %d entries" % len(ref["entries"]))

gold = json.load(open(os.path.join(ROOT, "spec/golden/plan-ids.json")))
skipped = []
for v in gold["vectors"]:
    if v["plan"].get("v") != 2:
        skipped.append(v["name"])
        continue
    # json.dumps with these separators matches JSON.stringify for these plans
    text = json.dumps(v["plan"], separators=(",", ":"), ensure_ascii=False)
    rc, out = run("planid", text)
    check("planid " + v["name"], out.strip() == v["planId"], (out.strip(), v["planId"]))
    if v["name"] == "v2-createPlan-default":
        p = v["plan"]
        args = ["ltx", p["title"]] + ["%s:%s:%s:%d" % (n["name"], n["role"], n["location"], n["delay"])
                                      for n in p["nodes"]]
        rc, out = run(*args, "--at", "1773583200000")
        f = fields(out)
        check("ltx createPlan-default planId", f.get("Plan ID") == v["planId"], f.get("Plan ID"))
        check("ltx createPlan-default JSON", f.get("JSON") == text, f.get("JSON"))
print("plan-ids.json: v2 vectors checked; skipped (v3): %s" % ", ".join(skipped))

# planId prefixes: JS whitespace, full Unicode upper-casing, UTF-16 slicing.
# The id can hold a lone surrogate, so compare raw WTF-8 bytes.
pref = json.load(open(os.path.join(ROOT, "spec/golden/plan-id-prefixes.json")))
pskipped = []
for v in pref["vectors"]:
    if v["plan"].get("v") != 2:
        pskipped.append(v["name"])
        continue
    text = json.dumps(v["plan"], separators=(",", ":"), ensure_ascii=False)
    r = subprocess.run([BIN, "planid", text], capture_output=True)
    got = r.stdout.strip().hex()
    check("prefix " + v["name"], got == v["planIdWtf8Hex"],
          (r.stdout.strip().decode("utf-8", "replace"), v["planIdUtf8"]))
print("plan-id-prefixes.json: v2 vectors checked; skipped (v3): %s" % ", ".join(pskipped))

print("%d checks, %d failures" % (checks, fails))
sys.exit(1 if fails else 0)
