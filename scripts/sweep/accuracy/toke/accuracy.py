#!/usr/bin/env python3
"""Accuracy harness for the toke CLI port (see ../gen-cases-group2.js).

Runs `interplanet time <body> --at <ms>` and `interplanet mtc --at <ms>` for
every instant and prints the comparator's tab-separated lines. Earth and the
Moon print no light time (it is 0 to Earth), so 0 is emitted for them.

  python3 scripts/sweep/accuracy/toke/accuracy.py toke/interplanet \
      scripts/sweep/accuracy/instants-group2.txt
"""
import subprocess
import sys

BODIES = ["mercury", "venus", "earth", "mars", "jupiter", "saturn", "uranus", "neptune", "moon"]


def fields(out):
    d = {}
    for line in out.splitlines():
        if ":" in line and line.startswith("  "):
            k, v = line.strip().split(":", 1)
            d[k.strip()] = v.strip()
    return d


def main():
    binary, instants = sys.argv[1], sys.argv[2]
    for line in open(instants):
        ms = line.strip()
        if not ms:
            continue
        for body in BODIES:
            r = subprocess.run([binary, "time", body, "--at", ms], capture_output=True, text=True)
            f = fields(r.stdout)
            if r.returncode != 0 or "Time" not in f:
                print("%s %s: %s" % (ms, body, r.stdout + r.stderr), file=sys.stderr)
                continue
            h, m, s = f["Time"].split(":")
            light = f.get("Light (Earth)", "0").split()[0]
            yes = lambda k: "1" if f[k] == "yes" else "0"
            print("\t".join([ms, body, str(int(h)), str(int(m)), str(int(s)), f["Day number"],
                             f["Day in year"], f["Year"], f["Period in week"], yes("Work period"),
                             yes("Work hour"), light]))
        r = subprocess.run([binary, "mtc", "--at", ms], capture_output=True, text=True)
        f = fields(r.stdout)
        h, m, s = f["Time"].split(":")
        print("\t".join([ms, "mtc", f["Sol"], str(int(h)), str(int(m)), str(int(s))]))


main()
