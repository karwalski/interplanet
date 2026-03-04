package interplanet_time_test

import (
	"math"
	"strings"
	"testing"

	ipt "github.com/interplanet/time/interplanet_time"
)

const j2000Ms = int64(946_728_000_000)

// ── 1. Constants ──────────────────────────────────────────────────────────────

func TestJ2000Ms(t *testing.T) {
	if ipt.J2000Ms != 946_728_000_000 {
		t.Errorf("J2000Ms = %d, want 946728000000", ipt.J2000Ms)
	}
}

func TestMarsEpochMs(t *testing.T) {
	if ipt.MarsEpochMs != -524_069_761_536 {
		t.Errorf("MarsEpochMs = %d", ipt.MarsEpochMs)
	}
}

func TestMarsSolMs(t *testing.T) {
	if ipt.MarsSolMs != 88_775_244 {
		t.Errorf("MarsSolMs = %d", ipt.MarsSolMs)
	}
}

func TestAuSeconds(t *testing.T) {
	expected := 149_597_870.7 / 299_792.458
	if math.Abs(ipt.AuSeconds-expected) > 0.1 {
		t.Errorf("AuSeconds = %f, want ~%f", ipt.AuSeconds, expected)
	}
}

func TestPlanetsCount(t *testing.T) {
	if len(ipt.Planets) != 9 {
		t.Errorf("Planets count = %d, want 9", len(ipt.Planets))
	}
}

func TestOrbitalElementsCount(t *testing.T) {
	if len(ipt.ORBITAL_ELEMENTS) != 9 {
		t.Errorf("ORBITAL_ELEMENTS count = %d, want 9", len(ipt.ORBITAL_ELEMENTS))
	}
}

func TestLeapSecondsCount(t *testing.T) {
	if len(ipt.LEAP_SECONDS) == 0 {
		t.Error("LEAP_SECONDS is empty")
	}
	last := ipt.LEAP_SECONDS[len(ipt.LEAP_SECONDS)-1]
	if last.Delta != 37 {
		t.Errorf("last leap second delta = %d, want 37", last.Delta)
	}
}

// ── 2. TaiMinusUtc ────────────────────────────────────────────────────────────

func TestTaiAtJ2000(t *testing.T) {
	if ipt.TaiMinusUtc(j2000Ms) != 32 {
		t.Errorf("TaiMinusUtc at J2000 = %d, want 32", ipt.TaiMinusUtc(j2000Ms))
	}
}

func TestTaiAfterLastLeap(t *testing.T) {
	if ipt.TaiMinusUtc(1_483_228_800_001) != 37 {
		t.Errorf("TaiMinusUtc after last leap = %d, want 37", ipt.TaiMinusUtc(1_483_228_800_001))
	}
}

func TestTaiBeforeFirst(t *testing.T) {
	if ipt.TaiMinusUtc(0) != 10 {
		t.Errorf("TaiMinusUtc at 0 = %d, want 10", ipt.TaiMinusUtc(0))
	}
}

// ── 3. JDE / JC ───────────────────────────────────────────────────────────────

func TestJdeAtJ2000(t *testing.T) {
	jde := ipt.JDE(j2000Ms)
	if math.Abs(jde-2_451_545.0) > 0.01 {
		t.Errorf("JDE at J2000 = %f, want ~2451545.0", jde)
	}
}

func TestJcAtJ2000(t *testing.T) {
	jc := ipt.JC(j2000Ms)
	if math.Abs(jc-0.0) > 0.01 {
		t.Errorf("JC at J2000 = %f, want ~0.0", jc)
	}
}

func TestJdeIncreases(t *testing.T) {
	a := ipt.JDE(j2000Ms)
	b := ipt.JDE(j2000Ms + 86_400_000)
	if b <= a {
		t.Error("JDE should increase with time")
	}
}

// ── 4. Heliocentric position ──────────────────────────────────────────────────

func TestEarthDistanceNearOneAu(t *testing.T) {
	pos := ipt.GetHelioPos("earth", j2000Ms)
	if math.Abs(pos.R-1.0) > 0.05 {
		t.Errorf("Earth distance = %f AU, want ~1.0", pos.R)
	}
}

func TestMarsDistanceInRange(t *testing.T) {
	pos := ipt.GetHelioPos("mars", j2000Ms)
	if pos.R < 1.3 || pos.R > 1.7 {
		t.Errorf("Mars distance = %f AU, want 1.3–1.7", pos.R)
	}
}

func TestXYConsistentWithR(t *testing.T) {
	pos := ipt.GetHelioPos("earth", j2000Ms)
	r := math.Sqrt(pos.X*pos.X + pos.Y*pos.Y)
	if math.Abs(r-pos.R) > 0.001 {
		t.Errorf("|xy| = %f, pos.R = %f, mismatch", r, pos.R)
	}
}

// ── 5. Light travel ───────────────────────────────────────────────────────────

func TestEarthMarsAtJ2000(t *testing.T) {
	lt := ipt.LightTravelSeconds("earth", "mars", j2000Ms)
	if lt < 100 || lt > 2000 {
		t.Errorf("Earth-Mars light travel = %f s, want 100–2000", lt)
	}
}

func TestEarthMarsOpposition2003(t *testing.T) {
	// 2003-08-27 — historic closest approach
	lt := ipt.LightTravelSeconds("earth", "mars", 1_061_942_400_000)
	if math.Abs(lt-185.0) > 30.0 {
		t.Errorf("Earth-Mars 2003 opposition = %f s, want ~185", lt)
	}
}

func TestSymmetric(t *testing.T) {
	ab := ipt.LightTravelSeconds("earth", "mars", j2000Ms)
	ba := ipt.LightTravelSeconds("mars", "earth", j2000Ms)
	if math.Abs(ab-ba) > 0.001 {
		t.Errorf("Light travel not symmetric: ab=%f ba=%f", ab, ba)
	}
}

// ── 6. MTC ────────────────────────────────────────────────────────────────────

func TestMtcAtJ2000(t *testing.T) {
	mtc := ipt.GetMTC(j2000Ms)
	if mtc.Hour < 0 || mtc.Hour >= 24 {
		t.Errorf("MTC hour = %d out of range", mtc.Hour)
	}
	if mtc.Minute < 0 || mtc.Minute >= 60 {
		t.Errorf("MTC minute = %d out of range", mtc.Minute)
	}
}

func TestMtcStrFormat(t *testing.T) {
	mtc := ipt.GetMTC(j2000Ms)
	if len(mtc.MTCStr) != 5 || mtc.MTCStr[2] != ':' {
		t.Errorf("MTCStr format wrong: %q", mtc.MTCStr)
	}
}

func TestMtcSolAtMarsEpoch(t *testing.T) {
	mtc := ipt.GetMTC(ipt.MarsEpochMs)
	if mtc.Sol != 0 {
		t.Errorf("MTC sol at Mars epoch = %d, want 0", mtc.Sol)
	}
}

// ── 7. GetPlanetTime ──────────────────────────────────────────────────────────

func assertValidTime(t *testing.T, planet string) {
	t.Helper()
	pt := ipt.GetPlanetTime(planet, j2000Ms, 0)
	if pt.Hour < 0 || pt.Hour >= 24 {
		t.Errorf("%s hour %d out of range", planet, pt.Hour)
	}
	if pt.Minute < 0 || pt.Minute >= 60 {
		t.Errorf("%s minute %d out of range", planet, pt.Minute)
	}
	if pt.Second < 0 || pt.Second >= 60 {
		t.Errorf("%s second %d out of range", planet, pt.Second)
	}
	if len(pt.TimeStr) != 5 || pt.TimeStr[2] != ':' {
		t.Errorf("%s TimeStr format wrong: %q", planet, pt.TimeStr)
	}
	if len(pt.TimeStrFull) != 8 {
		t.Errorf("%s TimeStrFull format wrong: %q", planet, pt.TimeStrFull)
	}
}

func TestAllPlanets(t *testing.T) {
	for _, p := range ipt.Planets {
		t.Run(p, func(t *testing.T) { assertValidTime(t, p) })
	}
}

func TestTzOffsetShiftsHour(t *testing.T) {
	base := ipt.GetPlanetTime("mars", j2000Ms, 0)
	off := ipt.GetPlanetTime("mars", j2000Ms, 2.0)
	diff := (off.Hour*60 + off.Minute) - (base.Hour*60 + base.Minute)
	if diff > 23*60 {
		diff -= 24 * 60
	}
	if diff < -23*60 {
		diff += 24 * 60
	}
	if math.Abs(float64(diff)-120.0) > 1.0 {
		t.Errorf("tz offset 2h → diff %d min, want ~120", diff)
	}
}

func TestMarsHasSolInYear(t *testing.T) {
	pt := ipt.GetPlanetTime("mars", j2000Ms, 0)
	if pt.SolInYear < 0 {
		t.Error("Mars SolInYear should be non-negative")
	}
	if pt.SolsPerYear != 669 {
		t.Errorf("Mars SolsPerYear = %d, want 669", pt.SolsPerYear)
	}
}

func TestEarthNoSolInYear(t *testing.T) {
	pt := ipt.GetPlanetTime("earth", j2000Ms, 0)
	if pt.SolInYear != -1 {
		t.Errorf("Earth SolInYear should be -1, got %d", pt.SolInYear)
	}
}

func TestEarthEpochHourIsZero(t *testing.T) {
	pt := ipt.GetPlanetTime("earth", j2000Ms, 0)
	if pt.Hour != 0 {
		t.Errorf("Earth at J2000 hour = %d, want 0", pt.Hour)
	}
}

// ── 8. Work-hour logic ────────────────────────────────────────────────────────

func TestWorkHourAtNine(t *testing.T) {
	ms := j2000Ms + 9*3_600_000
	pt := ipt.GetPlanetTime("earth", ms, 0)
	if pt.Hour < 9 || pt.Hour >= 17 {
		t.Errorf("hour %d should be in [9,17)", pt.Hour)
	}
	if !pt.IsWorkHour {
		t.Error("should be work hour at 9:00")
	}
}

func TestRestHourAtMidnight(t *testing.T) {
	pt := ipt.GetPlanetTime("earth", j2000Ms, 0)
	if pt.Hour != 0 {
		t.Errorf("hour = %d, want 0", pt.Hour)
	}
	if pt.IsWorkHour {
		t.Error("midnight should not be work hour")
	}
}

// ── 9. Line of sight ──────────────────────────────────────────────────────────

func TestLosEarthMarsAtJ2000(t *testing.T) {
	los := ipt.CheckLineOfSight("earth", "mars", j2000Ms)
	if los.ElongDeg <= 0 {
		t.Errorf("ElongDeg = %f, want > 0", los.ElongDeg)
	}
}

func TestLosBlockedConjunction2021(t *testing.T) {
	// 2021-10-08: Mars near superior conjunction
	los := ipt.CheckLineOfSight("earth", "mars", 1_633_651_200_000)
	if los.Clear {
		t.Error("should not be clear near superior conjunction")
	}
}

func TestLosOpposition2020(t *testing.T) {
	// 2020-10-13: Mars opposition — clear path
	los := ipt.CheckLineOfSight("earth", "mars", 1_602_547_200_000)
	if !los.Clear {
		t.Error("should be clear at Mars opposition")
	}
}

// ── 10. Meeting windows ───────────────────────────────────────────────────────

func TestEarthEarthAlwaysOverlaps(t *testing.T) {
	wins := ipt.FindMeetingWindows("earth", "earth", j2000Ms, 1, 15)
	if len(wins) == 0 {
		t.Error("Earth+Earth should always overlap")
	}
}

func TestWindowsHavePositiveDuration(t *testing.T) {
	wins := ipt.FindMeetingWindows("earth", "mars", j2000Ms, 7, 15)
	for _, w := range wins {
		if w.DurationMinutes <= 0 {
			t.Errorf("window duration %d ≤ 0", w.DurationMinutes)
		}
		if w.EndMs <= w.StartMs {
			t.Errorf("window end %d ≤ start %d", w.EndMs, w.StartMs)
		}
	}
}

// ── 11. Formatting ────────────────────────────────────────────────────────────

func TestFormat186Seconds(t *testing.T) {
	got := ipt.FormatLightTime(186)
	if got != "3 min 6 s" {
		t.Errorf("FormatLightTime(186) = %q, want %q", got, "3 min 6 s")
	}
}

func TestFormatSecondsOnly(t *testing.T) {
	if ipt.FormatLightTime(45) != "45 s" {
		t.Errorf("FormatLightTime(45) = %q", ipt.FormatLightTime(45))
	}
}

func TestFormatHours(t *testing.T) {
	if ipt.FormatLightTime(3700) != "1 h 1 min 40 s" {
		t.Errorf("FormatLightTime(3700) = %q", ipt.FormatLightTime(3700))
	}
}

func TestFormatZero(t *testing.T) {
	if ipt.FormatLightTime(0) != "0 s" {
		t.Errorf("FormatLightTime(0) = %q", ipt.FormatLightTime(0))
	}
}

func TestFormatOneMinute(t *testing.T) {
	if ipt.FormatLightTime(60) != "1 min" {
		t.Errorf("FormatLightTime(60) = %q", ipt.FormatLightTime(60))
	}
}

func TestFormatPlanetTimeISO(t *testing.T) {
	s := ipt.FormatPlanetTimeISO("mars", 14, 30, 0)
	if !strings.Contains(s, "14:30:00") || !strings.Contains(s, "mars") {
		t.Errorf("FormatPlanetTimeISO result = %q", s)
	}
}
