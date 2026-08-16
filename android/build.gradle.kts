allprojects {
    repositories {
        google()
        mavenCentral()
        // flutter_background_geolocation ships its native SDK (tslocationmanager)
        // as a local maven repo inside the pub package. Gradle 8.9 doesn't pick up
        // the plugin's own project repo, so register it centrally here.
        val fbgLibs = file("${System.getProperty("user.home")}/AppData/Local/Pub/Cache/hosted/pub.dev/flutter_background_geolocation-4.18.3/android/libs")
        if (fbgLibs.exists()) maven { url = fbgLibs.toURI() }
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
