# Sprint 25 BL-01 C-3 — 迁移 archived 5 步 UI 组件到 V6.2

> **目标**: 把 `src/renderer/components_archived/training/flow/` 下的 7 个文件(编排 + 5 步骤 + 进度条 + 1 CSS)迁移到 V6.2 新位置 `src/renderer/components/training/flow/`,适配 V6.2 类型/store/CSS Modules/design tokens。
> **依据**: `docs/bl-01-sprint-25-five-step-flow-integration.md` §2.2 C-3
> **前置**: C-1 (R-014 配置外置重构) 已完成(D-073)
> **R-010**: 单一原子 commit,职责 = UI 迁移 + 类型/store 适配,不重构逻辑
> **范围**: 仅 C-3,C-4 (submitStep 扩展) 推后续

---

## 0. 范围与边界

### 0.1 目标

让 V6.2 训练视图消费 `flowType='flow5'`:

- ✅ 编排组件从 `FiveStepFlow` 重命名为 `FlowPanel`(对齐计划文件 DoD-1)
- ✅ 7 个文件 + 1 共享 CSS 迁移到 V6.2 新位置
- ✅ 类型 import 从 `src/shared/types/types-training.ts`(stale) 切换到 `src/renderer/shared/types-training.ts`(真实定义,避免与 store 类型冲突)
- ✅ CSS BEM 全局类名 → CSS Modules `styles.xxx` 访问(R-019)
- ✅ archived `ActiveTrainingView.tsx` 改 1 行 import 指向新路径

### 0.2 不在范围

- ❌ 5 步业务逻辑重构(纯迁移,行为零变更)
- ❌ `submitStep` 扩展(C-4 推后续)
- ❌ 父组件 `ActiveTrainingView` 整体迁移到 V6.2(保留 archived,只改 import)
- ❌ 9 个原 unit test 全部重写(迁移到新位置,内部逻辑保持)
- ❌ CSS 拆 7 个独立 .module.css(决策:保留 1 共享,见 §3)

### 0.3 当前现状(2026-07-03)

**已完成**:
- ✅ C-1 R-014 配置外置重构(D-073)
- ✅ archived UI 完整:`FiveStepFlow` + 5 Step + `FlowStepIndicator` + `flow.module.css` + 9 测试

**缺口**:
- ❌ `src/renderer/components/training/` 目录不存在,V6.2 无 FlowPanel
- ❌ 编排组件名 `FiveStepFlow` 与计划 DoD-1 `FlowPanel` 不一致
- ❌ archived 类型 import 指向 `src/shared/types/types-training.ts`(stale),与 store 真实类型 `src/renderer/shared/types-training.ts` 不同源
- ❌ archived CSS 用 BEM 全局类名(`flow-panel`),不满足 R-019 CSS Modules 规范
- ❌ archived `ActiveTrainingView.tsx:26` 仍指向 `./flow/FiveStepFlow`(本地相对路径)

---

## 1. 关键决策(已与用户确认)

| 决策点 | 选择 | 依据 |
|:-------|:-----|:-----|
| 编排组件命名 | **FlowPanel.tsx**(原 FiveStepFlow) | 计划文件 §2.2 DoD-1 |
| CSS 拆分粒度 | **1 个共享 `flow.module.css`** | 避免 7×200=1400 行冗余,5 步+指示器+容器共享一套 design token |
| 父组件处理 | **archived 保留,只改 import 路径** | R-010 最小化范围,符合"archived 历史快照"原则 |

---

## 2. 详细文件变更

### 2.1 新建文件(V6.2 目标位置)

| # | 文件 | 来源 | 行数 | 关键变更 |
|:-:|:-----|:-----|:----:|:---------|
| 1 | `src/renderer/components/training/flow/FlowPanel.tsx` | archived/FiveStepFlow.tsx | ~140 | ① 重命名组件 ② 改 import(类型/store/5 子组件) ③ 改 className 为 `styles.xxx` ④ JSDoc 顶部加"Sprint 25 BL-01 C-3 迁移自 archived" |
| 2 | `src/renderer/components/training/flow/FlowStepIndicator.tsx` | archived/FlowStepIndicator.tsx | ~60 | 同上模式 |
| 3 | `src/renderer/components/training/flow/StepExplain.tsx` | archived/StepExplain.tsx | ~50 | 同上 |
| 4 | `src/renderer/components/training/flow/StepExample.tsx` | archived/StepExample.tsx | ~50 | 同上 |
| 5 | `src/renderer/components/training/flow/StepConfirm.tsx` | archived/StepConfirm.tsx | ~70 | 同上 |
| 6 | `src/renderer/components/training/flow/StepPractice.tsx` | archived/StepPractice.tsx | ~80 | 同上 |
| 7 | `src/renderer/components/training/flow/StepFeedback.tsx` | archived/StepFeedback.tsx | ~80 | 同上 |
| 8 | `src/renderer/components/training/flow/flow.module.css` | archived/flow.module.css | ~185 | ① 全局类名转 CSS Modules(`.flowPanel`/`.flowPanelTitle` 等) ② 类名访问统一 `styles.xxx` ③ 顶部注释更新为 V6.2 |
| 9 | `src/renderer/components/training/flow/__tests__/FlowPanel.test.tsx` | archived/__tests__/FiveStepFlow.test.tsx | ~210 | ① import 路径指向新位置 ② 组件名 FiveStepFlow → FlowPanel ③ 行为断言零变更(9 用例) |

### 2.2 修改文件(只改 import 路径)

| 文件 | 变更 |
|:-----|:-----|
| `src/renderer/components_archived/training/ActiveTrainingView.tsx:26` | `import { FiveStepFlow } from './flow/FiveStepFlow';` → `import { FlowPanel } from '../../training/flow/FlowPanel';` |
| `src/renderer/components_archived/training/ActiveTrainingView.tsx:63-69` | `<FiveStepFlow ...>` → `<FlowPanel ...>`,props 名 `active/flow/evaluation/onExit` 保持不变 |

### 2.3 不变文件

- ✅ `src/renderer/components_archived/training/flow/*`(历史快照,完整保留)
- ✅ `src/renderer/stores/training.store.ts`(A-4 已含订阅)
- ✅ `src/main/domains/04-validation/training/*`(C-1 已重构)
- ✅ `src/renderer/styles/variables.css`(design tokens 已就位)
- ✅ `src/renderer/flow/training.flow.ts`(renderer 端 loader,独立可用)
- ✅ `resources/config/training-flow-mapping.json`(C-1 已扩展 categoryTemplates)

### 2.4 新建辅助文件

| 文件 | 用途 | 行数 |
|:-----|:-----|:-----|
| `src/renderer/components/training/flow/README.md` | 简短说明迁移来源 + archived 引用关系 | ~15 |

---

## 3. CSS Modules 转换规则

BEM 全局类名 → CSS Modules camelCase 访问,示例:

```css
/* 原 BEM */
.five-step-flow { ... }
.five-step-flow__header { ... }
.flow-panel { ... }
.flow-panel--explain { ... }
.flow-panel__title { ... }

/* 转换后(同一文件内) */
.fiveStepFlow { ... }
.fiveStepFlowHeader { ... }
.flowPanel { ... }
.flowPanelExplain { ... }   /* BEM 修饰符 → 独立类 */
.flowPanelTitle { ... }     /* BEM 元素 → 独立类 */
```

**TSX 中访问**:
```tsx
import styles from './flow.module.css';
// 原: <div className="five-step-flow">
// 新: <div className={styles.fiveStepFlow}>
```

**状态类拼接**:
```tsx
// 原: className={`flow-step flow-step--${status}`}
// 新: className={`${styles.flowStep} ${styles[`flowStep${capitalize(status)}`]}`}
```

**完整类名映射表**(按出现频次排序):

| 旧 BEM | 新 CSS Modules |
|:-------|:---------------|
| `five-step-flow` | `styles.fiveStepFlow` |
| `five-step-flow__header` | `styles.fiveStepFlowHeader` |
| `five-step-flow__body` | `styles.fiveStepFlowBody` |
| `five-step-flow__footer` | `styles.fiveStepFlowFooter` |
| `flow-step-indicator` | `styles.flowStepIndicator` |
| `flow-step` | `styles.flowStep` |
| `flow-step--pending` | `styles.flowStepPending` |
| `flow-step--active` | `styles.flowStepActive` |
| `flow-step--completed` | `styles.flowStepCompleted` |
| `flow-step__num` | `styles.flowStepNum` |
| `flow-step__label` | `styles.flowStepLabel` |
| `flow-panel` | `styles.flowPanel` |
| `flow-panel--explain/example/confirm/practice/feedback` | `styles.flowPanel{Modifier}` |
| `flow-panel__title/content/action/textarea/...` | `styles.flowPanel{Element}` |

---

## 4. 类型 Import 路径调整

```tsx
// 原(archived 7 个文件统一)
import type {
  ActiveTrainingSession,
  TrainingFlow,
  EvaluationResult,
} from '../../../../shared/types/types-training';
//      ↑ 4 层,指向 src/shared/types/types-training.ts (stale)

// 新(V6.2 新位置)
import type {
  ActiveTrainingSession,
  TrainingFlow,
  EvaluationResult,
} from '../../../shared/types-training';
//      ↑ 3 层,指向 src/renderer/shared/types-training.ts (真实)
```

**为什么必须改**: `src/renderer/shared/types-training.ts` 是 training.store 真实消费的类型,有 `flowType?: 'flow5' | 'legacy'` 字段;`src/shared/types/types-training.ts` 缺该字段(详见 D-073 / 项目记忆 "ActiveTrainingSession 在两处定义")。混用会导致 typecheck 报 "has or is using private name"。

**store import 路径**(FlowPanel.tsx 唯一需要):
```tsx
// 原: import { useTrainingStore } from '../../../stores/training.store';
// 新: import { useTrainingStore } from '../../../stores/training.store';
// (路径相同,3 层)
```

---

## 5. 依赖图与执行顺序

```
读取 archived 7 文件(只读)
  ↓
建目录 src/renderer/components/training/flow/
  ↓
复制 + 转换 flow.module.css (1 个)
  ↓
复制 + 转换 5 步骤子组件 + FlowStepIndicator (6 个 .tsx,叶子优先)
  ↓
复制 + 转换 FlowPanel.tsx (1 个 .tsx,依赖子组件)
  ↓
复制 + 改造 __tests__/FlowPanel.test.tsx (1 个)
  ↓
建 README.md
  ↓
改 archived ActiveTrainingView.tsx 2 处 import
  ↓
跑 typecheck + test + lint (R-027 门禁)
  ↓
git add + commit
  ↓
更新 D-073 子条目 + decision-log.md
```

**无并行** — 7 文件相互依赖(FlowPanel 引用 5 Step + FlowStepIndicator),严格串行。

---

## 6. DoD 验证清单

1. ✅ 新建目录 `src/renderer/components/training/flow/` 存在
2. ✅ 7 .tsx 文件 + 1 共享 `flow.module.css` + 1 测试 + 1 README = **10 文件**全部到位
3. ✅ `FlowPanel.tsx` 顶部 JSDoc 注明"迁移自 components_archived/training/flow/FiveStepFlow.tsx (Sprint 25 BL-01 C-3)"
4. ✅ 7 .tsx 文件类型 import 全部走 `src/renderer/shared/types-training.ts`
5. ✅ 7 .tsx 文件 className 全部使用 `styles.xxx`,无 BEM 全局类名
6. ✅ `archived/ActiveTrainingView.tsx` 改 2 处(import + JSX 标签名),其他不改
7. ✅ `npm run typecheck` 0 errors
8. ✅ `npm test -- FlowPanel` 9 用例全绿(从 archived 原 9 个)
9. ✅ `npm run lint --max-warnings 300` 0 errors
10. ✅ 单文件 ≤ 300 行(R-019) — FlowPanel 预估 ~140 行(最重)
11. ✅ `grep -n "five-step-flow\|flow-panel\|flow-step--" src/renderer/components/training/flow/` 0 命中(全局类名已清除)
12. ✅ `grep -n "from '.*shared/types/types-training'" src/renderer/components/training/flow/` 0 命中(stale 类型不再引用)
13. ✅ 决策日志:D-073 追加"C-3 UI 迁移完成"子条目

---

## 7. 风险与缓解

| # | 风险 | 影响 | 缓解 |
|:-:|:-----|:-----|:-----|
| 1 | **类型混用**:`shared/types/types-training` vs `renderer/shared/types-training` 字段差异 | typecheck 失败 / store 类型不匹配 | 强制所有 7 .tsx 走 `renderer/shared/types-training`,grep 验证 |
| 2 | **CSS Modules 漏转**:某个 className 忘加 `styles.` | 样式失效 | 转换表核对 + grep `flow-panel\|flow-step--` 0 命中 |
| 3 | **archived 父组件引用断裂**:改 FlowPanel 名字后 archived ActiveTrainingView 未同步改 | 白屏 | §2.2 第 26 行 + 63-69 行两处同步改 |
| 4 | **测试路径错位**:vi.mock 路径未跟着改 | 测试失败 | `vi.mock('../../../stores/training.store', ...)` 路径核对(原 2 层 → 新 3 层) |
| 5 | **R-020 循环依赖**:FlowPanel 反向 import archived 任何文件 | 编译失败 | 严格单向:archived 引用 V6.2,V6.2 不引用 archived |

---

## 8. Commit 与文档

**Commit 标题**: `feat(training-ui): 迁移 archived 5 步组件到 V6.2 (FlowPanel)`

**Commit body**:
```
- 7 个 .tsx + 1 共享 CSS + 9 测试迁移到 src/renderer/components/training/flow/
- 编排组件 FiveStepFlow 重命名为 FlowPanel
- 类型 import 切到 src/renderer/shared/types-training.ts (避免与 store 类型冲突)
- BEM 全局类名 → CSS Modules styles.xxx 访问 (R-019)
- archived/ActiveTrainingView.tsx 改 1 行 import 指向 FlowPanel
- 行为零变更,9 测试断言全部保持

Closes BL-01 (Sprint 25 §C-3)
```

**决策日志**(D-073 追加):
```markdown
#### C-3: UI 迁移 5 步组件到 V6.2

- **类型**: 重构(零行为变更) + 命名收敛
- **背景**: C-1 完成 R-014 配置外置后,UI 层仍位于 `components_archived/training/flow/`,V6.2 无 FlowPanel 消费 `flowType='flow5'`
- **方案**:
  - 7 .tsx + 1 共享 CSS + 1 测试 → `src/renderer/components/training/flow/`
  - 编排组件 `FiveStepFlow` → `FlowPanel`(对齐计划 DoD-1)
  - BEM 全局类名 → CSS Modules(R-019)
  - 类型 import 切到 `src/renderer/shared/types-training.ts`(避免 stale 类型与 store 冲突)
  - archived 父组件 `ActiveTrainingView` 改 1 行 import,保留作为历史快照
- **DoD 验证**:
  1. ✅ 10 文件到位(7 tsx + 1 css + 1 test + 1 readme)
  2. ✅ 9 测试全绿(行为零变更)
  3. ✅ typecheck + lint 0 errors
  4. ✅ R-019 硬上限满足(单文件 ≤ 300 行)
  5. ✅ grep 全局类名 0 命中
```

---

## 9. 时间盒与产出

| 步骤 | 工时 |
|:-----|:----:|
| 目录建立 + 共享 CSS 转换 | 0.2 人天 |
| 6 子组件 .tsx 转换(StepExplain/Example/Confirm/Practice/Feedback + FlowStepIndicator) | 0.3 人天 |
| FlowPanel.tsx 编排组件转换 | 0.2 人天 |
| 测试文件迁移 + 路径调整 | 0.1 人天 |
| archived ActiveTrainingView import 调整 | 0.05 人天 |
| 门禁验证(typecheck + test + lint) | 0.1 人天 |
| 决策日志 D-073 子条目 | 0.05 人天 |
| **合计** | **1.0 人天**(对齐计划 §6 预算) |

---

## 10. 关联文档

- **D-073** Sprint 25 BL-01 主条目(C-1 + C-3 + C-4,本任务追加 C-3 子条目)
- **bl-01-sprint-25-five-step-flow-integration.md** 总计划文件 §2.2
- **R-010** 最小化范围(archived 不重构,只迁移)
- **R-019** 代码规范(单文件 ≤ 300 行,CSS Modules)
- **R-020** 循环依赖(archived 单向引用 V6.2)
- **R-027** AI 代码质量门禁(完成前必须 typecheck + test + lint 全绿)
- **BL-01** Backlog 条目(本任务编号)
- **C-1** 决策记录(`flow-mapping.loader.ts` + `technique-library.loader.ts` 已落)

---

**状态**: 已就绪
**审批人**: 用户(已通过 AskUserQuestion 确认 3 个设计决策)
**开始执行条件**: 用户回复"开始"或"批准"
