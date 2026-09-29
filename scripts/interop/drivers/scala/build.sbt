// Interop driver build for scala/ltx: compiles the port's sources together
// with src/Driver.scala (see scripts/interop/run.js).
scalaVersion := "3.6.4"
Compile / unmanagedSourceDirectories := Seq(
  baseDirectory.value / "src",
  baseDirectory.value / ".." / ".." / ".." / ".." / "scala" / "ltx" / "src" / "main" / "scala",
)
target := baseDirectory.value / "build" / "target"
