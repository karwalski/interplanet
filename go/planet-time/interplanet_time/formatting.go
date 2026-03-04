package interplanet_time

import "fmt"

// FormatLightTime formats a light travel duration in seconds as a human-readable string.
// Examples: 45 → "45 s", 186 → "3 min 6 s", 3700 → "1 h 1 min 40 s"
func FormatLightTime(seconds float64) string {
	s := int(seconds)
	if s < 60 {
		return fmt.Sprintf("%d s", s)
	}
	h := s / 3600
	m := (s % 3600) / 60
	sec := s % 60
	if h > 0 {
		if sec > 0 {
			return fmt.Sprintf("%d h %d min %d s", h, m, sec)
		}
		return fmt.Sprintf("%d h %d min", h, m)
	}
	if sec > 0 {
		return fmt.Sprintf("%d min %d s", m, sec)
	}
	return fmt.Sprintf("%d min", m)
}

// FormatPlanetTimeISO returns a simple ISO-like string for a planet time.
// Format: "planet/HH:MM:SS"
func FormatPlanetTimeISO(planet string, hour, minute, second int) string {
	return fmt.Sprintf("%s/%02d:%02d:%02d", planet, hour, minute, second)
}
