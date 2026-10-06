import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing is mandatory for release builds. Values may come from Gradle properties,
// environment variables, or the ignored android/key.properties file.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun signingValue(environmentName: String, propertyName: String = environmentName): String? =
    providers.gradleProperty(environmentName).orNull?.takeIf { it.isNotBlank() }
        ?: System.getenv(environmentName)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val releaseSigningValues = mapOf(
    "ANDROID_KEYSTORE_PATH" to releaseStorePath,
    "ANDROID_KEYSTORE_PASSWORD" to releaseStorePassword,
    "ANDROID_KEY_ALIAS" to releaseKeyAlias,
    "ANDROID_KEY_PASSWORD" to releaseKeyPassword,
)

android {
    namespace = "com.quickshare.quickshare"
    // Some plugins (permission_handler) are compiled against API 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.quickshare.quickshare"
        // cryptography_flutter requires API 24 (Android 7.0+).
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = rootProject.file(releaseStorePath ?: ".missing-release-keystore")
            storePassword = releaseStorePassword ?: ""
            keyAlias = releaseKeyAlias ?: ""
            keyPassword = releaseKeyPassword ?: ""
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        val missing = releaseSigningValues.filterValues { it.isNullOrBlank() }.keys
        if (missing.isNotEmpty()) {
            throw GradleException("Release signing is required. Configure: ${missing.joinToString()}")
        }
        if (!rootProject.file(releaseStorePath!!).isFile) {
            throw GradleException("The configured Android release keystore does not exist.")
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild") dependsOn(validateReleaseSigning)
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
    // FileProvider (opening received files, installing updates).
    implementation("androidx.core:core-ktx:1.15.0")
}
