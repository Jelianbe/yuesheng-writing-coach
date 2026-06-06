# 月笙写作教练 - 外部资源详细情况报告 V1.0

> **文档性质**：分资源深度剖析  
> **目标读者**：开发人员、架构师  
> **生成时间**：2026-06-04  
> **覆盖范围**：9个高价值外部资源的详细技术分析

---

## 目录

1. [Prober.ai — Challenge-Unlock 机制](#1-proberai)
2. [IntelliCode — 中心化学者状态](#2-intellicode)
3. [pyBKT — 贝叶斯知识追踪](#3-pybkt)
4. [OATutor — 开源自适应教学系统](#4-oatutor)
5. [Claw-STU — ZPD 校准流程](#5-claw-stu)
6. [OpenMAIC (清华) — 多智能体编排](#6-openmaic)
7. [GenMentor — 目标-技能映射架构](#7-genmentor)
8. [Stylus Education — 超细粒度诊断](#8-stylus)
9. [自适应脚手架理论 (arXiv:2508.01503)](#9-scaffolding-theory)
10. [综合推荐与实施优先级](#10-priority-summary)

---

## 1. Prober.ai — Challenge-Unlock 机制

### 1.1 资源背景

- **来源**：arXiv:2605.05598（2026年5月）
- **作者**：未公开（由搜索结果推断为教育AI研究团队）
- **核心创新**：Challenge-Unlock — 学生必须回答挑战问题后才能解锁导师建议，强迫主动思考
- **哲学立场**：**AI 不替学生写，只提问引导** — 与月笙教练哲学高度一致

### 1.2 技术架构

```
Prober.ai 两阶段 API 架构

阶段一：Challenge（挑战）
  LLM (角色A: 逻辑刺客审稿人)
    ↓ 生成 3 个挑战性问题
  Student Answers
    ↓
  LLM (角色B: 困惑的新手读者)
    ↓ 评估回答质量
  [通过？] ──Yes──→ 解锁阶段二
    ↓ No
  [追问/提示]

阶段二：Unlock（解锁建议）
  LLM 生成针对性教学建议
  （此时学生已证明自己尝试过思考）
```

**关键机制：三重 LLM 输出约束**

1. **系统提示否定约束**：明确告诉 LLM 不允许直接给答案
2. **内部推理协议**：要求 LLM 先输出推理过程，再输出最终回答（Chain-of-Thought 约束）
3. **JSON Schema 强制输出格式**：用结构化输出防止 LLM 跑题

### 1.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **哲学零冲突** | "不代笔"和月笙教练哲学完全一致 |
| **实现成本低** | 不需要新数据模型，只改 teaching-state-machine |
| **解决核心痛点** | 当前月笙诊断完直接给建议，学生容易"拿来主义" |
| **可验证效果** | Challenge-Unlock 有 A/B 测试框架（效果可衡量）|

### 1.4 对月笙项目的具体作用

**当前流程（无 Challenge-Unlock）**：
```
诊断完成 → 直接给教学建议 → 学生被动接受
```

**加入 Challenge-Unlock 后**：
```
诊断完成 → 生成 1-2 个反思问题 → 学生回答 → 评估回答质量
                                                  ↓
                                            [不够好] → 给提示，再问
                                            [够好]   → 解锁教学建议
```

**代码层面改动**：

在 `teaching-state-machine.ts` 中新增状态：

```typescript
// 现有状态
enum TeachingPhase {
  IDLE = 'idle',
  DIAGNOSING = 'diagnosing',
  DIAGNOSED = 'diagnosed',
  TEACHING = 'teaching',
  PRACTICING = 'practicing',
  REVIEWING = 'reviewing'
}

// 新增状态
enum TeachingPhase {
  // ... 现有状态 ...
  AWAITING_REFLECTION = 'awaiting_reflection',  // 新增
  REFLECTION_ASSESSED = 'reflection_assessed'     // 新增
}
```

在 `chat.handler.ts` 中，诊断完成后不直接进入 TEACHING，而是：
1. 调用 LLM 生成 1-2 个反思问题（基于诊断结果）
2. 把问题返回给用户
3. 等待用户回复
4. 评估回复质量（简单规则或轻量 LLM 调用）
5. 通过后，才注入教学建议到 System Prompt

### 1.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 架构改动 | ⭐⭐ | 只改状态机 + chat.handler，不动数据模型 |
| Prompt 工程 | ⭐⭐⭐ | 需要设计 Challenge 生成 Prompt + 回答评估 Prompt |
| 前端交互 | ⭐⭐ | 需要新的 UI 状态（"请先思考再查看建议"）|
| 测试 | ⭐⭐ | 需要模拟用户回复流程 |

**总计**：中等偏低，2-3天可完成原型。

### 1.6 前置需求

- ✅ 无强依赖（可以独立实施）
- ⚠️ 建议先修复 teaching-state-machine 中的状态流转 bug（如有）
- ⚠️ 建议先统一 Prompt 体系（V1/V3 断裂会影响 Challenge Prompt 的一致性）

### 1.7 实施路径

```
Day 1-2: 设计 Challenge 生成 Prompt + 回答评估 Prompt
Day 3-4: 修改 teaching-state-machine.ts 新增状态
Day 5-6: 修改 chat.handler.ts 注入新流程
Day 7:   前端适配（UI 状态提示）
Day 8-9: 测试 + 调优 Prompt
```

---

## 2. IntelliCode — 中心化学者状态

### 2.1 资源背景

- **来源**：GitHub (sirhanmacx/intellicode)
- **作者**：Sirhan Macx（独立开发者）
- **核心创新**：**中心化学者状态（Centralized Learner State）** — 所有教学 Agent 共享一个 LearnerState，避免状态不一致
- **架构模式**：单写者策略（Single Writer Policy）— 只有一个 Agent 可以写入状态

### 2.2 技术架构

**LearnerState Schema**：

```typescript
interface LearnerState {
  // 技能掌握度（核心）
  skillMastery: Map<string, number>;  // skillId → 0-1 掌握度
  
  // 误解记录
  misconceptions: Array<{
    conceptId: string;
    misconception: string;
    detectedAt: Date;
    resolved: boolean;
  }>;
  
  // 行为信号
  behavioralSignals: {
    timeOnTask: number;        // 任务停留时间
    helpRequestFrequency: number; // 求助频率
    errorPersistence: number;    // 错误持续度
    engagementLevel: number;     // 参与度 0-1
  };
  
  // 复习计划
  reviewSchedule: Map<string, {
    skillId: string;
    nextReviewAt: Date;
    interval: number;  // 间隔天数（艾宾浩斯曲线）
  }>;
  
  // 元认知
  metacognitive: {
    selfAssessmentAccuracy: number;  // 自我评估准确度
    reflectionDepth: number;          // 反思深度
  };
}
```

**单写者策略**：

```
┌─────────────────────────────────────────────┐
│           LearnerState (Single Source)        │
│  (所有 Agent 只读，只有一个 Agent 可写)      │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────┼──────────┐
    ↓          ↓          ↓
Diagnosis   Teaching   Practice
  Agent      Agent      Agent
 (只读)     (唯一写者)  (只读)
```

### 2.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **解决根本架构问题** | 月笙当前诊断结果、教学状态、学生模型散落各处，没有单一数据源 |
| **死代码复活** | `student-context.store.ts` 的更新逻辑可以直接对接 LearnerState |
| **支持多 Agent 扩展** | 未来月笙如果有多个教学 Agent，中心化状态是必须的 |
| **实现模式清晰** | 单写者策略避免了并发写入冲突 |

### 2.4 对月笙项目的具体作用

**当前数据流（断裂）**：

```
DiagnosisAgent → diagnosis-parser.ts → TeachingState.activeProblems (主进程)
                                            ↓
student-context.store.ts (渲染进程，从未被调用)
                                            ↓
AbilityProfileService (主进程，计算结果未被消费)
```

**目标数据流（中心化）**：

```
┌──────────────────────────────────────────────────┐
│            StudentModelService (主进程)            │
│  (替代 student-context.store.ts + AbilityProfile) │
│                                                  │
│  interface StudentModel {                         │
│    sessionId: string;                            │
│    syndromeHistory: SyndromeResult[];  // 诊断历史 │
│    abilityScores: Map<SyndromeId, number>; // 能力分 │
│    actionHistory: Action[];              // 教学动作历史 │
│    reflectionRecords: Reflection[];      // 反思记录 │
│  }                                             │
└──────────────┬───────────────────────────────────┘
               │
    ┌──────────┼──────────────┐
    ↓          ↓              ↓
Diagnosis   Teaching      Prompt
  Agent      Agent        Builder
            (读能力分)   (读症候历史)
```

**代码层面改动**：

1. **新建 `student-model.service.ts`**（主进程）：
```typescript
export class StudentModelService {
  private models: Map<string, StudentModel> = new Map();
  
  // 从诊断结果更新
  updateFromDiagnosis(sessionId: string, result: DiagnosisResult): void;
  
  // 从交互更新（激活死代码逻辑）
  updateFromInteraction(sessionId: string, message: ChatMessage): void;
  
  // 获取当前能力分（供 PromptBuilder 使用）
  getAbilityScores(sessionId: string): Map<SyndromeId, number>;
  
  // 单写者保护
  private async acquireWriteLock(sessionId: string): Promise<void>;
}
```

2. **修改 `chat.handler.ts`**：在诊断完成后调用 `studentModelService.updateFromDiagnosis()`

3. **修改 `prompt-builder.ts`**：从 `studentModelService.getAbilityScores()` 读取能力分，注入 System Prompt

4. **删除 `student-context.store.ts`**（渲染进程死代码）

### 2.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 架构改动 | ⭐⭐⭐⭐ | 需要新建 Service，修改多个现有文件 |
| 数据迁移 | ⭐⭐ | 需要从现有 SQLite 日志中恢复历史数据（如有）|
| 渲染进程通信 | ⭐⭐⭐ | 需要通过 IPC 把主进程的学生模型同步到渲染进程（用于 UI 展示）|
| 测试 | ⭐⭐⭐ | 需要 mock 学生模型状态 |

**总计**：中等偏高，1-2周完成。

### 2.6 前置需求

- ✅ 需要先统一症候 ID 体系（P001-P010，已完成）
- ⚠️ 需要先修复 Prompt 体系断裂（V1/V3 统一）
- ⚠️ 需要设计主进程→渲染进程的模型同步机制（IPC）

### 2.7 实施路径

```
Week 1:
  Day 1-2: 设计 StudentModel TypeScript 接口（参照 LearnerState）
  Day 3-4: 实现 StudentModelService（内存版，不持久化）
  Day 5:   修改 chat.handler.ts 注入更新逻辑

Week 2:
  Day 1-2: 实现 SQLite 持久化（新建 student_models 表）
  Day 3:   实现 IPC 同步机制（主进程→渲染进程）
  Day 4-5: 修改 PromptBuilder 读取学生模型
```

---

## 3. pyBKT — 贝叶斯知识追踪

### 3.1 资源背景

- **来源**：PyPI (pyBKT) + GitHub (CAHLR/pyBKT)
- **作者**：CAHLR（Carnegie Learning AI Research）
- **核心创新**：**贝叶斯知识追踪（Bayesian Knowledge Tracing）** — 用概率模型追踪学生的技能掌握度变化
- **理论基础**：Corbett & Anderson (1995) 经典 BKT 模型

### 3.2 技术架构

**BKT 四参数模型**：

```
对于每个技能 i，BKT 维护四个概率：

P(L_i) = prior          — 学生事先掌握技能 i 的概率
P(T_i) = learn          — 学生从"未掌握"到"掌握"的学习概率
P(S_i) = slip           — 已掌握却答错的概率（失误）
P(G_i) = guess          — 未掌握却答对的概率（猜测）
```

**更新公式（贝叶斯推理）**：

```
观察到学生答题结果后：

如果答对了：
  P(掌握 | 答对) = P(掌握) * (1 - P_S) / [P(掌握) * (1 - P_S) + (1 - P(掌握)) * P_G]
  
如果答错了：
  P(掌握 | 答错) = P(掌握) * P_S / [P(掌握) * P_S + (1 - P(掌握)) * (1 - P_G)]

然后应用学习更新：
  P(掌握)' = P(掌握) + (1 - P(掌握)) * P_T
```

**pyBKT Python API**：

```python
from pyBKT.models import model

# 训练 BKT 模型（从答题数据）
data = {
  'correct': [1, 0, 1, 1, 0, ...],  # 答题正确与否
  'skill': [0, 0, 0, 1, 1, ...]     # 对应的技能ID
}
bkt_model = model.Model()
bkt_model.fit(data)

# 预测未来答题正确率
pred = bkt_model.predict(data)

# 获取技能掌握度
mastery = bkt_model.mastery  # 每个技能的掌握概率 0-1
```

### 3.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **替代静态 severity→score 映射** | 当前 `AbilityProfile` 用 L1=85/L2=55/L3=20 静态映射，不追踪进步 |
| **科学衡量进步** | BKT 提供每个技能的掌握概率（0-1），比静态分数更科学 |
| **支持个性化教学** | 掌握度高的技能可以减少练习，掌握度低的技能需要更多训练 |
| **有现成库可用** | pyBKT 是成熟库，也可以直接用 TypeScript 重新实现算法 |

### 3.4 对月笙项目的具体作用

**当前能力评估（静态快照）**：

```typescript
// src/main/services/ability-profile.service.ts (当前实现)
private readonly SEVERITY_TO_SCORE: Record<SeverityLevel, number> = {
  L1: 85,  // 轻微 → 高分（能力强）
  L2: 55,  // 中等 → 中分
  L3: 20,  // 严重 → 低分（能力弱）
};

// 问题：每次诊断都是独立快照，不追踪"是否进步"
```

**BKT 赋能后的能力评估（动态追踪）**：

```typescript
// 新增：bk-t.service.ts
export class BKTService {
  // 每个症候对应一个 BKT 模型
  private models: Map<SyndromeId, BKTModel> = new Map();
  
  // 观察到一次诊断结果（"答题"）
  update(syndromeId: SyndromeId, severity: SeverityLevel): void {
    const isCorrect = severity === 'L1';  // L1 = 答对了（问题轻）
    const model = this.models.get(syndromeId);
    model.update(isCorrect);  // 贝叶斯更新
  }
  
  // 获取技能掌握度
  getMastery(syndromeId: SyndromeId): number {
    return this.models.get(syndromeId).mastery;  // 0-1
  }
}
```

**映射到月笙的诊断场景**：

| BKT 概念 | 月笙对应 | 说明 |
|----------|----------|------|
| "答题" | 一次写作诊断 | 每次用户提交文本并获得诊断结果 = 一次"答题" |
| "答对" | 症候 severity 降低 | 上次 L3，这次 L2 或 L1 = 进步 = "答对" |
| "答错" | 症候 severity 升高或不变 | 没进步 = "答错" |
| "技能" | 症候类型（P001-P010）| 每个症候对应一个独立 BKT 模型 |
| "掌握度" | 能力分数 | 掌握度 > 0.8 = 该症候已改善 |

### 3.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 算法理解 | ⭐⭐⭐ | BKT 算法本身不复杂，但参数估计需要理解 |
| TypeScript 实现 | ⭐⭐ | BKT 更新公式只有几行，容易重写 |
| 参数初始化 | ⭐⭐⭐⭐ | BKT 四参数需要初始化（可以用专家经验或历史数据训练）|
| 数据需求 | ⭐⭐⭐ | BKT 需要多次观测才能准确估计掌握度，新用户数据少时效果差 |

**总计**：中等，但**冷启动问题是最大挑战**。

### 3.6 前置需求

- ✅ 需要先完成 StudentModelService（IntelliCode 方案）— BKT 需要融入学生模型
- ⚠️ 需要设计"答题"定义 — 如何把诊断结果映射为 BKT 的"对/错"
- ⚠️ 需要历史数据来训练 BKT 参数（或设计合理的默认值）

### 3.7 实施路径

```
Week 1: 算法实现
  Day 1:   用 TypeScript 实现 BKT 更新公式（不依赖 pyBKT Python 库）
  Day 2-3: 设计症候→BKT 的映射规则（如何定义"答对"）
  Day 4-5: 集成到 StudentModelService

Week 2: 参数调优 + 冷启动策略
  Day 1-2: 设计 BKT 参数默认值（基于专家经验）
  Day 3-4: 实现冷启动策略（前 3 次诊断用规则，之后用 BKT）
  Day 5:   测试 + 调优
```

### 3.8 冷启动策略（关键！）

**问题**：BKT 需要 5-10 次观测才能准确估计掌握度，但新用户只有 1-2 次诊断记录。

**解决方案（借鉴 OATutor）**：

```
前 3 次诊断：用专家规则
  - severity 从 L3→L2→L1：快速进步，mastery 从 0.2→0.5→0.8
  - severity 不变：mastery 不变
  - severity 升高：mastery 下降 0.1

第 4 次诊断开始：切换到 BKT 动态追踪
```

---

## 4. OATutor — 开源自适应教学系统

### 4.1 资源背景

- **来源**：GitHub (jaredkirby/oatutor)
- **作者**：Jared Kirby（开源社区）
- **核心创新**：**完整的自适应教学系统参考实现** — 包含 BKT、技能模型、自适应问题选择、提示系统
- **技术栈**：React + Node.js + PostgreSQL（和月笙技术栈有重叠）

### 4.2 技术架构

**OATutor 核心模块**：

```
OATutor 架构

前端 (React):
  - SkillTree 组件（技能树可视化）
  - ProblemViewer 组件（问题展示）
  - HintSystem 组件（三级提示：hint→scaffold→solution）
  - ProgressDashboard 组件（进度仪表盘）

后端 (Node.js):
  - BKT Engine（贝叶斯知识追踪）
  - Skill Model（技能→问题映射）
  - Problem Selector（自适应问题选择）
  - Hint Generator（提示生成）

数据库 (PostgreSQL):
  - skill_model.json（技能定义 + 问题映射）
  - course_plans.json（学习计划）
  - student_logs（学生行为日志）
```

**自适应问题选择算法**：

```javascript
// OATutor 的问题选择启发式（简化版）
function selectNextProblem(studentModel) {
  // 策略1：选最弱的技能（掌握度最低的）
  const weakestSkill = getWeakestSkill(studentModel.skillMastery);
  
  // 策略2：选"即将掌握"的技能（掌握度 0.6-0.8 的）
  const almostMastered = getAlmostMasteredSkills(studentModel.skillMastery);
  
  // 默认用策略1（选最弱技能）
  return getProblemForSkill(weakestSkill);
}
```

**三级提示系统**：

```
学生答错时：

Level 1 Hint（轻轻提示）:
  "你有没有考虑过 [关键概念]？"

Level 2 Scaffold（给脚手架）:
  "这一步应该这样做：[部分解法]"

Level 3 Solution（给答案）:
  "[完整解法]"

→ 月笙可以借鉴这个三级提示设计教学动作的强度递进
```

### 4.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **完整系统参考** | OATutor 是"活生生的例子"，可以看到每个模块怎么实现 |
| **技术栈同源** | React + Node.js，和月笙的 Electron + React 有重叠 |
| **BKT + 自适应选择** | 可以直接借鉴其问题选择启发式 |
| **三级提示系统** | 给月笙的"引导→指导→挑战"三模式提供参考 |

### 4.4 对月笙项目的具体作用

**OATutor 可借鉴的模块 vs 月笙现有模块**：

| OATutor 模块 | 月笙对应 | 借鉴点 |
|--------------|----------|--------|
| `skill_model.json` | `SYNDROME_TO_ACTIONS` | 技能→问题映射的数据结构设计 |
| `ProblemSelector` | 训练推荐引擎（待开发）| 自适应推荐算法 |
| `HintSystem` | 教学动作强度（待开发）| 三级提示→三模式教学 |
| `ProgressDashboard` | 能力雷达图（已有，但简陋）| 进度可视化设计 |
| BKT Engine | `AbilityProfile`（静态）| 动态掌握度追踪 |

**具体借鉴：训练推荐引擎设计**

```typescript
// 借鉴 OATutor，设计月笙的训练推荐引擎
export class TrainingRecommender {
  // 推荐下一个练习目标
  recommend(sessionId: string, studentModel: StudentModel): TrainingGoal {
    const mastery = studentModel.abilityScores;
    
    // 策略1：选最弱的症候（掌握度最低的）
    const weakest = getLowestMastery(mastery);
    
    // 策略2：如果最弱症候的掌握度 < 0.3，先练它
    if (mastery[weakest] < 0.3) {
      return { syndromeId: weakest, actionId: getActionForSyndrome(weakest) };
    }
    
    // 策略3：如果最弱症候的掌握度 0.3-0.7，混合练习
    return selectMixedPractice(mastery);
  }
}
```

### 4.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 代码复用 | ⭐ | OATutor 是独立系统，不能直接复用代码 |
| 设计借鉴 | ⭐⭐ | 需要理解 OATutor 架构，提取可借鉴的设计模式 |
| 训练系统开发 | ⭐⭐⭐⭐ | 月笙目前没有训练系统，需要从零开发 |
| 内容创作 | ⭐⭐⭐⭐⭐ | 训练题目需要人工创作（或 AI 生成+人工审核）|

**总计**：中高，训练系统的内容创作是最大瓶颈。

### 4.6 前置需求

- ✅ 需要先完成 StudentModelService + BKTService（能力追踪基础）
- ⚠️ 需要设计训练内容的数据模型（练习题目 + 评分标准）
- ⚠️ 需要创作或生成第一批训练题目（每个症候 5-10 题）

### 4.7 实施路径

```
Phase 1: 借鉴数据结构设计（1周）
  - 参考 OATutor 的 skill_model.json，设计月笙的训练内容数据模型
  
Phase 2: 实现推荐引擎（1周）
  - 实现 TrainingRecommender（借鉴 OATutor 的问题选择算法）
  
Phase 3: 创作训练内容（2-4周，人力瓶颈）
  - 为每个症候（P001-P010）创作 5-10 个微型练习
  - 例如 P001"视角混乱" → 给一段视角混乱的文本，让用户识别问题
  
Phase 4: 前端训练界面（1周）
  - 实现训练练习的交互界面
```

---

## 5. Claw-STU — ZPD 校准流程

### 5.1 资源背景

- **来源**：PyPI (clawstu) + GitHub (sirhanmacx/clawstu)
- **作者**：Sirhan Macx（同 IntelliCode 作者）
- **核心创新**：**ZPD（最近发展区）校准流程** — 通过 3-5 道诊断题建立用户能力基线
- **哲学**：SOUL.md 教学哲学（"不替代学生思考"）

### 5.2 技术架构

**ZPD 校准流程**：

```
新用户首次使用 Claw-STU：

Step 1: 能力自测（3-5 道题）
  Q1: [简单题] → 答对 → 继续
              → 答错 → 记录"该技能薄弱"
  Q2: [中等题] → 答对 → 继续
              → 答错 → 记录
  Q3: [难题]   → 答对 → 记录"该技能强"
              → 答错 → 记录

Step 2: 建立基线
  根据答题结果，估计每个技能的 ZPD 区间：
    ZPD = [能独立完成的难度, 需要帮助能完成的难度]
    
Step 3: 自适应教学
  推荐难度 ∈ ZPD 区间内
```

**Claw-STU 的 Learner Profile**：

```python
class LearnerProfile:
    # ZPD 区间（每个技能）
    zpd_ranges: Dict[str, Tuple[float, float]]  # skill_id → (lower, upper)
    
    # 当前教学模式下（面向 ZPD 的哪个位置）
    teaching_mode: str  # 'remediation' | 'scaffolded' | 'independent'
    
    # 信心指数
    confidence: Dict[str, float]  # skill_id → 0-1（学生对自己能力的信心）
    
    # SOUL 教学哲学约束
    philosophy: str = "dont_replace-student-thinking"
```

### 5.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **解决冷启动问题** | 月笙当前新用户第一次对话时，系统不知道用户水平 |
| **ZPD 理论支撑** | 教学内容的难度应该在用户的 ZPD 区间内（Vygotsky）|
| **和 Prober.ai 哲学一致** | 不替代学生思考 |
| **实现简单** | 只需要设计 3-5 个诊断问题 |

### 5.4 对月笙项目的具体作用

**当前新用户体验（无校准）**：

```
新用户：你好，我想提高写作
月笙：好的，请粘贴你的文字，我来帮你诊断
新用户：[粘贴长文]
月笙：[诊断...] → 可能给出过难或过易的教学建议
```

**加入 ZPD 校准后**：

```
新用户：你好，我想提高写作
月笙：好的！在开始前，我想了解一下你的写作水平。
      [显示 3 个快速诊断问题]

问题1（简单）：下面这段文本有什么问题？
      [给出一段有明显 P001 问题的短文]
      
新用户：视角混乱了
月笙：答对！继续下一个问题...

问题2（中等）：[...]
问题3（困难）：[...]

月笙：[根据答题结果] 我了解到你的写作水平是 XXX。
     现在请粘贴你的文字，我会给出针对性的诊断。
```

**代码层面改动**：

1. **新增 `zpd-calibration.service.ts`**：
```typescript
export class ZPDCalibrationService {
  // 3 个校准问题（硬编码或从题库随机选）
  private calibrationQuestions: CalibrationQuestion[] = [...];
  
  // 开始校准
  startCalibration(sessionId: string): CalibrationQuestion;
  
  // 评估回答，返回下一个问题 or 校准完成
  submitAnswer(sessionId: string, answer: string): {
    nextQuestion?: CalibrationQuestion;
    calibrationDone: boolean;
    estimatedLevel?: 'beginner' | 'intermediate' | 'advanced';
  };
}
```

2. **修改 `chat.handler.ts`**：检测新用户，触发校准流程

3. **前端新组件**：`CalibrationWizard.tsx`（引导式校准界面）

### 5.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 问题设计 | ⭐⭐⭐ | 需要设计 3-5 个能区分用户水平的问题 |
| 前端交互 | ⭐⭐ | 需要新的向导式 UI |
| 后端逻辑 | ⭐ | 逻辑简单（记录答题结果 + 估计水平）|
| 集成 | ⭐⭐ | 需要和现有对话流程衔接 |

**总计**：低到中等，1周可完成。

### 5.6 前置需求

- ✅ 无强依赖
- ⚠️ 需要设计校准问题（可以参考现有症候 P001-P010 设计）

### 5.7 实施路径

```
Day 1-2: 设计 3 个校准问题（每个问题覆盖 3-4 个症候类型）
Day 3:   实现 ZPDCalibrationService（后端逻辑）
Day 4-5: 实现 CalibrationWizard 前端组件
Day 6:   集成到 chat.handler.ts（新用户检测）
Day 7:    测试 + 调优
```

---

*[由于篇幅限制，第 6-10 节（OpenMAIC、GenMentor、Stylus、脚手架理论、综合推荐）将在下一个文件中继续]*
