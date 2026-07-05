# Sprint 26 计划 — Electron → Capacitor Android 双端复用

> **核心目标**: 把现有 React/TS 渲染层 100% 复用到 Android 平台，通过 StorageAdapter 抽象层让业务 services 在双端共享。
> **依据**: D-074 战略转向（commit 4db34bd）+ 用户确认 Android Studio 今日/明日装好
> **开始日期**: 2026-07-04
> **完成日期**: 待定（预估 2-3 周）
> **R-010**: 每阶段最小化，阶段 1（PoC）→ 阶段 2-3（5 表迁移）→ 阶段 4（IPC 移除）→ 阶段 5（AI 真实化，可选）

---

## 0. 范围与边界

### 0.1 目标
让月笙写作教练**双端共享业务逻辑**：
- ✅ Windows（Electron）：代码冻结不删，不维护不发版，横幅提示转 Android
- ✅ Android（Capacitor 6.x + WebView）：主力设备，APK 产出
- ✅ 业务 services、5 张核心表 schema、数据模型在双端共享
- ✅ StorageAdapter 抽象：BetterSqliteAdapter (Windows) + CapacitorSqliteAdapter (Android)

### 0.2 不在范围
- ❌ iOS 端（Capacitor 已支持，推 S27+）
- ❌ 22 张非核心表迁移（用户接受"重新开始"）
- ❌ 业务逻辑重写（只做存储层抽象）
- ❌ AI 集成层真实化（诊断/教学/训练仍走 mock）
- ❌ Play 商店发布（产出签名 APK，不上架）
- ❌ 跨设备同步（云端 + 冲突合并，推 S27+）

### 0.3 当前现状
- 27 张 SQLite 表（其中 5 张核心：sessions / projects / active_training / teaching_state / training_records）
- 27 个 IPC 通道（main ↔ renderer）
- React/TS 渲染层（含 mobile-first UI：max-width:375px、status bar、tabbar/navbar）
- 主进程 services（同步 better-sqlite3 调用）
- 状态机：Sprint 24 A 轨 ActiveTrainingService（5 状态 + 5 转换）

---

## 1. 阶段划分

### 1.1 阶段 1: Plan + PoC（2-3 天）

#### 1.1.1 子任务 1: Sprint 26 plan 文档（本文件）
- 目标：完整设计 Sprint 26 全部阶段
- 状态：进行中

#### 1.1.2 子任务 2: ADR-009 StorageAdapter 接口设计
- 目标：定义双端共用接口 + 2 个 adapter
- 产出：dev-docs/designs/adr/009-storage-adapter.md
- 状态：进行中

#### 1.1.3 子任务 3: ADR-010 IPC 移除策略
- 目标：明确 27 个 IPC 通道的处置方式
- 产出：dev-docs/designs/adr/010-ipc-removal.md
- 状态：进行中

#### 1.1.4 子任务 4: Capacitor 项目初始化
- 目标：capacitor.config.ts、android/ 目录结构、APK 构建成功
- 阻塞：需要用户安装 Android Studio / JDK 17
- 工作量：~0.5 天
- DoD:
  1. `npx cap init` 成功生成 capacitor.config.ts
  2. `npx cap add android` 成功生成 android/ 目录
  3. `npx cap sync android` 成功
  4. `cd android && ./gradlew assembleDebug` 产出 debug APK
  5. APK 安装到模拟器/真机成功

#### 1.1.5 子任务 5: StorageAdapter 端到端 PoC
- 目标：1 张表（建议 `sessions`）端到端跑通
- 工作量：~1 天
- DoD:
  1. StorageAdapter 接口定义（src/shared/storage/StorageAdapter.ts）
  2. BetterSqliteAdapter 实现（Windows/Electron 保留）
  3. CapacitorSqliteAdapter 实现（Android）
  4. sessions 表 schema 同步
  5. 端到端验证：SQL → Adapter → Service → Store → Zustand
  6. 单测覆盖：两个 adapter 各 ≥ 6 用例

#### 1.1.6 子任务 6: Android 模拟器/真机验证
- 目标：APK 安装后能看到"sessions"页加载（可空列表）
- 阻塞：需要 Android 模拟器/真机
- 工作量：~0.5 天
- DoD:
  1. Android Studio AVD 创建成功
  2. APK 安装并启动
  3. UI 加载：tabbar 可见，sessions 页面（空列表）可见
  4. 无 JS 错误（Chrome DevTools 远程调试验证）

---

### 1.2 阶段 2-3: 5 张核心表迁移（~1 周）

按以下顺序迁移（依赖关系）：
1. **sessions**（依赖最少，最先迁移，作为 PoC 验证）
2. **projects**（依赖 sessions）
3. **teaching_state**（依赖 sessions，UI 频繁读）
4. **training_records**（依赖 sessions + active_training）
5. **active_training**（最复杂，Sprint 24 A 轨刚做完）

每张表的迁移步骤：
1. 在 CapacitorSqliteAdapter 中实现 CRUD
2. 单元测试覆盖（≥ 6 用例）
3. 集成测试：Service 通过 Adapter 读写
4. UI 验证：对应页面正常加载
5. 端到端 E2E：1 个完整流程

---

### 1.3 阶段 4: 27 个 IPC 通道移除（~1 周）

详见 ADR-010。策略：
- 通道全部丢弃（不维护，注释 `@deprecated` 标识）
- WebView 内部直接 import service 调用
- R-020 边界从"main ↔ renderer"变成"store ↔ adapter"
- 状态机/事件总线适配：主进程 → 双端共用

---

### 1.4 阶段 5: AI 集成层真实化（可选，~1 周）

诊断/教学/训练 AI 仍走 mock 模式，可选激活：
- 接入 DeepSeek API（凭证走环境变量，R-029）
- Prompt 链：v5.0.1 + SkillDispatcher
- 流式响应：SSE → 渲染层
- 决策：D-055/D-056 已完成 Phase 1，可直接复用

---

### 1.5 阶段 6: 签名 APK 产出（~0.5 天）

- 生成签名密钥（keystore）
- 配置 release 签名
- 产出 release APK
- 不上架 Play 商店

---

## 2. 关键决策

### 2.1 决策 1: Capacitor 6.x vs React Native vs Flutter

**背景**: 三种跨端方案可选。

**决策**: Capacitor 6.x。

**理由**:
- **复用现有 React/TS 渲染层**：100% 复用 0 改动（Capacitor = WebView 套壳）
- **学习成本低**：现有 React/TS 开发者无需学 Kotlin/Swift/Dart
- **生态成熟**：5.x 稳定，6.x 主流
- **业务逻辑零改动**：services 适配 async adapter 即可

**风险**:
- WebView 性能不如原生（但本项目无高性能需求，写作教练 + 训练流）
- 包体积稍大（~10MB vs Flutter ~5MB），可接受

**依据**: D-074 关键事实校正（UI 早已移动端化，复用 React 即可）

---

### 2.2 决策 2: StorageAdapter 抽象层 — 接口先行

**背景**: 业务 services 当前直接调用 better-sqlite3 同步方法。

**决策**: 定义 StorageAdapter 接口先行，2 个 adapter 并行实现。

**接口设计原则**:
- 异步（async/await）— 双端统一
- 返回 Promise + 标准 Error 类型
- 事务支持（begin/commit/rollback）
- SQL 预处理（防注入）
- 不暴露平台特定 API

**两个实现**:
- `BetterSqliteAdapter`: 包装 better-sqlite3（同步→async 适配）
- `CapacitorSqliteAdapter`: 基于 @capacitor-community/sqlite

**详见 ADR-009**。

---

### 2.3 决策 3: 5 张表迁移顺序

**决策**: sessions → projects → teaching_state → training_records → active_training

**理由**:
- sessions 是其他表的外键依赖（必须先迁移）
- projects 依赖 sessions
- teaching_state 依赖 sessions
- training_records 依赖 sessions + active_training
- active_training 最复杂（Sprint 24 A 轨刚做完），放最后

---

### 2.4 决策 4: Windows 处理 — 代码冻结不删

**决策**: Windows（Electron）代码冻结不删不维护。

**实施**:
- README 添加横幅："本项目主力设备已转向 Android，Windows 版本冻结不维护"
- BetterSqliteAdapter 仍维护（保证 Windows 可用，但不投入新功能）
- 不发版 Windows（仅 Android 出 APK）

**理由**:
- 用户战略决定
- 避免双端维护成本
- 保留 Windows 旧代码便于紧急回退

---

## 3. 门禁

### 3.1 每阶段门禁
- typecheck: 0 errors
- vitest: 当前数 + 该阶段新增 ≥ DoD 数
- lint: 0 errors
- 安全: 0 硬编码密钥（R-029）
- Android: 真机/模拟器验证（Capacitor 阶段）

### 3.2 阶段 1 全局门禁
- typecheck: 0 errors
- vitest: 当前 881 + 阶段 1 新增 ≥ 15 用例
- lint: 0 errors
- 集成测试: 1 张表（sessions）端到端跑通
- Android 验证: APK 安装成功 + sessions 页可见

### 3.3 Sprint 26 验收清单（阶段 1）
- [ ] ADR-009 StorageAdapter 接口定义 + 2 个空 adapter
- [ ] Capacitor 项目初始化（APK 构建成功）
- [ ] sessions 表端到端跑通
- [ ] Android 模拟器/真机装 APK 后能看到 sessions 页
- [ ] 4 道门禁全绿
- [ ] 决策日志 D-074 实施结果 + 复盘 + S27 候选

---

## 4. 实施计划

| 阶段 | 任务 | 预计改动 | 工作量 |
|:----:|:-----|:--------|:------:|
| 1.1 | Sprint 26 plan + ADR-009 + ADR-010 | 3 新文件 | 0.5 天 |
| 1.2 | Capacitor 初始化 | capacitor.config.ts + android/ | 0.5 天 |
| 1.3 | StorageAdapter PoC（sessions） | 5 新文件 + 测试 | 1 天 |
| 1.4 | Android 模拟器/真机验证 | - | 0.5 天 |
| 2-3 | 5 张核心表迁移 | 每表 ~5 文件改造 | ~1 周 |
| 4 | 27 IPC 通道移除 | 27 文件注释 + 状态机改造 | ~1 周 |
| 5 | AI 集成层真实化（可选） | 复用 D-055/D-056 | ~1 周 |
| 6 | 签名 APK 产出 | 1 keystore + release config | 0.5 天 |

---

## 5. 风险与对策

| 风险 | 影响 | 对策 |
|:-----|:-----|:-----|
| Android Studio 未及时装好 | 阶段 1 阻塞 | 用户已确认今天/明天装好，阶段 1 拆分：先做不依赖环境的（plan + ADR） |
| Capacitor 性能问题 | 训练流卡顿 | 监控 P99 延迟，超过 100ms 考虑优化 |
| better-sqlite3 异步适配遗漏 | 数据不一致 | 强制所有 service 方法 async，统一错误处理 |
| 27 个 IPC 通道误删 | 功能丢失 | 先注释 @deprecated，保留 1 sprint 观察再删 |
| 5 张表迁移顺序错误 | 外键约束失败 | 严格按 sessions → projects → ... 顺序 |
| 签名密钥泄露 | 安全 | keystore 走 .gitignore，密码走环境变量（R-029） |
| Windows 横幅未显示 | 用户困惑 | README 顶部 + 启动弹窗 |

---

## 6. 后续候选（S27+）

### S27 候选
1. iOS 端（Capacitor 已支持）
2. 22 张非核心表迁移
3. 跨设备同步（云端 + 冲突合并）
4. 业务逻辑重写（异步化深度优化）

### S27+ 候选
1. Play 商店发布
2. 训练协作（CRDT/OT）
3. 离线优先架构（IndexedDB 本地缓存）

---

## 7. 关联

- D-074 Sprint 26 战略转向（commit 4db34bd）
- Issue #44 Sprint 26 容器
- Sprint 24 plan: dev-docs/tasks/sprint-24-plan.md
- D-070 Sprint 24 Reflect
- D-073 推 S26 治理（264 warnings，独立任务）
- ADR-009 StorageAdapter 接口设计
- ADR-010 IPC 移除策略
- Issue #41 / #42 / #43（Sprint 25 暂缓）

### 教训（D-074 提取）
1. 技术栈推荐前必须审计实际代码
2. 战略转向需做"事实校正"
3. 环境依赖前置检测
4. 抽象层设计要"为未来复用"而非"为当前需求"
