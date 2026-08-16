// ── 国内网络：仓库源优先级（项目级，不动全局 ~/.gradle）────────
// 经验教训（#1055208）：官方源 google()/mavenCentral() 在 Windows 下常因
// DNS/链路抖动触发 connect/read timed out，把国内镜像放在列表最前，
// 命中失败才回退到官方源，不修改全局 init.gradle。
// 腾讯 maven-public 已聚合 maven-central + google + jcenter 等公共仓库。
private val tencentMavenPublic: java.net.URI =
    java.net.URI.create("https://mirrors.cloud.tencent.com/nexus/repository/maven-public/")

allprojects {
    buildscript {
        repositories {
            maven { url = tencentMavenPublic }
            google()
            mavenCentral()
        }
    }
    repositories {
        maven { url = tencentMavenPublic }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

// 注意：evaluationDependsOn 会抢先 evaluate 所有子项目，任何 compileSdk
// 覆盖方案在 AGP 9 下都会触发 "It is too late to set compileSdk"。
// compileSdk 统一走官方机制：gradle.properties 的 flutter.compileSdkVersion，
// 各插件模块继承该值，app 模块在 build.gradle.kts 显式 compileSdk = 36。
// （file_picker 曾写死 34 导致 AAR metadata 检查失败，已升级到 10.3.11 修复）
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
