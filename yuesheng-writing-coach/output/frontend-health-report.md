---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: f2ac1166b9bdaea71c23aabee181e425_b061705f688c11f1a0095254002afed2
    ReservedCode1: QBY5GEIpqaG8VQRbKCmvBLV5/PWsEKGfVP/UaxwQyrad8Nj0dP+VJfJFPJ8W9y8qtiYSLzhoLHtoWeJ+ITdaQ/w/d/9kIDyszdrO07O6DwkGzg57Hj4teXGCHcL1zNzrHkEn+mBQhmLhGXVqQpWtqGFC6DVVzYkZ2uFG2vrt7VjT4cUL46mR6DUUfjw=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: f2ac1166b9bdaea71c23aabee181e425_b061705f688c11f1a0095254002afed2
    ReservedCode2: QBY5GEIpqaG8VQRbKCmvBLV5/PWsEKGfVP/UaxwQyrad8Nj0dP+VJfJFPJ8W9y8qtiYSLzhoLHtoWeJ+ITdaQ/w/d/9kIDyszdrO07O6DwkGzg57Hj4teXGCHcL1zNzrHkEn+mBQhmLhGXVqQpWtqGFC6DVVzYkZ2uFG2vrt7VjT4cUL46mR6DUUfjw=
---

# 前端渲染层健康诊断报告

> **诊断范围**: `src/renderer` (117 文件 / ~15,000 行)
> **诊断日期**: 2026-06-15
> **严重度分级**: P0 (立即修复) / P1 (本迭代修复) / P2 (技术债跟踪)

---

## 一、总览摘要

| 维度 | 问题总数 | P0 | P1 | P2 | 最高风险点 |
|------|---------|-----|-----|-----|-----------|
| 接口定义不清 | 32 | 32 | 0 | 0 | 12 个 FC 组件无泛型参数 |
| 错误处理 | 55 | 17 | 38 | 0 | 17 个空 catch 块吞没错误 |
| 耦合拓扑 | 19 文件 | 3 | 16 | 0 | App.tsx 直接导入 6 store + 9 处 getState() |
| 类型安全 | 114 | 0 | 95 | 19 | 64 处 `as` 类型断言 |
| CSS 内联泛滥 | 47 文件 | 0 | 47 | 0 | DiagnosisPanel 39 处内联 style |
| 性能隐患 | 510 | 0 | 510 | 0 | 427 处内联对象字面量 props |
| 格式混乱 | 134 | 0 | 30 | 104 | 魔法数字 + 硬编码色值遍布 |
| 内容溢出风险 | 15 | 0 | 0 | 15 | 固定尺寸容器无 overflow |
| 可访问性 | 14 | 0 | 0 | 14 | 11 个 input 无 label 关联 |

---

## 二、逐维度详析

### 2.1 接口定义不清 [P0] — 32 处

组件 Props 未显式声明类型、导出函数缺少返回类型注解，直接影响 IDE 智能提示和编译期类型检查。

#### 2.1.1 React.FC 无泛型参数 (12 处)

`React.FC` 未传入 Props 类型参数，组件接收隐式 `{}` 或 `any` props。

| 文件 | 行号 | 声明 |
|------|------|------|
| `components\chat\MessageBubble.tsx` | 26 | `const CoachAvatar: React.FC = () =>` |
| `components\chat\MessageBubble.tsx` | 47 | `const UserAvatar: React.FC = () =>` |
| `components\chat\WelcomeCard.tsx` | 10 | `export const WelcomeCard: React.FC = () =>` |
| `components\editor\ChapterEditor.tsx` | 17 | `export const ChapterEditor: React.FC = () =>` |
| `components\growth\DiagnosisComparisonView.tsx` | 39 | `export const DiagnosisComparisonView: React.FC = () =>` |
| `components\growth\GrowthPanel.tsx` | 32 | `export const GrowthPanel: React.FC = () =>` |
| `components\layout\DiagnosisPanel.tsx` | 281 | `export const DiagnosisPanel: React.FC = () =>` |
| `components\layout\HintPanel.tsx` | 176 | `export const HintPanel: React.FC = () =>` |
| `components\layout\ModeSwitch.tsx` | 12 | `export const ModeSwitch: React.FC = () =>` |
| `components\layout\SoloSidebar.tsx` | 31 | `export const SoloSidebar: React.FC = () =>` |
| `components\manuscript\EmptyEditorState.tsx` | 5 | `export const EmptyEditorState: React.FC = () =>` |
| `components\manuscript\SettingsPopover.tsx` | 8 | `export const SettingsPopover: React.FC = () =>` |

#### 2.1.2 导出函数缺少返回类型 (9 处)

| 文件 | 行号 | 函数 |
|------|------|------|
| `hooks\useDiagnosisFlow.ts` | 42 | `function useDiagnosisFlow` — 核心编排 Hook |
| `stores\training.actions.ts` | 37 | `createStartAction` |
| `stores\training.actions.ts` | 105 | `createStartReadingAction` |
| `stores\training.actions.ts` | 162 | `createSubmitStepAction` |
| `stores\training.actions.ts` | 312 | `createLoadHistoryAction` |
| `stores\training.actions.ts` | 334 | `createRefreshFromDiagnosisAction` |
| `stores\training.actions.ts` | 430 | `createEvaluateTrainingAction` |
| `stores\training.actions.ts` | 459 | `createDeriveBehaviorAction` |
| `components\onboarding\OnboardingFlow.tsx` | 29 | `function OnboardingFlow` |

**典型代码片段** (`training.actions.ts:37`):
```typescript
export function createStartAction(
  set: (partial: Partial<TrainingState>) => void,
  get: () => TrainingState
) {  // 缺少返回类型注解
```

---

### 2.2 错误处理 [P0] — 55 处

#### 2.2.1 空 catch 块 (17 处) — P0

静默吞没所有异常，线上故障完全不可追踪，属于生产级阻断项。

| 文件 | 行号 | 上下文 |
|------|------|--------|
| `hooks\useDiagnosisFlow.ts` | 60 | `} catch {` — IPCall 失败静默 |
| `hooks\useDiagnosisFlow.ts` | 119 | `} catch {` — 诊断结果获取失败静默 |
| `stores\chapter.store.ts` | 107 | `} catch {` — 加载章节失败静默 |
| `stores\chapter.store.ts` | 222 | `} catch {` — 保存章节失败静默 |
| `stores\chat.store.ts` | 61,71,78 | 3 处 `} catch { /* ignore */ }` |
| `stores\config.store.ts` | 82 | `} catch {` — 配置持久化失败 |
| `stores\paradigm.store.ts` | 45,67 | 2 处 `} catch { /* ignore */ }` |
| `App.tsx` | 72 | `} catch { /* IPC 失败时静默 */ }` |
| `components\diagnosis\OriginalEvidenceSection.tsx` | 69 | `} catch {` |
| `components\layout\DiagnosisPanel.tsx` | 188 | `} catch {` |
| `components\layout\SoloSidebar.tsx` | 63,70 | 2 处 `} catch { /* ignore */ }` |
| `components\onboarding\OnboardingFlow.tsx` | 63 | `} catch {` |
| `components\search\SearchPanel.tsx` | 51 | `} catch {` |

**建议修复**: 每个空 catch 至少添加 `console.error('[ModuleName] 操作描述:', e)`；关键路径（store 持久化、IPC 通信）应触发用户可见的错误提示。

#### 2.2.2 async 函数无 try-catch (38 处) — P1

38 个 async 函数/回调内部无任何 try-catch 保护。部分位于 `useCallback` 包裹的 handler 中，依赖调用方兜底，缺乏自包含的错误隔离。

**重点文件**:
- `stores\__tests__\training.store.test.ts` — 14 处（测试代码，风险低）
- `stores\config.store.ts` — 6 处
- `components\layout\WorkTreePanel.tsx` — 6 处（handleCopyRef、handleDeleteChapter 等关键操作）
- `App.tsx` — 4 处（handleSendMessage、handleOnboardingComplete 等）

#### 2.2.3 ErrorBoundary 覆盖不足 — P1

整个渲染层仅有 1 个 ErrorBoundary (`components\layout\AppErrorBoundary.tsx`)，位于 App 根节点。任意子组件未捕获异常将导致整个应用白屏。缺少路由级/面板级的 ErrorBoundary 隔离。

---

### 2.3 耦合拓扑 [P0] — 架构级问题

#### 2.3.1 Store→组件依赖图 (ASCII Art)

```
                        ┌─────────────────────────────────────┐
                        │            App.tsx (124L)            │
                        │  直接导入 6 个 store                  │
                        │  9 处 getState() 跨模块调用          │
                        │  22 props → ChatView                 │
                        │  19 props → TrainingWorkshop         │
                        └──┬──┬──┬──┬──┬──┬──────────────────┘
                           │  │  │  │  │  │
              ┌────────────┼──┼──┼──┼──┼──┼──────────────────┐
              ▼            ▼  ▼  ▼  ▼  ▼  ▼                  ▼
    ┌─────────────────┐  ┌──────────────────────────────────────┐
    │  config.store   │  │         stores (6 个)                 │
    │  chat.store     │  │  chat / config / diag / session      │
    │  diag.store     │  │  student-context / training          │
    │  session.store  │  └──────────────────────────────────────┘
    │  student-ctx.st.│
    │  training.store │
    └────────┬────────┘
             │
    ┌────────┴────────────────────────────────────────────────┐
    │                  直接消费者 (19 文件)                      │
    │                                                         │
    │  ChatView ──────── useChatStore                          │
    │  WorkTreePanel ─── useChapterStore.getState() [10 处!]   │
    │                    useManuscriptStore.getState()         │
    │  DiagnosisPanel ── useDiagStore + getState()             │
    │  ManuscriptPanel ─ useChapterStore.getState() [2 处]     │
    │  SoloSidebar ───── useSessionStore.getState()            │
    │  ChapterEditor ─── useParadigmStore/useManuscriptStore   │
    │                    useChapterStore                       │
    │  TrainingWorkshop ─ useTrainingStore (通过 App.tsx props)│
    │  ... (其余 12 文件)                                      │
    └─────────────────────────────────────────────────────────┘
```

#### 2.3.2 关键反模式

**A. App.tsx 为"上帝组件"** (P0)
- 行 19-24：直接 import 6 个 store hook 和 2 个 service
- 行 28：9 处跨 store `getState()` 调用（`useConfigStore.getState()`、`useStudentContextStore.getState()` 等）
- 行 113-114：ChatView 接收 22 个 props，TrainingWorkshop 接收 19 个 props
- 本应作为纯编排层，实际承担了数据聚合和跨模块协调的职责

**B. WorkTreePanel 跨 store getState() 滥用** (P0)
- 共 10 处 `getState()` 调用，直接访问 `useChapterStore` 和 `useManuscriptStore`
- 行 129: `useChapterStore.getState().deleteChapter(...)`
- 行 135: `useManuscriptStore.getState().remove(msId)`
- 行 207,268,352: 多个内联 `onClick={async () => { ... getState() ... }}`
- 违反单向数据流，store 状态变更无法触发组件重渲染

**C. ChatView 和 TrainingWorkshop Props 爆炸** (P1)
- `ChatViewProps` (行 28-53): 22 个字段，其中 10 个为回调函数
- `TrainingWorkshopProps` (行 24-53): 19 个字段
- 任何 store 新增字段都需要级联修改 App.tsx 和子组件 Props 接口

#### 2.3.3 疑似死代码 (P2)

| 文件 | 导出 | 状态 |
|------|------|------|
| `components\editor\ChapterEditor.tsx` | `ChapterEditor` | 全局无 import 引用 |
| `components\layout\HintPanel.tsx` | `HintPanel` | 全局无 import 引用 |
| `plugins\cjs-to-esm-fix.ts` | `cjsToEsmFix` | 全局无 import 引用 |
| `services\session.service.ts` | `sessionService` | 全局无 import 引用 |
| `services\student-context.service.ts` | `studentContextService` | 全局无 import 引用 |
| `services\training.service.ts` | `trainingService` | 全局无 import 引用 |

---

### 2.4 类型安全 [P1] — 114 处

#### 2.4.1 `any` 类型使用 (31 处)

| 文件 | 数量 | 风险 |
|------|------|------|
| `stores\__tests__\training.store.test.ts` | 26 | 低（测试代码） |
| `stores\training.actions.ts` | 2 | **中**: L316 `as { error?: string; records?: any[] }`, L320 `(r: any)` |
| `types\electron.d.ts` | 1 | 低（类型声明） |
| `utils\ipc.ts` | 1 | 低 |
| `components\layout\AppConfigGate.tsx` | 1 | **中**: L12 `onOnboardingComplete: (baseline: any) => Promise<void>` |

**典型代码片段** (`training.actions.ts:316-320`):
```typescript
const result = await getInvoke()(TrainingApi.history.channel, { sessionId })
  as { error?: string; records?: any[] };
const records: TrainingRecord[] = (result.records ?? []).map((r: any) => ({
```

#### 2.4.2 类型断言 `as` (64 处 / 28 文件)

| 文件 | 数量 |
|------|------|
| `services\right-panel.service.ts` | 8 |
| `services\app-controller.ts` | 4 |
| `stores\student-context.store.ts` | 4 |
| `stores\training.actions.ts` | 4 |
| `components\chat\MessageInput.tsx` | 4 |
| `components\growth\DiagnosisComparisonView.tsx` | 4 |
| `components\layout\SessionTabBar.tsx` | 4 |
| 其余 21 文件 | 1-3 各 |

`right-panel.service.ts` 以 8 处断言位居榜首，建议改用类型守卫函数替代硬断言。

#### 2.4.3 非空断言 `!` (19 处 / 4 文件)

| 文件 | 数量 |
|------|------|
| `stores\__tests__\training.store.test.ts` | 15 |
| `hooks\useDiagnosisFlow.ts` | 2 |
| `stores\chapter.store.ts` | 1 |
| `stores\session.store.ts` | 1 |

生产代码仅 4 处，整体可控。

---

### 2.5 CSS 内联泛滥 [P1] — 47 文件

47 个 TSX 文件使用内联 `style={{}}`，部分对象包含 12-16 个 CSS 属性，严重违反关注点分离。

#### 2.5.1 内联 style 使用量 Top 10

| 文件 | 行数 | 内联 style 数 | 密度 |
|------|------|-------------|------|
| `components\layout\DiagnosisPanel.tsx` | 349 | 39 | 每 9 行 1 处 |
| `components\profile\AbilityProfilePanel.tsx` | 207 | 39 | 每 5 行 1 处 |
| `components\growth\DiagnosisComparisonView.tsx` | 230 | 31 | 每 7 行 1 处 |
| `components\layout\HintPanel.tsx` | 232 | 28 | — (死代码) |
| `components\settings\SettingsPanel.tsx` | 326 | 27 | 每 12 行 1 处 |
| `components\training\BehaviorDerivationTool.tsx` | 227 | 24 | 每 9 行 1 处 |
| `components\growth\GrowthPanel.tsx` | 230 | 23 | 每 10 行 1 处 |
| `components\editor\ChapterEditor.tsx` | — | 16 | — (死代码) |
| `components\search\SearchPanel.tsx` | — | 15 | — |
| `components\tools\ToolsPanel.tsx` | — | 15 | — |

#### 2.5.2 超大 style 对象 (>5 属性)

| 文件 | 行号 | 属性数 |
|------|------|--------|
| `components\manuscript\ToolbarBtn.tsx` | 27 | 16 |
| `components\layout\SessionTabBar.tsx` | 81 | 15 |
| `components\settings\SettingsPanel.tsx` | 222 | 14 |
| `components\chat\MessageBubble.tsx` | 27 | 13 |
| `components\chat\MessageList.tsx` | 214 | 13 |
| `components\layout\DiagnosisPanel.tsx` | 61 | 13 |
| `components\layout\HintPanel.tsx` | 42 | 13 |
| `components\layout\HintPanel.tsx` | 96 | 13 |
| `components\layout\TemplateFormView.tsx` | 103 | 13 |
| `components\settings\SettingsPanel.tsx` | 275 | 13 |

#### 2.5.3 混用内联 style 与 CSS Modules

`components\chat\ChatView.tsx` 同时使用内联 `style={{}}` 和 `styles from './ChatView.module.css'`，风格不一致。

**建议**: 统一使用 CSS Modules，将 ≥5 属性的超大 style 对象提取为 CSS 类。

---

### 2.6 性能隐患 [P1] — 510 处

#### 2.6.1 内联对象字面量 props (427 处) — 每次渲染新建引用

| 文件 | 数量 | 典型模式 |
|------|------|----------|
| `components\layout\DiagnosisPanel.tsx` | 41 | `style={{...}}` |
| `components\profile\AbilityProfilePanel.tsx` | 39 | `style={{...}}` |
| `components\growth\DiagnosisComparisonView.tsx` | 34 | `style={{...}}` |
| `components\layout\HintPanel.tsx` | 30 | — (死代码) |
| `components\settings\SettingsPanel.tsx` | 28 | `style={{...}}` |
| `components\growth\GrowthPanel.tsx` | 27 | `style={{...}}` |

这些内联对象每次 render 创建新引用，即使值相同也会触发 `React.memo` 子组件重渲染。

#### 2.6.2 内联函数 props (63 处)

`App.tsx:113` 中 TrainingWorkshop 的 `onBackToChat` 为内联箭头函数:
```typescript
onBackToChat={() => { rightPanelService.close(); backToChat(); }}
```
导致 TrainingWorkshop 每次必重渲染。

#### 2.6.3 大组件无 useMemo/useCallback (20 个文件)

>100 行且无任何 `useMemo`/`useCallback` 的文件：

- `components\chat\ChatView.tsx` (251L)
- `components\chat\MessageBubble.tsx`
- `components\chat\MessageInput.tsx` (233L)
- `components\chat\MessageList.tsx` (260L)
- `components\diagnosis\DiagnosisCard.tsx`
- `components\diagnosis\EditPanel.tsx`
- `components\diagnosis\OriginalEvidenceSection.tsx`
- `components\diagnosis\SelfCheckList.tsx`
- `components\growth\DiagnosisComparisonView.tsx` (230L)
- `components\growth\GrowthPanel.tsx` (230L)
- `components\layout\DiagnosisPanel.tsx` (349L)
- `components\layout\HintPanel.tsx` (232L)
- `components\layout\SoloSidebar.tsx` (270L)
- `components\layout\ToolGrid.tsx` (203L)
- `components\manuscript\ManuscriptPanel.tsx` (420L)
- `components\profile\AbilityProfilePanel.tsx` (207L)
- `components\settings\SettingsPanel.tsx` (326L)
- `components\training\BehaviorDerivationTool.tsx` (227L)
- `components\training\RecommendationsSection.tsx` (261L)
- `components\training\ErrorCardsSection.tsx`

#### 2.6.4 大列表无虚拟滚动

以下文件包含 2+ 个 `.map()` 渲染列表，但未使用虚拟滚动:

- `components\diagnosis\BeatCheckChart.tsx` — 2 个 map
- `components\diagnosis\DiagnosisCard.tsx` — 2 个 map
- `components\growth\DiagnosisComparisonView.tsx` — 2 个 map
- `components\growth\GrowthPanel.tsx` — 2 个 map
- `components\layout\ToolGrid.tsx` — 3 个 map
- `components\manuscript\ManuscriptPanel.tsx` — 2 个 map
- `components\search\SearchPanel.tsx` — 2 个 map

---

### 2.7 格式混乱 [P1/P2] — 134 处

#### 2.7.1 魔法数字 [P2] — 遍布

width: 32, height: 32, gap: 10/12 等裸数字出现在内联 style 中，无语义变量名。

| 文件 | 行号 | 示例 |
|------|------|------|
| `components\chat\MessageBubble.tsx` | 28-29 | `width: 32, height: 32` |
| `components\chat\MessageInput.tsx` | 185-186 | `width: 32, height: 32` |
| `components\chat\WelcomeCard.tsx` | 22-24 | `width: 64, height: 64, borderRadius: 16` |
| `components\chat\WelcomeCard.tsx` | 30 | `fontSize: 28` |

#### 2.7.2 硬编码色值 [P2]

`color`、`backgroundColor` 等属性直接使用 `#xxxxxx` 字面量，缺少设计系统 Token。

#### 2.7.3 混用风格 [P1]

`components\chat\ChatView.tsx` 同时使用内联 style 和 `ChatView.module.css`，增加维护心智负担。

---

### 2.8 内容溢出风险 [P2] — 15 处

固定尺寸容器缺少 `overflow` 声明，长内容可能导致布局崩溃。

| 文件 | 行号 | 问题 |
|------|------|------|
| `App.tsx` | 116 | `<div style={{ position: 'relative', height: '100%' }}>` 无 overflow |
| `components\chat\WelcomeCard.tsx` | 17 | `height: '100%'` 无 overflow |
| `components\editor\ChapterEditor.tsx` | 85 | `height: '100%'` flex 容器无 overflow |
| `components\layout\AppErrorBoundary.tsx` | 37 | `height: '100vh'` 无 overflow |
| `components\layout\DiagnosisPanel.tsx` | 62,127,230 | 3 处 `width: '100%'` 无 overflow |
| `components\layout\HintPanel.tsx` | 43,97 | 2 处 `width: '100%'` 无 overflow |
| `components\layout\ResizeHandle.tsx` | 34 | `height: '100%'` 无 overflow |
| `components\settings\SettingsPanel.tsx` | 154,279 | 2 处 `width: '100%'` 无 overflow |
| `components\tools\ToolsPanel.tsx` | 46 | `width: '100%'` 无 overflow |
| `components\training\TrainingWorkshop.tsx` | 116 | `<div ... style={{ height: '100%' }}>` 无 overflow |

---

### 2.9 可访问性 [P2] — 14 处

#### 2.9.1 input 无 label 关联 (11 处)

| 文件 | 行号 |
|------|------|
| `components\chat\ChatSearchBar.tsx` | 29 |
| `components\diagnosis\SelfCheckList.tsx` | 43 |
| `components\layout\SessionList.tsx` | 105, 163 |
| `components\layout\TemplateFormView.tsx` | 82 |
| `components\layout\WorkTreePanel.tsx` | 2 处 |
| `components\search\SearchPanel.tsx` | 1 处 |
| `components\settings\SettingsPanel.tsx` | 2 处 |
| `components\training\ActiveTrainingView.tsx` | 1 处 |
| `components\training\BehaviorDerivationTool.tsx` | 1 处 |
| `components\training\EvaluationStepContent.tsx` | 1 处 |

#### 2.9.2 图标按钮无 aria-label (3 处)

| 文件 | 行号 | 按钮用途 |
|------|------|----------|
| `components\common\Button.tsx` | 60 | 通用按钮组件 |
| `components\training\ActiveTrainingView.tsx` | 103 | 跳过训练 |
| `components\training\EvaluationStepContent.tsx` | 84 | 发送到编辑器 |

---

## 三、修复优先级排序

### P0 — 立即修复 (阻断生产质量)

| 序号 | 项目 | 文件 | 预估工时 |
|------|------|------|----------|
| 1 | 空 catch 块添加错误日志 | 12 文件 / 17 处 | 2h |
| 2 | App.tsx 拆分 store 聚合逻辑，引入自定义 Hook | `App.tsx` | 4h |
| 3 | WorkTreePanel getState() 重构为 hook selector | `WorkTreePanel.tsx` | 3h |
| 4 | ChatView/TrainingWorkshop Props 精简，引入 Context 或组合模式 | `ChatView.tsx`, `TrainingWorkshop.tsx`, `App.tsx` | 6h |
| 5 | React.FC 补全泛型参数 | 12 文件 | 1h |
| 6 | 导出函数补全返回类型 | 3 文件 / 9 处 | 1.5h |

### P1 — 本迭代修复

| 序号 | 项目 | 文件 | 预估工时 |
|------|------|------|----------|
| 7 | async 函数加 try-catch (生产代码) | 6 文件 | 3h |
| 8 | 内联 style 迁移到 CSS Modules | DiagnosisPanel, AbilityProfilePanel 等 Top 10 | 8h |
| 9 | 内联对象/函数提取为 useMemo/useCallback | Top 10 文件 | 6h |
| 10 | `training.actions.ts` 消除 any 类型 | `stores\training.actions.ts` | 1h |
| 11 | 面板级 ErrorBoundary 添加 | 3-5 个面板 | 2h |
| 12 | `right-panel.service.ts` 类型守卫替代 as | `services\right-panel.service.ts` | 1h |

### P2 — 技术债跟踪

| 序号 | 项目 | 预估工时 |
|------|------|----------|
| 13 | 魔法数字提取为设计 Token 常量 | 4h |
| 14 | 硬编码色值迁移到 CSS 变量 | 3h |
| 15 | 固定尺寸容器添加 overflow: auto | 1h |
| 16 | input 添加 aria-label / htmlFor-label 关联 | 2h |
| 17 | 图标按钮添加 aria-label | 0.5h |
| 18 | 虚拟滚动引入 (react-window) | 4h |
| 19 | 删除死代码文件 (6 个) | 0.5h |

---

## 四、修复路线图建议

```
Week 1 (P0):  ████████████████  17h
  Day 1-2: 错误处理修复 (空 catch + ErrorBoundary)
  Day 3-4: 接口类型补全 (FC 泛型 + 返回类型)
  Day 4-5: App.tsx 拆分 + WorkTreePanel 重构

Week 2 (P1):  ██████████████████  21h
  Day 1-3: CSS 内联迁移 (Top 5 文件)
  Day 3-5: 性能优化 (useMemo/useCallback + 内联对象提取)
  Day 5:   any 类型消除 + 类型守卫

Week 3 (P2):  ██████████  15h
  设计 Token 化 + 可访问性 + 虚拟滚动 + 清理死代码
```

---

> **报告生成**: 基于自动化扫描（正则模式匹配 + AST 级别统计）+ 人工对关键文件的手动审查。
> **数据截止**: 2026-06-15，117 文件 / ~15,000 行代码。
*（内容由AI生成，仅供参考）*
