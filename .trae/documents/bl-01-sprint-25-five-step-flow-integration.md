# Sprint 25 BL-01 计划 — 五步训练流集成到教学管道

> **核心目标**: 把 `TrainingFlowService` 已生成的 5 步流从"半贯通"补完到"完整教学管道",消除 R-014 配置外置违反,让 V6.2 UI 真正消费 flowType='flow5'。
> **依据**: D-072 (D-DEBT-34 收尾) + BL-01 backlog + RWR-MASTER-CHAIN §S25 候选
> **开始日期**: 2026-07-03
> **R-010**: 3 个原子 commit 串行交付,每 commit 单一职责
> **范围**: 仅 BL-01,BL-02/03/04/05/07/15 推 S26+

---

## 0. 范围与边界

### 0.1 目标

让 5 步通用训练流(解说/例证/确认/尝试/反馈)在主进程 + 渲染层贯通:
- ✅ 5 步流生成**配置外置**(R-014 零硬编码)
- ✅ V6.2 UI 有专门 `FlowPanel` 组件消费 `flowType='flow5'`
- ✅ 5 步独立提交(每步可保存+评估)
- ✅ 现有 `submitStep` 统一提交通道**向后兼容**

### 0.2 不在范围

- ❌ 跨端加载器统一(跳过 C-2,renderer 端独立 loader 已工作)
- ❌ 技法库过滤(S26 BL-02)
- ❌ 5 步流 UI 全面重设计(仅迁移 + design tokens 适配)
- ❌ sendToEditor 编辑器联动(S26 BL-03)

### 0.3 当前现状(2026-07-03)

**已完成**:
- ✅ `TrainingFlowService.generateTrainingFlow` 完整实现 5 步流(`src/main/domains/04-validation/training/training-flow.service.ts:189`)
- ✅ IPC 通道 `training:generateFlow` 已注册(`src/main/ipc/training.handler.ts:313`)
- ✅ renderer 调用链:`training.actions.ts:91` startTraining 时调 generateFlow + `session.flowType = 'flow5'`
- ✅ `TrainingFlow` / `TrainingFlowStep` / `TrainingFlowStepId` 类型已定义(`src/shared/types/types-training.ts:64`)
- ✅ `ActiveTrainingService.start()` 接受 `trainingFlow?` + `flowType?`(`active-training.service.ts:80-81`)
- ✅ archived UI 完整:`FiveStepFlow` + `StepExplain` + `StepExample` + `StepConfirm` + `StepPractice` + `StepFeedback` + `FlowStepIndicator`(9 个测试覆盖)
- ✅ renderer 端 flow loader:`src/renderer/flow/training.flow.ts`(模块级单例 + fail-fast 校验)
- ✅ JSON 配置文件:`resources/config/training-flow-mapping.json`(categories + flowTemplates 两段)

**缺口**:
- ❌ **R-014 配置外置违反**:`training-flow.service.ts:63-119` 硬编码 4 处(CATEGORY_CONFIGS/DEFAULT_CONFIG/inferEffect/estimateMinutes)
- ❌ **直接 import JSON 违反**:`training-flow.service.ts:20` 直接 `import techniqueLibrary`(应走 loader)
- ❌ **V6.2 UI 缺 FlowPanel**:`src/renderer/components/training/`(非 archived)下没有 flow 子目录
- ❌ **5 步独立提交未实现**:当前 `submitStep` 统一提交,无 `stepIndex` 区分

---

## 1. 推荐决策组合

| 决策点 | 选择 | 依据 |
|:-------|:-----|:-----|
| 跨端加载器 | **跳过 C-2** | renderer 端 `training.flow.ts` 独立可用,R-010 最小化 |
| UI 策略 | **迁移 archived 5 步组件** | 9 个测试成熟,迁移风险 < 新建 |
| Sprint 25 范围 | **3 commit (C-1 + C-3 + C-4)** | 3 人天,功能闭环 |

---

## 2. 阶段划分

### 2.1 C-1: R-014 配置外置重构 (1 人天)

**目标**: 删除 `training-flow.service.ts` 硬编码 4 处,走 `training-flow-mapping.json` + 新建 main 端 loader。

**DoD**:
1. ✅ 新建 `src/main/domains/04-validation/training/flow-mapping.loader.ts` — 模块级单例 + fail-fast 校验
2. ✅ `training-flow.service.ts` 删除 `CATEGORY_CONFIGS` / `DEFAULT_CONFIG` / `inferEffect` / `estimateMinutes` 硬编码
3. ✅ `training-flow.service.ts` 删除 `import techniqueLibrary from '*.json'` 直接 import,走 `techniqueLibraryLoader`(新建)
4. ✅ `resources/schemas/training-flow-mapping.v1.json` JSON Schema 校验文件(可选,首期可省)
5. ✅ `npm run typecheck` 0 errors
6. ✅ `npm test -- training-flow.service` 11 个测试全绿(行为零变更)
7. ✅ `npm run lint` 0 errors
8. ✅ `grep -n "CATEGORY_CONFIGS\|DEFAULT_CONFIG\|inferEffect" src/main` 0 命中
9. ✅ 决策日志:新增 D-073(R-014 重构 + loader 拆分)

**关键文件**:
| 文件 | 操作 | 变更 |
|:-----|:-----|:-----|
| `src/main/domains/04-validation/training/training-flow.service.ts` | M | 272 行 → 150 行(删除硬编码) |
| `src/main/domains/04-validation/training/flow-mapping.loader.ts` | A | ~60 行(单例 + 校验) |
| `src/main/domains/04-validation/training/technique-library.loader.ts` | A | ~40 行(替代直接 import) |
| `src/main/domains/04-validation/training/index.ts` | M | export 新 loader |
| `src/main/domains/04-validation/training/__tests__/training-flow.service.test.ts` | M | 0 变更(行为一致) |
| `docs/decision-log.md` | M | 新增 D-073 |

**复用现有**:
- `src/renderer/flow/training.flow.ts:48-67` FLOW_CATEGORIES/FLOW_TEMPLATES 单例模式 → 复制到 main 端 loader
- `resources/config/training-flow-mapping.json` 现有 JSON,直接复用

**R-010 最小化**:
- 不修改 JSON 文件内容(只新增 schema 校验)
- 不修改 IPC 通道签名
- 不动其他 4 个配置文件(syndrome-action-map / teaching-flow / technique-library)

**Commit 标题**: `refactor(training-flow): 拆分五步流配置外置,删除硬编码 4 处(R-014)`

---

### 2.2 C-3: 迁移 archived 5 步 UI 组件到 V6.2 (1 人天)

**目标**: 把 `src/renderer/components_archived/training/flow/` 5 步组件迁移到 `src/renderer/components/training/flow/`,适配 V6.2 store + CSS Modules + design tokens。

**DoD**:
1. ✅ 新建 `src/renderer/components/training/flow/FlowPanel.tsx` + 5 步骤子组件 + FlowStepIndicator
2. ✅ 迁移后 7 个文件 + 配套 CSS Modules + 适配 design tokens(`src/renderer/styles/variables.css`)
3. ✅ `src/renderer/components/training/ActiveTrainingView.tsx` 改造:`flowType === 'flow5'` 走 FlowPanel,否则走 legacy
4. ✅ archived 旧文件**保留**(作为 ADR 历史快照,不删)
5. ✅ 新建 `src/renderer/components/training/flow/__tests__/FlowPanel.test.tsx`(5 步切换 + 评估 + 退出覆盖)
6. ✅ 单文件 ≤ 300 行(R-019)
7. ✅ `npm run typecheck` + `npm test` + `npm run lint` 全绿
8. ✅ 决策日志:新增 D-073 子条目(UI 迁移完成)

**关键文件**:
| 文件 | 操作 | 变更 |
|:-----|:-----|:-----|
| `src/renderer/components/training/flow/FlowPanel.tsx` | A | ~140 行(从 archived 迁移 + tokens 适配) |
| `src/renderer/components/training/flow/StepExplain.tsx` | A | ~50 行 |
| `src/renderer/components/training/flow/StepExample.tsx` | A | ~50 行 |
| `src/renderer/components/training/flow/StepConfirm.tsx` | A | ~70 行 |
| `src/renderer/components/training/flow/StepPractice.tsx` | A | ~80 行 |
| `src/renderer/components/training/flow/StepFeedback.tsx` | A | ~80 行 |
| `src/renderer/components/training/flow/FlowStepIndicator.tsx` | A | ~60 行 |
| `src/renderer/components/training/flow/*.module.css` | A×7 | ~200 行 × 7 |
| `src/renderer/components/training/ActiveTrainingView.tsx` | M | +~20 行(flowType 分支) |
| `src/renderer/components_archived/training/flow/*` | 保留 | 不删,加 README 说明 |

**复用现有**:
- `src/renderer/components_archived/training/flow/FiveStepFlow.tsx` 完整 props 接口(ActiveTrainingSession + TrainingFlow + EvaluationResult + onExit)
- `src/renderer/styles/variables.css` design tokens(颜色/间距/圆角)
- `src/renderer/stores/training.store.ts` 已提供 `useTrainingStore` selector

**R-010 最小化**:
- archived 文件不改(历史快照)
- 不修改 FlowStepIndicator 的 props(向后兼容)
- 不重构 5 步逻辑(纯迁移)

**Commit 标题**: `feat(training-ui): 迁移 archived 5 步组件到 V6.2 flow 子目录`

---

### 2.3 C-4: 扩展 submitStep 接受 stepIndex (0.5 人天)

**目标**: 让 `submitStep` 接受可选 `stepIndex?: 1|2|3|4|5` + `content?: string`,实现 5 步独立提交/评估,旧调用方无参走 legacy。

**DoD**:
1. ✅ `src/main/domains/03-teaching/state/active-training.service.ts` 新增 `submitFlowStep(sessionId, stepIndex, content)` 方法
2. ✅ `active_training` 表新增 `step_responses_json TEXT` 字段(SQL migration 027)
3. ✅ `src/main/ipc/active-training.handler.ts` `activeTraining:submitStep` payload 接受可选 `stepIndex` + `content`
4. ✅ `src/renderer/stores/training.actions.ts` `submitStep(stepIndex?, content?)` 签名扩展
5. ✅ 向后兼容:无参调用走原逻辑(尾部 submit)
6. ✅ `src/main/domains/03-teaching/state/__tests__/active-training.service.test.ts` 新增 5 步分步提交测试(至少 5 用例)
7. ✅ `src/main/ipc/__tests__/active-training.handler.e2e.test.ts` 新增 E2E 场景:5 步全链路(start → 5 次 submitFlowStep → complete)
8. ✅ 决策日志:D-073 子条目(分步提交契约)

**关键文件**:
| 文件 | 操作 | 变更 |
|:-----|:-----|:-----|
| `drizzle/027_active_training_step_responses.sql` | A | ~10 行(新增字段) |
| `src/main/domains/03-teaching/state/active-training.service.ts` | M | +~30 行(submitFlowStep) |
| `src/main/domains/03-teaching/state/active-training.store.ts` | M | +~15 行(updateStepResponses) |
| `src/main/ipc/active-training.handler.ts` | M | +~10 行(扩展 payload) |
| `src/renderer/stores/training.actions.ts` | M | +~20 行(stepIndex 透传) |
| `src/shared/api-contracts/active-training.contract.ts` | M | +type definition |
| `src/main/domains/03-teaching/state/__tests__/active-training.service.test.ts` | M | +5 用例 |
| `src/main/ipc/__tests__/active-training.handler.e2e.test.ts` | M | +1 E2E 场景 |
| `docs/decision-log.md` | M | D-073 子条目 |

**复用现有**:
- `src/main/domains/03-teaching/state/active-training.service.ts:49-67` `onStateChange` 订阅模式(新增 'submitStep' 类型)
- `src/shared/api-contracts/active-training.contract.ts` 现有 `ActiveTrainingUpdateDraftResponse` 模式

**R-010 最小化**:
- 不新增 IPC 通道(扩展现有)
- 不修改 `ActiveTraining` 核心状态机(只新增方法)
- 不动 `userDraft` 字段(独立 `step_responses_json` 存每步回答)

**Commit 标题**: `feat(active-training): submitStep 接受 stepIndex 实现 5 步分步提交`

---

## 3. 依赖图与执行顺序

```
C-1 (R-014 重构)
  ↓
  ├─→ C-3 (UI 迁移) ┐
  └─→ C-4 (submitStep 扩展) ┘
```

C-3 与 C-4 可并行,但 C-3 依赖 C-1 完成后才能验证(flow 配置改动 UI 才生效)。

**推荐顺序**:C-1 → C-3 → C-4(串行,降低集成风险)

---

## 4. 验收与门禁(R-027)

| 门禁 | 工具 | 期望 |
|:-----|:-----|:-----|
| Type check | `npm run typecheck` | 0 errors |
| Unit test | `npm test -- training-flow FlowPanel active-training` | 全绿(原 11 + 新 5~10) |
| Lint | `npm run lint --max-warnings 300` | 0 errors |
| R-014 检查 | `grep -n "CATEGORY_CONFIGS\|DEFAULT_CONFIG\|inferEffect" src/main` | 0 命中 |
| 行数硬上限 | 文件大小检查 | 单文件 ≤ 300 行 |
| 决策日志 | `git log --oneline -- docs/decision-log.md` | D-073 新增 |
| E2E 链路 | `npm test -- active-training.handler.e2e` | 5 步分步提交场景全绿 |

---

## 5. 风险与缓解

| # | 风险 | 影响 | 缓解 |
|:-:|:-----|:-----|:-----|
| 1 | **R-020 循环依赖**:main 端误 import renderer/flow/ | 编译失败 | main 端独立 loader,共享仅 JSON |
| 2 | **行为漂移**:C-1 重构后 5 步流内容变化 | 训练内容走样 | 11 个单测断言零行为变更 |
| 3 | **archived 组件 import 失败**:V6.2 store selector 不兼容 | UI 白屏 | 迁移时同步改 import + selector |
| 4 | **submitStep 兼容**:旧调用方传 null stepIndex | 旧链路断 | handler 默认值 `stepIndex = steps.length` |
| 5 | **JSON 路径跨域**:main/renderer 相对路径不一致 | 加载失败 | C-1 单测断言 import 路径一致 |
| 6 | **范围爆炸**:C-3 顺手重构周边组件 | 5+ 人天 | 严格限定 `components/training/flow/` 子树 |

---

## 6. 时间盒与产出

| 阶段 | 工时 | 累计 |
|:-----|:----:|:----:|
| C-1 R-014 重构 | 1.0 人天 | 1.0 |
| C-3 UI 迁移 | 1.0 人天 | 2.0 |
| C-4 submitStep 扩展 | 0.5 人天 | 2.5 |
| 门禁验证 | 0.3 人天 | 2.8 |
| 决策日志 D-073 | 0.2 人天 | **3.0 人天** |

**Sprint 25 BL-01 最小可验证产品形态**:
1. 用户触发技法训练时自动渲染 V6.2 五步面板(C-3)
2. 5 步流配置在 `training-flow-mapping.json` 改动后下次启动生效(C-1)
3. 每步独立提交 + AI 评估 + 进入下一步(C-4)
4. `submitStep` 无参调用行为不变(向后兼容)

---

## 7. 关联文档

- **D-072** D-DEBT-34 收尾(本轮决策日志依据)
- **D-073** BL-01 R-014 重构 + UI 迁移 + 分步提交契约(本轮新增)
- **R-010** 最小化范围(每 commit 单一职责)
- **R-014** 配置外置规范(loader 模式)
- **R-019** 代码规范标准(单文件 ≤ 300 行)
- **R-020** 循环依赖零容忍(main/renderer 边界)
- **R-027** AI 代码质量门禁(typecheck + test + lint + 文档)
- **BL-01** Backlog 条目(本任务编号)
- **Sprint 24 计划** 状态机基础(前置)
- **Sprint 26 计划** 技法库过滤 + 编辑器联动(后续)

---

## 8. 后续 Sprint 衔接

Sprint 25 完成后,Sprint 26 候选:
- **BL-02** 技法消费层过滤(P0)
- **BL-03** X-02 训练编辑器联动(P1)
- **BL-07** Attitude 透传链路(D-DEBT-17)(P1)
- **BL-04** 技法库 P011/P012 补全(P1)
- **BL-05** UX 问题批量修复(P1)

---

**状态**: 待用户审批
**审批人**: (待确认)
**开始执行条件**: 用户回复"开始"或"批准"
