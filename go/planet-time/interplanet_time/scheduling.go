package interplanet_time

// MeetingWindow represents a time window when all parties are in work hours.
type MeetingWindow struct {
	StartMs         int64
	EndMs           int64
	DurationMinutes int
}

// FindMeetingWindows scans earthDays ahead in stepMin increments and returns
// windows where both planet a and planet b are in work hours.
func FindMeetingWindows(a, b string, fromMs int64, earthDays, stepMin int) []MeetingWindow {
	if earthDays <= 0 {
		earthDays = 7
	}
	if stepMin <= 0 {
		stepMin = 15
	}
	stepMs := int64(stepMin) * 60_000
	endMs := fromMs + int64(earthDays)*EarthDayMs

	var windows []MeetingWindow
	inWindow := false
	var winStart int64

	for t := fromMs; t < endMs; t += stepMs {
		ptA := GetPlanetTime(a, t, 0)
		ptB := GetPlanetTime(b, t, 0)
		both := ptA.IsWorkHour && ptB.IsWorkHour

		if both && !inWindow {
			inWindow = true
			winStart = t
		} else if !both && inWindow {
			inWindow = false
			durMin := int((t - winStart) / 60_000)
			if durMin > 0 {
				windows = append(windows, MeetingWindow{
					StartMs:         winStart,
					EndMs:           t,
					DurationMinutes: durMin,
				})
			}
		}
	}
	if inWindow {
		durMin := int((endMs - winStart) / 60_000)
		if durMin > 0 {
			windows = append(windows, MeetingWindow{
				StartMs:         winStart,
				EndMs:           endMs,
				DurationMinutes: durMin,
			})
		}
	}
	return windows
}
