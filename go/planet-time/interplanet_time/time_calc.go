package interplanet_time

import (
	"fmt"
	"math"
)

// PlanetTime holds the result of GetPlanetTime.
type PlanetTime struct {
	Hour           int
	Minute         int
	Second         int
	LocalHour      float64
	DayFraction    float64
	DayNumber      int64
	DayInYear      int64
	YearNumber     int64
	PeriodInWeek   int
	IsWorkPeriod   bool
	IsWorkHour     bool
	TimeStr        string // "HH:MM"
	TimeStrFull    string // "HH:MM:SS"
	SolInYear      int64  // Mars only; -1 otherwise
	SolsPerYear    int64  // Mars only; -1 otherwise
}

// MTC holds Mars Coordinated Time.
type MTC struct {
	Sol    int64
	Hour   int
	Minute int
	Second int
	MTCStr string // "HH:MM"
}

// GetPlanetTime returns the local time on a planet at utcMs.
// tzOffsetH is the optional hour offset from the planet's prime meridian.
func GetPlanetTime(planet string, utcMs int64, tzOffsetH float64) PlanetTime {
	effective := planet
	if planet == "moon" {
		effective = "earth"
	}

	pd := PLANET_DATA[effective]
	solarDay := float64(pd.SolarDayMs)

	// tz offset applied as a fraction of one solar day (same as JS)
	elapsedMs := float64(utcMs-pd.EpochMs) + tzOffsetH/24.0*solarDay
	totalDays := elapsedMs / solarDay
	dayNumber := int64(math.Floor(totalDays))
	dayFrac := totalDays - float64(dayNumber)

	localHour := dayFrac * 24.0
	hour := int(localHour)
	minF := (localHour - float64(hour)) * 60.0
	minute := int(minF)
	second := int((minF - float64(minute)) * 60.0)

	// Work period / is_work_hour
	var piw int
	var isWorkPeriod, isWorkHour bool
	if pd.EarthClockSched {
		// Mercury/Venus: solar day >> circadian rhythm — use UTC weekday + UTC hour.
		// UTC day-of-week: ((floor(unix_ms / 86400000) % 7) + 3) % 7 → Mon=0..Sun=6
		// Use math.Floor for correct signed floor division
		utcDay := int64(math.Floor(float64(utcMs) / float64(EarthDayMs)))
		piw = int(((utcDay%7)+7+3)%7)
		isWorkPeriod = piw < pd.WorkPeriodsPerWeek
		msInDay := ((utcMs % int64(EarthDayMs)) + int64(EarthDayMs)) % int64(EarthDayMs)
		utcHour := float64(msInDay) / 3_600_000.0
		isWorkHour = isWorkPeriod && utcHour >= float64(pd.WorkStart) && utcHour < float64(pd.WorkEnd)
	} else {
		totalPeriods := totalDays / pd.DaysPerPeriod
		piw = (int(math.Floor(totalPeriods))%pd.PeriodsPerWeek + pd.PeriodsPerWeek) % pd.PeriodsPerWeek
		isWorkPeriod = piw < pd.WorkPeriodsPerWeek
		isWorkHour = isWorkPeriod && localHour >= float64(pd.WorkStart) && localHour < float64(pd.WorkEnd)
	}

	// Year / day-in-year
	yearLenDays := float64(pd.SiderealYrMs) / solarDay
	yearNumber := int64(math.Floor(totalDays / yearLenDays))
	dayInYear := int64(math.Floor(totalDays - float64(yearNumber)*yearLenDays))

	solInYear := int64(-1)
	solsPerYear := int64(-1)
	if effective == "mars" {
		solInYear = dayInYear
		solsPerYear = int64(math.Round(float64(pd.SiderealYrMs) / solarDay))
	}

	return PlanetTime{
		Hour:         hour,
		Minute:       minute,
		Second:       second,
		LocalHour:    localHour,
		DayFraction:  dayFrac,
		DayNumber:    dayNumber,
		DayInYear:    dayInYear,
		YearNumber:   yearNumber,
		PeriodInWeek: piw,
		IsWorkPeriod: isWorkPeriod,
		IsWorkHour:   isWorkHour,
		TimeStr:      fmt.Sprintf("%02d:%02d", hour, minute),
		TimeStrFull:  fmt.Sprintf("%02d:%02d:%02d", hour, minute, second),
		SolInYear:    solInYear,
		SolsPerYear:  solsPerYear,
	}
}

// GetMTC returns Mars Coordinated Time for the given UTC milliseconds.
func GetMTC(utcMs int64) MTC {
	ms := float64(utcMs - MarsEpochMs)
	sol := int64(math.Floor(ms / float64(MarsSolMs)))
	fracMs := math.Mod(ms, float64(MarsSolMs))
	if fracMs < 0 {
		fracMs += float64(MarsSolMs)
	}
	totalSec := fracMs / 1000.0
	hour := int(totalSec / 3600.0)
	minute := int(math.Mod(totalSec, 3600.0) / 60.0)
	second := int(math.Mod(totalSec, 60.0))

	return MTC{
		Sol:    sol,
		Hour:   hour,
		Minute: minute,
		Second: second,
		MTCStr: fmt.Sprintf("%02d:%02d", hour, minute),
	}
}
