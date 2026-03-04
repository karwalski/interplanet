plugins {
    kotlin("jvm") version "1.9.22"
    application
}

group = "interplanet"
version = "1.0.0"

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(kotlin("test"))
    // JSON parsing for fixture runner
    implementation("org.json:json:20231013")
}

application {
    mainClass.set("interplanet.time.FixtureRunnerKt")
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}

// Include fixture-runner sources in compilation
sourceSets {
    main {
        kotlin {
            srcDirs("src/main/kotlin", "fixture-runner")
        }
    }
}
