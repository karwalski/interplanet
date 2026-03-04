name := "interplanet-time-scala"
version := "0.1.0"
scalaVersion := "3.6.4"

libraryDependencies += "org.scalameta" %% "munit" % "1.0.4" % Test
libraryDependencies += "com.lihaoyi" %% "ujson" % "4.0.2"

testFrameworks += new TestFramework("munit.Framework")

// Include fixture-runner sources in main compilation
Compile / unmanagedSourceDirectories += baseDirectory.value / "fixture-runner"
