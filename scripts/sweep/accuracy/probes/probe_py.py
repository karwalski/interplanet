"""Python port (python/planet-time/src). Usage: python3 probe_py.py <inputs.txt>"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[4] / "python" / "planet-time" / "src"))
from interplanet_time import Planet, get_planet_time, get_mtc, light_travel_seconds  # noqa: E402

for line in open(sys.argv[1]):
    if not line.strip():
        continue
    body, s = line.split()
    ms = int(s)
    p = Planet[body.upper()]
    pt = get_planet_time(p, ms, 0)
    light = "-" if body in ("earth", "moon") else "%.3f" % light_travel_seconds(Planet.EARTH, p, ms)
    mtc = ["-"] * 4
    if body == "mars":
        m = get_mtc(ms)
        mtc = [m.sol, m.hour, m.minute, m.second]
    print("\t".join(str(x) for x in [body, ms, pt.hour, pt.minute, pt.second, pt.day_number, light, *mtc]))
