package interplanet_time

import "math"

// ── Leap seconds / TT ────────────────────────────────────────────────────────

// TaiMinusUtc returns TAI-UTC (leap seconds) for the given UTC milliseconds.
func TaiMinusUtc(utcMs int64) int {
	tai := 10
	for _, ls := range LEAP_SECONDS {
		if utcMs >= ls.UtcMs {
			tai = ls.Delta
		} else {
			break
		}
	}
	return tai
}

// JDE returns the Julian Ephemeris Day (TT) from UTC milliseconds.
func JDE(utcMs int64) float64 {
	ttMs := float64(utcMs) + float64(TaiMinusUtc(utcMs))*1000 + 32184 // TT = TAI + 32.184s
	return 2_440_587.5 + ttMs/86_400_000.0
}

// JC returns Julian centuries from J2000.0 (TT).
func JC(utcMs int64) float64 {
	return (JDE(utcMs) - J2000JD) / 36_525.0
}

// ── Kepler solver ─────────────────────────────────────────────────────────────

// keplerE solves Kepler's equation M = E - e*sin(E) via Newton-Raphson.
func keplerE(M, e float64) float64 {
	E := M
	for i := 0; i < 50; i++ {
		dE := (M - E + e*math.Sin(E)) / (1.0 - e*math.Cos(E))
		E += dE
		if math.Abs(dE) < 1e-12 {
			break
		}
	}
	return E
}

// ── Heliocentric position ─────────────────────────────────────────────────────

// HelioPos holds heliocentric ecliptic coordinates.
type HelioPos struct {
	X, Y float64 // AU
	R    float64 // distance (AU)
	Lon  float64 // ecliptic longitude (radians)
}

// GetHelioPos computes the heliocentric position of a planet at utcMs.
func GetHelioPos(planet string, utcMs int64) HelioPos {
	elems, ok := ORBITAL_ELEMENTS[planet]
	if !ok {
		elems = ORBITAL_ELEMENTS["earth"]
	}

	T := JC(utcMs)
	L := math.Mod(elems.L0+elems.DL*T, 360.0)
	om := elems.Om0
	e := elems.E0
	a := elems.A

	// Mean anomaly (deg → rad)
	M := (math.Mod(L-om+360.0, 360.0)) * math.Pi / 180.0
	E := keplerE(M, e)

	// True anomaly
	nu := 2.0 * math.Atan2(
		math.Sqrt(1.0+e)*math.Sin(E/2.0),
		math.Sqrt(1.0-e)*math.Cos(E/2.0),
	)

	r := a * (1.0 - e*math.Cos(E))
	lon := math.Mod(om*math.Pi/180.0+nu+2.0*math.Pi, 2.0*math.Pi)

	return HelioPos{
		X:   r * math.Cos(lon),
		Y:   r * math.Sin(lon),
		R:   r,
		Lon: lon,
	}
}

// ── Distance & light travel ───────────────────────────────────────────────────

// BodyDistanceAu returns the distance between two bodies in AU.
func BodyDistanceAu(a, b string, utcMs int64) float64 {
	pa := GetHelioPos(a, utcMs)
	pb := GetHelioPos(b, utcMs)
	dx := pa.X - pb.X
	dy := pa.Y - pb.Y
	return math.Sqrt(dx*dx + dy*dy)
}

// LightTravelSeconds returns one-way light travel time between two bodies (seconds).
func LightTravelSeconds(a, b string, utcMs int64) float64 {
	return BodyDistanceAu(a, b, utcMs) * AuSeconds
}

// ── Line of sight ─────────────────────────────────────────────────────────────

// LineOfSight holds the result of a line-of-sight check.
type LineOfSight struct {
	Clear         bool
	Blocked       bool
	Degraded      bool
	ClosestSunAu  float64 // -1 if same body
	ElongDeg      float64
}

// CheckLineOfSight checks whether two bodies have a clear line of sight.
func CheckLineOfSight(a, b string, utcMs int64) LineOfSight {
	pa := GetHelioPos(a, utcMs)
	pb := GetHelioPos(b, utcMs)

	abx := pb.X - pa.X
	aby := pb.Y - pa.Y
	d2 := abx*abx + aby*aby

	if d2 < 1e-20 {
		return LineOfSight{Clear: true, Blocked: false, Degraded: false,
			ClosestSunAu: -1, ElongDeg: 0.0}
	}

	t := math.Max(0.0, math.Min(1.0, -(pa.X*abx+pa.Y*aby)/d2))
	cx := pa.X + t*abx
	cy := pa.Y + t*aby
	closest := math.Sqrt(cx*cx + cy*cy)

	dotAB := abx*pa.X + aby*pa.Y
	abMag := math.Sqrt(d2)
	aMag := math.Sqrt(pa.X*pa.X + pa.Y*pa.Y)
	cosEl := 0.0
	if aMag > 1e-10 && abMag > 1e-10 {
		cosEl = -dotAB / (abMag * aMag)
	}
	elongDeg := 180.0 / math.Pi * math.Acos(math.Max(-1.0, math.Min(1.0, cosEl)))

	blocked := closest < 0.1
	degraded := !blocked && (closest < 0.25 || elongDeg < 5.0)

	return LineOfSight{
		Clear:        !blocked && !degraded,
		Blocked:      blocked,
		Degraded:     degraded,
		ClosestSunAu: closest,
		ElongDeg:     elongDeg,
	}
}

// ── Lower-quartile light time ─────────────────────────────────────────────────

// LowerQuartileLightTime samples one Earth year (360 steps) and returns
// the lower-quartile (p25) one-way light time in seconds.
func LowerQuartileLightTime(a, b string, refMs int64) float64 {
	yearMs := int64(365) * EarthDayMs
	step := yearMs / 360
	samples := make([]float64, 360)
	for i := 0; i < 360; i++ {
		samples[i] = LightTravelSeconds(a, b, refMs+int64(i)*step)
	}
	// simple insertion sort (small slice)
	for i := 1; i < len(samples); i++ {
		for j := i; j > 0 && samples[j] < samples[j-1]; j-- {
			samples[j], samples[j-1] = samples[j-1], samples[j]
		}
	}
	return samples[int(float64(len(samples))*0.25)]
}
