plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Credentials are supplied only by the local build environment, never source control.
val releaseSecrets = listOf("MONEYTRACK_RELEASE_STORE_FILE", "MONEYTRACK_RELEASE_STORE_PASSWORD",
    "MONEYTRACK_RELEASE_KEY_ALIAS", "MONEYTRACK_RELEASE_KEY_PASSWORD").associateWith { System.getenv(it) }
val hasReleaseSigning = releaseSecrets.values.all { !it.isNullOrBlank() }
require(hasReleaseSigning || releaseSecrets.values.all { it.isNullOrBlank() }) {
    "Release signing requires all four MONEYTRACK_RELEASE_* environment variables"
}

android {
    namespace = "com.moneytrack.moneytrack"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.moneytrack.moneytrack"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("privateRelease") {
                storeFile = file(releaseSecrets.getValue("MONEYTRACK_RELEASE_STORE_FILE")!!)
                storePassword = releaseSecrets.getValue("MONEYTRACK_RELEASE_STORE_PASSWORD")
                keyAlias = releaseSecrets.getValue("MONEYTRACK_RELEASE_KEY_ALIAS")
                keyPassword = releaseSecrets.getValue("MONEYTRACK_RELEASE_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without credentials this is an unsigned verification artifact.
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("privateRelease")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

flutter {
    source = "../.."
}

// Platform-backed, enrollment-bound biometric authentication.
dependencies {
    implementation("androidx.biometric:biometric:1.1.0")
    implementation("androidx.core:core-ktx:1.13.1")
}
