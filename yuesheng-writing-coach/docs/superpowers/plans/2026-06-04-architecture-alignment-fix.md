# 架构对齐修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复代码审查发现的 5 个核心架构问题：病症定义冲突、双次 API 延迟、Prompt 集成缺失、学生上下文死代码、诊断动作缺失。

**Architecture:** 统一 constants.ts 与 mappings.ts 的病症定义；将诊断动作映射接入 analysisToDiagnosisEntry；连接 PromptLoader 与 PromptBuilder；在诊断完成后激活学生上下文 store；优化诊断流程减少延迟。

**Tech Stack:** TypeScript, Electron IPC, Zustand, Vitest

**依据文档:**
- [module-independence-assessment-v1.0.md](file:///D:/ai-teacher/yuesheng-writing-coach/docs/tests/module-independence-assessment-v1.0.md)
- 代码审查报告（用户与另一 AI 的对话结论）

---

## 文件结构映射

### 修改文件
- `src/shared/constants.ts` — 统一病症定义，补充缺失的 P008
- `src/shared/mappings.ts` — 修正 P009/P010 名称与 constants.ts 一致
- `src/main/ipc/chat.handler.ts` — analysisToDiagnosisEntry 填充 suggestedActions，优化双 API 流程
- `src/main/services/prompt-loader.ts` — 连接 PromptBuilder，注入教学进度
- `src/renderer/stores/student-context.store.ts` — 保持现有逻辑不变（死代码问题通过调用方修复）
- `src/renderer/stores/chat.store.ts` — 在诊断完成后调用 updateFromDiagnosis
- `src/main/ipc/teaching-state.handler.ts` — 提供 getPromptBuilder 给 PromptLoader 使用

---

## 修复计划

### Task 1: 统一病症定义（修复 P009/P010 冲突）

**Files:**
- Modify: `src/shared/constants.ts:5-15`
- Modify: `src/shared/mappings.ts:8-19, L27-38`

**目的：** constants.ts 和 mappings.ts 对 P009、P010 的定义冲突，必须以 mappings.ts 为准（因为 mappings.ts 有完整的动作/能力映射关联）。

- [ ] **Step 1: 更新 constants.ts 补充 P008，修正 P009/P010**

当前 constants.ts：
```typescript
export const SyndromeId = {
  WorldviewBloat: 'P001',
  CharacterTool: 'P002',
  EmotionLabeling: 'P003',
  InfoDumping: 'P004',
  PerspectiveDrift: 'P005',
  PacingStagnation: 'P006',
  ReadingStructureSingle: 'P007',
  MotivationDeficit: 'P009',     // ← 错误：应该是 'BuildingBlockPile'（设定堆砌）
  OCConstant: 'P010',             // ← 错误：应该是 'OmniscientView'（视角全知）
} as const;
```

修改为（与 mappings.ts 一致）：
```typescript
export const SyndromeId = {
  WorldviewBloat: 'P001',
  CharacterTool: 'P002',
  EmotionLabeling: 'P003',
  InfoDumping: 'P004',
  PerspectiveDrift: 'P005',
  PacingStagnation: 'P006',
  ReadingStructureSingle: 'P007',
  OCConstant: 'P008',             // ← 新增
  BuildingBlockPile: 'P009',      // ← 修正：设定堆砌
  OmniscientView: 'P010',         // ← 修正：视角全知
} as const;
```

- [ ] **Step 2: 搜索所有使用 `SyndromeId.MotivationDeficit` 和 `SyndromeId.OCConstant` 的地方**

```bash
# 搜索引用
grep -r "MotivationDeficit\|OCConstant" src/
```

将找到的引用更新为新的常量名（BuildingBlockPile / OmniscientView / OCConstant(P008)）。

- [ ] **Step 3: 运行类型检查和测试**

```bash
npx tsc --noEmit
npx vitest run
```

---

### Task 2: 修复 analysisToDiagnosisEntry 的 suggestedActions 为空

**Files:**
- Modify: `src/main/ipc/chat.handler.ts:125-155`

**目的：** 路径A（DiagnosisAgent）产出的诊断结果不带教学动作。需要从 mappings.ts 的 SYNDROME_TO_ACTIONS 查找并填充。

- [ ] **Step 1: 修改 analysisToDiagnosisEntry 函数**

当前代码：
```typescript
function analysisToDiagnosisEntry(
  analysis: DiagnosisAnalysis,
  sessionId: string,
  messageId: string,
): DiagnosisEntry {
  const syndromes: SyndromeResult[] = analysis.syndromeRef.map((ref) => {
    const meta = SYNDROME_META[ref] ?? { name: ref, severity: 'L1' as SeverityLevel };
    return {
      id: ref,
      name: meta.name,
      severity: meta.severity,
      evidence: analysis.keyPassages.slice(0, 3).map(kp => kp.text),
      score: analysis.confidence,
      suggestedActions: [],  // ← 永远为空！
    };
  });
  // ...
  return {
    sessionId,
    messageId,
    syndromes,
    suggestedActions: [],  // ← 也是空！
    timestamp: new Date().toISOString(),
    confidence: analysis.confidence,
  };
}
```

修改为：
```typescript
import { SYNDROME_META, getActionsForSyndrome } from '../../shared/mappings';

function analysisToDiagnosisEntry(
  analysis: DiagnosisAnalysis,
  sessionId: string,
  messageId: string,
): DiagnosisEntry {
  const allSuggestedActions: string[] = [];

  const syndromes: SyndromeResult[] = analysis.syndromeRef.map((ref) => {
    const meta = SYNDROME_META[ref] ?? { name: ref, severity: 'L1' as SeverityLevel };
    const actions = getActionsForSyndrome(ref);
    allSuggestedActions.push(...actions);
    return {
      id: ref,
      name: meta.name,
      severity: meta.severity,
      evidence: analysis.keyPassages.slice(0, 3).map(kp => kp.text),
      score: analysis.confidence,
      suggestedActions: actions,  // ← 从映射表查找
    };
  });

  // 去重
  const uniqueActions = [...new Set(allSuggestedActions)];

  return {
    sessionId,
    messageId,
    syndromes,
    suggestedActions: uniqueActions,  // ← 填充！
    timestamp: new Date().toISOString(),
    confidence: analysis.confidence,
  };
}
```

- [ ] **Step 2: 运行类型检查和测试**

```bash
npx tsc --noEmit
npx vitest run
```

---

### Task 3: 连接 PromptLoader 和 PromptBuilder

**Files:**
- Modify: `src/main/services/prompt-loader.ts`
- Modify: `src/main/index.ts`

**目的：** PromptLoader 目前没有调用 PromptBuilder，导致教学进度信息（已完成动作、当前问题、建议下一步）没有注入到 System Prompt 中。

- [ ] **Step 1: 修改 PromptLoader 接受 PromptBuilder**

在 PromptLoader 中添加：
```typescript
import { PromptBuilder } from './prompt-builder';
import { ACTION_NAMES, ACTION_GOALS, SYNDROME_NAMES } from '../../shared/mappings';

// 在 PromptLoader 类中添加字段：
private promptBuilder: PromptBuilder | null = null;

setPromptBuilder(builder: PromptBuilder): void {
  this.promptBuilder = builder;
}
```

- [ ] **Step 2: 在 loadSystemPrompt 中注入教学进度**

修改 `loadSystemPrompt` 方法，在有 sessionId 时获取教学状态并注入：

```typescript
// 在 loadSystemPrompt 方法中，组装 basePrompt 后添加：
if (sessionId && this.promptBuilder && this.stateContextGetter) {
  const stateContext = this.stateContextGetter(sessionId);
  if (stateContext) {
    // 构建完整的教学进度注入文本
    const progressText = this.buildTeachingProgressInject(sessionId);
    if (progressText) {
      basePrompt += `\n\n${progressText}`;
    }
  }
}
```

添加 `buildTeachingProgressInject` 私有方法：
```typescript
/**
 * 构建教学进度注入文本
 * 通过 IPC 获取教学状态，然后用 PromptBuilder 格式化
 */
private buildTeachingProgressInject(sessionId: string): string | null {
  if (!this.promptBuilder || !this.stateContextGetter) return null;

  // 注意：此处不能直接访问 TeachingStateStore，需要通过注入的 getter
  // 但 stateContextGetter 只返回 { currentPhase, currentSubphase }
  // 我们需要一个更完整的 getter

  // 方案：使用 IPC_CHANNELS.TEACHING_STATE_GET_PROMPT 获取已格式化的进度文本
  // 但在主进程内不能调用 ipcMain.handle
  // 所以我们需要在初始化时注入一个 getTeachingProgressText 函数

  return null; // 暂时返回 null，等待 getTeachingProgressText 注入
}
```

由于 PromptLoader 在主进程内无法直接调用 IPC，我们需要换一个方案：**在初始化时注入一个 `getTeachingProgressText` 回调函数。**

```typescript
// 添加字段和 setter：
private getTeachingProgressText: ((sessionId: string) => string) | null = null;

setTeachingProgressGetter(getter: (sessionId: string) => string): void {
  this.getTeachingProgressText = getter;
}

// 在 loadSystemPrompt 中使用：
if (sessionId && this.getTeachingProgressText) {
  const progressText = this.getTeachingProgressText(sessionId);
  if (progressText && !progressText.includes('新对话')) {
    basePrompt += `\n\n${progressText}`;
  }
}
```

- [ ] **Step 3: 在 index.ts 中注入 getTeachingProgressText**

```typescript
// 在 app.whenReady() 中，setPromptLoader 之后添加：
promptLoader.setTeachingProgressGetter((sessionId: string) => {
  const store = getStoreInstance();
  const state = store.getBySession(sessionId);
  if (!state) return '';

  const pb = getPromptBuilder();
  if (!pb) return '';

  return pb.buildSystemPrompt(
    state,
    (id: string) => ACTION_NAMES[id] ?? id,
    (id: string) => ACTION_GOALS[id] ?? '',
    (id: string) => SYNDROME_NAMES[id] ?? id,
  );
});
```

- [ ] **Step 4: 运行类型检查和测试**

```bash
npx tsc --noEmit
npx vitest run
```

---

### Task 4: 激活学生上下文 store 的自动推断

**Files:**
- Modify: `src/renderer/stores/chat.store.ts:95-130`
- Modify: `src/renderer/App.tsx`（或诊断更新监听处）

**目的：** `updateFromDiagnosis` 和 `updateFromInteraction` 从未被调用，需要在前端监听诊断结果后自动调用。

- [ ] **Step 1: 在 chat.store.ts 的发送消息流程中调用 updateFromDiagnosis**

当前 chat.store.ts 发送消息后只处理了消息列表更新，没有调用学生上下文更新。

在诊断结果返回后（CHAT_STREAM_END 事件中），调用 updateFromDiagnosis：

```typescript
// 在 App.tsx 或 chat.store.ts 的 CHAT_STREAM_END 监听中：
ipcRenderer.on(IPC_CHANNELS.DIAGNOSIS_UPDATE, (_event, diagnosis: DiagnosisEntry) => {
  // 更新诊断面板
  setCurrentDiagnosis(diagnosis);

  // ← 新增：激活学生上下文自动推断
  useStudentContextStore.getState().updateFromDiagnosis(
    diagnosis.syndromes.map(s => ({
      id: s.id,
      name: s.name,
      severity: s.severity,
    }))
  );
});
```

- [ ] **Step 2: 在交互结果更新中调用 updateFromInteraction**

在 CHAT_STREAM_END 中，根据用户反应（如用户是否重写、是否继续提问）推断交互结果：

```typescript
// 简化方案：每次 AI 回复完成后，默认视为 "partial"（部分成功）
// 后续可以基于用户行为更精细判断
ipcRenderer.on(IPC_CHANNELS.CHAT_STREAM_END, (_event, data) => {
  if (data.fullResponse && data.fullResponse.length > 0) {
    // AI 成功回复 → 视为部分成功
    useStudentContextStore.getState().updateFromInteraction('partial');
  }
});
```

- [ ] **Step 3: 运行类型检查和测试**

```bash
npx tsc --noEmit
npx vitest run
```

---

### Task 5: 优化诊断流程减少双 API 延迟

**Files:**
- Modify: `src/main/ipc/chat.handler.ts:178-198`

**目的：** 当前流程是串行调用两次 API（DiagnosisAgent + Teaching Agent），用户感知延迟 10-15 秒。优化方案：让 DiagnosisAgent 流式输出，或者跳过 DiagnosisAgent 直接让 Teaching Agent 在回复中附带诊断。

**方案选择：** 不删除 DiagnosisAgent，而是改为**可选的异步后台诊断**——先启动 Teaching Agent 流式回复，DiagnosisAgent 在后台并行运行，诊断结果通过 IPC 推送更新 System Prompt（但这需要 mid-stream prompt update，比较复杂）。

**更务实的方案：** 保留当前串行流程，但**让 DiagnosisAgent 流式输出**，用户能在 3-5 秒内看到分析摘要开始显示，而不是空白等待。

- [ ] **Step 1: 修改 callDiagnosisAgent 支持流式输出**

当前 callDiagnosisAgent 收集完整响应后才返回：

```typescript
async function callDiagnosisAgent(userText: string): Promise<DiagnosisAnalysis | null> {
  // ...
  let fullResponse = '';
  for await (const chunk of proxy.chatStream(messages)) {
    fullResponse += chunk;
  }
  // 解析 JSON
}
```

修改为流式回调模式：
```typescript
async function callDiagnosisAgent(
  userText: string,
  onChunk?: (chunk: string) => void,
): Promise<DiagnosisAnalysis | null> {
  const proxy = getApiProxy();
  try {
    // ... 构建 messages ...

    let fullResponse = '';
    for await (const chunk of proxy.chatStream(messages)) {
      fullResponse += chunk;
      if (onChunk) onChunk(chunk);  // 流式推送
    }

    const jsonMatch = fullResponse.match(/\{[\s\S]*\}/);
    if (!jsonMatch) return null;
    return JSON.parse(jsonMatch[0]) as DiagnosisAnalysis;
  } catch (err) {
    console.error('[DiagnosisAgent] Failed to analyze:', err);
    return null;
  }
}
```

- [ ] **Step 2: 在 CHAT_SEND 中流式推送诊断摘要**

```typescript
if (shouldRunDiagnosis) {
  // 流式推送诊断分析进度
  diagnosisAnalysis = await callDiagnosisAgent(message, (chunk) => {
    // 将原始诊断 chunk 推送给用户（前缀标记）
    mainWindow.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
      sessionId: activeSessionId,
      chunk: `\u{1F50D} ${chunk}`,  // 放大镜 emoji 表示分析中
    });
  });

  if (diagnosisAnalysis) {
    // 推送分析摘要
    mainWindow.webContents.send(IPC_CHANNELS.CHAT_STREAM_DATA, {
      sessionId: activeSessionId,
      chunk: `\n\n---\n\n\u{1F4CB} 分析摘要：${diagnosisAnalysis.rootCause}\n\n---\n\n`,
    });

    // ... 保存和推送诊断结果 ...
  }
}
```

这样用户在 DiagnosisAgent 调用期间就能实时看到分析过程，而不是空白等待。

- [ ] **Step 3: 运行类型检查和测试**

```bash
npx tsc --noEmit
npx vitest run
```

---

## 验证清单

完成所有任务后，运行以下验证：

- [ ] **类型检查通过**
```bash
npx tsc --noEmit
```

- [ ] **全部测试通过**
```bash
npx vitest run
```

- [ ] **验证 P009/P010 一致性**
```bash
# constants.ts 和 mappings.ts 中 P009 都应表示"设定堆砌"
# P010 都应表示"视角全知"
# P008 在两个文件中都应表示"OC 常量"
```

- [ ] **验证 analysisToDiagnosisEntry 不再返回空 suggestedActions**
```bash
# 搜索 suggestedActions: [] 应不再出现在 analysisToDiagnosisEntry 中
```

- [ ] **验证 PromptBuilder 被 PromptLoader 调用**
```bash
grep -r "setTeachingProgressGetter" src/
# 应有至少一处调用
```

---

## DoD（完成标准）

1. **P009/P010 定义一致**：constants.ts 和 mappings.ts 对同一 ID 的定义完全一致，类型检查通过。
2. **路径A诊断结果携带教学动作**：analysisToDiagnosisEntry 返回的 syndromes[i].suggestedActions 不为空数组。
3. **教学进度注入 System Prompt**：PromptLoader 在有 sessionId 时，将 PromptBuilder 构建的教学进度文本注入到 System Prompt 末尾。
4. **学生上下文自动推断激活**：诊断结果推送时自动调用 updateFromDiagnosis，学生 store 的 userType/confidenceLevel 会随诊断变化。
5. **诊断流程流式输出**：DiagnosisAgent 调用期间用户能看到分析进度，而不是空白等待。
6. **类型检查和测试全部通过**：`npx tsc --noEmit` 和 `npx vitest run` 无错误。

---

> 计划生成时间：2026-06-04
> 计划版本：V1.0
> 依据：代码审查报告（用户与 AI 的完整对话结论）
