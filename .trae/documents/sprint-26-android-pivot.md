# Sprint 26 — 月笙写作教练:Electron + Capacitor 双端复用(MVP 在 Android)

> **核心目标**: 用 Capacitor 把现有 React/TS 渲染层打包成 Android APK,核心业务服务 70% 复用,通过 `StorageAdapter` 抽象层让 Windows(Electron + better-sqlite3)和 Android(Capacitor SQLite)共用同一份业务代码。
> **依据**: 用户 S26 战略调整(2026-07-03)+ 决策日志 D-073 C-4 收尾 + 事实校正(UI 已是手机端风格,不是桌面风格)
> **开始日期**: (待用户批准)
> **R-004**: 每阶段 DoD ≥ 3 条可验证标准
> **范围**: 仅 Android MVP(MVP 完成后,Windows 版保留 Electron 不动;未来 WIN11/10 版本可选择走 Capacitor Windows 或保留 Electron)

---

## 0. 战略背景与边界

### 0.1 触发原因(校正后)

**事实校正**:
- 项目 UI 早已是**移动端风格**(`PageStackRouter.module.css:max-width:375px`、`--phone-container-max`、`tabbar/navbar/status-bar` 模拟)
- 只是用 Electron `BrowserWindow` 当"手机壳"在桌面端运行
- 用户期望:**真正在手机上能用**,不是再做一遍 Android

**关键决策(用户已确认)**:
- MVP 集中 Android
- 后续可能加 WIN11/10(当前 Electron 已支持 Windows,可保留)
- 后端共用是"期待",不强求
- AI 决定技术细节

### 0.2 推荐方案: Capacitor + StorageAdapter 抽象

**为什么不用 Kotlin 原生**:
- React UI 已手机端化,100% 复用,Kotlin 重写是浪费
- 37 个 better-sqlite3 文件翻译为 Room 是大工程
- Capacitor 1.5-2 周 vs Kotlin 2-3 周,且产出更高(共用代码)

**为什么不用纯 PWA**:
- PWA 部署简单但**不是真 APK**,用户要"装在手机上"
- Capacitor 输出 `.apk` 文件,符合用户对"安卓应用"的预期
- 未来可上 Play 商店

**为什么不用 React Native**:
- 仍然要重写 UI 组件(`<div>` → `<View>`、CSS → StyleSheet)
- React 代码可复用率 < 30%(hooks 可复用,JSX 不能)
- 2-3 周工作量与 Kotlin 持平

### 0.3 目标形态

| 维度 | Android(本轮) | Windows(本轮) | Windows(未来选项) |
|:-----|:--------------|:-------------|:----------------|
| **运行时** | Capacitor + WebView | Electron + Node | 同 Android / 保留 Electron |
| **渲染层** | 同一份 React/TS | 同 Android | 同 Android |
| **业务服务** | 同一份 TS(去掉 IPC) | 同 Android | 同 Android |
| **存储** | @capacitor-community/sqlite | better-sqlite3 | 任一 |
| **打包** | .apk | .exe(Electron) | .exe(Capacitor Win) |

### 0.4 不在范围

- ❌ iOS(暂不考虑,Capacitor 已支持,推 S27+ 评估)
- ❌ 22 张非核心 SQLite 表(用户接受"重新开始",S26 只迁核心 5 张)
- ❌ 业务逻辑优化重构(只做存储层抽象,不顺手重写 services)
- ❌ AI 集成层迁移(MVP 只跑通数据 + UI,AI 走 IPC mock 阶段)
- ❌ Play 商店发布(产出签名 APK,不上架,等用户决定)

---

## 1. 架构扫描 — 复用度评估

### 1.1 现有模块复用度矩阵

| 模块 | 行数 | Android 复用度 | 改动内容 |
|:-----|:----:|:--------------:|:--------|
| `src/renderer/`(React UI) | ~6000 | 🟢 **100%** | 0 行,WebView 直接跑 |
| `src/renderer/stores/`(Zustand) | ~800 | 🟢 **100%** | 0 行,纯浏览器状态 |
| `src/main/domains/03-teaching/state/ActiveTrainingService` | ~470 | 🟢 **90%** | 把 `this.store.update()` 改为 `this.adapter.update()` |
| `src/main/domains/03-teaching/state/ActiveTrainingStore` | ~340 | 🟡 **50%** | 重写为薄包装,委托给 `StorageAdapter` |
| `src/main/domains/03-teaching/state/TeachingState` 等 stores | ~600 | 🟡 **50%** | 同上,改用 Adapter |
| 27 个 SQL migration | ~1500 | 🔴 **不适用** | 翻译为 StorageAdapter schema definition |
| `src/main/db/connection.ts`(better-sqlite3 入口) | ~100 | 🔴 **丢弃** | 替换为 Adapter factory |
| `src/main/ipc/`(27 通道) | ~2000 | 🔴 **不适用** | 改为直接 import + 调用 |
| `src/main/core/`(app-initializer) | ~400 | 🟡 **70%** | 删 IPC 注册,改 Adapter 初始化 |
| `src/main/index.ts`(Electron 入口) | ~300 | 🔴 **不适用** | 替换为 Capacitor 入口 |

**总计**:
- 🟢 100% 复用:~6800 行(UI + stores)
- 🟡 50-90% 复用:~1100 行(services + 部分 stores)
- 🔴 丢弃/重写:~3900 行(IPC + main + connection)

**净效益**: ~7900 行直接可用 + ~1500 行改造 vs ~6800 行 Kotlin 重写。

### 1.2 关键改造点详解

#### 改造 1: `StorageAdapter` 抽象层(新文件)

**位置**: `src/shared/storage/storage-adapter.ts`(原 src/main 移至 src/shared,因双端共用)

```typescript
// 接口定义(双端共用)
export interface StorageAdapter {
  initialize(): Promise<void>;
  query<T>(sql: string, params?: unknown[]): Promise<T[]>;
  execute(sql: string, params?: unknown[]): Promise<{ changes: number; lastInsertId: number }>;
  transaction<T>(fn: (tx: TransactionContext) => Promise<T>): Promise<T>;
  close(): Promise<void>;
}
```

**两个实现**:
- `BetterSqliteAdapter`(原 `connection.ts` 逻辑,改名复用)
- `CapacitorSqliteAdapter`(@capacitor-community/sqlite 包装)

**工作量**: 2-3 天(接口 + 2 个 adapter + 测试)

#### 改造 2: Stores 重写为薄包装

**原 `ActiveTrainingStore`**:
```typescript
export class ActiveTrainingStore {
  private db: Database.Database;
  constructor(db) { this.db = db; }
  create(input) { this.db.prepare('INSERT...').run(...) }
  // ...
}
```

**新 `ActiveTrainingStore`**:
```typescript
export class ActiveTrainingStore {
  constructor(private adapter: StorageAdapter) {}
  async create(input) {
    await this.adapter.execute(
      'INSERT INTO active_training (session_id, ...) VALUES (?, ?)',
      [input.sessionId, ...]
    );
  }
}
```

**注意**: stores 从同步变异步,需要处理 callers 调整(已经在 async context 内,大部分 OK)。

**工作量**: 3-4 天(7 个 store 全部改造)

#### 改造 3: IPC 全部移除

**原模式**:
```typescript
// main 端
ipcMain.handle('activeTraining:submitStep', async (event, args) => {
  return activeTrainingService.submitFlowStep(args.sessionId, args.stepId, args.content);
});

// renderer 端
const result = await window.api.activeTraining.submitStep({ ... });
```

**新模式**:
```typescript
// 在 Capacitor/WebView 上下文中,直接调用
import { activeTrainingService } from '@/main/domains/03-teaching/state/active-training.service';
const result = await activeTrainingService.submitFlowStep(sessionId, stepId, content);
```

**工作量**: 1-2 天(删 IPC handler 文件 + 改 renderer import + 替换 wrapper)

### 1.3 27 SQL Migrations 翻译策略

**轻量方案**(推荐,本轮用):
- 只保留 5 张核心表的 schema:`sessions` / `projects` / `active_training` / `teaching_state` / `training_records`
- 在 `StorageAdapter.initialize()` 内,按依赖顺序 `CREATE TABLE IF NOT EXISTS`
- 不保留 migration 历史(用户接受"重新开始",无生产数据迁移压力)

**完整方案**(S27+ 考虑):
- 实现 `Migration` 接口,按版本号顺序执行
- 跟踪 `_migrations` 表记录已执行版本
- 支持 up/down

**工作量**: 轻量 0.5 天,完整 3 天

---

## 2. 阶段拆解与 DoD

### 阶段 1: Plan + 抽象层 PoC(2-3 天)

**DoD**:
1. ✅ 本计划文档获用户批准
2. ✅ Capacitor 项目初始化(`capacitor.config.ts`、`android/` 目录结构、APK 构建成功)
3. ✅ `StorageAdapter` 接口定义完成 + 2 个空实现文件
4. ✅ 1 张表(如 `sessions`)端到端跑通: SQL → Adapter → Service → Store → Zustand
5. ✅ Android 模拟器/真机装 APK 后能看到"sessions"页加载(可空列表)
6. ✅ Sprint 26 决策日志 D-074 启动条目

**关键产出**:
- `capacitor.config.ts`
- `android/`(Capacitor 生成)
- `src/shared/storage/`(新目录)
- `src/shared/storage/storage-adapter.ts`
- `src/shared/storage/adapters/better-sqlite.adapter.ts`
- `src/shared/storage/adapters/capacitor-sqlite.adapter.ts`

### 阶段 2: Build — 全量适配(7-10 天)

#### 2.1 存储抽象 + Stores 改造(4-5 天)
- 2.1.1 `StorageAdapter` 接口 + 2 个实现 + 集成测试(2 天)
- 2.1.2 7 个 store 全部改造为 Adapter 调用(2-3 天)

**DoD**:
- 7 个 store 全部通过 `npm test`(单元测试 + 集成测试)
- better-sqlite3 adapter 与 Capacitor SQLite adapter 行为一致(同一测试套件双跑)
- `StorageAdapter` 覆盖率 ≥ 90%

#### 2.2 IPC 移除(1-2 天)
- 2.2.1 删 `src/main/ipc/`(27 个 handler 文件)
- 2.2.2 renderer 端 `services/*.service.ts` 改直接 import
- 2.2.3 删 `src/preload/`、`src/shared/api-contracts/` 中的 IPC 相关类型(保留共享类型)

**DoD**:
- `npm run typecheck` 0 errors(IPC 引用全清)
- `grep -r "ipcMain\|ipcRenderer" src/` 0 命中
- renderer 启动 < 1s(无 IPC 桥接开销)

#### 2.3 Services 异步化适配(1-2 天)
- 2.3.1 `ActiveTrainingService` 等 services 内部 store 调用改 `await`
- 2.3.2 Zustand actions 处理异步状态

**DoD**:
- 所有 service 方法返回 `Promise<T>`
- 单元测试 `async/await` 正确
- 端到端: 启动训练 → 5 步分步提交 → 评估 → 完成 全链路在 Android 模拟器跑通

#### 2.4 UI 在 Android 验证(0.5-1 天)
- 2.4.1 在 Capacitor Android 模拟器中完整跑通关键流程
- 2.4.2 修复移动端特有 bug(虚拟键盘、屏幕旋转、状态栏适配)

**DoD**:
- 至少 1 个完整用户旅程在 Android 真机/模拟器跑通
- 屏幕旋转不崩
- 软键盘弹出输入框不被遮挡

### 阶段 3: Test — 集成 + E2E(2-3 天)

**DoD**:
1. ✅ 5 张核心表全链路: 写入 → 读取 → 修改 → 删除 在双端行为一致
2. ✅ 完整用户旅程: 创建项目 → 启动训练 → 5 步分步提交 → 评估 → 完成 → 历史查看
3. ✅ 性能基线: 启动 < 2s,首屏 < 500ms
4. ✅ 兼容性: Android 10 / 12 / 14 模拟器测试
5. ✅ Windows 端 Electron 仍正常工作(回归测试)

**测试工具**:
- Vitest(单元 + 集成)
- Capacitor Android 模拟器(E2E)
- Electron(Windows 回归)

### 阶段 4: Ship — 打包 + 文档(1-2 天)

**DoD**:
1. ✅ 签名 APK 生成(release,Android 14 兼容)
2. ✅ 体积 < 30MB(纯 React/TS,无大资源)
3. ✅ 应用 ID: `com.yuesheng.writingcoach`
4. ✅ 首次启动引导: "从 Windows Electron 导入数据?"
5. ✅ 用户使用文档(MIGRATION_GUIDE.md)
6. ✅ GitHub Release 草稿 APK
7. ✅ Electron 端不破坏(回归通过)

---

## 3. 关键决策点(必须用户确认才能启动)

### 决策 A: 5 张核心表清单

✅ **建议**: sessions / projects / active_training / teaching_state / training_records

- 加入第 6 张: ___________
- 调整清单: ___________

### 决策 B: 存储 adapter 选择

✅ **建议**: Capacitor 端用 `@capacitor-community/sqlite`(可复用现有 SQL,改动最小)

- 备选: `Dexie.js`(IndexedDB 包装,需翻译 SQL → query API,改动大)
- 备选: `expo-sqlite`(若考虑 RN,本轮不用)

### 决策 C: Capacitor 工具链

✅ **建议**: `@capacitor/core` + `@capacitor/cli` + `@capacitor/android` + `@capacitor-community/sqlite`

- 确认? ☐ 是 ☐ 调整

### 决策 D: 时间盒

✅ **建议**: 14-15 工作日(2.5-3 周)

- 同意? ☐ 是 ☐ 压缩到 ___ 周 ☐ 放宽到 ___ 周

### 决策 E: 真机/模拟器

- 是否能用 Android 模拟器? ☐ 是 ☐ 否(用 BrowserStack/远程)
- Android 版本目标: ☐ 10 ☐ 12 ☐ 14(默认全支持)
- 是否需要签名 release APK? ☐ 是(需 keystore) ☐ 否(debug APK 即可测试)

### 决策 F: Windows 端处理

✅ **建议**: 本轮 Windows Electron 保留(已工作),不动

- 同意? ☐ 是 ☐ Windows 也要重构成 Capacitor(本轮) ☐ 不确定

---

## 4. 风险与缓解

| # | 风险 | 影响 | 概率 | 缓解 |
|:-:|:-----|:-----|:----:|:-----|
| 1 | **Capacitor SQLite 与 better-sqlite3 行为差异**(日期/JSON 字段) | 数据兼容 | 中 | 抽象层加统一 `safeQuery` / `formatRow` 函数 |
| 2 | **37 个文件 better-sqlite3 改造范围爆炸** | 延期 | 高 | 严守"只改 stores + 抽象层",不顺手优化 services(R-010) |
| 3 | **Capacitor 性能差**(WebView 启动慢) | UX 卡顿 | 中 | Vite 构建优化 + 懒加载,首屏只加载必需 chunks |
| 4 | **Android 模拟器不可用** | 阻塞 | 低 | 用 BrowserStack 远程模拟器 + 真机备份 |
| 5 | **用户数据迁移复杂**(从 Windows SQLite 到 Android SQLite) | 用户流失 | 中 | 导出 JSON 格式最简,MVP 阶段先不做双向同步,只单向导入 |
| 6 | **Stores 异步化导致连锁改动** | 范围扩散 | 高 | 限定 stores 内部异步,service 签名保持 Promise 兼容,R-021 边界 |
| 7 | **Electron 端回归失败** | Windows 失能 | 中 | 改造前 100% 测试通过,改造后逐 store 验证,出问题立即回滚 |

---

## 5. 资源与依赖

### 5.1 工具/库

| 工具 | 版本 | 用途 |
|:-----|:-----|:-----|
| Capacitor | 6.x | 跨端容器 |
| @capacitor/core | 6.x | Capacitor 核心 |
| @capacitor/android | 6.x | Android 平台 |
| @capacitor-community/sqlite | 6.x | SQLite 插件 |
| Android Studio | Hedgehog+ | APK 构建/调试 |
| JDK | 17+ | 编译 |
| Gradle | 8.x | Android 构建 |

### 5.2 团队角色

- **AI 主开发**: 全栈改造
- **Android 顾问**(用户): 模拟器/真机测试、签名、APK 验证
- **QA**(用户): 端到端验收

### 5.3 前置依赖

- Android Studio 已安装(JDK 17+)
- 至少 1 台 Android 模拟器或真机
- 1 个 keystore(release 签名用,可选)
- 用户对 5 张核心表清单确认

---

## 6. 决策日志联动

**D-074 启动**:
- 类型: 战略调整 + 架构重设计
- 内容: Sprint 26 Electron → Capacitor 双端复用启动
- 关键决策: 5 张核心表迁移 / Capacitor 跨端 / StorageAdapter 抽象 / Windows 保留 Electron
- 教训: 跨端决策应在 MVP 早期评估;**事实校正不可省**——本轮发现"UI 早已移动端化"颠覆原 Kotlin 计划

**Sprint 26 完成后**:
- D-074 收尾: 实际工时 vs 估算 / 风险触发 / 用户反馈
- S27 候选:
  - 22 张表迁移(可重启用)
  - Windows 端走 Capacitor(统一栈)
  - iOS 端(共享 80% 代码)
  - AI 集成层真实化(目前还是 mock)

---

## 7. 时间盒与产出

| 阶段 | 工时 | 累计 |
|:-----|:----:|:----:|
| 1. Plan + 抽象层 PoC | 2-3 天 | 3 |
| 2.1 存储抽象 + Stores | 4-5 天 | 8 |
| 2.2 IPC 移除 | 1-2 天 | 9.5 |
| 2.3 Services 异步化 | 1-2 天 | 11 |
| 2.4 UI 在 Android 验证 | 0.5-1 天 | 11.5 |
| 3. Test 集成 + E2E | 2-3 天 | 14 |
| 4. Ship 打包 + 文档 | 1-2 天 | 15-16 |
| **总计** | **15-16 工作日** | **约 2.5-3 周** |

**最小可验证产品形态**:
1. ✅ Android Studio 构建 + APK 装真机/模拟器成功
2. ✅ 5 张表 CRUD 正确(在 Android 端验证)
3. ✅ React UI 完整可用(已手机端化,直接展示)
4. ✅ 1 个完整用户旅程在 Android 跑通(创建项目 → 训练 → 完成)
5. ✅ Windows Electron 端仍正常工作(回归通过)
6. ✅ 启动 < 2s,首屏 < 500ms

---

## 8. 关联文档

- **D-073** Sprint 25 BL-01 五步流集成(前置)
- **D-074** Sprint 26 Capacitor 双端复用(本轮新增)
- **R-004** 准出标准 DoD
- **R-010** 最小化范围
- **R-019** 代码规范标准
- **R-020** 循环依赖零容忍(Stores ↔ Adapter 边界)
- **R-021** AI 行为边界(不顺手重写 services)
- **R-022** 过程可见
- **R-027** AI 代码质量门禁
- **D-070** Sprint 24 A 轨状态机基础

---

## 9. 用户回复模板

请直接回复:
- 决策 A: ✅ 默认 / 调整: ___
- 决策 B: ✅ Capacitor SQLite / 选 Dexie / 选其他
- 决策 C: ✅ 默认工具链 / 调整
- 决策 D: ✅ 2.5-3 周 / 压缩 / 放宽
- 决策 E: 模拟器: 是/否 / Android 版本: ___ / 签名: 是/否
- 决策 F: ✅ Windows 保留 Electron / Windows 也重构
- 总体: 批准 / 修改 / 重新讨论

---

**状态**: 待用户审批 + 6 项决策确认
**审批后启动**: 进入阶段 1(Plan + 抽象层 PoC)
**预计 Sprint 26 完成日期**: 2026-07-25(假设 2026-07-03 批准)
