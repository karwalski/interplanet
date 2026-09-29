plugins {
    kotlin("jvm") version "1.9.22"
}

group = "com.interplanet"
version = "1.1.0"

repositories {
    mavenCentral()
}

kotlin {
    // Ed25519 (java.security) needs JDK 15+; CI uses Temurin 17.
    jvmToolchain(17)
}

// The tests are a plain main() (src/test/kotlin/.../InterplanetLTXTest.kt) that
// prints "N passed  M failed" and exits 1 on failure. Run with:
//   gradle ltxTest      (or: gradle check)
val ltxTest by tasks.registering(JavaExec::class) {
    group = "verification"
    description = "Runs the LTX test main (InterplanetLTXTest + V11Test)."
    classpath = sourceSets["test"].runtimeClasspath
    mainClass.set("com.interplanet.ltx.InterplanetLTXTestKt")
    workingDir = projectDir
}

tasks.named("check") { dependsOn(ltxTest) }
