// Scala port (scala/planet-time). Built by run.sh in a scratch sbt project.
import interplanet.time.*
import scala.io.Source

@main def probe(path: String): Unit =
  val sb = StringBuilder()
  for line <- Source.fromFile(path).getLines() if line.trim.nonEmpty do
    val Array(body, s) = line.trim.split(" "): @unchecked
    val ms = s.toLong
    val p = Planet.fromString(body)
    val pt = getPlanetTime(p, ms, 0.0)
    val light =
      if body == "earth" || body == "moon" then "-"
      else String.format(java.util.Locale.ROOT, "%.3f", lightTravelSeconds(Planet.Earth, p, ms))
    val mtc =
      if body == "mars" then
        val m = getMtc(ms)
        s"${m.sol}\t${m.hour}\t${m.minute}\t${m.second}"
      else "-\t-\t-\t-"
    sb.append(s"$body\t$ms\t${pt.hour}\t${pt.minute}\t${pt.second}\t${pt.dayNumber}\t$light\t$mtc\n")
  print(sb)
