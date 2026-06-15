pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

/*dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
        // [CHANGE][autor: cormenos@onp.gob.pe][fecha: 2026-03-10 13:24 UTC-5 (Lima)][desc: Mueve repositorio autenticado de Mapbox a settings.gradle.kts siguiendo guía oficial de Navigation SDK][obj: android/settings.gradle.kts Mapbox Maven]
        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<org.gradle.authentication.http.BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password =
                    providers.gradleProperty("MAPBOX_DOWNLOADS_TOKEN").orNull
                        ?: System.getenv("MAPBOX_DOWNLOADS_TOKEN")
                        ?: ""
            }
        }
    }
}*/

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)

    val storageUrl: String =
        System.getenv("FLUTTER_STORAGE_BASE_URL") ?: "https://storage.googleapis.com"

    repositories {
        google()
        mavenCentral()
        maven(url = "$storageUrl/download.flutter.io")

        maven {
            url = uri("https://api.mapbox.com/downloads/v2/releases/maven")
            authentication {
                create<org.gradle.authentication.http.BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = providers.gradleProperty("MAPBOX_DOWNLOADS_TOKEN")
                    .orElse(providers.environmentVariable("MAPBOX_DOWNLOADS_TOKEN"))
                    .get()
            }
        }

        /*maven {
            url = uri("https://api.mapbox.com/downloads/v2/snapshots/maven")
            authentication {
                create<org.gradle.authentication.http.BasicAuthentication>("basic")
            }
            credentials {
                username = "mapbox"
                password = providers.gradleProperty("MAPBOX_DOWNLOADS_TOKEN")
                    .orElse(providers.environmentVariable("MAPBOX_DOWNLOADS_TOKEN"))
                    .get()
            }
        }*/
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.9.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.10") apply false
    // END: FlutterFire Configuration
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
