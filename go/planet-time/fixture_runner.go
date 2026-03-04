package main

import (
	"encoding/json"
	"fmt"
	"math"
	"os"

	ipt "github.com/interplanet/time/interplanet_time"
)

type fixtureEntry struct {
	UtcMs        int64   `json:"utc_ms"`
	Planet       string  `json:"planet"`
	Hour         int     `json:"hour"`
	Minute       int     `json:"minute"`
	LightTravelS float64 `json:"light_travel_s"`
}

type fixtureFile struct {
	Entries []fixtureEntry `json:"entries"`
}

func main() {
	fixturePath := "../../c/planet-time/fixtures/reference.json"
	if len(os.Args) > 1 {
		fixturePath = os.Args[1]
	}

	data, err := os.ReadFile(fixturePath)
	if err != nil {
		fmt.Printf("SKIP: fixture file not found at %s\n", fixturePath)
		fmt.Println("0 passed  0 failed  (fixtures skipped)")
		os.Exit(0)
	}

	var fixture fixtureFile
	if err := json.Unmarshal(data, &fixture); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to parse fixture: %v\n", err)
		os.Exit(1)
	}

	passed, failed := 0, 0

	for _, entry := range fixture.Entries {
		tag := fmt.Sprintf("%s@%d", entry.Planet, entry.UtcMs)
		pt := ipt.GetPlanetTime(entry.Planet, entry.UtcMs, 0)

		if pt.Hour == entry.Hour {
			passed++
		} else {
			failed++
			fmt.Printf("FAIL: %s hour=%d (got %d)\n", tag, entry.Hour, pt.Hour)
		}

		if pt.Minute == entry.Minute {
			passed++
		} else {
			failed++
			fmt.Printf("FAIL: %s minute=%d (got %d)\n", tag, entry.Minute, pt.Minute)
		}

		if entry.LightTravelS != 0 && entry.Planet != "earth" && entry.Planet != "moon" {
			lt := ipt.LightTravelSeconds("earth", entry.Planet, entry.UtcMs)
			if math.Abs(lt-entry.LightTravelS) <= 2.0 {
				passed++
			} else {
				failed++
				fmt.Printf("FAIL: %s lightTravel — expected %.3f, got %.3f\n",
					tag, entry.LightTravelS, lt)
			}
		}
	}

	fmt.Printf("Fixture entries checked: %d\n", len(fixture.Entries))
	fmt.Printf("%d passed  %d failed\n", passed, failed)
	if failed > 0 {
		os.Exit(1)
	}
}
