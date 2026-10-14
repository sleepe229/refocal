import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (GitHub Releases): key.properties next to this file, never committed.
// Without it the release APK is unsigned — that is what the F-Droid build server produces
// before copying our signature onto it (COMP-FDR-004, S8).
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

android {
    namespace = "io.github.refocal.app"
    compileSdk = 36
    ndkVersion = "28.2.13676358" // pinned: native code is part of the reproducible build

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.refocal.app"
        minSdk = 29 // NFR-COMPAT-001
        targetSdk = 36 // NFR-COMPAT-002
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Q-03: arm64-v8a; x86_64 for emulator/CI, stripped from release below. Requires
        // disable-abi-filtering=true (gradle.properties), else Flutter replaces this list.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }

    // ADR-0020: flavors differ only in metadata and signing; neither has GMS/Firebase.
    flavorDimensions += "store"
    productFlavors {
        create("play") { dimension = "store" }
        create("fdroid") { dimension = "store" }
    }

    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = rootProject.file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            // AGP writes the git revision into META-INF/version-control-info.textproto; a build
            // from a tarball, a shallow or a dirty clone would differ (S8).
            vcsInfo { include = false }
        }
    }

    // Reproducibility: no build-time metadata in the APK.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
    // NFR-SIZE-001: native libraries (~27 MB) are deflated in the APK and extracted on install.
    // Uncompressed libs load in place but make every download ~10 MB larger; the roadmap
    // (drift + sqlite in 0.3, C2PA in 1.3) would not fit 30 MB otherwise. The .so files stay
    // 16 KB-aligned ELF (-z max-page-size=16384, COMP-AND-007); zip alignment does not apply
    // to compressed entries.
    packaging {
        jniLibs { useLegacyPackaging = true }
    }
}

androidComponents {
    onVariants(selector().withBuildType("release")) { variant ->
        variant.packaging.jniLibs.excludes.add("lib/x86_64/**") // release APK: arm64-v8a only
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
