## Sprint 26 阶段 2: 5 张核心表迁移（服务层 + 渲染层双轨过渡）

### 背景
- Sprint 26 阶段 1 完成（commit 7f45afb）：StorageAdapter 接口 + 3 个 adapter + Capacitor 初始化
- 阶段 1.1.6 Android 模拟器/真机验证依赖 Android Studio（用户 2026-07-04 确认今天/明天装好）
- 阶段 2 目标：5 张核心表的服务层迁移 + 渲染层双轨过渡

### 5 张表迁移顺序
1. **sessions**（依赖最少，最先迁移）
2. **projects**（依赖 sessions）
3. **teaching_state**（依赖 sessions）
4. **training_records**（依赖 sessions + active_training）
5. **active_training**（最复杂，Sprint 24 A 轨刚做完）

### 阶段 2 子任务（按表拆分）

#### T26-2.1: sessions 表迁移
- 把 main 进程 `SessionService`（同步 better-sqlite3）改造为异步 + StorageAdapter
- 保留 IPC handler 作为过渡（双轨：Electron 走旧 IPC，Android 走 direct）
- 实际已部分完成：`src/shared/services/session.service.ts` 已是 adapter 版本（双端共用）
- 剩余：main 进程 `SessionService` 切到 adapter + IPC handler 标 @deprecated

#### T26-2.2: projects 表迁移
- 重复 sessions 模式
- 新增 `src/shared/services/project.service.ts`（adapter 版本）
- main 进程 `ProjectService` 同步→异步
- 渲染层双轨

#### T26-2.3: teaching_state 表迁移
- 状态机相关（Sprint 22-24 改造过）
- 涉及状态机事件总线 → 双端共享
- 复杂

#### T26-2.4: training_records 表迁移
- 训练记录（Sprint 21 真实 Orchestrator 适配器）
- 与 active_training 关联

#### T26-2.5: active_training 表迁移
- Sprint 24 A 轨刚做的状态机
- 5 张表中最复杂

### 范围与边界

**在范围内**：
- 5 张表的服务层 + 渲染层双轨改造
- StorageAdapter 完整使用
- 保持 IPC handler 过渡（@deprecated）

**不在范围内**：
- ❌ 22 张非核心表迁移
- ❌ IPC 通道完全移除（阶段 4）
- ❌ AI 集成层真实化（阶段 5）
- ❌ 业务逻辑重写

### DoD（阶段 2，每张表 ≥ 3 条）

#### 每张表的 DoD 模板
- [ ] **DoD-1**: `src/shared/services/<name>.service.ts` 创建（adapter 版本）
- [ ] **DoD-2**: main 进程对应 service 改造（同步→异步 + adapter）
- [ ] **DoD-3**: 渲染层双轨（Electron IPC + Android direct）
- [ ] **DoD-4**: 单测覆盖（≥ 6 用例，含 MemoryAdapter 跑通）
- [ ] **DoD-5**: 4 道门禁全绿

#### 阶段 2 全局 DoD
- [ ] 5 张表全部迁移完成
- [ ] main 进程所有 service 异步化
- [ ] 渲染层双轨统一模式（参考 session.service）
- [ ] 阶段 1.1.6 Android 验证完成（依赖 Android Studio）
- [ ] D-076 决策日志更新（5 张表迁移结果）
- [ ] 4 道门禁全绿（typecheck 0 / test 全绿 / lint 0 / 安全 OK）

### 风险与对策

| 风险 | 对策 |
|:-----|:-----|
| 同步→异步遗漏 | 严格 typecheck + 全量单测 |
| 业务逻辑分叉 | 渲染层统一双轨接口（参考 session.service） |
| 5 张表迁移顺序错误 | 严格按 sessions → projects → ... 顺序 |
| 状态机事件丢失 | main 进程事件总线保留（参考 ADR-010） |
| Android 端验证延迟 | sessions 表 PoC 已验证，可先推进其他 4 张 |

### 关联
- D-074 Sprint 26 战略转向
- dev-docs/tasks/sprint-26-plan.md §1.2
- ADR-009 StorageAdapter 接口设计
- Issue #44 Sprint 26 容器
- commit 7f45afb 阶段 1 实施
- D-075 jsdom Capacitor 误判债务（待阶段 2 修复）

### 阻塞
- Android Studio 安装（用户确认今天/明天）
- 阶段 1.1.6 Android 模拟器/真机验证（需先验证 sessions 表在 Android 端跑通）

### 预估工作量
- 每张表 ~1-2 天
- 5 张表总计 ~1-2 周
