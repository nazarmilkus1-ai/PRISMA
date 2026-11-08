plugins {
    id("java")
    id("com.gradleup.shadow") version "9.6.1"
}

group = "team.prisma"
version = rootProject.file("../VERSION").readText().trim()

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(25))
    }
}

repositories {
    mavenCentral()
    maven("https://repo.papermc.io/repository/maven-public/")
}

dependencies {
    // Targets Paper/Minecraft 26.3 and its required Java 25 runtime.
    compileOnly("io.papermc.paper:paper-api:26.3.build.195-stable")
    implementation("com.google.code.gson:gson:2.11.0")
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
    options.release.set(25)
}

tasks.shadowJar {
    archiveBaseName.set("PrismaPlugin")
    archiveVersion.set(project.version.toString())
    archiveClassifier.set("")
    relocate("com.google.gson", "team.prisma.plugin.libs.gson")
}

tasks.build {
    dependsOn(tasks.shadowJar)
}

tasks.named<ProcessResources>("processResources") {
    filesMatching("plugin.yml") {
        expand("version" to project.version)
    }
    from(rootProject.file("../packages/contracts/minecraft-commands.json")) {
        into("prisma")
    }

    from(rootProject.file("../modules/registry.json")) {
        into("prisma")
    }
}
