plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.smacker"
    compileSdk = 36
    ndkVersion = "27.0.12077973"


    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.smacker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

// NOTE: Removed global exclusion of `org.tensorflow` so TensorFlow Lite
// runtime classes (used by flutter_vision plugin) can be packaged.
dependencies {
    // TensorFlow Lite runtime (CPU)
    implementation("org.tensorflow:tensorflow-lite:2.11.0")

    // TensorFlow Lite GPU delegate (some plugins use GPU helper classes)
    implementation("org.tensorflow:tensorflow-lite-gpu:2.11.0")

    // NOTE: Removed LiteRT to avoid duplicate TensorFlow classes.
    // If you need LiteRT specifically, add it here and remove standard
    // tensorflow-lite artifacts, but ensure versions do not duplicate.
}

