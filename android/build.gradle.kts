allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Some plugins (e.g. agora_rtc_engine) read their compileSdk from
// `rootProject.ext.compileSdkVersion`, defaulting to an old 31 that fails
// against their modern AndroidX deps (need 34+). Seed it on the ROOT project.
// Mirrors the user app.
rootProject.extensions.extraProperties.set("compileSdkVersion", 36)

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
