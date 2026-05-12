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

    // Patch for legacy plugins (e.g. isar_flutter_libs 3.x) that pre-date AGP 8's
    // mandatory `namespace` property. We inject a namespace before evaluation
    // so Gradle can configure the Android library extension.
    plugins.withId("com.android.library") {
        extensions.configure(com.android.build.gradle.LibraryExtension::class.java) {
            if (namespace.isNullOrBlank()) {
                namespace = when (project.name) {
                    "isar_flutter_libs" -> "dev.isar.isar_flutter_libs"
                    else -> "com.${project.name.replace("-", "_")}"
                }
            }
            // Normalize Java compile options to 17 so that plugins that
            // default to 1.8 (e.g. receive_sharing_intent) stay aligned
            // with the app module's Kotlin JVM target.
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }

    // Align every Kotlin compilation in every subproject to JVM 17. Without
    // this, some plugins compile Kotlin against JVM 21 while their Java is
    // still 1.8, which fails AGP's "Inconsistent JVM Target" check.
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
