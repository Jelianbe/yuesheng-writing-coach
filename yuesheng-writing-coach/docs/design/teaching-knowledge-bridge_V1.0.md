# 教学知识桥接架构 — 从文档到可执行代码

> 版本：V1.0 | 创建：2026-06-04
> 解决的问题：教学策略 / 诊断规则 / 用户模型写在 md 里无法被代码执行
> 核心原则：业务逻辑不进 Prompt，进数据模型和服务层

---

## 一、问题分析

### 1.1 现状

```
设计哲学 + 教学策略 + 自适应教学 Spec
  (9 个 md 文件, 数万字)
        ↓
AI 开发者阅读 → 理解 → 写到 System Prompt 里
  (不可测试、不可审计、AI 不一定遵守)
        ↓
        ↓ (另一个开发者)
        ↓
再次阅读 md → 理解 → 再写一次到 System Prompt
  (不一致、不可复用)
```

### 1.2 根因

每个 md 文件描述了**一组教学决策规则**，但这些规则从未被提取为**可执行的代码结构**：

| 文档 | 包含的规则 | 当前处理方式 |
|------|-----------|-------------|
| teaching-strategy-notes.md | 用户类型→教学方式映射 | 丢给 AI 自己判断 |
| SPEC_adaptive-teaching_V1.0.md | 三模式切换条件 | 不存在于代码 |
| syndrome-manual.md | 每个症候的严重度判断标准 | 不存在于代码 |
| design-philosophy.md | "一次只说一个问题" | 不存在于代码 |

### 1.3 解决方向

教学知识从**文档→代码**的转化路径：

```
md 文件 (人类可读)
  ↓ 提取结构化规则
配置文件 + 服务 (代码可执行)
  ↓ 消费
PromptBuilder 生成最终 Prompt (AI 可理解)
```

---

## 二、核心架构：三层桥接模型

```
┌─────────────────────────────────────────────────────┐
│                   教学知识层                          │
│  md 文档 / 教学策略 / 诊断规则 / 用户模型            │
└────────────────────┬────────────────────────────────┘
                     │ 提取结构化
                     ▼
┌─────────────────────────────────────────────────────┐
│              数据配置层 (Config)                      │
│  teaching-strategies.json  教学策略配置               │
│  problem-tiering.json      问题分级规则               │
│  user-type-matrix.json     用户类型矩阵               │
│  challenge-templates.json  挑战式微练模板             │
└────────────────────┬────────────────────────────────┘
                     │ 读取
                     ▼
┌─────────────────────────────────────────────────────┐
│              策略服务层 (Service)                     │
│  TeachingStrategyService  → 决定如何教                │
│  ProblemPrioritizer       → 决定说什么                │
│  StudentModelService      → 学生模型维护              │
│  ChallengeGenerator      → 生成引导问题              │
└────────────────────┬────────────────────────────────┘
                     │ 输出决策
                     ▼
┌─────────────────────────────────────────────────────┐
│              Prompt 生成层 (Builder)                  │
│  PromptBuilder 消费 Service 输出，不直接读 md         │
└─────────────────────────────────────────────────────┘
```

### 2.1 关键约束

- **数据配置层** = 所有可变的决策规则，JSON 外置，可热更新
- **策略服务层** = 读取 Config + 读取 StudentModel → **输出决策**
- **PromptBuilder** = 只消费 Service 的输出，不直接读 Config
- **StudentModel** = 所有决策的输入来源，不在 Prompt 里判断用户类型

---

## 三、数据配置层 (Config)

### 3.1 teaching-strategies.json

```json
{
  "teachingModes": {
    "scaffolding": {
      "name": "支架模式",
      "triggerConditions": {
        "skillMasteryMax": 0.3,
        "consecutiveFailures": 2
      },
      "instruction": "给出具体示范和结构化步骤，让用户模仿"
    },
    "guiding": {
      "name": "引导模式",
      "triggerConditions": {
        "skillMasteryMin": 0.3,
        "skillMasteryMax": 0.7
      },
      "instruction": "用提问引导用户自己发现答案，不给示范"
    },
    "challenging": {
      "name": "挑战模式",
      "triggerConditions": {
        "skillMasteryMin": 0.7
      },
      "instruction": "给出变形条件，要求用户在约束下创作"
    }
  }
}
```

### 3.2 user-type-matrix.json

```json
{
  "userTypes": {
    "newbie": {
      "label": "新手",
      "confidenceBoost": true,
      "challengeFrequency": "low",
      "praiseFrequency": "high",
      "toneProfile": "encouraging"
    },
    "experienced": {
      "label": "老手",
      "confidenceBoost": false,
      "challengeFrequency": "high",
      "praiseFrequency": "low",
      "toneProfile": "direct"
    },
    "analytical": {
      "label": "理工型",
      "preferredFormat": "problem→cause→evidence→solution",
      "toneProfile": "logical"
    },
    "emotional": {
      "label": "感性型",
      "preferredFormat": "example→feeling→demonstration",
      "toneProfile": "resonant"
    }
  },
  "teachingStyleMap": {
    "low_confidence_newbie": { "mode": "scaffolding", "tone": "encouraging" },
    "high_confidence_experienced": { "mode": "challenging", "tone": "direct" },
    "analytical_medium": { "mode": "guiding", "tone": "logical" },
    "emotional_low": { "mode": "scaffolding", "tone": "resonant" }
  }
}
```

### 3.3 problem-tiering.json

```json
{
  "problemTiers": [
    {
      "tier": "fatal",
      "label": "致命伤",
      "action": "must_fix",
      "conditions": {
        "types": ["logic_contradiction", "character_break"]
      }
    },
    {
      "tier": "structural",
      "label": "结构病",
      "action": "priority",
      "conditions": {
        "types": ["info_dumping", "perspective_drift", "motivation_missing", "pacing_stagnation"]
      }
    },
    {
      "tier": "surface",
      "label": "皮肤症",
      "action": "deferrable",
      "conditions": {
        "types": ["emotion_labeling", "reading_structure_single", "oc_planarization"]
      }
    }
  ],
  "maxIssuesPerTurn": 1,
  "prioritizationRule": "最高优先级的唯一一个，其余折叠"
}
```

### 3.4 challenge-templates.json

```json
{
  "templates": [
    {
      "syndromeId": "P004",
      "challenge": "你刚刚写了一段世界观说明。能不能删掉它，只用一个角色的动作来暗示同样的信息？",
      "mode": "rewrite_constrained"
    },
    {
      "syndromeId": "P001",
      "challenge": "你的开篇设定很宏大。现在请你挑出其中**一个**具体的场景，把其他设定全部删掉。",
      "mode": "narrow_focus"
    },
    {
      "syndromeId": "P009",
      "challenge": "你的角色正在做某个决定。写一句他内心真正的恐惧——不是剧情需要他做什么，而是他害怕什么。",
      "mode": "deepen_motivation"
    }
  ]
}
```

---

## 四、策略服务层 (Service)

### 4.1 StudentModelService

**定位**：学生模型的唯一维护者。所有服务读取学生状态都通过此服务。

```typescript
// src/main/services/student-model.service.ts

interface StudentModel {
  // 基础画像
  userId: string;
  userType: 'newbie' | 'experienced' | 'analytical' | 'emotional' | 'unknown';
  confidence: 'low' | 'medium' | 'high';
  
  // 能力掌握度（来自 AbilityProfile）
  skillMastery: Record<string, number>;  // abilityId → 0-1
  
  // 行为信号（来自 student-context.store）
  behavioralSignals: {
    consecutiveFailures: number;
    engagementTrend: 'rising' | 'stable' | 'declining';
    lastInteractionType: 'question' | 'rewrite' | 'reflection' | 'none';
  };
  
  // 错误模式历史
  misconceptions: Array<{
    syndromeId: string;
    description: string;
    detectedAt: string;
    resolvedAt?: string;
  }>;
  
  // 复习计划
  reviewSchedule: Array<{
    syndromeId: string;
    nextReviewAt: string;
    reviewCount: number;
  }>;
}

class StudentModelService {
  getBySession(sessionId: string): StudentModel;
  updateConfidence(sessionId: string, delta: number): void;
  recordMisconception(sessionId: string, syndromeId: string, description: string): void;
  recordInteraction(sessionId: string, type: 'question' | 'rewrite' | 'reflection'): void;
}
```

**数据来源**：
- `student-context.store.ts` (前端状态) → 行为信号
- `AbilityProfileService` (主进程) → 能力掌握度
- `teaching_state.active_problems` (DB) → 错误模式历史
- `user_type` 新字段 (待扩展) → 用户类型

### 4.2 TeachingStrategyService

**定位**：决定"怎么教"。

```typescript
// src/main/services/teaching-strategy.service.ts

interface TeachingStrategyDecision {
  teachingMode: 'scaffolding' | 'guiding' | 'challenging';
  tone: 'encouraging' | 'direct' | 'logical' | 'resonant';
  challengeFirst: boolean;  // Challenge-Unlock：先提问后教学
  format?: 'problem→cause→evidence→solution' | 'example→feeling→demonstration';
}

class TeachingStrategyService {
  constructor(
    private config: TeachingStrategyConfig,  // 从 JSON 加载
  ) {}
  
  decide(student: StudentModel): TeachingStrategyDecision {
    // 规则 1：置信度低 → 鼓励语气
    // 规则 2：连续失败 ≥ 2 → 支架模式
    // 规则 3：掌握度 > 0.7 → 挑战模式
    // 规则 4：用户类型决定 tone
    // 以上规则从 JSON 读取，不在代码里硬编码
  }
}
```

**关键设计**：decision 的逻辑是**从 config 加载规则**，不是 if-else 硬编码。修改教学策略只需改 JSON，不需改代码。

### 4.3 ProblemPrioritizer

**定位**：决定"说什么"。

```typescript
// src/main/services/problem-prioritizer.service.ts

interface PrioritizedProblem {
  syndromeId: string;
  tier: 'fatal' | 'structural' | 'surface';
  action: 'must_fix' | 'priority' | 'deferrable';
}

class ProblemPrioritizer {
  prioritize(syndromes: SyndromeResult[]): PrioritizedProblem[] {
    // 按 tier 排序 → 取第一个 → 其余标记为折叠
    // tier 映射从 problem-tiering.json 加载
  }
}
```

### 4.4 ChallengeGenerator

**定位**：生成 Challenge-Unlock 的引导问题。

```typescript
// src/main/services/challenge-generator.service.ts

class ChallengeGenerator {
  constructor(
    private templates: ChallengeTemplate[],  // 从 JSON 加载
  ) {}
  
  generate(syndromeId: string, context: string): string {
    // 查找模板 → 用 context 填充变量 → 返回引导问题
    // 如果无匹配模板，返回通用引导问题
  }
}
```

---

## 五、PromptBuilder 改造

当前 PromptBuilder 接收原始教学状态。改造后它接收**策略服务层的输出**：

```typescript
// 改造后
class PromptBuilder {
  buildSystemPrompt(
    strategy: TeachingStrategyDecision,      // 新增：策略决策
    prioritizedProblems: PrioritizedProblem[], // 新增：排序后的问题
    challenge: string | null,                 // 新增：引导问题
    state: TeachingState,                     // 原有
    nameMap: ..., goalMap: ..., syndromeMap: ..., // 原有
  ): string {
    // 不再直接判断状态
    // 而是将 strategy 的决策翻译为 Prompt 指令
    
    // 1. 教学模式指令
    // 2. 语气指令  
    // 3. Challenge-Unlock（如果有）
    // 4. 折叠次要问题
    // 5. 教学进度（原有）
  }
}
```

---

## 六、与现有系统的集成

### 6.1 数据流

```
用户发消息
  ↓
chat.handler.ts
  ├── MessageRouter → 判断是否需要诊断
  ├── StudentModelService.getBySession() → 加载学生模型
  ├── TeachingStrategyService.decide() → 策略决策
  ├── ProblemPrioritizer.prioritize() → 问题排序
  ├── ChallengeGenerator.generate() → 引导问题
  ├── PromptBuilder.buildSystemPrompt(策略决策) → 生成Prompt
  ├── API Proxy → AI 响应
  ├── DiagnosisParser → 解析诊断表
  ├── StudentModelService.recordMisconception() → 更新学生模型
  └── DiagnosisMerger → 合并到教学状态
```

### 6.2 文件清单

| 类别 | 文件 | 操作 |
|------|------|------|
| **新增** | `resources/config/teaching-strategies.json` | 新建 |
| **新增** | `resources/config/user-type-matrix.json` | 新建 |
| **新增** | `resources/config/problem-tiering.json` | 新建 |
| **新增** | `resources/config/challenge-templates.json` | 新建 |
| **新增** | `src/main/services/student-model.service.ts` | 新建 |
| **新增** | `src/main/services/teaching-strategy.service.ts` | 新建 |
| **新增** | `src/main/services/problem-prioritizer.service.ts` | 新建 |
| **新增** | `src/main/services/challenge-generator.service.ts` | 新建 |
| **修改** | `src/main/services/prompt-builder.ts` | 接收 Service 输出 |
| **修改** | `src/main/ipc/chat.handler.ts` | 调用策略服务 |
| **修改** | `src/main/index.ts` | 注册新 Service |
| **修改** | `src/shared/types.ts` | 扩展 AbilityProfile |
| **修改** | `src/renderer/stores/student-context.store.ts` | 扩展学生模型 |
| **验证** | 4 个 Config JSON 文件 | 类型检查（JSON Schema） |

---

## 七、执行顺序

### Phase A：数据配置层（先做）

把教学知识从 md 提取为 JSON。**不写任何代码**，只做结构化。

1. 从 `teaching-strategy-notes.md` 提取 → `user-type-matrix.json`
2. 从 `SPEC_adaptive-teaching_V1.0.md` 提取 → `teaching-strategies.json`
3. 从 `syndrome-manual.md` 提取 → `problem-tiering.json`
4. 从 `action-library.md` 提取 → `challenge-templates.json`

**DoD**：4 个 JSON 文件配置完成，每个字段有对应 md 文档的引用来源。

### Phase B：学生模型扩展（基础设施）

5. 扩展 `StudentModel` 类型 + `StudentModelService`
6. `AbilityProfile` 增加 `userType`、`learningStyle` 字段
7. `student-context.store.ts` 增加 `behavioralSignals` 追踪

**DoD**：StudentModelService.getBySession() 返回完整学生状态。

### Phase C：策略服务（核心逻辑）

8. 实现 `TeachingStrategyService` — 读取 Config + StudentModel → 决策
9. 实现 `ProblemPrioritizer` — 读取 problem-tiering.json → 排序症候
10. 实现 `ChallengeGenerator` — 读取 challenge-templates.json → 生成问题

**DoD**：每个 Service 有单元测试，输入/输出明确。

### Phase D：集成到现有流程（改动最小）

11. 改造 `PromptBuilder`，接收服务层输出
12. 在 `chat.handler.ts` 的 processMessage 中调用策略服务
13. `main/index.ts` 注册新服务

**DoD**：端到端验证：配置 JSON 变更 → AI 反应变化。

---

## 八、设计约束检查

| 约束 | 如何满足 |
|------|---------|
| 业务逻辑不进 Prompt | 教学决策由 Service 代码执行，Prompt 只做翻译 |
| 可测试 | Service 有明确 input/output，不依赖 AI |
| 可审计 | 每次决策 log：输入(StudentModel) → 输出(strategy decision) |
| 可热更新 | 教学策略在 JSON 中，重启即可加载新规则 |
| 最小改动 | 不改 diagnosis-parser、teaching-state-machine 等已有 Service |
| 推进不靠 Prompt 补丁 | 新 Service 替代了"在 Prompt 里加规则"的做法 |

---

## 九、风险

| 风险 | 概率 | 应对 |
|------|------|------|
| JSON 配置膨胀到不可维护 | 中 | 每个 JSON 文件不超过 100 行。超出则拆文件 |
| 学生模型数据来源不足 | 高 | V1 只有 diagnosis 和 interaction 两个来源，不依赖 ML 预测 |
| 策略决策规则过于简单 | 中 | V1 用确定性规则（从 JSON 读取），不做概率/ML 决策 |
| PromptBuilder 改造成本 | 低 | 接口变化，但内部实现可逐步替换 |

---

## 变更记录

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V1.0 | 2026-06-04 | 初始版本，三层桥接架构 | 月笙团队 |
