---
AIGC:
    Label: "1"
    ContentProducer: 001191440300708461136T1XGW3
    ProduceID: f2ac1166b9bdaea71c23aabee181e425_d6e2c753666a11f18805525400d9a7a1
    ReservedCode1: Bzli+nuBlrmhoruVEPq4kJoPN1TpjuTr1jBiYyDKpyXlmMJqawsrXorAZL/c/egqVw+m6q211QgFkjb83BlWUUaO1FKLYsKvYX/Xey7vJbRAIyrb1ZqzwQ13VDpE5iLcSDObkJTCMrw1BRYWdMOfjLptUy4aDkU69gyaTnLciH9PUvZqk5QOCGvQnU4=
    ContentPropagator: 001191440300708461136T1XGW3
    PropagateID: f2ac1166b9bdaea71c23aabee181e425_d6e2c753666a11f18805525400d9a7a1
    ReservedCode2: Bzli+nuBlrmhoruVEPq4kJoPN1TpjuTr1jBiYyDKpyXlmMJqawsrXorAZL/c/egqVw+m6q211QgFkjb83BlWUUaO1FKLYsKvYX/Xey7vJbRAIyrb1ZqzwQ13VDpE5iLcSDObkJTCMrw1BRYWdMOfjLptUy4aDkU69gyaTnLciH9PUvZqk5QOCGvQnU4=
---

# 右侧栏映射检查报告

**日期**：2026-06-12  
**范围**：用户输入 → 诊断 → 右侧栏各模块端到端数据流  
**方法**：IPC 通道定义、Handler 注册、Preload 白名单、前端 Store/Component 四层交叉比对

---

## 1. 右侧栏组件结构

### 1.1 布局容器

| 文件 | 作用 |
|------|------|
| `src/renderer/components/layout/RightDrawer.tsx` | 右侧栏抽屉容器，管理标签切换 |
| `src/renderer/components/layout/DiagnosisPanel.tsx` | 诊断面板（诊断卡片 + 编辑面板容器） |
| `src/renderer/App.tsx` | 顶层组装，管理 toolStatus + fetchGrowthSummary |

### 1.2 右侧栏子模块

| 模块 | 组件 | Store | 数据来源 |
|------|------|-------|---------|
| **诊断** | `DiagnosisCard.tsx`, `EditPanel.tsx`, `EvaluationCard.tsx`, `BeatCheckChart.tsx`, `GrowthCard.tsx` | `diag.store.ts` | `diagnosis:update` 事件推送 |
| **证据** | `OriginalEvidenceSection` (内嵌于 DiagnosisCard) | `diag.store.ts` (evidenceMap) | `evidence:getBySyndrome` IPC invoke |
| **训练** | `TrainingWorkshop.tsx`, `RecommendationsSection.tsx`, `ErrorCardsSection.tsx`, `ActiveTrainingView.tsx` 等 16 个组件 | `training.store.ts` + `training.actions.ts` | `training:recommend` IPC invoke |
| **成长** | `GrowthPanel.tsx` | 组件内 `useState`（无独立 store） | `growth:getTrends` IPC invoke |
| **教学状态** | `TaskPanel.tsx` | `teaching-state.store.ts` | `teachingState:updated` 事件推送 |

### 1.3 多 Store 协作协议 (X-01)

`right-panel.actions.ts` 作为统一入口，`panel-session.store.ts` 做 SSOT：
- `openTool()` / `openEditor()` / `openTraining()` — 打开右侧栏标签
- `closePanel()` / `togglePanel()` — 关闭/切换面板
- `switchSession()` / `removeSession()` — 切换时自动联动

---

## 2. 诊断结果分发（核心链路）

### 2.1 数据流全貌

```
用户输入
  │
  ▼
chat.handler.ts: CHAT_SEND handler (line 845)
  ├── resolveChapterReference(message)
  ├── runDiagnosis(message, sessionId)          ← A路：DiagnosisAgent
  │     ├── callDiagnosisAgent(message)
  │     └── analysisToDiagnosisEntry() → DIAGNOSIS_UPDATE 事件
  ├── prepareTeachingContext()
  ├── handleStreamResponse() 或 handleStreamResponseWithTools()
  │     ├── chat:stream:data 事件（逐 chunk 推送）
  │     ├── saveMessage(assistant, fullResponse)
  │     ├── processDiagnosisFromAI()            ← B路：Parser 解析
  │     │     ├── parseDiagnosisFromAIResponse()
  │     │     ├── diagnosisService.save()
  │     │     ├── evidenceService.save() + linkToDiagnosis()
  │     │     ├── diagnosisMerger.merge()
  │     │     ├── teachingState:updated 事件
  │     │     └── DIAGNOSIS_UPDATE 事件
  │     └── chat:stream:end 事件
  └── result
```

### 2.2 双诊断管道问题 (⚠️)

| 管道 | 触发时机 | 解析方式 | 发送事件 |
|------|---------|---------|---------|
| **A路**（runDiagnosis） | 流开始前（同步） | `callDiagnosisAgent` 单独 API 调用 | `diagnosis:update` |
| **B路**（processDiagnosisFromAI） | 流结束后 | `parseDiagnosisFromAIResponse` 解析 `---DIAGNOSIS_START---` 标记 | `diagnosis:update` |

**影响**：若 A 路和 B 路均产出诊断，前端先收到 A 路结果（可能只含 syndromeRef），后被 B 路结果覆盖。可能导致短暂闪烁。

**当前实际**：A 路调用 `DiagnosisAgent` 分析用户输入内容是否叙事，产出的 `entry.syndromes` 可能为空数组（仅含 rootCause + syndromeRef）。B 路解析 AI 主回复中的诊断表，产出的 `DiagnosisEntry.syndromes` 更完整。

### 2.3 IPC 通道注册汇总

| 通道 | 类型 | Handler 位置 | Preload | 前端监听 |
|------|------|-------------|---------|---------|
| `diagnosis:update` | 事件推送 | `chat.handler.ts:707` + `diagnosis.handler.ts:248` | ✅ | `useAppIpcListener.ts:29` |
| `diagnosis:query` | invoke | `diagnosis.handler.ts:57` | ✅ | 无显式调用 |
| `diagnosis:submitRewrite` | invoke | `diagnosis.handler.ts:150` | ✅ | `useDiagnosisFlow.ts:96` |
| `diagnosis:getComparison` | invoke | `diagnosis.handler.ts:71` | ✅ | `useDiagnosisFlow.ts:142` |
| `teachingState:updated` | 事件推送 | `diagnosis.handler.ts:244` + `teaching-state.handler.ts` | ✅ | `useAppIpcListener.ts:69` |
| `chat:stream:data` | 事件推送 | `chat.handler.ts:750` + `:507` + `:768` | ✅ | `useAppIpcListener.ts:45` |
| `chat:stream:end` | 事件推送 | `chat.handler.ts:553` + `:787` | ✅ | `useAppIpcListener.ts:50` |
| `chat:tool:executing` | 事件推送 | `chat.handler.ts:516` | ✅ | `App.tsx:110` |
| `evidence:getBySyndrome` | invoke | `evidence.handler.ts:70` | ✅ | `diag.store.ts:89` |
| `growth:getTrends` | invoke | `diagnosis.handler.ts:122` | ✅ | `GrowthPanel.tsx:95` |
| `growth:getGlobalTrends` | invoke | `diagnosis.handler.ts:133` | ✅ | **无人调用** |
| `training:recommend` | invoke | `training.handler.ts:51` | ✅ | `training.actions.ts:169` |

---

## 3. 各模块映射验证

### 3.1 诊断结果模块 (diagnosis) — ✅ 正常

**数据流**：
```
diagnosis:update 事件 → useAppIpcListener.ts:29
  → useDiagStore.getState().setCurrentDiagnosis(entry)
  → useDiagStore.getState().addToHistory(sessionId, entry)
  → useStudentContextStore.getState().updateFromDiagnosis(syndromes)
  → useTrainingStore.getState().refreshFromDiagnosis()
```

| 检查项 | 结果 | 详情 |
|--------|:--:|------|
| 事件名一致 | ✅ | 主进程 `IPC_CHANNELS.DIAGNOSIS_UPDATE` = `'diagnosis:update'`，前端同 |
| Payload 类型一致 | ✅ | 主进程推送 `DiagnosisEntry`，前端 `as DiagnosisEntry` 断言 |
| Preload 白名单 | ✅ | `allowedEventChannels` 含 `diagnosis:update` |
| 渲染链路 | ✅ | `DiagnosisCard` 从 `useDiagStore.currentDiagnosis` 读取，展开显示症候列表+证据 |
| Store 结构 | ✅ | `currentDiagnosis / history / evidenceMap` 三态结构 |

**文件路径**：
- 主进程：`src/main/ipc/chat.handler.ts:693-711` (`runDiagnosis`), `src/main/ipc/diagnosis.handler.ts:177-250` (`processDiagnosisFromAI`)
- 前端监听：`src/renderer/hooks/useAppIpcListener.ts:29-42`
- Store：`src/renderer/stores/diag.store.ts:175`
- 组件：`src/renderer/components/diagnosis/DiagnosisCard.tsx:314`

---

### 3.2 证据/技法模块 (evidence) — ✅ 正常

**数据流**：
```
DiagnosisCard 展开 → OriginalEvidenceSection mount
  → useDiagStore.loadEvidence(syndromeId, sessionId)
    → getInvoke()(IPC_CHANNELS.EVIDENCE_GET_BY_SYNDROME, { syndromeId, sessionId })
      → evidence.handler.ts:70 → evidenceService.getBySyndrome()
        → 返回 EvidenceRecord[]
  → 缓存到 evidenceMap[syndromeId]
  → 渲染原文证据 (contentJson 解析 text + issue)
```

| 检查项 | 结果 | 详情 |
|--------|:--:|------|
| IPC 通道注册 | ✅ | `evidence.handler.ts:70` 使用 `ipcMain.handle` 注册 |
| 前端调用 | ✅ | `diag.store.ts:89` 使用 `EVIDENCE_GET_BY_SYNDROME` 常量 |
| Payload 格式 | ✅ | 主进程期望 `{ syndromeId, sessionId }`，前端发送一致 |
| 响应格式 | ✅ | `apiSuccess(data)` → `{ success: true, data: EvidenceRecord[] }` |
| Preload 白名单 | ✅ | `allowedInvokeChannels` 含 `evidence:getBySyndrome` |

**注意**：`evidence.handler.ts` 使用 `ipcMain.handle()` 直接注册 + `apiSuccess`/`apiError` 包装，与其他 handler 使用 `createHandler` 的方式不一致。不影响功能但风格不统一。

**文件路径**：
- 主进程：`src/main/ipc/evidence.handler.ts:70-79`
- 前端：`src/renderer/stores/diag.store.ts:89-107` (`loadEvidence`)
- 组件：`src/renderer/components/diagnosis/DiagnosisCard.tsx:271-314` (`OriginalEvidenceSection`)

---

### 3.3 训练推荐模块 (training) — ✅ 正常

**数据流**：
```
DIAGNOSIS_UPDATE → useAppIpcListener:39
  → useTrainingStore.getState().refreshFromDiagnosis()
    → training.actions.ts:createRefreshFromDiagnosisAction
      → 从 diag.store 聚合 errorCards
      → getInvoke()(IPC_CHANNELS.TRAINING_RECOMMEND, { sessionId })
        → training.handler.ts:51 → studentModelService.getSyndromeProfile()
          → generateRecommendations(activeProblems)
        → 返回 { recommendations: TrainingRecommendation[] }
  → 设置 recommendations + errorCards 到 training store
  → TrainingWorkshop → RecommendationsSection 渲染
```

| 检查项 | 结果 | 详情 |
|--------|:--:|------|
| IPC 通道注册 | ✅ | `training.handler.ts:51` |
| 前端触发链路 | ✅ | `useAppIpcListener:39` → `refreshFromDiagnosis` → `TRAINING_RECOMMEND` |
| Payload 格式 | ✅ | 主进程期望 `{ sessionId }`，前端发送一致 |
| 响应消费 | ✅ | `training.actions.ts` 用 `result.recommendations` + `result.errorCards` |
| Preload 白名单 | ✅ | `allowedInvokeChannels` 含 `training:recommend` |

**完整 training 通道列表**（8 个）：
`recommend / assign / complete / skip / history / submit / evaluate / deriveBehavior` — 全部在 `training.handler.ts:211` 内注册，preload 白名单完整覆盖。

**文件路径**：
- 主进程：`src/main/ipc/training.handler.ts:51-75`
- 前端 Action：`src/renderer/stores/training.actions.ts:147-205` (`createRefreshFromDiagnosisAction`)
- 组件：`src/renderer/components/training/RecommendationsSection.tsx:141`

---

### 3.4 成长趋势模块 (growth) — ⚠️ 部分断裂

**数据流 A：GrowthPanel 自取**
```
GrowthPanel mount
  → useEffect([sessionId]) → getInvoke()(IPC_CHANNELS.GROWTH_GET_TRENDS, { sessionId })
    → diagnosis.handler.ts:122 → growthTrendService.getGrowthSummary(sessionId, ...)
    → 返回 { trends, masteredCount, improvingCount, stableCount, needsAttentionCount }
  → 组件内 useState 管理，SVG 柱状图 + 详细列表渲染
```

**数据流 B：growth:getGlobalTrends — 断裂**
```
✅ IPC 通道定义：shared/constants.ts → GROWTH_GET_GLOBAL_TRENDS
✅ Handler 注册：diagnosis.handler.ts:133
✅ Preload 白名单：allowedInvokeChannels 含 'growth:getGlobalTrends'
❌ 前端调用：无任何文件 invoke(IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS)
```

| 检查项 | 结果 | 详情 |
|--------|:--:|------|
| `growth:getTrends` 端到端 | ✅ | GrowthPanel 自取，链路完整 |
| `growth:getGlobalTrends` 消费 | ❌ | Handler 存在但无前端调用 |
| `fetchGrowthSummary` 回调 | ❌ | App.tsx:47 定义为空函数 `async () => { /* used by IPC listener */ }` |
| 诊断后趋势更新 | ⚠️ | GrowthPanel 依赖 `sessionId` 变化后 useEffect 重新拉取，1-2 秒延迟 |
| Store 管理 | ⚠️ | GrowthPanel 使用组件内 `useState`，无独立 store，数据不能跨组件共享 |

**问题详情**：
1. **`fetchGrowthSummary` 为空函数**：`App.tsx:47` 定义为 `useCallback(async () => { /* used by IPC listener */ }, [])`，该函数通过 `useAppIpcListener(fetchGrowthSummary)` 传入，在 `chat:stream:end` 事件后调用，但实际不执行任何操作。
2. **`growth:getGlobalTrends` 成为死代码**：Handler 已注册但整个前端从未调用，IPC 通道浪费。
3. **GrowthPanel 不响应诊断推送**：`DIAGNOSIS_UPDATE` 事件不会触发 GrowthPanel 重新拉取数据，仅在 sessionId 变化时（useEffect 依赖）拉取。

**文件路径**：
- 主进程：`src/main/ipc/diagnosis.handler.ts:122-138`
- 前端组件：`src/renderer/components/growth/GrowthPanel.tsx:253`
- 空回调：`src/renderer/App.tsx:47`

---

### 3.5 教学状态模块 (teachingState) — ✅ 正常

**数据流**：
```
processDiagnosisFromAI → diagnosisMerger.merge(diagnosis)
  → getTeachingStateStore().getBySession(sessionId)
  → mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_UPDATED, updatedState)
    → useAppIpcListener.ts:69
      → useTeachingStateStore.getState().setCurrentState(teaching)

training:evaluate → score >= 7 → downgradeSyndromeSeverity + pushTeachingStateUpdate
  → teachingState:updated 事件
```

| 检查项 | 结果 | 详情 |
|--------|:--:|------|
| 事件名一致 | ✅ | 常量 `TEACHING_STATE_UPDATED` = `'teachingState:updated'` |
| Payload 类型 | ✅ | `TeachingState & { phaseName, subphaseName, phaseProgress }` |
| 诊断合并触发 | ✅ | `processDiagnosisFromAI` → `diagnosisMerger.merge` → 推送 |
| 训练降级触发 | ✅ | `training:evaluate` 中 score≥7 自动降级严重度 |
| Preload 白名单 | ✅ | `allowedEventChannels` 含 `teachingState:updated` |

**Invoke 通道**（5 个）：`get / update / confirm / getPrompt / updateSummary` — 全部在 `teaching-state.handler.ts:282` 注册，preload 白名单完整覆盖。

**文件路径**：
- 主进程：`src/main/ipc/teaching-state.handler.ts:282`
- 前端监听：`src/renderer/hooks/useAppIpcListener.ts:69-74`
- Store：`src/renderer/stores/teaching-state.store.ts:108`
- 组件：`src/renderer/components/teaching/TaskPanel.tsx`

---

## 4. 断点检查

### 4.1 已确认无断裂

| 检查项 | 状态 |
|--------|:--:|
| Preload invoke 白名单 vs constants.ts ALLOWED_INVOKE_CHANNELS | ✅ 50 = 50，完全一致 |
| Preload event 白名单 vs constants.ts ALLOWED_EVENT_CHANNELS | ✅ 5 = 5（`diagnosis:update`, `teachingState:updated`, `chat:stream:data`, `chat:stream:end`, `chat:tool:executing`） |
| 前端事件监听覆盖 5 个 event 通道 | ✅ `useAppIpcListener.ts`(4) + `App.tsx:110`(1) |
| 所有 invoke handler 均通过 `createHandler` 或 `ipcMain.handle` 注册 | ✅ |
| diagnosis:update payload 类型匹配 | ✅ `DiagnosisEntry` ↔ `as DiagnosisEntry` |
| teachingState:updated payload 类型匹配 | ✅ 解构 `phaseName/subphaseName/phaseProgress` → `setCurrentState(rest)` |
| evidence:getBySyndrome handler 注册 | ✅ `evidence.handler.ts:70` |

### 4.2 发现的问题

#### P1 — `fetchGrowthSummary` 空函数（`App.tsx:47`）

```typescript
const fetchGrowthSummary = useCallback(async () => { /* used by IPC listener */ }, []);
```

- **影响**：`useAppIpcListener` 在 `chat:stream:end` 后调用此函数，期望更新成长数据，但函数体为空
- **根因**：注释表明 "panels now fetch independently via useSessionStore"，但 GrowthPanel 独立拉取仅在 `sessionId` 变化时触发，不会在诊断后自动刷新
- **建议**：在 `fetchGrowthSummary` 中触发 GrowthPanel 的数据刷新（如设置一个递增的 `refreshKey` state 或使用 event bus）

#### P2 — `growth:getGlobalTrends` 无前端消费

- **影响**：IPC 通道 + Handler 完整实现但从未被调用，属于死代码
- **建议**：①如有全局趋势展示需求则在前端接入；②否则考虑移除该通道以减少维护负担

#### P3 — `types-ipc.ts` 未覆盖 growth/training 通道

- **影响**：`GrowthPanel` 和 `training.actions.ts` 中使用 `getInvoke()` 的非类型化版本，失去编译时类型校验
- **位置**：`types-ipc.ts` 中 `IPCRequestMap` / `IPCResponseMap` 缺少 `growth:getTrends`、`growth:getGlobalTrends`、`training:recommend` 等 10+ 个通道
- **建议**：补充类型定义，渐进式迁移到类型化 `invoke<>()` 调用

#### P4 — 双诊断管道无去重

- **影响**：A 路（DiagnosisAgent）和 B 路（Parser 解析）可能先后推送两次 `DIAGNOSIS_UPDATE`，前端最后一次生效
- **位置**：`chat.handler.ts:707` (A) + `diagnosis.handler.ts:248` (B)
- **建议**：明确两路职责分工 — A 路用于 `contentType` 判断（叙事/非叙事），不推送完整 DiagnosisEntry；或两路合并为一路

#### P5 — `diagnosis:query` 无显式前端调用

- `diagnosis.handler.ts:57` 注册的 `DIAGNOSIS_QUERY` handler 从 `TeachingState.activeProblems` 读取
- 前端 `types-ipc.ts` 定义了请求响应类型，但实际 store 中无调用
- 状态：低优先级，可能为预留接口

---

## 5. 汇总表

| 模块 | 数据来源 | 传输方式 | 消费端 | 状态 |
|------|---------|---------|--------|:--:|
| 诊断结果 | `chat.handler` + `diagnosis.handler` | 事件 `diagnosis:update` | `diag.store` → `DiagnosisCard` | ✅ |
| 原文证据 | `evidence.handler` | invoke `evidence:getBySyndrome` | `diag.store.loadEvidence` → `OriginalEvidenceSection` | ✅ |
| 训练推荐 | `training.handler` | invoke `training:recommend` | `training.actions.refreshFromDiagnosis` → `RecommendationsSection` | ✅ |
| 训练执行 | `training.handler` | invoke `training:assign/submit/evaluate/complete` | `training.actions` → `ActiveTrainingView` | ✅ |
| 成长趋势(会话) | `diagnosis.handler` | invoke `growth:getTrends` | `GrowthPanel` (组件内 state) | ✅ |
| 成长趋势(全局) | `diagnosis.handler` | invoke `growth:getGlobalTrends` | **无人调用** | ❌ |
| 教学状态 | `diagnosis.handler` + `teaching-state.handler` | 事件 `teachingState:updated` | `teaching-state.store` → `TaskPanel` | ✅ |
| 流式数据 | `chat.handler` | 事件 `chat:stream:data` | `chat.store.appendToLastAssistant` → `ChatView` | ✅ |
| 流结束 | `chat.handler` | 事件 `chat:stream:end` | `chat.store` + `fetchGrowthSummary`(空函数) | ⚠️ |
| 工具调用状态 | `chat.handler` | 事件 `chat:tool:executing` | `App.tsx` toolStatus state → UI 提示 | ✅ |

---

## 6. 建议优先级

| ID | 问题 | 优先级 | 影响范围 |
|:--:|------|:--:|------|
| **RP-01** | `fetchGrowthSummary` 空函数导致诊断后成长数据不刷新 | 🔴 P1 | GrowthPanel 数据滞后 |
| **RP-02** | 双诊断管道可能重复推送 `diagnosis:update` | 🟡 P2 | 诊断卡片闪烁 |
| **RP-03** | `growth:getGlobalTrends` 死代码 | 🟡 P2 | 维护负担 |
| **RP-04** | `types-ipc.ts` 缺少 growth/training 通道类型 | 🟢 P3 | 类型安全 |
| **RP-05** | `evidence.handler` 使用 `ipcMain.handle` 而非 `createHandler` | 🟢 P3 | 代码风格一致性 |

---

**综合评估**：右侧栏核心链路（诊断 → 证据 → 训练 → 教学状态）完整可用。成长趋势模块存在两个独立问题：全局趋势通道无人消费、诊断后自动刷新回调为空函数。IPC 通道白名单一致性已验证（50 invoke + 5 event），preload 与 constants.ts 完全同步，比上次审计的 12 个缺失通道状态已有改善。
*（内容由AI生成，仅供参考）*
