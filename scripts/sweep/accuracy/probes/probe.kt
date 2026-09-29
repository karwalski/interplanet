// Kotlin port (kotlin/planet-time). Built by run.sh in a scratch Gradle project.
import interplanet.time.*
import java.io.File
import java.util.Locale

fun main(args: Array<String>) {
    val sb = StringBuilder()
    for (line in File(args[0]).readLines()) {
        if (line.isBlank()) continue
        val (body, s) = line.trim().split(" ")
        val ms = s.toLong()
        val p = Planet.fromString(body)
        val pt = getPlanetTime(p, ms, 0.0)
        val light = if (body == "earth" || body == "moon") "-"
            else String.format(Locale.ROOT, "%.3f", lightTravelSeconds(Planet.EARTH, p, ms))
        val mtc = if (body == "mars") getMtc(ms).let { "${it.sol}\t${it.hour}\t${it.minute}\t${it.second}" }
            else "-\t-\t-\t-"
        sb.append("$body\t$ms\t${pt.hour}\t${pt.minute}\t${pt.second}\t${pt.dayNumber}\t$light\t$mtc\n")
    }
    print(sb)
}
