plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing key, passed in by scripts/build-release.sh. Without it the release APK is unsigned.
val releaseKeystore: String? = System.getenv("CROSSLINK_KEYSTORE")

android {
    namespace = "kg.crosslink.app"
    compileSdk = 36
    defaultConfig {
        applicationId = "kg.crosslink.app"
        minSdk = 29
        targetSdk = 36
        versionCode = 3
        versionName = "0.2.0"
    }
    signingConfigs {
        if (releaseKeystore != null) create("release") {
            storeFile = file(releaseKeystore)
            storePassword = System.getenv("CROSSLINK_KEYSTORE_PASSWORD")
            keyAlias = System.getenv("CROSSLINK_KEY_ALIAS") ?: "crosslink"
            keyPassword = System.getenv("CROSSLINK_KEYSTORE_PASSWORD")
        }
    }
    buildTypes {
        release {
            if (releaseKeystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
    // Licences of the bundled Inter font (OFL) and lucide icons (ISC) ship inside the APK
    sourceSets["main"].assets.srcDir("../../licenses")
}

kotlin {
    compilerOptions { jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17) }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2026.03.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.13.0")
    implementation("com.google.android.gms:play-services-code-scanner:16.1.0")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
