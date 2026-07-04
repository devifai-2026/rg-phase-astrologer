plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.rudraganga.rg_astrologer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications needs core library desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // App-factory: EVERY tenant injects its own applicationId + label at build
        // time via Gradle properties (set by the build worker). The compiled
        // default is brand-NEUTRAL — no tenant's brand may leak into another's build.
        applicationId = (project.findProperty("tenant.applicationId") as String?) ?: "app.saasastro.astrologer"
        resValue("string", "app_name", (project.findProperty("tenant.appLabel") as String?) ?: "Astro Partner")
        // Android 6+ (API 23) — comfortably covers the Android 9+ target. Pinned
        // explicitly so a plugin can't silently raise it above the support range.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Per-tenant release signing (see user app for details). Absent → debug signing.
    val tenantKeystore = project.findProperty("tenant.keystore") as String?
    val tenantKeystoreProps = project.findProperty("tenant.keystoreProps") as String?
    if (tenantKeystore != null && tenantKeystoreProps != null && file(tenantKeystoreProps).exists()) {
        val props = java.util.Properties().apply { load(java.io.FileInputStream(tenantKeystoreProps)) }
        signingConfigs.create("tenant") {
            storeFile = file(tenantKeystore)
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = if (signingConfigs.findByName("tenant") != null)
                signingConfigs.getByName("tenant")
            else
                signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
