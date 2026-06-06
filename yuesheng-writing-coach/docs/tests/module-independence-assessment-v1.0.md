# 模块独立性评估报告

> 版本：V1.0
> 日期：2026-06-04
> 评估范围：教学库、诊断库、话术库（教学动作库、病症手册、训练任务库）
> 评估目标：识别权责不清、引用混乱、存放混乱、内容实质重复等问题

---

## 一、文件清单与职责声明

### 1.1 教学库（Teaching Library）

| 文件 | 声明职责 | 实际职责 |
|------|---------|---------|
| `src/main/services/teaching-state-machine.ts` | 教学阶段流转、子阶段推进、状态验证 | 阶段流转 + 子阶段推进 + 动作计算 + Prompt构建 + 诊断摘要管理 |
| `src/main/services/teaching-state.store.ts` | teaching_state 表的 CRUD | 教学状态持久化（职责清晰） |
| `src/main/services/teaching-state.types.ts` | 教学状态类型定义 | 类型定义（职责清晰） |
| `src/main/ipc/teaching-state.handler.ts` | 教学状态 IPC 处理 | IPC 路由 + 暴露 `getStoreInstance()` 供外部直接访问 |

### 1.2 诊断库（Diagnosis Library）

| 文件 | 声明职责 | 实际职责 |
|------|---------|---------|
| `src/main/services/diagnosis-parser.ts` | 解析 AI 回复中的诊断表 JSON | 解析 + 验证 + 构建（职责清晰） |
| `src/main/services/diagnosis.service.ts` | 诊断结果数据库操作 | 诊断持久化 + 结构化分析存取（职责清晰） |
| `src/main/ipc/diagnosis.handler.ts` | 诊断 IPC 处理 | **越权**：直接操作 TeachingStateStore、合并诊断到教学状态、推送 IPC |

### 1.3 话术库（Prompt Library）

| 文件 | 声明用途 | 实际内容 |
|------|---------|---------|
| `resources/prompts/action-library.md` | 教学动作库 | 动作定义 + 话术模板 + 病症→动作映射表 + 动作组合规则 + AI 执行规则 |
| `resources/prompts/syndrome-manual.md` | 病症识别手册 | 病症定义 + 信号权重 + 严重度分级 + 触发条件 + 对应动作 |
| `resources/prompts/training-tasks.md` | 训练任务库 | 任务定义 + 评估标准 + 训练流程 + AI 执行规则 |
| `resources/config/transition-prompts.json` | 过渡邀请话术配置 | 话术模板 + 变体轮询（职责清晰） |
| `resources/prompts/teaching-agent-prompt-v1.md` | Teaching Agent Prompt | Agent 系统提示词 |
| `resources/prompts/yuesheng-prompt-v3.md` | 月笙主 Prompt | 主系统提示词 |
| `resources/prompts/diagnosis-agent-prompt-v1.md` | Diagnosis Agent Prompt | 诊断 Agent 系统提示词 |

---

## 二、引用关系图

```
┌─────────────────────────────────────────────────────────────────┐
│                        chat.handler.ts                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ 实际职责过度膨胀：                                          │   │
│  │ - Router 逻辑（判断是否触发诊断）                            │   │
│  │ - 调用 Diagnosis Agent                                     │   │
│  │ - 加载 System Prompt（教学提示词）                           │   │
│  │ - 后处理诊断结果                                            │   │
│  └──────────────────────────────────────────────────────────┘   │
│         │                    │                    │              │
│         ▼                    ▼                    ▼              │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────────┐    │
│  │ diagnosis.   │   │ teaching-    │   │ loadSystemPrompt │    │
│  │ handler.ts   │   │ state.handler│   │ (本应在 prompt   │    │
│  │              │   │              │   │  层管理)         │    │
│  └──────┬───────┘   └──────┬───────┘   └──────────────────┘    │
│         │                  │                                    │
│         ▼                  ▼                                    │
│  ┌─────────────────────────────────────┐                        │
│  │      teaching-state.store.ts        │                        │
│  │      (被诊断 handler 直接操作)        │                        │
│  └─────────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                    话术库引用混乱                                 │
│                                                                 │
│  action-library.md ──────┐                                      │
│                          │  病症→动作映射（重复 3 处）             │
│  syndrome-manual.md ─────┼──→ P001 → A001                      │
│                          │     P002 → A004                      │
│  teaching-state-machine ─┘     P003 → A004                      │
│                              ...                                │
│                                                                 │
│  ┌─────────────────────────────────────────┐                    │
│  │     映射数据散落各处，无统一数据源           │                    │
│  │     mappings.ts 只有名称映射，没有业务逻辑   │                    │
│  └─────────────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 三、问题诊断

### X-01：诊断 Handler 越权操作教学状态（P0-严重）

**文件**：`src/main/ipc/diagnosis.handler.ts`

**问题**：诊断 Handler 直接 import 并操作 `TeachingStateStore`，违反了模块独立性原则。

**证据**：
```typescript
// diagnosis.handler.ts L19
import { TeachingStateStore } from '../services/teaching-state.store';

// L276-298: 直接合并诊断到 TeachingState
function mergeDiagnosisIntoTeachingState(diagnosis: DiagnosisEntry): void {
  if (!store) return;
  const state = store.getBySession(diagnosis.sessionId);
  if (!state) return;
  const updated = mergeSyndromesIntoState(state, diagnosis);
  store.update(diagnosis.sessionId, updated);
}
```

**影响**：
- 诊断库和教学库强耦合，无法独立测试或替换
- 诊断结果必须同步更新教学状态，无法异步处理
- 如果诊断逻辑变更，可能意外影响教学状态

**建议**：提取 `diagnosis-merger` 服务，通过事件通信而非直接调用 Store。

---

### X-02：Chat Handler 承担过多职责（P0-严重）

**文件**：`src/main/ipc/chat.handler.ts`

**问题**：chat.handler.ts 同时承担了 Router、Diagnosis Agent 调用、Prompt 加载、诊断后处理四个职责。

**证据**：
```typescript
// L286-310: Router 逻辑
const hasAnalysisText = isAnalyzeableText(message);
if (hasAnalysisText) {
  diagnosisAnalysis = await callDiagnosisAgent(message);
}

// L192-257: Prompt 加载（30+ 行逻辑）
function loadSystemPrompt(...): string {
  // 读取 teaching-agent-prompt-v1.md
  // 替换 {diagnosisResult}、{techniquePool}、{attitudeLevel}、{stateContext}
  // 读取 yuesheng-prompt-v3.md
  // 注入 studentContext、diagnosisHistory
}

// L363-367: 诊断后处理
processDiagnosisFromAI(fullResponse, activeSessionId, messageId);
```

**影响**：
- 违反单一职责原则，难以维护和测试
- Prompt 加载逻辑应该在专门的 Prompt 管理服务中
- Router 逻辑应该在专门的消息路由服务中

**建议**：拆分为 `message-router.ts`、`prompt-loader.ts`、`diagnosis-orchestrator.ts` 三个独立服务。

---

### X-03：病症→动作映射三处重复（P1-高）

**问题**：病症到动作的映射在三个地方重复定义，且内容不完全一致。

**对比**：

| 来源 | 位置 | P001 映射 | P002 映射 | P003 映射 |
|------|------|-----------|-----------|-----------|
| action-library.md | L312-329 映射表 | A001 缩小范围 | A004 现实锚点 | A004 现实锚点 |
| syndrome-manual.md | 各病症详细定义中 | A001 | A004 | A004 |
| teaching-state-machine.ts | L250-278 calculateNextActions | 按子阶段映射，不按病症 | 按子阶段映射，不按病症 | 按子阶段映射，不按病症 |

**关键矛盾**：
- `action-library.md` 和 `syndrome-manual.md` 定义了 **病症→动作** 的映射
- `teaching-state-machine.ts` 定义了 **子阶段→动作** 的映射
- 两套映射体系互不关联，但都影响 AI 的教学行为

**实际使用混乱**：
- AI 在 System Prompt 中收到 `teaching-state-machine.ts` 构建的「建议你下一步使用」列表
- 但同时也在 Prompt 中收到 `action-library.md` 的病症→动作映射
- 两套建议可能冲突，AI 不知道该遵循哪个

**建议**：统一到 `mappings.ts` 或新建 `src/shared/action-mappings.ts` 作为唯一数据源。

---

### X-04：话术内容散落多处（P1-高）

**问题**：话术模板和教学话术散落在多个文件中，没有统一管理。

**散落位置**：

| 话术类型 | 存放位置 | 格式 |
|---------|---------|------|
| 教学动作话术模板 | `action-library.md` 各动作定义中 | Markdown 内嵌 |
| 过渡邀请话术 | `resources/config/transition-prompts.json` | JSON |
| 病症识别信号 | `syndrome-manual.md` 各病症定义中 | Markdown 表格 |
| 训练任务话术 | `training-tasks.md` 各任务定义中 | Markdown |
| Agent 语气修饰 | `chat.handler.ts` L166-191（硬编码） | TypeScript 字符串 |

**问题**：
- 没有统一的话术管理机制
- `chat.handler.ts` 中硬编码了 `DOUBAO_TONE_MODIFIER` 和 `DIRECT_TONE_MODIFIER`，应该在配置文件中
- 修改话术需要同时修改多个文件
- 无法进行话术的 A/B 测试或版本管理

**建议**：建立统一的话术目录 `resources/prompts/scripts/`，按类型分类存放，并通过加载器动态读取。

---

### X-05：教学状态机混合了 Prompt 构建逻辑（P2-中）

**文件**：`src/main/services/teaching-state-machine.ts`

**问题**：`buildSystemPromptWithState()` 函数（L312-356）将教学状态转换为 Prompt 文本，这是 Prompt 层的职责，不应在状态机中。

**证据**：
```typescript
export function buildSystemPromptWithState(
  state: TeachingState,
  getActionName: (id: string) => string,
  getActionGoal: (id: string) => string,
  getSyndromeName: (id: string) => string,
): string {
  // 30+ 行 Prompt 模板拼接逻辑
  return [
    '【当前教学进度】',
    `你正在与用户进行【${phaseName}】阶段的教学。`,
    // ...
  ].join('\n');
}
```

**影响**：
- 状态机负责流程控制，不应关心 Prompt 格式
- 修改 Prompt 格式需要改动状态机文件
- 难以独立测试状态流转逻辑

**建议**：将 `buildSystemPromptWithState` 移至新的 `src/main/services/prompt-builder.ts`。

---

### X-06：teaching-state.handler 暴露内部 Store（P2-中）

**文件**：`src/main/ipc/teaching-state.handler.ts`

**问题**：`getStoreInstance()` 函数（L51-53）将内部 Store 暴露给外部模块，破坏了封装性。

**证据**：
```typescript
export function getStoreInstance(): TeachingStateStore {
  return getStore();
}
```

**被谁使用**：
- `chat.handler.ts` L89: `const { getStoreInstance } = require('./teaching-state.handler');`

**问题**：
- 使用 `require` 动态引入，绕过了正常的模块依赖管理
- 外部模块可以直接操作 Store，不受 IPC 层控制
- 无法追踪 Store 的访问来源

**建议**：提供专用的 IPC 通道或事件，而非暴露 Store 实例。

---

### X-07：mappings.ts 不完整（P2-中）

**文件**：`src/shared/mappings.ts`

**问题**：作为"共享映射中心"，只包含了名称映射，缺少业务映射。

**当前内容**：
- `SYNDROME_NAMES`：症候名称
- `SYNDROME_META`：症候元数据（含严重度）
- `ACTION_NAMES`：动作名称
- `ACTION_GOALS`：动作目标
- `ABILITY_NAMES`：能力名称

**缺失内容**：
- 病症→动作映射（在 action-library.md 中）
- 病症→能力映射（在 syndrome-ability-map.ts 中）
- 病症→训练任务映射（在 training-tasks.md 中）
- 子阶段→动作映射（在 teaching-state-machine.ts 中）

**建议**：将所有业务映射统一到 `mappings.ts` 或拆分为多个映射文件。

---

### X-08：action-library.md 内容过载（P2-中）

**文件**：`resources/prompts/action-library.md`

**问题**：一个文件包含了四种不同类型的内容：

1. **动作定义**（L14-26）：动作编号、精髓、适用病症
2. **详细话术**（L31-375）：每个动作的核心逻辑、话术模板、禁忌
3. **业务映射**（L312-329）：病症→动作映射表
4. **执行规则**（L377-414）：动作组合规则、AI 执行规则

**建议**：拆分为三个文件：
- `action-definitions.md`：动作定义和话术
- `action-mappings.json`：病症→动作映射（结构化数据）
- `action-rules.md`：组合规则和执行规则

---

## 四、问题汇总表

| 编号 | 严重度 | 问题描述 | 影响模块 | 建议优先级 |
|------|--------|---------|---------|-----------|
| X-01 | P0-严重 | 诊断 Handler 直接操作教学状态 Store | 诊断库、教学库 | 立即修复 |
| X-02 | P0-严重 | Chat Handler 承担过多职责 | 聊天模块 | 立即修复 |
| X-03 | P1-高 | 病症→动作映射三处重复且不一致 | 教学库、话术库 | 优先修复 |
| X-04 | P1-高 | 话术内容散落多处，无统一管理 | 话术库 | 优先修复 |
| X-05 | P2-中 | 教学状态机混合 Prompt 构建逻辑 | 教学库 | 规划修复 |
| X-06 | P2-中 | 教学 Handler 暴露内部 Store | 教学库 | 规划修复 |
| X-07 | P2-中 | 共享映射中心不完整 | 共享层 | 规划修复 |
| X-08 | P2-中 | 动作库文件内容过载 | 话术库 | 规划修复 |

---

## 五、总结

### 5.1 整体评估

项目在模块设计上有一定的独立性意识，将教学、诊断、话术分为不同的文件和目录。但在实际实现中，存在以下系统性问题：

1. **权责边界模糊**：诊断库直接操作教学状态，Chat Handler 承担了 Router、Prompt 加载、诊断后处理等多重职责。
2. **引用关系混乱**：`teaching-state.handler.ts` 暴露内部 Store，`chat.handler.ts` 使用 `require` 动态引用，绕过了正常的模块依赖管理。
3. **存放位置不合理**：话术模板、业务映射、执行规则散落在多个文件中，没有统一管理。
4. **内容实质重复**：病症→动作映射在 `action-library.md`、`syndrome-manual.md`、`teaching-state-machine.ts` 三处重复定义，且不完全一致。

### 5.2 核心矛盾

**两套动作映射体系的矛盾**：
- 诊断驱动的映射：病症 → 动作（action-library.md, syndrome-manual.md）
- 阶段驱动的映射：子阶段 → 动作（teaching-state-machine.ts）

这两套映射互不关联，但都影响 AI 的教学行为，导致 AI 可能收到冲突的建议。

### 5.3 建议方向

1. **立即修复（P0）**：解决 X-01 和 X-02，消除模块间的越权操作和职责膨胀。
2. **优先修复（P1）**：统一映射数据源，建立话术管理机制，解决 X-03 和 X-04。
3. **规划修复（P2）**：重构状态机、封装 Store、完善映射中心，解决 X-05~X-08。

---

> 报告生成时间：2026-06-04
> 评估人：AI 辅助分析
> 下一步：根据优先级制定修复计划
