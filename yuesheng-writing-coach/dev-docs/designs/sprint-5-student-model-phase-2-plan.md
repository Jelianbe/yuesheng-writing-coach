# Sprint 5 — 学生模型 Phase 2：进度追踪与可视化

## 定位
Issue #? 的实施计划。在主进程 StudentModelService 基础上，打通渲染层的进度追踪和可视化。

## 现状

| 模块 | 状态 | 说明 |
|:-----|:------|:------|
| StudentModelService | ✅ 完整 | 症候聚合 + 画像推理 + 持久化 |
| StudentModelPersister | ✅ 完整 | student_model 表 CRUD |
| IPC handlers | ✅ 已注册 | ability:getProfile, growth:getTrends, teachingHistory:add |
| types | ✅ 已定义 | AbilityProfile, GrowthChain, TeachingHistoryEntry |
| **渲染层可视化** | ❌ 缺失 | 无 progress.store，无进度组件 |
| **teachingProgress 字段** | ❌ 缺失 | DiagnosisEntry 缺少教学进度追踪 |
| **态度锁** | ❌ 缺失 | attitudePreference.locked 未实现 |

## 实施范围

### 1. Progress Store — 教学进度状态管理
- 新建 `src/renderer/stores/progress.store.ts`
- 状态：`{ teachingProgress: Record<string, TeachingProgress>, isLoading, error }`
- Action：`loadProgress(sessionId)`, `updateProgress(syndromeId, update)`, `clearProgress()`
- IPC 通道：teachingProgress:get / teachingProgress:update（新建）

### 2. DiagnosisEntry 扩展 — teachingProgress 字段
- 修改诊断类型，新增 `teachingProgress[]` 字段
- 每个条目：`{ syndromeId, status, learningStage, teachingStartedAt, masteredAt, teachingApproaches, relapseCount }`
- DB migration（不影响既有数据，新字段默认空数组）

### 3. 态度锁机制
- config.store 增加 `locked: boolean`；`setAttitudeLevel` 返回 `skip-if-locked`
- 持久化到 `student_model.attitude_preference`（JSON 扩展为 `{ level, locked }`）

### 4. 进度可视化组件
- 新建 `ProgressOverview.tsx` — 右侧栏进度总览卡片
- 展示：0/N 症候教学进度、阶段完成状态
- 数据来自 progress.store

## 不涉及
- TrainingWorkshop 重构（Sprint 4 已完成）
- 项目级画像（大功能，需要项目容器整合，暂缓）
- 文本片段引用系统（大功能，暂缓）
- 学生模型测试补全（可做但非核心交付）

## 文件变更清单

| 文件 | 改动量 | 说明 |
|:-----|:------:|:------|
| `progress.store.ts` | 新增 ~120行 | Zustand store |
| `types-growth.ts` | ~20行 | 新增 TeachingProgress 类型 |
| `types-teaching.ts` | ~10行 | DiagnosisEntry 增加 teachingProgress |
| `config.store.ts` | ~15行 | 态度锁机制 |
| `constants.ts` | ~4行 | 新增 IPC 通道 |
| `ipc-registry.ts` | ~10行 | 注册新 handler |
| `progress.handler.ts` | 新增 ~60行 | IPC handler |
| `ProgressOverview.tsx` | 新增 ~100行 | 进度展示组件 + CSS |
| `migrations/` | 新增 ~15行 | 022_teaching_progress.sql |

## 门禁
- typecheck 0 errors
- 既有测试全绿
- lint 0 errors
