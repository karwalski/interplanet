// Package interplanet_time provides planetary time calculations.
// Ported verbatim from planet-time.js.
package interplanet_time

import "math"

// Fundamental constants
const (
	J2000Ms       = int64(946_728_000_000)    // Date.UTC(2000,0,1,12,0,0) — TT noon
	J2000JD       = 2_451_545.0               // Julian Day at J2000
	EarthDayMs    = int64(86_400_000)         // ms per Earth solar day
	MarsEpochMs   = int64(-524_069_761_536)   // MY 0 sol 0 — Date.UTC(1953,4,24,9,3,58,464)
	MarsSolMs     = int64(88_775_244)         // ms per Mars solar day
	AuKm          = 149_597_870.7             // km per AU
	CKms          = 299_792.458               // km/s (speed of light)
	AuSeconds     = AuKm / CKms              // ~499.0 light-seconds per AU
)

// Planets ordered by index
var Planets = []string{
	"mercury", "venus", "earth", "mars",
	"jupiter", "saturn", "uranus", "neptune", "moon",
}

// PlanetData holds per-planet calendar constants.
type PlanetData struct {
	SolarDayMs         int64
	SiderealYrMs       int64
	EpochMs            int64
	WorkStart          int
	WorkEnd            int
	DaysPerPeriod      float64
	PeriodsPerWeek     int
	WorkPeriodsPerWeek int
	EarthClockSched    bool // Mercury/Venus: use UTC weekday+hour instead of planet local time
}

// PLANET_DATA mirrors the PLANETS table in planet-time.js.
var PLANET_DATA = map[string]PlanetData{
	"mercury": {
		SolarDayMs:        int64(math.Round(175.9408 * float64(EarthDayMs))),
		SiderealYrMs:      int64(math.Round(87.9691 * float64(EarthDayMs))),
		EpochMs:           J2000Ms,
		WorkStart:         9, WorkEnd: 17, // Earth-clock scheduling: UTC 09–17
		DaysPerPeriod: 1.0, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
		EarthClockSched: true,
	},
	"venus": {
		SolarDayMs:        int64(math.Round(116.7500 * float64(EarthDayMs))),
		SiderealYrMs:      int64(math.Round(224.701 * float64(EarthDayMs))),
		EpochMs:           J2000Ms,
		WorkStart:         9, WorkEnd: 17, // Earth-clock scheduling: UTC 09–17
		DaysPerPeriod: 1.0, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
		EarthClockSched: true,
	},
	"earth": {
		SolarDayMs:        EarthDayMs,
		SiderealYrMs:      int64(math.Round(365.25636 * float64(EarthDayMs))),
		EpochMs:           J2000Ms,
		WorkStart:         9, WorkEnd: 17,
		DaysPerPeriod: 1.0, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
	},
	"mars": {
		SolarDayMs:        MarsSolMs,
		SiderealYrMs:      int64(math.Round(686.9957 * float64(EarthDayMs))),
		EpochMs:           MarsEpochMs,
		WorkStart:         9, WorkEnd: 17,
		DaysPerPeriod: 1.0, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
	},
	"jupiter": {
		SolarDayMs:        int64(math.Round(9.9250 * 3_600_000)),
		SiderealYrMs:      int64(math.Round(4332.589 * float64(EarthDayMs))),
		EpochMs:           J2000Ms,
		WorkStart:         8, WorkEnd: 16,
		DaysPerPeriod: 2.5, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
	},
	"saturn": {
		// Mankovich, Marley, Fortney & Mozshovitz 2023 ring seismology refinement
		SolarDayMs:        int64(math.Round(10.578 * 3_600_000)),
		SiderealYrMs:      int64(math.Round(10_759.22 * float64(EarthDayMs))),
		EpochMs:           J2000Ms,
		WorkStart:         8, WorkEnd: 16,
		DaysPerPeriod: 2.25, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
	},
	"uranus": {
		SolarDayMs:        int64(math.Round(17.2479 * 3_600_000)),
		SiderealYrMs:      int64(math.Round(30_688.5 * float64(EarthDayMs))),
		EpochMs:           J2000Ms,
		WorkStart:         8, WorkEnd: 16,
		DaysPerPeriod: 1.0, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
	},
	"neptune": {
		SolarDayMs:        int64(math.Round(16.1100 * 3_600_000)),
		SiderealYrMs:      int64(math.Round(60_195.0 * float64(EarthDayMs))),
		EpochMs:           J2000Ms,
		WorkStart:         8, WorkEnd: 16,
		DaysPerPeriod: 1.0, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
	},
	"moon": {
		SolarDayMs:        EarthDayMs,
		SiderealYrMs:      int64(math.Round(365.25636 * float64(EarthDayMs))),
		EpochMs:           J2000Ms,
		WorkStart:         9, WorkEnd: 17,
		DaysPerPeriod: 1.0, PeriodsPerWeek: 7, WorkPeriodsPerWeek: 5,
	},
}

// OrbitalElements holds Keplerian elements at J2000.0 (Meeus Table 31.a).
type OrbitalElements struct {
	L0  float64 // mean longitude (deg)
	DL  float64 // rate (deg/Julian century)
	Om0 float64 // longitude of perihelion (deg)
	E0  float64 // eccentricity
	A   float64 // semi-major axis (AU)
}

// ORBITAL_ELEMENTS mirrors the JS table verbatim.
var ORBITAL_ELEMENTS = map[string]OrbitalElements{
	"mercury": {L0: 252.2507, DL: 149_474.0722, Om0: 77.4561, E0: 0.20564, A: 0.38710},
	"venus":   {L0: 181.9798, DL: 58_519.2130, Om0: 131.5637, E0: 0.00677, A: 0.72333},
	"earth":   {L0: 100.4664, DL: 36_000.7698, Om0: 102.9373, E0: 0.01671, A: 1.00000},
	"mars":    {L0: 355.4330, DL: 19_141.6964, Om0: 336.0600, E0: 0.09341, A: 1.52366},
	"jupiter": {L0: 34.3515, DL: 3_036.3027, Om0: 14.3320, E0: 0.04849, A: 5.20336},
	"saturn":  {L0: 50.0775, DL: 1_223.5093, Om0: 93.0572, E0: 0.05551, A: 9.53707},
	"uranus":  {L0: 314.0550, DL: 429.8633, Om0: 173.0052, E0: 0.04630, A: 19.19126},
	"neptune": {L0: 304.3480, DL: 219.8997, Om0: 48.1234, E0: 0.00899, A: 30.06900},
	"moon":    {L0: 100.4664, DL: 36_000.7698, Om0: 102.9373, E0: 0.01671, A: 1.00000},
}

// LeapSecond is a [utcMs, taiMinusUtc] pair.
type LeapSecond struct {
	UtcMs int64
	Delta int
}

// LEAP_SECONDS is the 28-entry IERS table (last entry: 2017-01-01).
var LEAP_SECONDS = []LeapSecond{
	{63_072_000_000, 10}, {78_796_800_000, 11}, {94_694_400_000, 12},
	{126_230_400_000, 13}, {157_766_400_000, 14}, {189_302_400_000, 15},
	{220_924_800_000, 16}, {252_460_800_000, 17}, {283_996_800_000, 18},
	{315_532_800_000, 19}, {362_793_600_000, 20}, {394_329_600_000, 21},
	{425_865_600_000, 22}, {489_024_000_000, 23}, {567_993_600_000, 24},
	{631_152_000_000, 25}, {662_688_000_000, 26}, {709_948_800_000, 27},
	{741_484_800_000, 28}, {773_020_800_000, 29}, {820_454_400_000, 30},
	{867_715_200_000, 31}, {915_148_800_000, 32}, {1_136_073_600_000, 33},
	{1_230_768_000_000, 34}, {1_341_100_800_000, 35}, {1_435_708_800_000, 36},
	{1_483_228_800_000, 37},
}
