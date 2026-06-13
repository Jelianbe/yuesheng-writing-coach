# 月笙写作教练 — 渲染进程模块耦合分析报告

> 分析日期：2026-06-13  
> 分析范围：`src/renderer/` 下 stores、hooks、components + `src/shared/constants.ts`

---

## 一、耦合清单

### 1.1 App.tsx（God Component）→ 各模块

| 源模块 | 目标模块 | 耦合方式 | 文件:行号 | 严重度 |
|--------|----------|----------|-----------|--------|
| App.tsx | config.store | `useConfigStore()` hook import + `getState()` | App.tsx:20, :142 | P0 |
| App.tsx | diag.store | `useDiagStore()` hook import | App.tsx:22, :32 | P0 |
| App.tsx | chat.store | `useChatStore()` hook import + `getState()` | App.tsx:23, :66, :118, :131, :132 | P0 |
| App.tsx | session.store | `useSessionStore()` hook import + `getState()` | App.tsx:24, :47 | P0 |
| App.tsx | student-context.store | `useStudentContextStore()` hook import + `getState()` | App.tsx:25, :48 | P0 |
| App.tsx | training.store | `useTrainingStore()` hook import + `getState()` | App.tsx:26, :193 | P0 |
| App.tsx | right-panel.actions | `rightPanelActions` direct import | App.tsx:27 | P0 |
| App.tsx | useDiagnosisFlow | hook import (7 state/action destructured) | App.tsx:18, :36 | P1 |
| App.tsx | useAppIpcListener | hook import | App.tsx:19, :39 | P1 |
| App.tsx | IPC_CHANNELS | direct import from `../shared/constants` | App.tsx:21, :51, :68, :97, :113 | P1 |

### 1.2 Store → Store 跨模块 getState() 调用

| 源模块 | 目标模块 | 耦合方式 | 文件:行号 | 严重度 |
|--------|----------|----------|-----------|--------|
| chat.store | session.store | `useSessionStore.getState().currentSessionId` | chat.store.ts:177 | P0 |
| chat.store | session.store | `useSessionStore.getState()` + `switchSession()` | chat.store.ts:179-183 | P0 |
| chat.store | session.store | `sessionStore.createSession()` | chat.store.ts:186-191 | P0 |
| chat.store | config.store | `useConfigStore.getState().attitudeLevel` | chat.store.ts:209 | P1 |
| chat.store | student-context.store | `useStudentContextStore.getState().toJSON()` | chat.store.ts:210 | P1 |
| training.actions.ts | chat.store | `useChatStore.getState().currentSessionId` | training.actions.ts:39 | P1 |
| training.actions.ts | chat.store | `useChatStore.getState().addMessage()` | training.actions.ts:153 | P1 |
| training.actions.ts | diag.store | `useDiagStore.getState().getHistoryBySession()` | training.actions.ts:186 | P1 |
| training.actions.ts | chat.store | `useChatStore.getState().currentSessionId` | training.actions.ts:243 | P1 |
| training.actions.ts | chat.store | `useChatStore.getState().currentSessionId` | training.actions.ts:290 | P1 |
| training.store | chat.store | `dynamic import('./chat.store')` → `getState()` | training.store.ts:37 | P1 |
| training.store | chapter.store | `dynamic import('./chapter.store')` → `setState()` | training.store.ts:99 | P1 |
| right-panel.actions | drawer.store | `useDrawerStore.getState().openPanel()` | right-panel.actions.ts:40, :60, :75, :91, :94, :103, :108 | P2 |
| right-panel.actions | panel-session.store | `usePanelSessionStore.getState().upsertSession()` | right-panel.actions.ts:41 | P2 |
| right-panel.actions | panel-session.store | `usePanelSessionStore.getState().sessions` | right-panel.actions.ts:91, :98, :101 | P2 |
| right-panel.actions | chapter.store | `useChapterStore.getState().openTab()` | right-panel.actions.ts:53 | P2 |
| right-panel.actions | panel-session.store | `usePanelSessionStore.getState().switchSession()` | right-panel.actions.ts:90 | P2 |
| right-panel.actions | panel-session.store | `usePanelSessionStore.getState().removeSession()` | right-panel.actions.ts:101 | P2 |

### 1.3 hooks → Store 跨模块依赖

| 源模块 | 目标模块 | 耦合方式 | 文件:行号 | 严重度 |
|--------|----------|----------|-----------|--------|
| useAppIpcListener | diag.store | `useDiagStore.getState()` — setCurrentDiagnosis, addToHistory | useAppIpcListener.ts:31-34 | P0 |
| useAppIpcListener | student-context.store | `useStudentContextStore.getState().updateFromDiagnosis()` | useAppIpcListener.ts:36 | P0 |
| useAppIpcListener | training.store | `useTrainingStore.getState().refreshFromDiagnosis()` | useAppIpcListener.ts:37 | P0 |
| useAppIpcListener | chat.store | `useChatStore.getState().appendToLastAssistant()` | useAppIpcListener.ts:43 | P1 |
| useAppIpcListener | chat.store | `useChatStore.getState()` — setLoading, setError, abortStream | useAppIpcListener.ts:48-52 | P1 |
| useAppIpcListener | student-context.store | `useStudentContextStore.getState().updateFromInteraction()` | useAppIpcListener.ts:56 | P1 |
| useAppIpcListener | teaching-state.store | `useTeachingStateStore.getState().setCurrentState()` | useAppIpcListener.ts:63-65 | P1 |
| useDiagnosisFlow | IPC_CHANNELS | direct import | useDiagnosisFlow.ts:3 | P2 |
| useDiagnosisFlow | shared/types | type imports only (no store coupling) | useDiagnosisFlow.ts:4 | — |

### 1.4 Components → Store 直接操作案例

| 源模块 | 目标模块 | 耦合方式 | 文件:行号 | 严重度 |
|--------|----------|----------|-----------|--------|
| ChatView | chat.store | `useChatStore()` — onboardingActive, onboardingStep, completeOnboarding, skipOnboarding, setOnboardingStep | ChatView.tsx:21, :136 | P1 |
| ChatView | IPC_CHANNELS | direct import (bypassing store) | ChatView.tsx:20 | P1 |
| SoloSidebar | ui-layout.store | `useUiLayoutStore()` — 5 selectors | SoloSidebar.tsx:12-15 | P1 |
| SoloSidebar | session.store | `useSessionStore()` — 6 selectors | SoloSidebar.tsx:13, :46-51 | P1 |
| SoloSidebar | chapter.store | `useChapterStore()` — 3 selectors | SoloSidebar.tsx:14, :57-60 | P1 |
| SoloSidebar | manuscript.store | `useManuscriptStore()` — 3 selectors | SoloSidebar.tsx:15, :53-55 | P1 |
| ManuscriptPanel | chapter.store | `useChapterStore()` — 5 selectors | ManuscriptPanel.tsx:33-39 | P2 |
| ManuscriptPanel | editor.store | `useEditorStore()` — 5 selectors | ManuscriptPanel.tsx:34, :41-45 | P2 |
| WorkTreePanel | chapter.store | `useChapterStore` import + `getState().deleteChapter()` | WorkTreePanel.tsx:10, :126 | P2 |
| WorkTreePanel | chapter.store | `useChapterStore` import + `getState().createChapter()` | WorkTreePanel.tsx:10, :229 | P2 |
| WorkTreePanel | chapter.store | `useChapterStore` import + `getState().error` | WorkTreePanel.tsx:10, :236 | P2 |
| WorkTreePanel | manuscript.store | `useManuscriptStore` import + `getState().remove()` | WorkTreePanel.tsx:11, :131 | P2 |
| WorkTreePanel | manuscript.store | `useManuscriptStore` import + `getState().create()` | WorkTreePanel.tsx:11, :295 | P2 |
| WorkTreePanel | manuscript.store | `useManuscriptStore` import + `getState().error` | WorkTreePanel.tsx:11, :297 | P2 |
| WorkTreePanel | right-panel.actions | direct import | WorkTreePanel.tsx:12 | P2 |
| RightDrawer | drawer.store | `useDrawerStore()` — 3 selectors | RightDrawer.tsx:28-30 | P2 |
| RightDrawer | panel-session.store | `usePanelSessionStore()` — 2 selectors | RightDrawer.tsx:31-32 | P2 |
| RightDrawer | right-panel.actions | direct import | RightDrawer.tsx:29 | P2 |

### 1.5 IPC 通道引用（已有 API 层雏形）

`src/shared/constants.ts` 已定义完整的 IPC 通道命名空间（`IPC_CHANNELS`），按领域划分为：

| 领域 | 通道数 | 示例 |
|------|--------|------|
| config | 3 | `config:get`, `config:set`, `config:testConnection` |
| diagnosis | 4 | `diagnosis:update`, `diagnosis:query`, `diagnosis:submitRewrite`, `diagnosis:getComparison` |
| growth | 2 | `growth:getTrends`, `growth:getGlobalTrends` |
| teachingState | 6 | `teachingState:get`, `teachingState:update`, etc. |
| ability | 1 | `ability:getProfile` |
| evidence | 5 | `evidence:getByDisease`, etc. |
| training | 8 | `training:recommend`, `training:assign`, etc. |
| chat | 4 | `chat:send`, `chat:stop`, `chat:stream:data`, `chat:stream:end` |
| session | 8 | `session:list`, `session:create`, etc. |
| manuscript/chapter | 10 | `manuscript:list`, `chapter:create`, etc. |

**现状评估**：IPC 通道已按领域命名空间良好组织，具备 `ALLOWED_INVOKE_CHANNELS` 和 `ALLOWED_EVENT_CHANNELS` 白名单机制。但 **渲染进程中大量跨 store 的 getState() 调用与 IPC 调用混杂在一起**，未形成统一的"服务层"抽象。

---

## 二、Top 5 最严重的耦合点

### #1 App.tsx — God Component 综合症（P0）

**位置**：`src/renderer/App.tsx`

App.tsx 直接 import 了 **6 个 store、2 个 hook、rightPanelActions、IPC_CHANNELS**，组件内部有 **10+ 处 `.getState()` 跨 store 调用**：

```typescript
// App.tsx:20-27 — 6 个 store 的直接 hook import
import { useConfigStore } from './stores/config.store';
import { useDiagStore } from './stores/diag.store';
import { useChatStore } from './stores/chat.store';
import { useSessionStore } from './stores/session.store';
import { useStudentContextStore } from './stores/student-context.store';
import { useTrainingStore } from './stores/training.store';

// App.tsx:47 — useSessionStore.getState() 在 useEffect 中
const st = useSessionStore.getState(); if (st.sessions.length === 0)...

// App.tsx:66 — useChatStore.getState() 
const { clearMessages, setMessages, setLoading } = useChatStore.getState();

// App.tsx:118 — useChatStore.getState().abortStream()
// App.tsx:131 — useChatStore.getState().setLoading()
// App.tsx:142 — useConfigStore.getState().testConnection()
// App.tsx:193 — useTrainingStore.getState().startTraining()
```

**影响**：App.tsx 无法独立测试，任何 store 的接口变更都会影响 App。组件承担了"编排器"角色而非纯展示。

### #2 chat.store → 3 个外部 Store 的紧耦合（P0）

**位置**：`src/renderer/stores/chat.store.ts:177-210`

`sendMessage` action 是跨 store 调用的重灾区，在单个 action 内直接读取并操作 3 个外部 store：

```typescript
// chat.store.ts:177 — 直接读 session store
let sessionId = useSessionStore.getState().currentSessionId;

// chat.store.ts:179-183 — 直接调 session store 的 switchSession
sessionStore.switchSession(sessionStore.sessions[0].id);

// chat.store.ts:186-191 — 直接调 session store 的 createSession
const newSession = await sessionStore.createSession();

// chat.store.ts:209 — 直接读 config store
const attitudeLevel = useConfigStore.getState().attitudeLevel;

// chat.store.ts:210 — 直接读 student-context store
const studentContext = useStudentContextStore.getState().toJSON();
```

**影响**：chat.store 无法脱离 session/config/student-context 单独测试，形成"巨石 store"趋势。

### #3 useAppIpcListener — 5 个 Store 的蜘蛛网耦合（P0）

**位置**：`src/renderer/hooks/useAppIpcListener.ts:28-65`

单个 hook 通过 IPC 事件回调直接操作 5 个不同的 store：

```typescript
// useAppIpcListener.ts:31-37 — DIAGNOSIS_UPDATE 事件 → 3 个 store
const { setCurrentDiagnosis, addToHistory } = useDiagStore.getState();
setCurrentDiagnosis(entry);
addToHistory(entry.sessionId, entry);
useStudentContextStore.getState().updateFromDiagnosis(entry.syndromes);
useTrainingStore.getState().refreshFromDiagnosis();

// useAppIpcListener.ts:43 — CHAT_STREAM_DATA → chat.store
useChatStore.getState().appendToLastAssistant(chunk);

// useAppIpcListener.ts:48-56 — CHAT_STREAM_END → chat + student-context
useChatStore.getState().setLoading(false);
useStudentContextStore.getState().updateFromInteraction('partial');

// useAppIpcListener.ts:63-65 — TEACHING_STATE_UPDATED → teaching-state.store
useTeachingStateStore.getState().setCurrentState(rest);
```

**影响**：IPC 事件监听器成了"隐式编排器"，任何事件处理的修改都可能波及其余 4 个 store。

### #4 training.actions.ts — 跨域读取 chat + diag store（P1）

**位置**：`src/renderer/stores/training.actions.ts:39, :153, :186, :243, :290`

训练模块的核心 actions 在 5 处直接依赖 chat.store 和 diag.store：

```typescript
// training.actions.ts:39 — startTraining 需要 sessionId
const sessionId = useChatStore.getState().currentSessionId;

// training.actions.ts:153 — submitStep 完成后向 chat 插入消息
const { addMessage } = useChatStore.getState();
addMessage({ id: ..., role: 'assistant', content: ... });

// training.actions.ts:186 — refreshFromDiagnosis 直接读 diag store
const diagHistory = useDiagStore.getState().getHistoryBySession(sessionId);

// training.actions.ts:243, :290 — evaluateTraining / deriveBehavior
const sessionId = useChatStore.getState().currentSessionId;
```

**影响**：训练模块无法独立部署，必须与 chat 和 diagnosis 模块共存。

### #5 training.store — 动态 import 其他 store（P1）

**位置**：`src/renderer/stores/training.store.ts:37, :99`

training.store 在 runtime 通过 `dynamic import()` 延迟加载其他 store，制造了难以静态分析的耦合：

```typescript
// training.store.ts:37 — enterWorkshop 动态加载 chat.store
const { useChatStore } = await import('./chat.store');
const sessionId = useChatStore.getState().currentSessionId;

// training.store.ts:99 — sendToEditor 动态加载 chapter.store
void import('./chapter.store').then(({ useChapterStore }) => {
  useChapterStore.setState({ pendingRewrite: activeTraining.userDraft });
});
```

**影响**：动态 import 绕过了 ES module 静态分析，耦合关系不可见于 import graph，增加了重构风险。且 `sendToEditor` 使用 `setState()` 直接修改外部 store 状态，是最脆弱的耦合形式。

---

## 三、每条耦合的严重度评级

### P0（阻断级 — 阻碍模块独立部署/测试/替换）

| 条目 | 原因 |
|------|------|
| App.tsx → 6 stores + 2 hooks | God Component，无法单独测试，任何 store 接口变更都影响 App |
| chat.store → session/config/student-context stores | sendMessage 内 5 处 getState() 跨 store 调用，无法独立测试 |
| useAppIpcListener → 5 stores | IPC 事件监听器中直接操作 5 个 store，形成隐式编排器 |
| App.tsx 内 store.getState() 调用链（10+ 处） | 绕过 React 生命周期，状态变更不可追踪 |

### P1（高风险 — 阻碍模块抽取/复用/重构）

| 条目 | 原因 |
|------|------|
| training.actions.ts → chat.store (3 处) | 训练 action 依赖 chat 的 sessionId 和消息写入能力 |
| training.actions.ts → diag.store (1 处) | train 数据刷新直接依赖 diag 历史数据 |
| training.store → chat.store (dynamic import) | 运行时动态加载其他 store，静态分析不可见 |
| training.store → chapter.store (dynamic import) | 跨模块 setState()，最脆弱的耦合形式 |
| ChatView → chat.store (onboarding state) | 组件绕过 props 直接读 store，props 接口不完整 |
| ChatView → IPC_CHANNELS (分页加载) | 组件内直接调用 IPC，应通过 store action 封装 |
| SoloSidebar → 4 stores (12+ selectors) | 组件同时读取 4 个 store，成为"小 God Component" |
| App.tsx → IPC_CHANNELS (4 处 invoke/on) | IPC 通信直接写在组件中，无法复用 |

### P2（中风险 — 跨关注点/可容忍但有重构价值）

| 条目 | 原因 |
|------|------|
| right-panel.actions → drawer/panel-session/chapter stores | 已有 X-01 协议抽象，但底层仍是 3 store getState() |
| ManuscriptPanel → chapter.store + editor.store | 编辑器组件同时绑定内容和偏好两个 store |
| WorkTreePanel → chapter/manuscript stores (getState) | 组件内直接调 store action 创建/删除，应通过上层 props |
| WorkTreePanel → right-panel.actions | 组件直接调面板 action，应通过回调 props |
| RightDrawer → drawer/panel-session stores + right-panel.actions | 已有 X-01 协议，但 selector 数量较多 |
| useDiagnosisFlow → IPC_CHANNELS | hook 直接 import IPC 常量而非通过 store/service 层 |
| 9 个 store 中仅 3 个无跨 store 耦合 | diag / session / student-context / manuscript / chapter / editor / drawer / panel-session / paradigm / teaching-state / ui-layout / config 中，config、diag、manuscript、editor、drawer、panel-session、paradigm、teaching-state、ui-layout、session、student-context 自身无向其他 store 的 getState()，但被其他 store 大量引用 |

---

## 附录：IPC 通道现状与 API 层建议

`src/shared/constants.ts` 已定义了完善的 IPC 通道命名空间，是现有架构中最接近"API 层"的资产。建议基于此建设：

1. **创建 `src/renderer/services/` 目录**，将跨 store 协调逻辑从组件和 hook 中提取为服务函数
2. **每个服务对应一个 IPC 领域**（如 `chat.service.ts` 封装 `CHAT_SEND`、`CHAT_STOP` 等通道）
3. **服务层作为 store 之间的唯一通信中介**，取代当前的 store-to-store `getState()` 调用
4. **Event 监听器改造为服务层内部实现**，组件仅通过 store hook 消费最终状态

现有 store 中 **无跨 store 依赖、可直接抽取为独立模块** 的候选：`config.store`、`diag.store`、`manuscript.store`、`editor.store`、`drawer.store`、`panel-session.store`、`paradigm.store`、`teaching-state.store`、`ui-layout.store`、`student-context.store`。
