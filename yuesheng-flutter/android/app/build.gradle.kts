import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── release 签名（批次2 2.2 fail-fast）────────────────────────────
// key.properties 缺失即构建失败，禁止静默回退 debug 签名（防止误发布 debug 签名包）。
// 本地无秘钥调试 release 需显式放行：flutter build apk --release -PreleaseSigningDisabled=true
// 批次70 修复：fail-fast 仅作用于 release 构建（原实现写在脚本顶层，误拦 debug 构建——
// 过去 flutter build apk --debug 链路被批次11 引入的检查打断，属回归）
val keystorePropertiesFile = rootProject.file("key.properties")
val releaseSigningDisabled =
    (project.findProperty("releaseSigningDisabled") as String? ?: "false")
        .toBoolean()
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseKeys = listOf("storeFile", "keyAlias", "keyPassword", "storePassword")
val hasReleaseKeystore =
    keystorePropertiesFile.exists() &&
        releaseKeys.all { !keystoreProperties.getProperty(it).isNullOrBlank() }

// 仅 release 变体（assembleRelease / bundleRelease 等）执行 fail-fast；
// debug 构建不受签名配置约束（过去 flutter build apk --debug 链路）
val isReleaseBuild =
    gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (isReleaseBuild && !releaseSigningDisabled && !hasReleaseKeystore) {
    throw GradleException(
        "release 签名配置缺失：未找到完整 key.properties（需 storeFile/keyAlias/keyPassword/storePassword）。" +
            "请创建 android/key.properties 后重试；" +
            "本地调试 release 可加 -PreleaseSigningDisabled=true 临时放行（将使用 debug 签名）。",
    )
}

android {
    namespace = "com.yuesheng.writingcoach"
    // flutter_plugin_android_lifecycle 2.0.35 要求 compileSdk >= 36
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            // 从 key.properties 读取，禁止明文写死（project memory 硬约束）
            keyAlias = keystoreProperties.getProperty("keyAlias") ?: "androiddebugkey"
            keyPassword = keystoreProperties.getProperty("keyPassword") ?: "android"
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                ?: file("${System.getenv("HOME") ?: System.getenv("USERPROFILE")}/.android/debug.keystore")
            storePassword = keystoreProperties.getProperty("storePassword") ?: "android"
        }
    }

    defaultConfig {
        applicationId = "com.yuesheng.writingcoach"
        // flutter_plugin_android_lifecycle 2.0.35 写死 minSdk=24
        // （Manifest merger 失败，必须 >=24；Flutter 官方也 warning 23 快弃用）
        minSdk = 24
        // 对齐 compileSdk，与插件要求保持一致
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // R8/ProGuard 混淆 + 资源压缩（project memory 硬约束：减小 APK 体积 + 防反编译）
            isMinifyEnabled = true
            isShrinkResources = true
            // 批次2（2.2）：默认 release 签名（fail-fast 保证 key.properties 完整）；
            // 仅显式 -PreleaseSigningDisabled=true 时回退 debug 签名（本地调试放行）
            signingConfig = if (releaseSigningDisabled) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
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
