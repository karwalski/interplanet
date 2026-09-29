// Interop driver build for kotlin/ltx: compiles the port's sources together
// with src/Driver.kt (see scripts/interop/run.js).
plugins {
    kotlin("jvm") version "1.9.22"
    application
}

repositories { mavenCentral() }

kotlin { jvmToolchain(17) }

sourceSets["main"].kotlin.srcDirs("../../../../kotlin/ltx/src/main/kotlin", "src")

application { mainClass.set("DriverKt") }
