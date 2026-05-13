plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.mnemo.mnemo"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications desugaring.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.mnemo.mnemo"
        // Isar + ML Kit text recognition both require at least API 23.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Replace with a release signing config before publishing.
            signingConfig = signingConfigs.getByName("debug")
            // Disable R8 minification. The aggressive shrinker was stripping
            // reflection-accessed classes in flutter_local_notifications and
            // the MLKit text recognizer, causing silent failures in release
            // builds (notifications not firing, reminder cancel() throwing
            // and aborting Isar write transactions mid-way, toasts not
            // appearing because their stream subscription crashed silently).
            // For a side-loaded APK the size penalty (~20 MB) is an
            // acceptable trade vs. debugging R8 keep rules for every plugin.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.3")
}

flutter {
    source = "../.."
}
