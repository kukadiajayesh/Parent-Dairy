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
// `receive_sharing_intent` hardcodes `compileSdk 37`, but this SDK release only
// ships the minor-versioned platform `android-37.0`, so the plain `android-37`
// hash never resolves and the module fails to configure. Pinning every plugin
// module to the compileSdk Flutter itself targets keeps the build consistent
// and costs nothing — no plugin here uses an API newer than 36.
//
// Registered before the `evaluationDependsOn` block below, which would
// otherwise have already evaluated these projects.
subprojects {
    afterEvaluate {
        val android = extensions.findByName("android") ?: return@afterEvaluate
        // Located by name rather than by a typed cast: the DSL interface that
        // owns compileSdk has moved between AGP major versions, and this build
        // should survive the next move.
        val setter = android.javaClass.methods.firstOrNull { method ->
            method.parameterCount == 1 &&
                (method.name == "setCompileSdk" || method.name == "setCompileSdkVersion") &&
                (method.parameterTypes[0] == Int::class.javaPrimitiveType ||
                    method.parameterTypes[0] == Integer::class.java)
        }
        runCatching { setter?.invoke(android, 36) }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
