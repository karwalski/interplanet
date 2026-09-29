name := "interplanet-ltx-scala"
version := "1.1.0"
scalaVersion := "3.6.4"

// No library dependencies: the SDK and its tests use only the Scala and Java
// standard libraries. The tests are plain `main` objects that exit 1 on
// failure, so they run in a forked JVM to report a real exit status:
//   sbt "Test/runMain InterplanetLtxTest" "Test/runMain SecurityTest" "Test/runMain V11Test" "Test/runMain ParityTest" "Test/runMain PrefixTest"
Test / fork := true
run / fork := true
