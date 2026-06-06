# 模块独立性修复计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复教学库、诊断库、话术库的权责不清、引用混乱、内容重复问题，实现模块解耦和职责清晰。

**Architecture:** 通过提取独立服务（DiagnosisMerger、PromptLoader）、统一映射中心、重构 Handler 职责，将强耦合模块解耦为通过明确接口通信的独立模块。

**Tech Stack:** TypeScript, Electron IPC, better-sqlite3, Vitest

**依据文档:**
- [module-independence-assessment-v1.0.md](file:///D:/ai-teacher/yuesheng-writing-coach/docs/tests/module-independence-assessment-v1.0.md) — 问题评估报告

---

## 文件结构映射

在开始任务前，锁定每个文件的责任：

### 新建文件
- `src/main/services/diagnosis-merger.ts` — 诊断合并服务，负责将诊断结果合并到教学状态，解耦 diagnosis.handler 对 TeachingStateStore 的直接依赖
- `src/main/services/prompt-loader.ts` — Prompt 加载服务，负责读取、组装、注入 System Prompt
- `src/main/services/message-router.ts` — 消息路由服务，负责判断用户输入是否需要诊断分析
- `src/shared/action-mappings.ts` — 业务映射中心，统一管理病症→动作、子阶段→动作、病症→能力等业务映射

### 修改文件
- `src/main/ipc/diagnosis.handler.ts` — 移除对 TeachingStateStore 的直接操作，改用 DiagnosisMerger 服务
- `src/main/ipc/chat.handler.ts` — 移除 Router、Prompt 加载逻辑，改用新服务；移除 `require` 动态引用
- `src/main/ipc/teaching-state.handler.ts` — 移除 `getStoreInstance()` 暴露，提供专用 IPC 通道替代
- `src/main/services/teaching-state-machine.ts` — 移除 `buildSystemPromptWithState()` 和 `updateDiagnosisSummary()`
- `src/shared/mappings.ts` — 扩展为完整映射中心（保留现有内容，新增业务映射）
- `src/main/index.ts` — 更新初始化逻辑，注入新服务
- `src/main/services/syndrome-ability-map.ts` — 合并到 `src/shared/mappings.ts` 后删除

---

## 修复计划

### Phase 1: P0 严重问题修复（X-01, X-02）— 消除越权操作和职责膨胀

#### Task 1: 提取 DiagnosisMerger 服务（修复 X-01）

**Files:**
- Create: `src/main/services/diagnosis-merger.ts`
- Modify: `src/main/ipc/diagnosis.handler.ts:19, L276-298`
- Modify: `src/main/index.ts:137`

**目的：** 将诊断 Handler 中对 TeachingStateStore 的直接操作提取到独立服务，通过事件或回调通信。

- [ ] **Step 1: 创建 DiagnosisMerger 服务**

```typescript
// src/main/services/diagnosis-merger.ts
/**
 * 诊断合并服务
 * 负责：将诊断结果合并到教学状态，推送更新
 * 设计原则：
 *   1. 不直接依赖 TeachingStateStore，通过回调注入
 *   2. 提供纯净的合并逻辑（纯函数）
 *   3. 通过事件通知机制解耦
 */

import { TeachingStateStore } from './teaching-state.store';
import { mergeSyndromesIntoState } from '../ipc/diagnosis.handler';
import { DiagnosisEntry } from '../../renderer/shared/types';

/** 合并回调类型 */
export type MergeCallback = (sessionId: string, updates: Record<string, unknown>) => void;

/** 诊断合并服务 */
export class DiagnosisMerger {
  private getStore: () => TeachingStateStore;

  constructor(getStore: () => TeachingStateStore) {
    this.getStore = getStore;
  }

  /**
   * 合并诊断结果到教学状态
   * @param diagnosis - 诊断结果
   */
  merge(diagnosis: DiagnosisEntry): void {
    const store = this.getStore();
    const state = store.getBySession(diagnosis.sessionId);
    if (!state) return;

    const updates = mergeSyndromesIntoState(state, diagnosis);
    store.update(diagnosis.sessionId, updates);
  }
}
```

- [ ] **Step 2: 修改 diagnosis.handler.ts — 移除 Store 直接依赖**

修改 `src/main/ipc/diagnosis.handler.ts`，删除以下内容：
- L19: 删除 `import { TeachingStateStore }`
- L24: 删除 `let store: TeachingStateStore | null = null`
- L39-41: 删除 `initStore()` 函数
- L276-298: 将 `mergeDiagnosisIntoTeachingState()` 改为调用 `DiagnosisMerger`

```typescript
// 在 diagnosis.handler.ts 顶部添加
import { DiagnosisMerger } from '../services/diagnosis-merger';
import { mergeSyndromesIntoState } from './diagnosis.handler'; // 导出纯函数

let diagnosisMerger: DiagnosisMerger | null = null;

/** 设置诊断合并服务 */
export function setDiagnosisMerger(merger: DiagnosisMerger): void {
  diagnosisMerger = merger;
}

// 修改 processDiagnosisFromAI 函数中的 L276-298
// 原来：
//   mergeDiagnosisIntoTeachingState(diagnosis);
// 改为：
if (diagnosisMerger) {
  diagnosisMerger.merge(diagnosis);
} else {
  console.warn('[DiagnosisHandler] DiagnosisMerger not initialized');
}
```

将 `mergeSyndromesIntoState` 和 `appendToSummary` 导出：

```typescript
// 将这两个函数从 private 改为 export
export function mergeSyndromesIntoState(
  state: TeachingState,
  diagnosis: DiagnosisEntry,
): Partial<TeachingState> {
  // ... 原有逻辑保持不变 ...
}

function appendToSummary(current: string, diagnosis: DiagnosisEntry): string {
  // ... 原有逻辑保持不变 ...
}
```

删除 `mergeDiagnosisIntoTeachingState` 函数（L290-298），因为它已被 DiagnosisMerger 替代。

同时删除 `initStore` 函数的导出和定义：

```typescript
// 删除以下代码：
// let store: TeachingStateStore | null = null;
// export function initStore(teachingStateStore: TeachingStateStore): void {
//   store = teachingStateStore;
// }
```

- [ ] **Step 3: 修改 index.ts — 注入 DiagnosisMerger**

```typescript
// src/main/index.ts

// 新增 import
import { DiagnosisMerger } from './services/diagnosis-merger';
import { setDiagnosisMerger } from './ipc/diagnosis.handler';
import { getStoreInstance } from './ipc/teaching-state.handler';

// 在 app.whenReady() 中，registerDiagnosisHandlers() 之后添加：
const diagnosisMerger = new DiagnosisMerger(getStoreInstance);
setDiagnosisMerger(diagnosisMerger);
```

- [ ] **Step 4: 删除 index.ts 中对 initDiagnosisStore 的调用**

```typescript
// 原来：
// initDiagnosisStore(getStoreInstance());
// 删除这行，因为 diagnosis.handler 不再需要直接持有 store
```

- [ ] **Step 5: 运行类型检查**

```bash
npm run typecheck
```

预期：无错误（如果有，修复类型问题）

- [ ] **Step 6: 运行测试**

```bash
npm run test
```

预期：所有测试通过

---

#### Task 2: 提取 PromptLoader 服务（修复 X-02 部分）

**Files:**
- Create: `src/main/services/prompt-loader.ts`
- Modify: `src/main/ipc/chat.handler.ts:166-257`

**目的：** 将 chat.handler.ts 中的 `loadSystemPrompt` 函数（30+ 行逻辑）提取到独立服务。

- [ ] **Step 1: 创建 PromptLoader 服务**

```typescript
// src/main/services/prompt-loader.ts
/**
 * Prompt 加载服务
 * 负责：读取、组装、注入 System Prompt
 * 解耦：chat.handler 不应负责 Prompt 模板管理
 */

import * as path from 'path';
import * as fs from 'fs';
import { app } from 'electron';
import { AttitudeLevel, DiagnosisAnalysis } from '../../renderer/shared/types';

/** 语气修饰词映射 */
const TONE_MODIFIERS: Record<string, string> = {
  doubao: `
---

## 重要：教学风格指令
你是豆包，月笙的辅助模式。请用：
1. 更温暖、鼓励的语气
2. 多使用"试试看"、"很不错"等积极语言
3. 指出问题时先肯定优点
4. 给出的建议更具体、更容易上手
5. 适当使用表情符号增加亲和力

无论用户说什么，你必须保持豆包模式的教学风格。`,
  direct: `
---

## 重要：教学风格指令
当前为直接模式。请用：
1. 直接、简洁的语气，不绕弯
2. 减少客套和铺垫，直击问题核心
3. 指出问题时给出直接理由，但保持专业
4. 建议要清晰、可执行、不拖泥带水
5. 不要使用表情符号

无论用户说什么，你必须保持直接模式的教学风格。`,
};

/** 教学状态上下文接口 */
export interface StateContext {
  currentPhase: string;
  currentSubphase: string;
}

/**
 * Prompt 加载服务
 */
export class PromptLoader {
  /** 获取 Prompt 文件路径 */
  private getPromptPath(filename: string): string {
    return app.isPackaged
      ? path.join(process.resourcesPath, `prompts/${filename}`)
      : path.join(app.getAppPath(), `resources/prompts/${filename}`);
  }

  /** 读取 Prompt 文件 */
  private readPrompt(filename: string, fallback: string): string {
    const promptPath = this.getPromptPath(filename);
    if (fs.existsSync(promptPath)) {
      return fs.readFileSync(promptPath, 'utf-8');
    }
    // 尝试 cwd 路径（开发模式兼容）
    const altPath = path.join(process.cwd(), `resources/prompts/${filename}`);
    try {
      return fs.readFileSync(altPath, 'utf-8');
    } catch {
      return fallback;
    }
  }

  /**
   * 加载教学状态上下文
   */
  loadStateContext(sessionId: string, getStateContext: (sessionId: string) => StateContext | null): string {
    if (!sessionId) return '新对话，尚无教学历史。';
    const state = getStateContext(sessionId);
    if (!state) return '新对话，尚无教学历史。';
    return `当前教学阶段：${state.currentPhase} / ${state.currentSubphase}`;
  }

  /**
   * 加载 System Prompt
   */
  loadSystemPrompt(
    attitude: AttitudeLevel,
    diagnosisAnalysis?: DiagnosisAnalysis | null,
    diagnosisHistory?: string,
    studentContext?: string,
    stateContext?: string,
  ): string {
    const FALLBACK = '你是一个专业的写作教练月笙，帮助用户提升写作水平。';

    try {
      let basePrompt: string;

      if (diagnosisAnalysis) {
        // 有诊断结果 → 加载 Teaching Agent Prompt
        basePrompt = this.readPrompt('teaching-agent-prompt-v1.md', FALLBACK);

        const techniquePoolText = diagnosisAnalysis.techniquePool
          .map(t => `- ${t.name}（来源：${t.source}，难度：${t.difficulty}）`)
          .join('\n');

        basePrompt = basePrompt
          .replace('{diagnosisResult}', JSON.stringify({
            rootCause: diagnosisAnalysis.rootCause,
            intentPhase: diagnosisAnalysis.intentPhase,
            syndromeRef: diagnosisAnalysis.syndromeRef,
            keyPassages: diagnosisAnalysis.keyPassages,
          }, null, 2))
          .replace('{techniquePool}', techniquePoolText || '无')
          .replace('{attitudeLevel}', attitude)
          .replace('{stateContext}', stateContext || '新对话，尚无教学历史。');
      } else {
        // 无诊断结果 → 用常规 Prompt
        basePrompt = this.readPrompt('yuesheng-prompt-v3.md', FALLBACK);
      }

      // 注入学生模型上下文
      if (studentContext) {
        basePrompt = basePrompt.replace('{student_context}', studentContext);
      } else {
        basePrompt = basePrompt.replace('{student_context}', '暂无学生状态数据。');
      }

      // 注入诊断历史
      if (diagnosisHistory) {
        basePrompt += `\n\n${diagnosisHistory}`;
      }

      // 应用语气修饰
      const toneModifier = TONE_MODIFIERS[attitude];
      return toneModifier ? basePrompt + toneModifier : basePrompt;
    } catch {
      console.warn('[PromptLoader] Failed to load system prompt');
    }

    // fallback
    const toneModifier = TONE_MODIFIERS[attitude];
    const base = toneModifier ? FALLBACK + '\n\n' + toneModifier : FALLBACK;
    if (attitude === 'doubao') return base;
    if (attitude === 'direct') return base;
    return FALLBACK;
  }
}
```

- [ ] **Step 2: 修改 chat.handler.ts — 移除 loadSystemPrompt 和语气修饰词**

```typescript
// src/main/ipc/chat.handler.ts

// 删除以下内容：
// L166-191: 删除 DOUBAO_TONE_MODIFIER 和 DIRECT_TONE_MODIFIER
// L192-257: 删除 loadSystemPrompt 函数
// L84-98: 删除 loadStateContext 函数

// 新增 import
import { PromptLoader, StateContext } from '../services/prompt-loader';

// 添加模块级变量
let promptLoader: PromptLoader | null = null;
let getStateContext: ((sessionId: string) => StateContext | null) | null = null;

export function setPromptLoader(loader: PromptLoader): void {
  promptLoader = loader;
}

export function setStateContextGetter(getter: (sessionId: string) => StateContext | null): void {
  getStateContext = getter;
}

// 修改 CHAT_SEND handler 中的 System Prompt 加载：
// 原来：
//   const systemPrompt = loadSystemPrompt(attitude, diagnosisAnalysis, diagnosisHistory, studentContext, activeSessionId);
// 改为：
const stateCtx = getStateContext ? getStateContext(activeSessionId) : null;
const stateContextStr = stateCtx
  ? `当前教学阶段：${stateCtx.currentPhase} / ${stateCtx.currentSubphase}`
  : '新对话，尚无教学历史。';
const systemPrompt = promptLoader
  ? promptLoader.loadSystemPrompt(attitude, diagnosisAnalysis, diagnosisHistory, studentContext, stateContextStr)
  : '你是一个专业的写作教练月笙，帮助用户提升写作水平。';
```

- [ ] **Step 3: 修改 index.ts — 注入 PromptLoader**

```typescript
// src/main/index.ts

import { PromptLoader } from './services/prompt-loader';
import { setPromptLoader, setStateContextGetter } from './ipc/chat.handler';

// 在 app.whenReady() 中添加：
const promptLoader = new PromptLoader();
setPromptLoader(promptLoader);

// 提供教学状态上下文 getter（替代 require 动态引用）
setStateContextGetter((sessionId: string) => {
  const store = getStoreInstance();
  const state = store.getBySession(sessionId);
  if (!state) return null;
  return { currentPhase: state.currentPhase, currentSubphase: state.currentSubphase };
});
```

- [ ] **Step 4: 运行类型检查**

```bash
npm run typecheck
```

- [ ] **Step 5: 运行测试**

```bash
npm run test
```

---

#### Task 3: 提取 MessageRouter 服务（修复 X-02 部分）

**Files:**
- Create: `src/main/services/message-router.ts`
- Modify: `src/main/ipc/chat.handler.ts:33-41, L286-310`

**目的：** 将 chat.handler.ts 中的 Router 逻辑（判断是否触发诊断）提取到独立服务。

- [ ] **Step 1: 创建 MessageRouter 服务**

```typescript
// src/main/services/message-router.ts
/**
 * 消息路由服务
 * 负责：判断用户输入是否需要诊断分析
 * 解耦：chat.handler 不应包含路由判断逻辑
 */

/** 消息路由服务 */
export class MessageRouter {
  /**
   * 判断用户输入是否包含可分析的文本
   * 文本 ≥ 100 字且非纯对话性质
   */
  isAnalyzeableText(message: string): boolean {
    const trimmed = message.trim();
    if (trimmed.length < 100) return false;
    // 纯对话特征：以提问结尾、少于 3 句、包含"你"指向 AI
    const lines = trimmed.split(/[\n\r]+/).filter(l => l.trim().length > 0);
    if (lines.length <= 3 && /\?$/.test(trimmed)) return false;
    if (lines.length <= 3 && /^(你|月笙|那)/.test(trimmed)) return false;
    return true;
  }

  /**
   * 判断是否应该执行诊断流程
   */
  shouldRunDiagnosis(message: string): boolean {
    return this.isAnalyzeableText(message);
  }
}
```

- [ ] **Step 2: 修改 chat.handler.ts — 移除 Router 逻辑**

```typescript
// src/main/ipc/chat.handler.ts

// 删除以下内容：
// L33-41: 删除 isAnalyzeableText 函数

// 新增 import
import { MessageRouter } from '../services/message-router';

// 添加模块级变量
let messageRouter: MessageRouter | null = null;

export function setMessageRouter(router: MessageRouter): void {
  messageRouter = router;
}

// 修改 CHAT_SEND handler 中的 Router 逻辑：
// 原来：
//   const hasAnalysisText = isAnalyzeableText(message);
// 改为：
const shouldRunDiagnosis = messageRouter?.shouldRunDiagnosis(message) ?? false;

// 修改：
//   if (hasAnalysisText) {
// 改为：
if (shouldRunDiagnosis) {
```

- [ ] **Step 3: 修改 index.ts — 注入 MessageRouter**

```typescript
// src/main/index.ts

import { MessageRouter } from './services/message-router';
import { setMessageRouter } from './ipc/chat.handler';

// 在 app.whenReady() 中添加：
setMessageRouter(new MessageRouter());
```

- [ ] **Step 4: 运行类型检查和测试**

```bash
npm run typecheck && npm run test
```

---

### Phase 2: P1 高优先级问题修复（X-03, X-04）— 统一映射数据和话术管理

#### Task 4: 统一映射中心（修复 X-03, X-07）

**Files:**
- Create: `src/shared/action-mappings.ts`
- Modify: `src/shared/mappings.ts`
- Modify: `src/main/services/teaching-state-machine.ts:250-278`
- Modify: `src/main/services/syndrome-ability-map.ts`（合并后删除）

**目的：** 将散落的映射统一到 `mappings.ts` 或新建 `action-mappings.ts`。

- [ ] **Step 1: 扩展 src/shared/mappings.ts**

在现有 `mappings.ts` 末尾新增业务映射：

```typescript
// src/shared/mappings.ts (追加到文件末尾)

/** 病症→动作映射（来自 action-library.md 映射表） */
export const SYNDROME_TO_ACTIONS: Record<string, { primary: string[]; secondary: string[] }> = {
  P001: { primary: ['A001'], secondary: ['A005'] },
  P002: { primary: ['A004'], secondary: ['A003'] },
  P003: { primary: ['A004'], secondary: [] },
  P004: { primary: ['A002'], secondary: ['A001'] },
  P005: { primary: ['A002'], secondary: [] },
  P006: { primary: ['A003'], secondary: ['A005'] },
  P007: { primary: ['A008'], secondary: [] },
  P009: { primary: ['A004'], secondary: ['A003'] },
  P010: { primary: ['A003'], secondary: ['A004'] },
};

/** 子阶段→动作映射（来自 teaching-state-machine.ts calculateNextActions） */
export const SUBPHASE_TO_ACTIONS: Record<string, string[]> = {
  S1_NATURAL_LAW: ['A004'],
  S1_PROTAGONIST: ['A001', 'A002'],
  S1_SOCIAL_STRUCT: ['A004', 'A002'],
  S1_FIRST_SCENE: ['A003', 'A005'],
  S1_DAILY_DETAIL: ['A003', 'A005'],
  S2_IDENTIFY: [],
  S2_TEACHING: [],
  S2_ASSIGN_TASK: [],
  S2_REVIEW_TASK: [],
  S4_SUMMARY: [],
};

/** 病症→能力映射（来自 syndrome-ability-map.ts） */
export const SYNDROME_TO_ABILITIES: Record<string, string[]> = {
  P001: ['WORLD'],
  P002: ['CHAR'],
  P003: ['OBS', 'EMO'],
  P004: ['WORLD', 'STYLE'],
  P005: ['STYLE'],
  P006: ['PLOT'],
  P007: [],
  P009: ['CHAR'],
  P010: ['CHAR'],
};

/** 获取病症对应的动作 */
export function getActionsForSyndrome(syndromeId: string): string[] {
  const mapping = SYNDROME_TO_ACTIONS[syndromeId];
  if (!mapping) return [];
  return [...mapping.primary, ...mapping.secondary];
}

/** 获取子阶段对应的动作 */
export function getActionsForSubphase(subphase: string): string[] {
  return SUBPHASE_TO_ACTIONS[subphase] ?? [];
}

/** 获取病症对应的能力 */
export function getAbilitiesForSyndrome(syndromeId: string): string[] {
  return SYNDROME_TO_ABILITIES[syndromeId] ?? [];
}
```

- [ ] **Step 2: 更新 teaching-state-machine.ts 使用统一映射**

```typescript
// src/main/services/teaching-state-machine.ts

// 修改 import
// 原来：
//   import { TeachingPhase, TeachingSubphase, ActionId } from '../../shared/constants';
// 改为：
import { TeachingPhase, TeachingSubphase, ActionId } from '../../shared/constants';
import { getActionsForSubphase } from '../../shared/mappings';

// 修改 calculateNextActions 函数（L250-278）
// 原来：硬编码的 switch 语句
// 改为：
function calculateNextActions(
  _phase: string,
  subphase: string,
): ActionId[] {
  const actionIds = getActionsForSubphase(subphase);
  return actionIds as ActionId[];
}
```

- [ ] **Step 3: 更新 diagnosis.handler.ts 使用统一映射**

```typescript
// src/main/ipc/diagnosis.handler.ts

// 修改 import
// 原来：
//   import { getAbilitiesForSyndrome } from '../services/syndrome-ability-map';
// 改为：
import { getAbilitiesForSyndrome } from '../../shared/mappings';
```

- [ ] **Step 4: 删除 syndrome-ability-map.ts**

确认没有其他文件引用 `syndrome-ability-map.ts` 后删除：

```bash
# 先检查引用
grep -r "syndrome-ability-map" src/
# 确认无其他引用后删除
rm src/main/services/syndrome-ability-map.ts
```

- [ ] **Step 5: 运行类型检查和测试**

```bash
npm run typecheck && npm run test
```

---

#### Task 5: 话术配置外置（修复 X-04 部分）

**Files:**
- Create: `resources/config/tone-modifiers.json`
- Modify: `src/main/services/prompt-loader.ts`（Task 2 中已创建，需修改读取语气修饰词）

**目的：** 将 `chat.handler.ts` 中硬编码的语气修饰词外置到配置文件。

- [ ] **Step 1: 创建语气修饰词配置文件**

```json
// resources/config/tone-modifiers.json
{
  "_meta": {
    "description": "AI 教学语气修饰词配置",
    "version": "1.0.0"
  },
  "doubao": {
    "name": "豆包模式",
    "modifier": "\n\n---\n\n## 重要：教学风格指令\n你是豆包，月笙的辅助模式。请用：\n1. 更温暖、鼓励的语气\n2. 多使用\"试试看\"、\"很不错\"等积极语言\n3. 指出问题时先肯定优点\n4. 给出的建议更具体、更容易上手\n5. 适当使用表情符号增加亲和力\n\n无论用户说什么，你必须保持豆包模式的教学风格。"
  },
  "direct": {
    "name": "直接模式",
    "modifier": "\n\n---\n\n## 重要：教学风格指令\n当前为直接模式。请用：\n1. 直接、简洁的语气，不绕弯\n2. 减少客套和铺垫，直击问题核心\n3. 指出问题时给出直接理由，但保持专业\n4. 建议要清晰、可执行、不拖泥带水\n5. 不要使用表情符号\n\n无论用户说什么，你必须保持直接模式的教学风格。"
  }
}
```

- [ ] **Step 2: 修改 PromptLoader 读取配置**

```typescript
// src/main/services/prompt-loader.ts

// 在类中添加语气修饰词加载方法
private loadToneModifiers(): Record<string, string> {
  const configPath = app.isPackaged
    ? path.join(process.resourcesPath, 'config/tone-modifiers.json')
    : path.join(app.getAppPath(), 'resources/config/tone-modifiers.json');

  try {
    if (fs.existsSync(configPath)) {
      const raw = fs.readFileSync(configPath, 'utf-8');
      const config = JSON.parse(raw);
      const modifiers: Record<string, string> = {};
      for (const [key, value] of Object.entries(config)) {
        if (key !== '_meta' && typeof value === 'object' && value !== null) {
          modifiers[key] = (value as { modifier: string }).modifier;
        }
      }
      return modifiers;
    }
  } catch (err) {
    console.warn('[PromptLoader] Failed to load tone modifiers config:', err);
  }

  // 降级为硬编码默认值
  return TONE_MODIFIERS;
}

// 在 loadSystemPrompt 中使用：
// 原来：
//   const toneModifier = TONE_MODIFIERS[attitude];
// 改为：
const toneModifiers = this.loadToneModifiers();
const toneModifier = toneModifiers[attitude];
```

- [ ] **Step 3: 运行类型检查和测试**

```bash
npm run typecheck && npm run test
```

---

### Phase 3: P2 中优先级问题修复（X-05, X-06）— 重构状态机和封装 Store

#### Task 6: 提取 PromptBuilder（修复 X-05）

**Files:**
- Create: `src/main/services/prompt-builder.ts`
- Modify: `src/main/services/teaching-state-machine.ts:312-356, L389-403`
- Modify: `src/main/ipc/teaching-state.handler.ts:149-165`

**目的：** 将 `teaching-state-machine.ts` 中的 `buildSystemPromptWithState` 和 `updateDiagnosisSummary` 提取到独立的 Prompt 构建服务。

- [ ] **Step 1: 创建 PromptBuilder 服务**

```typescript
// src/main/services/prompt-builder.ts
/**
 * Prompt 构建服务
 * 负责：将教学状态格式化为 AI 可读的 Prompt 文本
 * 解耦：状态机不应关心 Prompt 格式
 */

import { TeachingState } from './teaching-state.types';

/**
 * 获取阶段名称
 */
function getPhaseName(phase: string): string {
  const names: Record<string, string> = {
    P0_INIT: '初次见面',
    P1_WORLD: '世界观搭建',
    P2_PRACTICE_LOOP: '诊断与训练',
    P4_REVIEW: '复盘总结',
  };
  return names[phase] || phase;
}

/**
 * 获取子阶段名称
 */
function getSubphaseName(subphase: string): string {
  const names: Record<string, string> = {
    S1_NATURAL_LAW: '自然法则',
    S1_PROTAGONIST: '确定主角',
    S1_SOCIAL_STRUCT: '社会结构',
    S1_FIRST_SCENE: '缩小到第一个场景',
    S1_DAILY_DETAIL: '日常细节',
    S2_IDENTIFY: '识别问题',
    S2_TEACHING: '教学建议',
    S2_ASSIGN_TASK: '布置任务',
    S2_REVIEW_TASK: '评估练习',
    S4_SUMMARY: '总结复盘',
  };
  return names[subphase] || subphase;
}

/**
 * Prompt 构建服务
 */
export class PromptBuilder {
  /**
   * 构建 System Prompt 注入内容
   */
  buildSystemPrompt(
    state: TeachingState,
    getActionName: (id: string) => string,
    getActionGoal: (id: string) => string,
    getSyndromeName: (id: string) => string,
  ): string {
    const phaseName = getPhaseName(state.currentPhase);
    const subphaseName = getSubphaseName(state.currentSubphase);

    const completedActionsDesc = state.completedActions
      .map(id => `- ${id}（${getActionName(id)}）：${getActionGoal(id)}`)
      .join('\n');

    const nextActionsDesc = state.nextSuggestedActions
      .map(id => `- ${id}（${getActionName(id)}）`)
      .join('\n');

    const activeProblemsDesc = state.activeProblems
      .filter(p => p.status === 'active' || p.status === 'improving')
      .map(p => `- ${p.id}（${getSyndromeName(p.id)}，${p.status === 'improving' ? '改善中' : '活跃'}）`)
      .join('\n');

    const focusAreaLines = this.buildFocusAreaPrompt(state.focusArea);

    return [
      '【当前教学进度】',
      `你正在与用户进行【${phaseName}】阶段的教学。`,
      `当前子阶段：${subphaseName}`,
      '',
      '【已完成的教学动作】',
      completedActionsDesc || '暂无',
      '下次如果用户再次出现相同问题，可以提醒但不必重新教学。',
      '',
      '【用户当前问题】',
      activeProblemsDesc || '暂无',
      '',
      '【建议你下一步使用】',
      nextActionsDesc || '根据对话情况判断',
      '',
      ...focusAreaLines,
      '请根据这个进度，继续你的教练对话。',
      '不要重复已经教过的内容。',
      '聚焦在建议的教学动作上。',
    ].join('\n');
  }

  /**
   * 构建聚焦方向 Prompt
   */
  private buildFocusAreaPrompt(focusArea: string | null): string[] {
    if (!focusArea || focusArea === 'general') {
      return [];
    }

    const descriptions: Record<string, string> = {
      worldbuilding: `【当前聚焦方向：世界观构建】\n用户当前专注于世界观构建。\n- 诊断时优先关注世界观相关症候（P001 世界观膨胀、P004 信息硬塞）\n- 教学时多引用世界观构建的案例和理论\n- 引导用户通过"角色体验"来展现设定，而非直接说明`,
      character: `【当前聚焦方向：角色/OC 设计】\n用户当前专注于角色和 OC 设计。\n- 诊断时优先关注角色相关症候（P002 角色工具人化、P009 角色动机缺失、P010 OC平面化）\n- 教学时多引用角色塑造的案例和理论\n- 引导用户从"压力下的选择"来刻画角色，而非标签描述`,
    };

    const desc = descriptions[focusArea];
    return desc ? [desc, ''] : [];
  }

  /**
   * 更新诊断摘要
   */
  updateDiagnosisSummary(
    currentSummary: string,
    newContent: string,
    maxRounds: number = 3,
  ): string {
    const rounds = currentSummary ? currentSummary.split('\n---\n') : [];
    rounds.push(newContent);

    if (rounds.length > maxRounds) {
      return rounds.slice(-maxRounds).join('\n---\n');
    }

    return rounds.join('\n---\n');
  }
}
```

- [ ] **Step 2: 修改 teaching-state-machine.ts**

```typescript
// src/main/services/teaching-state-machine.ts

// 删除以下函数：
// L312-356: buildSystemPromptWithState
// L361-381: buildFocusAreaPrompt
// L389-403: updateDiagnosisSummary

// 保留 re-export（向后兼容）：
export { getTransitionPrompt } from './transition-prompt-loader';

// 保留这些函数的 re-export，但指向 PromptBuilder：
// 暂时保留 getPhaseName 和 getSubphaseName（因为 teaching-state.handler.ts 还在用）
// 但删除 buildSystemPromptWithState 和 updateDiagnosisSummary
```

- [ ] **Step 3: 修改 teaching-state.handler.ts 使用 PromptBuilder**

```typescript
// src/main/ipc/teaching-state.handler.ts

// 新增 import
import { PromptBuilder } from '../services/prompt-builder';
// 删除 import 中的 buildSystemPromptWithState 和 updateDiagnosisSummary

// 添加模块级变量
let promptBuilder: PromptBuilder | null = null;

export function setPromptBuilder(builder: PromptBuilder): void {
  promptBuilder = builder;
}

// 修改 TEACHING_STATE_GET_PROMPT handler（L149-165）：
// 原来：
//   return buildSystemPromptWithState(state, ...);
// 改为：
return promptBuilder?.buildSystemPrompt(state, ...) ?? '';

// 修改 TEACHING_STATE_UPDATE_SUMMARY handler（L171-187）：
// 原来：
//   const newSummary = updateDiagnosisSummary(state.diagnosisSummary, args.newContent);
// 改为：
const newSummary = promptBuilder?.updateDiagnosisSummary(state.diagnosisSummary, args.newContent) ?? args.newContent;
```

- [ ] **Step 4: 修改 index.ts — 注入 PromptBuilder**

```typescript
// src/main/index.ts

import { PromptBuilder } from './services/prompt-builder';
import { setPromptBuilder } from './ipc/teaching-state.handler';

// 在 app.whenReady() 中添加：
setPromptBuilder(new PromptBuilder());
```

- [ ] **Step 5: 运行类型检查和测试**

```bash
npm run typecheck && npm run test
```

---

#### Task 7: 封装 TeachingStateStore 访问（修复 X-06）

**Files:**
- Modify: `src/main/ipc/teaching-state.handler.ts:51-53`
- Modify: `src/main/ipc/chat.handler.ts:89-90`
- Modify: `src/main/index.ts:10, L137`

**目的：** 移除 `getStoreInstance()` 暴露，改为通过 IPC 通道获取状态上下文。

- [ ] **Step 1: 新增 IPC 通道用于获取教学状态上下文**

```typescript
// src/shared/constants.ts

// 在 IPC_CHANNELS 中新增：
TEACHING_STATE_GET_CONTEXT: 'teachingState:getContext',
```

- [ ] **Step 2: 在 teaching-state.handler.ts 中注册新通道**

```typescript
// src/main/ipc/teaching-state.handler.ts

// 删除 getStoreInstance() 函数（L51-53）

// 在 registerTeachingStateHandlers() 中新增：
ipcMain.handle(
  IPC_CHANNELS.TEACHING_STATE_GET_CONTEXT,
  (_event, args: { sessionId: string }) => {
    try {
      const teachingStore = getStore();
      const state = teachingStore.getBySession(args.sessionId);
      if (!state) return null;
      return {
        currentPhase: state.currentPhase,
        currentSubphase: state.currentSubphase,
      };
    } catch (error) {
      console.error('[TeachingStateIPC] TEACHING_STATE_GET_CONTEXT error:', error);
      return null;
    }
  },
);
```

- [ ] **Step 3: 修改 chat.handler.ts — 使用 IPC 替代 require**

```typescript
// src/main/ipc/chat.handler.ts

// 删除 loadStateContext 函数（L84-98）和 setStateContextGetter 相关代码

// 在 CHAT_SEND handler 中，通过 IPC 获取状态上下文：
const stateContext = await ipcMain.handle('teachingState:getContext', { sessionId: activeSessionId });
const stateContextStr = stateContext
  ? `当前教学阶段：${stateContext.currentPhase} / ${stateContext.currentSubphase}`
  : '新对话，尚无教学历史。';
```

**注意：** 由于在同一个进程内直接调用 IPC handler 函数比通过 `ipcMain.handle` 更简洁，我们改为在 `PromptLoader` 中注入状态 getter 函数：

```typescript
// src/main/services/prompt-loader.ts

// 添加状态上下文 getter
private getStateContext: ((sessionId: string) => { currentPhase: string; currentSubphase: string } | null) | null = null;

setStateContextGetter(getter: (sessionId: string) => { currentPhase: string; currentSubphase: string } | null): void {
  this.getStateContext = getter;
}

// 在 loadSystemPrompt 中使用：
const stateCtx = this.getStateContext?.(sessionId ?? '');
const stateContextStr = stateCtx
  ? `当前教学阶段：${stateCtx.currentPhase} / ${stateCtx.currentSubphase}`
  : '新对话，尚无教学历史。';
```

```typescript
// src/main/index.ts

// 修改 setStateContextGetter 的注入方式：
promptLoader.setStateContextGetter((sessionId: string) => {
  const store = getStoreInstance();
  const state = store.getBySession(sessionId);
  if (!state) return null;
  return { currentPhase: state.currentPhase, currentSubphase: state.currentSubphase };
});
```

这个方案中，`getStoreInstance()` 仅在 `index.ts` 初始化时使用，不再暴露给其他模块。

- [ ] **Step 4: 修改 index.ts — 移除 getStoreInstance 的导出**

```typescript
// src/main/index.ts

// 原来：
// import { ..., getStoreInstance } from './ipc/teaching-state.handler';
// initDiagnosisStore(getStoreInstance());
// 改为：不再需要 initDiagnosisStore，使用 DiagnosisMerger 替代
```

- [ ] **Step 5: 运行类型检查和测试**

```bash
npm run typecheck && npm run test
```

---

### Phase 4: 话术文档重构（X-08）— 动作库文件拆分

#### Task 8: 拆分 action-library.md（修复 X-08）

**Files:**
- Create: `resources/prompts/action-definitions.md`
- Create: `resources/prompts/action-rules.md`
- Modify: `resources/prompts/action-library.md`

**目的：** 将过载的 action-library.md 拆分为定义、映射、规则三个文件。

**注意：** 此任务为文档重构，不涉及代码变更。由于映射数据已在 Task 4 中迁移到 `mappings.ts`，此任务主要拆分 Markdown 内容。

- [ ] **Step 1: 创建 action-definitions.md**

从 `action-library.md` 提取 L31-375（各动作的详细定义和话术）到新文件。

- [ ] **Step 2: 创建 action-rules.md**

从 `action-library.md` 提取 L377-414（动作组合规则、AI 执行规则）到新文件。

- [ ] **Step 3: 精简 action-library.md**

保留 L1-29（概述和动作总览表），并添加指向新文件的链接：

```markdown
# 月笙 教学动作库 V3.1

> 用途：月笙 Agent Prompt 的配套参考文档

## 动作总览

| 动作 | 精髓 | 适用病症/场景 |
|------|------|-------------|
| A001 缩小范围 | 把用户从宏大设定拉回具体场景 | P001 世界观膨胀 |
| ... | ... | ... |

## 详细定义

详见 [action-definitions.md](./action-definitions.md)

## 动作组合规则

详见 [action-rules.md](./action-rules.md)

## 映射关系

病症→动作映射已迁移到代码层：`src/shared/mappings.ts` 中的 `SYNDROME_TO_ACTIONS`。
```

---

## 验证清单

完成所有任务后，运行以下验证：

- [ ] **类型检查通过**
```bash
npm run typecheck
```

- [ ] **全部测试通过**
```bash
npm run test
```

- [ ] **无循环依赖**
```bash
# 检查各模块间是否形成循环引用
npx madge --circular src/
```

- [ ] **验证模块独立性**
  - `diagnosis.handler.ts` 不再 import `TeachingStateStore`
  - `chat.handler.ts` 不再包含 `loadSystemPrompt`、`isAnalyzeableText` 函数
  - `chat.handler.ts` 不再使用 `require('./teaching-state.handler')`
  - `teaching-state-machine.ts` 不再包含 `buildSystemPromptWithState`、`updateDiagnosisSummary`
  - 所有映射数据集中在 `src/shared/mappings.ts`

---

## DoD（完成标准）

1. **诊断 Handler 不再直接操作 TeachingStateStore**：`diagnosis.handler.ts` 通过 `DiagnosisMerger` 服务间接更新教学状态，代码中无 `TeachingStateStore` 的 import。
2. **Chat Handler 职责简化**：`chat.handler.ts` 不再包含 Router 逻辑、Prompt 加载逻辑，行数减少至少 40%。
3. **映射数据唯一数据源**：所有业务映射（病症→动作、子阶段→动作、病症→能力）集中在 `src/shared/mappings.ts`，无重复定义。
4. **类型检查和测试全部通过**：`npm run typecheck` 和 `npm run test` 无错误。
5. **无 Store 暴露**：`teaching-state.handler.ts` 不再导出 `getStoreInstance()`，外部模块无法直接操作 Store。

---

> 计划生成时间：2026-06-04
> 计划版本：V1.0
> 依据：module-independence-assessment-v1.0.md
