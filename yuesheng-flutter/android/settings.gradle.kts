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

    // 国内网络：插件解析优先走腾讯镜像聚合仓（含 google/central/gradlePluginPortal），
    // 失败再回退到官方源；避免 AGP/Kotlin 插件下载超时。
    val tencentMavenPublic: java.net.URI =
        java.net.URI.create("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/")
    repositories {
        maven { url = tencentMavenPublic }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
