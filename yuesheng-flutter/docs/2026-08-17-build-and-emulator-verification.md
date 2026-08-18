# 构建与模拟器验证指南（月笙写作教练 Flutter）

> 沉淀于 2026-08-17。记录本机/沙箱环境下从「分析 → 构建 debug APK → 模拟器跑起来验证前端」的完整路径，以及踩过的环境坑与修复命令。
> 用途：下次构建或功能验证时直接照抄命令，不必重新排查环境。

---

## 0. 环境事实（本机固定值）

| 项 | 值 |
|---|---|
| Flutter SDK | `D:\flutter`（flutter 3.44.8 / Dart 3.12.2，stable） |
| Android SDK | `D:\Android\Sdk`（=`local.properties` 的 `sdk.dir`、`ANDROID_HOME`） |
| AVD 名称 | `yuesheng_test`（Google，android-34，x86_64） |
| AVD 位置 | `C:\Users\NewName\.android\avd\yuesheng_test.avd` |
| 硬件加速 | WHPX 可用（`emulator -accel-check` 提示 installed and usable） |
| 包名 | `com.yuesheng.writingcoach` |
| 入口 Activity | `com.yuesheng.writingcoach/.MainActivity` |
| 兜底模拟器 | BlueStacks_nxt 已安装（`C:\Program Files\BlueStacks_nxt`），未启用 |
| 当前 git 领先 upstream/main | 3 提交：`ef4dba99`(B12/B21/B1/B29/B30) + `e65186f4`(B2/B3) + `1503aa11`(chore gitignore) |

---

## 1. 三个必踩的环境坑（每次命令前都要先修正）

### 坑 1 — `ANDROID_SDK_ROOT` 指向不存在的路径
- **症状**：默认 env `ANDROID_SDK_ROOT=C:\Users\月笙如歌\AppData\Local\Android\Sdk`（该路径不存在，是老 profile 残留）。
- **修复**：每次构建/模拟器命令前先 export：
  ```bash
  export ANDROID_SDK_ROOT=D:/Android/Sdk
  export ANDROID_HOME=D:/Android/Sdk
  ```
- 不修會导致 `flutter build` / `emulator` 找不到 SDK。

### 坑 2 — Gradle 缓存权限被原用户占用
- **症状**：`flutter build apk` 报 `D:\Gradle\.gradle\caches\9.1.0\transforms\...\.lock (拒绝访问。)`。该 `D:\Gradle` 缓存由原始 Windows 用户（月笙如歌）创建，沙箱用户（NewName）无写权限。
- **修复**：把 Gradle 缓存隔离到当前用户可写目录（该目录已加入 `.gitignore`，勿提交）：
  ```bash
  export GRADLE_USER_HOME=D:/ai-teacher/yuesheng-flutter/.gradle_home
  ```
- 首次会重下依赖（耗时较长，约 20+ 分钟），之后走缓存。

### 坑 3 — `adb` 不在 PATH
- **症状**：`adb: command not found`。
- **修复**：用全路径调用，或把 platform-tools 加进 PATH：
  ```bash
  ADB="D:/Android/Sdk/platform-tools/adb.exe"
  ```

---

## 2. 分析（零错误门禁）

```bash
cd D:/ai-teacher/yuesheng-flutter
export ANDROID_SDK_ROOT=D:/Android/Sdk ANDROID_HOME=D:/Android/Sdk
flutter analyze lib          # 推荐：只看 lib
# 或 flutter analyze         # 全项目（既有文件有 11 条 warning/info，非本轮引入）
```
- 门禁标准：`dart analyze lib` 零错误（exit 0）。

---

## 3. 构建 debug APK

```bash
cd D:/ai-teacher/yuesheng-flutter
export ANDROID_SDK_ROOT=D:/Android/Sdk
export ANDROID_HOME=D:/Android/Sdk
export GRADLE_USER_HOME=D:/ai-teacher/yuesheng-flutter/.gradle_home
flutter build apk --debug
```
- 产物：`build/app/outputs/flutter-apk/app-debug.apk`（约 161 MB）。
- 验证：`GRADLE_BUILD_EXIT=0`，日志含 `√ Built ... app-debug.apk`。
- **已知非阻断告警（可忽略）**：
  - 插件提示「迁移到 Built-in Kotlin」（面向插件作者，与本项目代码无关）。
  - `ziparchive: Unable to open ... base.dm`（debug 构建正常）。

---

## 4. 启动模拟器（带窗口，可见 UI）

> 关键：若要**前端展示**给人看，必须**去掉 `-no-window`**，用窗口模式启动；无头模式只用于日志验证。

```bash
cd D:/ai-teacher/yuesheng-flutter
export ANDROID_SDK_ROOT=D:/Android/Sdk ANDROID_HOME=D:/Android/Sdk
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
# 带窗口（用户可见）
"D:/Android/Sdk/emulator/emulator.exe" -avd yuesheng_test -gpu swiftshader -no-audio
# 仅无头日志验证时改为：... -avd yuesheng_test -no-window -gpu swiftshader -no-audio
```
- 等待上线（轮询，约 1–3 分钟首次开机）：
  ```bash
  for i in $(seq 1 48); do [ "$(adb get-state 2>/dev/null)" = "device" ] && break; sleep 5; done
  adb devices -l   # 应见 emulator-5554  device
  ```
- 若图形后端报 `Failed to load opengl32sw` 并回退 system OpenGL，窗口仍可显示，属正常。

---

## 5. 安装并拉起 App

```bash
ADB="D:/Android/Sdk/platform-tools/adb.exe"
$ADB -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk   # → Success
$ADB -s emulator-5554 shell am start -n com.yuesheng.writingcoach/.MainActivity
```
- 进程存活检查：`$ADB -s emulator-5554 shell ps -A | grep writingcoach`。

---

## 6. 功能验证（截屏 + 日志）

### 截屏（最直观的前端验证）
```bash
$ADB -s emulator-5554 exec-out screencap -p > screen_launch.png
```
- 首屏应为：**「我是月笙 / 你的专属写作教练 / 陪你一起发现写作问题，拆解练习，持续成长」**，含「跳过」与「下一步 →」按钮。

### 崩溃检查
```bash
$ADB -s emulator-5554 logcat -d -b crash    # 正常应为空
```

### 引擎/冷启动打点
```bash
PID=$($ADB -s emulator-5554 shell pidof com.yuesheng.writingcoach)
$ADB -s emulator-5554 logcat -d -t 200 --pid="$PID"
```
- 期望看到：
  - `flutter (null) was loaded normally!`（Flutter 引擎加载成功）
  - `[IMPORTANT:...] Using the Impeller rendering backend (OpenGLES).`
  - 应用打点：`[批次55 冷启动] main→首帧 584ms`
- **已知非阻断告警**：`Choreographer: Skipped 89 frames!`（软件渲染冷启动下的主线程卡顿，不致命）。

---

## 7. git 与推送注意

- 本地已留 3 提交，**推远程需在当前 profile 写入 PAT**（`C:\Users\NewName\.git-credentials`），否则会回退 GCM 弹 OAuth 而挂起。
- `.gradle_home/`、各 `build_apk_debug*.log`、`emulator_*.log`、`screen_*.png` 等**勿提交**（`.gradle_home` 已 gitignore；日志/截图为本地验证产物）。
- 沙箱无 GCM 凭证，推送由用户本机执行：
  ```bash
  cd D:\ai-teacher && git -c http.sslVerify=false push upstream main
  ```

---

## 8. 一键速查（带窗口启动 + 装跑 + 验证）

```bash
cd D:/ai-teacher/yuesheng-flutter
export ANDROID_SDK_ROOT=D:/Android/Sdk ANDROID_HOME=D:/Android/Sdk
export GRADLE_USER_HOME=D:/ai-teacher/yuesheng-flutter/.gradle_home
export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
ADB="D:/Android/Sdk/platform-tools/adb.exe"

# 1) 构建
flutter build apk --debug
# 2) 启动模拟器（窗口可见）
"D:/Android/Sdk/emulator/emulator.exe" -avd yuesheng_test -gpu swiftshader -no-audio &
# 3) 等上线
for i in $(seq 1 48); do [ "$(adb get-state 2>/dev/null)" = "device" ] && break; sleep 5; done
# 4) 安装并拉起
$ADB -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk
$ADB -s emulator-5554 shell am start -n com.yuesheng.writingcoach/.MainActivity
# 5) 验证
sleep 12
$ADB -s emulator-5554 exec-out screencap -p > screen_launch.png
$ADB -s emulator-5554 logcat -d -b crash
```
