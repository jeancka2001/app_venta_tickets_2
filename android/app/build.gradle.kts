import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/* Firma de release: android/key.properties (NO se sube a git) apunta al
   mismo keystore con el que se firma hoy la app Ionic en Google Play. Sin ese
   archivo se firma con la clave de depuración (solo para probar). */
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // Mismo identificador que la app Ionic: así Google Play la trata como una
    // actualización de "T-ickets Ventas" y no como una app nueva.
    namespace = "ec.ticketsEC.ventas"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "ec.ticketsEC.ventas"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Sale de "version:" en pubspec.yaml (1.2.0+10 -> versionName 1.2.0, versionCode 10).
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Símbolos de depuración del código nativo dentro del .aab (quita
            // la advertencia de Play Console sobre símbolos nativos). Con la
            // tabla de símbolos basta para leer los fallos; "FULL" pesaría
            // ~150 MB por arquitectura solo por libflutter.so.
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
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
