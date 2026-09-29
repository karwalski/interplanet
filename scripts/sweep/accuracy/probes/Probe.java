// Java port (java/planet-time). Usage: java Probe <inputs.txt>
import com.interplanet.time.*;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;

public class Probe {
    public static void main(String[] args) throws Exception {
        StringBuilder sb = new StringBuilder();
        for (String line : Files.readAllLines(Path.of(args[0]))) {
            if (line.isBlank()) continue;
            String[] f = line.trim().split(" ");
            String body = f[0];
            long ms = Long.parseLong(f[1]);
            Planet p = Planet.fromString(body);
            PlanetTime pt = InterplanetTime.getPlanetTime(p, ms, 0.0);
            String light = (body.equals("earth") || body.equals("moon")) ? "-"
                : String.format(Locale.ROOT, "%.3f", InterplanetTime.lightTravelSeconds(Planet.EARTH, p, ms));
            String mtc = "-\t-\t-\t-";
            if (body.equals("mars")) {
                MTC m = InterplanetTime.getMTC(ms);
                mtc = m.sol() + "\t" + m.hour() + "\t" + m.minute() + "\t" + m.second();
            }
            sb.append(body).append('\t').append(ms).append('\t').append(pt.hour()).append('\t')
              .append(pt.minute()).append('\t').append(pt.second()).append('\t').append(pt.dayNumber())
              .append('\t').append(light).append('\t').append(mtc).append('\n');
        }
        System.out.print(sb);
    }
}
