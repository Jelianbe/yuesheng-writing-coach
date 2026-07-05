# 月笙写作教练 — 项目概况 & AVD 诊断上下文

> 发给其他 AI 时贴这个就够了。

---

## 一、项目简介

**月笙写作教练**（yuesheng-writing-coach）是一个 AI 驱动的写作辅导桌面工具，使用 Electron 构建，正在向 Android 端（通过 Capacitor）进行双平台迁移。

- Electron 端：**生产可用**，全功能运转
- Android 端：**核心模块已打通**，但从未真正在 Android 模拟器/真机上运行过

---

## 二、技术栈

| 层 | 技术 | 备注 |
|:---|:-----|:-----|
| 桌面壳 | Electron 28+ | 运行中 |
| 移动壳 | Capacitor (cross-platform) | 目标平台 |
| 渲染层 | React 18 + Vite | 双端共用 |
| 语言 | TypeScript 5.x | strict 模式 |
| 数据库 | better-sqlite3 (Electron) / CapacitorSqlitePlugin (Android) | 通过 StorageAdapter 抽象 |
| IPC | Electron IPC (Electron) / capacitor-diagnosis/training/teaching-state (Android) | 双轨模式 |
| LLM | LlmClient（shared/llm/ 自研） | 双端共用 |
| 构建 | vite build（renderer） + tsc（main） | Electron 端 |
| Android | Capacitor CLI + Android Studio + Gradle | 仅配置，未运行 |
| 测试 | Vitest + jsdom | 1080 测试全绿 |

---

## 三、项目目录结构（关键部分）

```
yuesheng-writing-coach/
├── src/
│   ├── main/                    # Electron 主进程（Android 端不存在）
│   │   ├── ipc/                 # IPC handlers（双轨路由入口）
│   │   ├── domains/
│   │   │   └── 03-teaching/     # TeachingStateMachine（5 文件状态机）
│   │   │       └── state/
│   │   │           ├── teaching-state-machine.ts
│   │   │           ├── teaching-state-machine.navigation.ts
│   │   │           ├── teaching-state-machine.locking.ts
│   │   │           ├── teaching-state-machine.reflection.ts
│   │   │           └── teaching-state-machine.guide.ts
│   │   └── db/                  # SQLite schema（29 个迁移文件）
│   ├── renderer/                # 渲染进程（双端共用）
│   │   └── services/
│   │       ├── _dual-track.ts   # isCapacitor() + runDualTrack()
│   │       ├── ipc-client.ts    # typedInvoke/typedOn（Electron IPC 封装）
│   │       ├── capacitor-config.ts    # Android 端配置管理
│   │       ├── capacitor-chat.ts      # Android 端 Chat（Sprint 31）
│   │       ├── capacitor-diagnosis.ts # Android 端 Diagnosis（Sprint 32）
│   │       ├── capacitor-training.ts  # Android 端 Training（Sprint 33）
│   │       ├── capacitor-teaching-state.ts # Android 端 TeachingState（Sprint 34）
│   │       ├── chat.service.ts        # Chat 路由
│   │       ├── diagnosis.service.ts   # Diagnosis 路由（4/4 已实现 Capacitor 分支）
│   │       ├── training.service.ts    # Training 路由（3/8 已实现 Capacitor 分支）
│   │       └── teaching-state.service.ts # TeachingState 路由（get/update 双轨 + 5/5 IPC-only 已实现）
│   └── shared/                  # 双端共用层
│       ├── storage/             # StorageAdapter 抽象
│       │   ├── storage-adapter.ts       # 接口定义
│       │   ├── capacitor-sqlite-adapter.ts  # Android 端实现
│       │   └── better-sqlite-adapter.ts     # Electron 端实现
│       ├── services/            # 跨端 service（纯 CRUD）
│       │   └── teaching-state.service.ts
│       ├── llm/llm-client.ts    # LLM 调用客户端（双端共用）
│       └── api-contracts/       # IPC channel 定义 + 类型
├── capacitor.config.ts          # Capacitor 配置
├── package.json                 # 版本 1.4.0
├── docs/
│   └── decision-log.md          # 关键决策日志（含 D-076 AVD 问题记录）
└── dev-docs/
    ├── plans/                   # Sprint 计划文档
    └── tasks/                   # Sprint 任务文档
```

---

## 四、当前进度（Sprint 34 完工）

### 已完成
| Sprint | 内容 | 状态 |
|:-------|:-----|:----:|
| S26 | StorageAdapter + IPC 双轨化 | Done |
| S27 | Lint 治理 | Done |
| S28 | `no-non-null-assertion` 治理 | Done |
| S29 | Capacitor 测试补强 | Done |
| S31 | Android 端 Chat 激活（LlmClient 直调） | Done |
| S32 | Android 端 Diagnosis 激活 | Done |
| S33 | Android 端 Training 激活 | Done |
| S34 | Android 端 TeachingState 激活 | Done |

### Android 端核心模块可用性
| 功能 | Electron | Android | 实现方式 |
|:-----|:---------|:--------|:---------|
| Chat (会话+LLM) | ✅ IPC handler | ✅ LlmClient 直调 | capacitor-chat.ts |
| Diagnosis 查询 | ✅ IPC handler | ✅ localStorage 缓存 | capacitor-diagnosis.ts |
| Diagnosis 改写评估 | ✅ IPC handler | ✅ LlmClient 直调 | capacitor-diagnosis.ts |
| Training 评估 | ✅ IPC handler | ✅ LlmClient 直调 | capacitor-training.ts |
| TeachingState CRUD | ✅ IPC handler | ✅ StorageAdapter 直连 | teaching-state.service.ts (双轨) |
| TeachingState 确认/事件 | ✅ IPC handler | ✅ localStorage + 事件总线 | capacitor-teaching-state.ts |
| Diagnosis 对比 | ✅ IPC handler | ❌ noop（需 diagnosis_records 表） | capacitor-diagnosis.ts |
| SQLite 持久化 | ✅ better-sqlite3 | ⚠️ 代码就绪但未运行验证 | CapacitorSqliteAdapter |
| 门禁 | typecheck/test/lint | ✅ 全部通过 | 1080 tests, 0 warnings |

---

## 五、AVD 问题（核心诊断请求）

### 环境
- **OS**: Windows 11 (64-bit), x86_64
- **GPU**: NVIDIA GeForce RTX 4060 Laptop GPU, driver 610.62
- **Hypervisor**: WHPX (Windows Hypervisor Platform) — 已启用
- **Android Studio**: 最新稳定版
- **AVD 配置**: Pixel 6, Android 14 (API 34), x86_64 google_apis
- **emulator**: 36.6.11
- **gfxstream**: 36.x

### 症状
启动 AVD 时，emulator 进程在 40 秒内崩溃（exit code 0xC0000005 — STATUS_ACCESS_VIOLATION）。

### 已试过的诊断步骤

#### 1. 渲染方案试错（全部失败）
| 方案 | 结果 |
|:-----|:-----|
| swiftshader_indirect（软件渲染） | 启动后黑屏，无崩溃 |
| lavapipe（Vulkan 软件回退） | 相同崩溃 |
| TCG 软件加速 | 无法完成启动 |
| gfxstream + Vulkan（硬件加速） | 40 秒内明确崩溃 0xC0000005 |

#### 2. TRAE 沙箱误诊
- 最初怀疑 TRAE 沙箱阻止了 emulator 访问驱动文件
- 用 `dangerouslyDisableSandbox: true` 脱沙箱运行 → **仍然崩溃在相同位置**
- 崩溃时序：`WHPX accelerator is operational` 之后 → VkEmulation features 初始化阶段
- **结论：崩溃与 TRAE 沙箱完全无关**

#### 3. 真实判断
**emulator 36.6.11 + gfxstream 36.x + WHPX + RTX 4060 + driver 610.62 存在兼容 bug。**
gfxstream 36.x 在 VkEmulation 初始化时与 WHPX + Vulkan 上下文交互触发段错误。

### 想知道
1. WSL2 与 WHPX 的冲突可能性（确认已设置 `hypervisorlaunchtype=OFF`）
2. 是否应将 WHPX 换为 Intel HAXM（但 CPU 不支持）
3. 推荐可用的 emulator 版本 + gfxstream 版本组合
4. Windows 上 AVD 硬件加速的替代方案（Hyper-V / GVM 等）
5. 或：是否值得改用真机调试，绕过 emulator 问题

### 关键日志特征
```
...
WHPX accelerator is operational
...（之后 VkEmulation 初始化阶段）
emulator: ERROR: ...
Process crashed with exit code 0xC0000005 (STATUS_ACCESS_VIOLATION)
```

---

## 六、沟通辅助信息

- **测试**: `npx vitest run` → 1080 passed, 0 failed
- **Typecheck**: `npx tsc --noEmit` → 0 error
- **Lint**: `npx eslint src/ --ext .ts,.tsx --max-warnings 300` → 0 warnings
- **Android 构建**: `npx cap copy` + `npx cap open android` 可以打开 Android Studio，但从未执行
- **决策日志**中 D-076 记录了完整的 AVD 崩溃现场和分析过程
