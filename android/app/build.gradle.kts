plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.flutter_application_1"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.flutter_application_1"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

flutter {
    source = "../.."
}

// [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:35 UTC-5 (Lima)][desc: Evita clases duplicadas Mapbox (android vs android-ndk27) al usar Navigation SDK + mapbox_maps_flutter, forzando variantes -ndk27 en una sola versión][obj: android/app/build.gradle.kts Mapbox duplicate classes]
configurations.all {
    resolutionStrategy {
        // Navigation SDK 3.19.0 usa Maps/Common 11.19.0/24.19.0; mapbox_maps_flutter usa variantes -ndk27.
        // Forzamos todo a -ndk27 en la misma versión para evitar "checkDebugDuplicateClasses".
        force("com.mapbox.maps:android-ndk27:11.19.0")
        force("com.mapbox.common:common-ndk27:24.19.0")
        force("com.mapbox.module:maps-telemetry-ndk27:11.19.0")
    }
}

dependencies {
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-18 00:00 UTC-5 (Lima)][desc: Agrega FusedLocationProvider para tracking nativo en background][obj: android/app/build.gradle.kts:play-services-location]
    implementation("com.google.android.gms:play-services-location:21.3.0")

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:25 UTC-5 (Lima)][desc: Agrega dependencias AndroidX necesarias para ActivityResult/ComponentActivity en NavigationActivity][obj: android/app/build.gradle.kts AndroidX deps]
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-19 16:10 UTC-5 (Lima)][desc: Agrega Mapbox Navigation SDK v3 (Android) (online, reroute sí, sin voz) + UI maps (route line/camera)][obj: android/app/build.gradle.kts Mapbox Navigationcore dependencies]
    // Fuente: https://docs.mapbox.com/android/navigation/guides/install/
    // Nota: el SDK usa artefactos con NDK; si el build requiere NDK 27, usar el sufijo -ndk27.
    // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2025-12-22 11:35 UTC-5 (Lima)][desc: Excluye artefactos no-ndk para evitar duplicados con variantes -ndk27 del plugin mapbox_maps_flutter][obj: android/app/build.gradle.kts Mapbox excludes]
    implementation("com.mapbox.navigationcore:android:3.19.0") {
        exclude(group = "com.mapbox.maps", module = "android")
        exclude(group = "com.mapbox.common", module = "common")
        exclude(group = "com.mapbox.module", module = "maps-telemetry")
    }
    implementation("com.mapbox.navigationcore:ui-maps:3.19.0") {
        exclude(group = "com.mapbox.maps", module = "android")
        exclude(group = "com.mapbox.common", module = "common")
        exclude(group = "com.mapbox.module", module = "maps-telemetry")
    }

    // Dependencias explícitas -ndk27 (version alineada con Navigation SDK 3.19.0).
    implementation("com.mapbox.maps:android-ndk27:11.19.0")
    implementation("com.mapbox.common:common-ndk27:24.19.0")
    implementation("com.mapbox.module:maps-telemetry-ndk27:11.19.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
}
