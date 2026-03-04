plugins {
    kotlin("jvm") version "1.9.22"
    application
}

group = "com.interplanet"
version = "1.0.0"

repositories {
    mavenCentral()
}

application {
    mainClass.set("com.interplanet.ltx.InterplanetLTXTestKt")
}

kotlin {
    jvmToolchain(11)
}
