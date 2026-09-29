// Go port (go/planet-time). Built by run.sh in a scratch module that
// replaces github.com/interplanet/time with the repository copy.
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"

	ipt "github.com/interplanet/time/interplanet_time"
)

func main() {
	f, err := os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer f.Close()
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 2 {
			continue
		}
		body := fields[0]
		ms, _ := strconv.ParseInt(fields[1], 10, 64)
		pt := ipt.GetPlanetTime(body, ms, 0)
		light := "-"
		if body != "earth" && body != "moon" {
			light = fmt.Sprintf("%.3f", ipt.LightTravelSeconds("earth", body, ms))
		}
		mtc := "-\t-\t-\t-"
		if body == "mars" {
			m := ipt.GetMTC(ms)
			mtc = fmt.Sprintf("%d\t%d\t%d\t%d", m.Sol, m.Hour, m.Minute, m.Second)
		}
		fmt.Fprintf(w, "%s\t%d\t%d\t%d\t%d\t%d\t%s\t%s\n", body, ms, pt.Hour, pt.Minute, pt.Second, pt.DayNumber, light, mtc)
	}
}
