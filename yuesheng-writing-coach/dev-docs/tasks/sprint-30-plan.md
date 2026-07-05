# Sprint 30 — Android 端端到端验证 + 签名 APK 产出

> **范围**: 把已构建成功的 Android APK 在真机/模拟器上跑起来，完成端到端验证
> **依据**: D-076（AVD 延期推 S30+）+ D-080（Sprint 29 完工）
> **前置**: Sprint 26-29 全部完成（双轨架构 + StorageAdapter + ServiceBridge + 测试补强）
> **状态**: 已审批

---

## 0. 目标与边界

### 0.1 目标
- Android APK 在设备上成功启动
- 核心页面（Sessions 列表）正常加载
- 双轨架构在 Android 端实际验证
- 产出签名 release APK

### 0.2 不在范围
- ❌ AI 集成层真实化（S30+ 候选）
- ❌ 22 张非核心表迁移（用户接受"重新开始"）
- ❌ Play 商店发布（推 S31+）
- ❌ iOS 端

---

## 1. 当前状态

### 1.1 已有成果
| 项 | 状态 |
|:---|:----:|
| APK 构建 | ✅ `assembleDebug` 成功，产出 25MB APK |
| JDK | ✅ 21.0.10 |
| Capacitor 配置 | ✅ `capacitor.config.ts` + `android/` 目录 |
| 双轨架构代码 | ✅ 单元测试 1079 全绿 |

### 1.2 剩余障碍
| 障碍 | 详情 | 来源 |
|:-----|:-----|:-----|
| AVD 崩溃 | emulator 36.6.11 + gfxstream 36.x + RTX 4060 兼容 bug | D-076 |
| 真机未连接 | 未曾尝试 USB 真机调试 | — |
| 签名 APK 未配置 | 需要 keystore + release build 配置 | Sprint 26 Phase 6 |

---

## 2. 阶段拆解

### 阶段 1: 尝试真机 USB 安装

**路径 A: 直接用 debug APK**
1. 用户 Android 手机开启"开发者模式" + "USB 调试"
2. USB 连接电脑
3. `adb install android/app/build/outputs/apk/debug/app-debug.apk`
4. 启动验证

**路径 B: 无线 ADB**
1. 手机和电脑同一 Wi-Fi
2. `adb connect <phone-ip>:5555`
3. `adb install ...`

**DoD**:
- APK 安装成功
- 应用启动不崩溃
- 核心页面加载

### 阶段 2: AVD 修复（备选方案）

如果真机不可行，尝试以下方案：

1. **降级 emulator**: `sdkmanager "emulator;32.1.15"`（降级避开 36.x gfxstream bug）
2. **升级 NVIDIA 驱动**: 610.62 → 最新 560+ 系列
3. **尝试 WARP 软件渲染**: `-gpu swiftshader_indirect` 绕过 GPU 加速

**DoD**:
- AVD 启动成功
- 应用在模拟器中加载

### 阶段 3: 签名 Release APK

1. 生成 keystore（走 `.gitignore`，R-029）
2. 配置 `android/app/build.gradle` signingConfigs
3. `cd android && gradlew assembleRelease`
4. APK 验证：`jarsigner -verify app-release.apk`

**DoD**:
- release APK 构建成功
- 签名验证通过
- APK 可安装（真机或模拟器）

### 阶段 4: CapacitorSqliteAdapter 测试 + 收尾

1. CapacitorSqliteAdapter 基础测试（mock Capacitor 运行时）
2. 写入决策日志 D-081
3. 门禁：typecheck + test + lint

**DoD**:
- CapacitorSqliteAdapter 基本覆盖
- 门禁全绿
- D-081 已写入

---

## 3. 总 DoD

1. ✅ APK 在 Android 设备（真机/模拟器）成功启动
2. ✅ 核心页面加载正常
3. ✅ release 签名 APK 产出
4. ✅ typecheck 0 error
5. ✅ test 全部通过
6. ✅ lint 0 warning
7. ✅ 决策日志 D-081

---

## 4. 决策点

| # | 决策 | 推荐 | 说明 |
|:--|:-----|:----:|:-----|
| D1 | 真机 vs AVD 验证 | 真机优先 | 真机更可靠，AVD 有已知兼容 bug |
| D2 | 签名 APK 的 keystore 密码 | 走环境变量 | R-029 要求，不写入代码 |
