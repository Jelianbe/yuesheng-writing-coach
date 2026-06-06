# 月笙写作教练 - 外部资源详细情况报告 V1.0

> **文档性质**：分资源深度剖析（续）  
> **目标读者**：开发人员、架构师  
> **生成时间**：2026-06-04  
> **覆盖范围**：剩余 4 个资源 + 综合推荐

---

## 目录（续）

6. [OpenMAIC (清华) — 多智能体编排](#6-openmaic)
7. [GenMentor — 目标-技能映射架构](#7-genmentor)
8. [Stylus Education — 超细粒度诊断](#8-stylus)
9. [自适应脚手架理论 (arXiv:2508.01503)](#9-scaffolding-theory)
10. [综合推荐与实施优先级](#10-priority-summary)

---

## 6. OpenMAIC (清华) — 多智能体编排

### 6.1 资源背景

- **来源**：GitHub (THU-MAIC/OpenMAIC)
- **作者**：清华大学 NLP 实验室
- **核心创新**：**多智能体课堂编排系统** — 28+ 种教学动作，支持 DeepSeek/OpenAI/Claude
- **定位**：一对多（课堂场景），月笙是一对一（教练场景）

### 6.2 技术架构

**OpenMAIC 架构**：

```
OpenMAIC 多智能体系统

Director Graph (LangGraph 状态机)
    │
    ├── Classroom Manager Agent（课堂管理）
    │     ├── 学生签到、分组、进度追踪
    │     └── 课堂节奏控制
    │
    ├── Teacher Agent（主讲教师）
    │     ├── 知识讲解、提问、反馈
    │     └── 28+ 教学动作（explain, question, feedback, etc.）
    │
    ├── Teaching Assistant Agent（助教）
    │     ├── 个别辅导、答疑
    │     └── 小组讨论引导
    │
    ├── Student Agent xN（学生模拟器）
    │     ├── 模拟学生行为（回答、提问、走神）
    │     └── 用于测试教学策略
    │
    └── Evaluator Agent（评估者）
          ├── 教学质量评估
          └── 学生掌握度估计
```

**技术栈**：

| 组件 | 技术 | 月笙对应 |
|------|------|----------|
| 状态机 | LangGraph | teaching-state-machine.ts |
| 前端 | Next.js + TypeScript | Electron + React |
| 状态管理 | Zustand | Zustand (student-context.store.ts) |
| LLM | DeepSeek/OpenAI/Claude | DeepSeek V3 |
| 工具调用 | LangChain Tools | 现有 Tool 体系 |

**核心数据结构（从 GitHub README 推断）**：

```typescript
// OpenMAIC 的 Action 类型（28+ 种）
type TeachingAction =
  | 'explain'           // 知识讲解
  | 'question'          // 提问
  | 'hint'              // 提示
  | 'feedback'          // 反馈
  | 'scaffold'          // 脚手架
  | 'challenge'         // 挑战
  | 'reflect'           // 反思引导
  | 'summarize'         // 总结
  | 'assess'            // 评估
  | ...;                // 共 28+ 种

// Director Graph 状态
interface GraphState {
  currentPhase: 'lecture' | 'discussion' | 'practice' | 'assessment';
  activeAgent: 'teacher' | 'assistant' | 'evaluator';
  classroomContext: ClassroomContext;
  studentStates: Map<string, StudentState>;  // 一对多
}
```

### 6.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **动作引擎设计参考** | 月笙目前只有 A001-A012，OpenMAIC 的 28+ 动作类型可借鉴扩展 |
| **LangGraph 状态机模式** | 月笙的 teaching-state-machine.ts 可以参照 LangGraph 的可视化状态图重构 |
| **支持 DeepSeek** | 月笙底层也是 DeepSeek，集成无障碍 |
| **多 Agent 协作模式** | 未来月笙如果有"诊断 Agent"+"教学 Agent"+"训练 Agent"协同，可参考 |

### 6.4 对月笙项目的具体作用

**6.4.1 扩展教学动作库**

月笙现有 A001-A012 动作，对比 OpenMAIC 的 28+ 动作：

| OpenMAIC 动作 | 月笙可借鉴 | 对应月笙动作 |
|---------------|--------------|--------------|
| `explain` | 知识讲解 | A001（认知重构）|
| `question` | 提问引导 | A003（五问法）|
| `hint` | 逐级提示 | 可新增 A013 |
| `scaffold` | 脚手架 | A004（现实锚点）|
| `challenge` | 挑战任务 | 可新增 A014 |
| `reflect` | 反思引导 | 可新增（配合 Challenge-Unlock）|
| `summarize` | 总结回顾 | 可新增 A015 |
| `assess` | 评估掌握度 | 可新增（配合 BKT）|

**建议**：V2 扩展动作库到 20+ 个，参考 OpenMAIC 的分类方式。

**6.4.2 状态机可视化重构**

teaching-state-machine.ts 当前是手写状态转换，可以考虑：

```typescript
// 借鉴 LangGraph 的思路，用声明式状态图
const teachingGraph = new StateGraph({
  phases: ['idle', 'diagnosing', 'diagnosed', 'awaiting_reflection', 'teaching', 'practicing', 'reviewing'],
  transitions: [
    { from: 'diagnosed', to: 'awaiting_reflection', condition: 'challengeUnlockEnabled' },
    { from: 'awaiting_reflection', to: 'teaching', condition: 'reflectionPassed' },
    // ...
  ]
});
```

**6.4.3 教学策略可配置化**

OpenMAIC 的 28+ 动作是通过配置文件定义的，月笙可以借鉴：

```json
// teaching-actions.json（新增配置文件）
{
  "A001": {
    "name": "认知重构",
    "type": "explain",
    "intensity": "soft",
    "applicableTo": ["P001", "P002"],
    "preconditions": ["diagnosisDone"],
    "llmPromptTemplate": "..."  // 可从 action-library.md 提取
  },
  "A003": {
    "name": "五问法",
    "type": "question",
    "intensity": "medium",
    ...
  }
}
```

### 6.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 直接代码复用 | ❌ 不可复用 | OpenMAIC 是一对多课堂，月笙是一对一教练 |
| 架构模式借鉴 | ⭐⭐⭐ | LangGraph 状态机模式可借鉴，但需要重写 |
| 动作库扩展 | ⭐⭐ | 新增动作定义 + Prompt 模板 |
| 集成成本 | ⭐⭐⭐⭐ | 需要大幅改造现有架构 |

**总计**：中等偏高，建议作为 V2/V3 的长期参考，不急于集成。

### 6.6 前置需求

- ✅ 需要先统一教学动作定义（A001-A012 的权威来源已是 syndrome-manual.md）
- ⚠️ 需要设计动作配置化框架（teaching-actions.json）
- ⚠️ 需要重构 teaching-state-machine 为声明式状态图

### 6.7 实施路径（长期参考）

```
Phase 1（V2，1-2 个月）: 动作库扩展
  - 参考 OpenMAIC 的 28+ 动作，扩展月笙到 20+ 动作
  - 设计 teaching-actions.json 配置格式

Phase 2（V3，3-6 个月）: 状态机重构
  - 用声明式状态图替代手写状态转换
  - 实现动作策略可配置化

不涉及代码集成，只借鉴设计思路。
```

---

## 7. GenMentor — 目标-技能映射架构

### 7.1 资源背景

- **来源**：GitHub (GeminiLight/gen-mentor)
- **作者**：独立开发者（GeminiLight）
- **核心创新**：**5 Agent 架构** — 技能差距识别 → 学习者建模 → 路径调度 → 内容生成 → 聊天导师
- **定位**：通用学科辅导（数学、编程等），非写作专项

### 7.2 技术架构

**GenMentor 5 Agent 架构**：

```
GenMentor 多 Agent 流水线

输入：学习目标（如"掌握微积分"）
  ↓
┌─────────────────────────────────────────────┐
│  Agent 1: Skill Gap Identifier              │
│  → 分解学习目标为技能树                    │
│  → 识别当前技能差距                      │
└────────────────┬────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────┐
│  Agent 2: Adaptive Learner Modeler         │
│  → 建模学习者当前状态                      │
│  → 估计每个技能的掌握度                  │
└────────────────┬────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────┐
│  Agent 3: Learning Path Scheduler          │
│  → 基于掌握度规划学习路径                │
│  → 决定下一步学什么                      │
└────────────────┬────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────┐
│  Agent 4: Tailored Content Generator       │
│  → 生成/获取适配内容                      │
│  → 基于 ZPD 调整难度                    │
└────────────────┬────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────┐
│  Agent 5: AI Chatbot Tutor                │
│  → 对话式辅导                             │
│  → 实时答疑、反馈                        │
└─────────────────────────────────────────────┘
```

**和月笙的架构对比**：

| GenMentor Agent | 月笙对应 | 说明 |
|-----------------|----------|------|
| Skill Gap Identifier | DiagnosisAgent | 都是识别差距（症候 = 技能差距）|
| Adaptive Learner Modeler | StudentModelService（待建）| GenMentor 已有，月笙待建 |
| Learning Path Scheduler | TeachingStrategyService（待建）| GenMentor 已有，月笙待建 |
| Tailored Content Generator | 训练内容生成（待建）| 月笙暂无 |
| AI Chatbot Tutor | chat.handler.ts + TeachingAgent | 月笙已有，但需增强 |

### 7.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **架构高度同构** | GenMentor 的 5 Agent 完美对应月笙的理想架构 |
| **验证架构可行性** | 证明这种 5 阶段流水线在实际项目中可行 |
| **路径调度算法参考** | Learning Path Scheduler 的实现可借鉴 |

### 7.4 对月笙项目的具体作用

**7.4.1 验证月笙的理想架构**

月笙的 `teaching-knowledge-bridge_V1.0.md` 方案提出了：

```
StudentModelService → TeachingStrategyService → PromptBuilder
```

这和 GenMentor 的 Agent 2 → Agent 3 → Agent 5 完全对应！

**结论**：`teaching-knowledge-bridge` 方案的架构方向是正确的，有真实项目（GenMentor）验证。

**7.4.2 借鉴路径调度算法**

GenMentor 的 Learning Path Scheduler 可能用了以下策略（从项目名称推断）：

```typescript
// 可能的路径调度策略（借鉴 GenMentor）
type SchedulingStrategy =
  | 'weakest-first'       // 先补最弱的技能（OATutor 也用这个）
  | 'prerequisite-first'  // 先学前置技能
  | 'interleaved'        // 混合练习（间隔重复）
  | 'mastered-then-advance';  // 掌握一个再进下一个

// 月笙可以用的最简单策略：weakest-first
function scheduleNextAction(studentModel: StudentModel): Action {
  const weakestSyndrome = getLowestMastery(studentModel.abilityScores);
  return SYNDROME_TO_ACTIONS[weakestSyndrome][0];
}
```

### 7.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 直接代码复用 | ❌ 不可复用 | GenMentor 是独立系统，技术栈不同 |
| 架构思路借鉴 | ⭐⭐ | 验证月笙架构方向正确 |
| 调度算法借鉴 | ⭐⭐⭐ | 需要自己实现 |

**总计**：低到中等，主要是概念启发。

### 7.6 前置需求

- ✅ 需要先实现 StudentModelService（IntelliCode 方案）
- ✅ 需要先实现 TeachingStrategyService（teaching-knowledge-bridge 方案）
- ⚠️ 需要设计路径调度算法

### 7.7 实施路径

```
Phase 1: 实现 GenMentor 对应的前 3 个组件
  - StudentModelService（借鉴 IntelliCode）
  - TeachingStrategyService（借鉴 teaching-knowledge-bridge）
  - 路径调度算法（借鉴 GenMentor 的 weakest-first）

Phase 2: 实现内容生成（对应 GenMentor Agent 4）
  - 训练内容生成（借鉴 OATutor）

不涉及直接集成 GenMentor 代码。
```

---

## 8. Stylus Education — 超细粒度诊断

### 8.1 资源背景

- **来源**：styluseducation.com（商业产品，非开源）
- **核心创新**：**近 100 个评估标准** — 对写作问题进行超细粒度诊断
- **定位**：面向学校的写作评估工具，非一对一教练

### 8.2 技术架构（从公开信息推断）

**Stylus 诊断维度（超细粒度）**：

```
Stylus 评估标准（近 100 个）

├── 叙事结构
│   ├── 开头吸引力
│   ├── 情节推进节奏
│   ├── 视角一致性
│   ├── 时间线清晰度
│   └── 结尾闭环
├── 角色塑造
│   ├── 角色动机清晰度
│   ├── 角色弧光
│   ├── 对话自然度
│   └── 角色独特性
├── 世界观构建
│   ├── 信息呈现节奏
│   ├── 设定一致性
│   ├── 魔法/科技系统逻辑
│   └── 世界观与情节的融合度
├── 文笔与风格
│   ├── 句式多样性
│   ├── "展示不讲述"执行度
│   ├── 感官细节丰富度
│   └── 词汇精准度
└── ...（近 100 个维度）
```

### 8.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **诊断维度扩展参考** | 月笙目前只有 P001-P010（9 个症候），维度可能不够 |
| **评估标准细化** | 每个症候可以拆分子维度（如 P004"信息堆积"可以细分） |

### 8.4 对月笙项目的具体作用

**8.4.1 扩展症候子维度**

月笙当前 P001-P010 是粗粒度诊断，可以借鉴 Stylus 细化为子维度：

| 当前症候 | 可细分的子维度（借鉴 Stylus） |
|----------|-------------------------------|
| P001 视角混乱 | ①视角跳频 ②有限视角越界 ③全知/有限混用 |
| P002 动机缺失 | ①目标不明确 ②动机与行动不匹配 ③外部动机缺失 |
| P004 信息堆积 | ①世界观信息堆 ②角色信息堆 ③背景信息堆 |
| P009 角色动机缺失 | ①内在动机缺失 ②外在动机缺失 ③动机与价值观冲突 |

**实施建议**：

```
V1.1（短期）: 保持 P001-P010 粗粒度，但在诊断报告中给出子维度标签
V2.0（中期）: 正式支持子维度诊断（P001-1, P001-2, ...）
V3.0（长期）: 支持用户自定义关注维度
```

**8.4.2 评估标准量化**

Stylus 的近 100 个评估标准每个都有量化评分（1-5 分或 0-100 分）。

月笙可以借鉴，给每个症候的 severity（L1/L2/L3）增加量化依据：

```typescript
// 当前：severity 是粗粒度 L1/L2/L3
// 未来：增加量化评分作为依据
interface SyndromeResult {
  id: SyndromeId;
  severity: SeverityLevel;
  score?: number;  // 0-100 量化评分（借鉴 Stylus）
  subDimensions?: {  // 子维度评分
    [key: string]: number;
  };
}
```

### 8.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 直接集成 | ❌ 不可集成 | Stylus 是商业产品，无开源代码 |
| 诊断维度扩展 | ⭐⭐⭐ | 需要重新设计 DiagnosisAgent Prompt |
| 量化评分 | ⭐⭐⭐ | 需要设计评分标准和校准 |

**总计**：中等，作为 V2 功能扩展参考。

### 8.6 前置需求

- ✅ 需要先验证当前 P001-P010 的诊断准确度
- ⚠️ 需要设计子维度诊断的 Prompt 工程
- ⚠️ 需要人工标注数据来校准量化评分

### 8.7 实施路径

```
V1.1（1-2 个月）: 增加子维度标签
  - 在 DiagnosisAgent Prompt 中增加子维度识别指令
  - 在诊断报告中展示子维度标签

V2.0（3-6 个月）: 支持子维度诊断
  - 重新设计 SyndromeResult 数据结构
  - 扩展 SYNDROME_TO_ACTIONS 映射到子维度
```

---

## 9. 自适应脚手架理论 (arXiv:2508.01503)

### 9.1 资源背景

- **来源**：arXiv:2508.01503（2025年8月）
- **标题**：*Adaptive Scaffolding for LLM-based Tutoring Systems: An Evidence-Centered Design Approach*
- **核心创新**：**ECD（证据中心设计）+ ZPD + 社会认知理论** 三者融合的理论框架
- **实用性**：理论框架论文，非开源代码，但提供设计方法论

### 9.2 理论框架

**ECD + ZPD + SCT 融合框架**：

```
自适应脚手架设计框架（arXiv:2508.01503）

Evidence-Centered Design (ECD)
  ↓ 提供
  证据推理链：
    [学生行为] → [证据] → [能力推断] → [教学决策]
    
      +
      
Zone of Proximal Development (ZPD)
  ↓ 提供
  难度校准：
    [当前能力] → [ZPD 区间] → [脚手架级别]
    
      +
      
Sociocognitive Theory (SCT)
  ↓ 提供
  社会交互设计：
    [ peer 建模] → [口头指导] → [ fading 撤除脚手架]

═══════════════════════════════════════════

最终输出：
  自适应脚手架系统设计方案
  （含 4 个脚手架级别）
```

**四层脚手架级别（从该论文推断）**：

| 级别 | 名称 | 支持度 | 适用场景 |
|------|------|--------|----------|
| Level 1 | Full Scaffold | 高 | 学生完全不会 |
| Level 2 | Partial Scaffold | 中高 | 学生有部分思路 |
| Level 3 | Hint Only | 中低 | 学生接近答案 |
| Level 4 | No Scaffold | 低 | 学生能独立完成 |

### 9.3 为什么推荐给月笙

| 推荐理由 | 说明 |
|----------|------|
| **理论支撑月笙方案** | `teaching-knowledge-bridge` 方案需要理论支撑，这篇论文提供 |
| **脚手架级别设计参考** | 月笙的"引导→指导→挑战"三模式可以扩展为四级别 |
| **ECD 证据推理链** | 月笙的诊断→教学推理链可以用 ECD 框架规范化 |

### 9.4 对月笙项目的具体作用

**9.4.1 为 `teaching-knowledge-bridge` 方案提供理论支撑**

该方案的 `TeachingStrategyService` 做策略决策，但**缺乏理论支撑**。

加入 ECD 框架后：

```typescript
// 基于 ECD 框架重新设计 TeachingStrategyService
class TeachingStrategyService {
  decide(studentModel: StudentModel, diagnosis: DiagnosisResult): Strategy {
    // ECD 证据推理链
    const evidence = this.collectEvidence(studentModel, diagnosis);
    // evidence = { syndromeSeverity, pastProgress, engagementLevel }
    
    const abilityEstimate = this.inferAbility(evidence);
    // abilityEstimate = { syndromeId: masteryProbability }
    
    const strategy = this.selectStrategy(abilityEstimate, studentModel.zpdRange);
    // strategy = { actionId, intensity, scaffoldingLevel }
    
    return strategy;
  }
  
  private collectEvidence(...): Evidence { ... }
  private inferAbility(evidence: Evidence): AbilityEstimate { ... }
  private selectStrategy(ability: AbilityEstimate, zpd: ZPD): Strategy { ... }
}
```

**9.4.2 扩展脚手架级别**

月笙当前"引导→指导→挑战"三模式，可以扩展为四级别（借鉴论文）：

| 级别 | 月笙对应 | 强度 | 适用 |
|------|----------|------|------|
| Level 1 Full Scaffold | "指导"模式 | 高 | severity L3 |
| Level 2 Partial Scaffold | "引导"模式 + 更多提示 | 中高 | severity L2（部分进步）|
| Level 3 Hint Only | "引导"模式 | 中低 | severity L1（接近掌握）|
| Level 4 No Scaffold | "挑战"模式 | 低 | 复盘验证阶段 |

**9.4.3 规范诊断→教学推理链**

当前月笙的诊断结果直接映射到教学动作（SYNDROME_TO_ACTIONS），缺乏**证据推理链**。

加入 ECD 后：

```
当前（无推理链）：
  诊断结果: P001(L3) → 直接映射 → 动作: A001

ECD 规范后：
  诊断结果: P001(L3)
    ↓ [证据收集]
  证据: { severity: L3, pastAttempts: 2, reflectionQuality: 'poor' }
    ↓ [能力推断]
  能力估计: { masterY_P001: 0.2, confidence: 0.6 }
    ↓ [ZPD 校准]
  ZPD 区间: [0.2, 0.5]
    ↓ [策略选择]
  教学策略: { actionId: 'A001', intensity: 'high', scaffolding: 'full' }
```

### 9.5 集成难度评估

| 维度 | 难度 | 说明 |
|------|------|------|
| 理论理解 | ⭐⭐⭐⭐ | ECD + ZPD + SCT 需要学习理解 |
| 代码实现 | ⭐⭐⭐ | 需要重构 TeachingStrategyService |
| 验证难度 | ⭐⭐⭐⭐ | 理论框架难以直接验证效果 |

**总计**：中等偏高，建议作为理论指导，不急于实现。

### 9.6 前置需求

- ✅ 需要先实现 StudentModelService（提供证据来源）
- ✅ 需要先实现 TeachingStrategyService（待加入 ECD 推理链）
- ⚠️ 需要团队理解 ECD 理论框架

### 9.7 实施路径

```
Phase 1: 理论学习（1-2 周）
  - 阅读 arXiv:2508.01503 全文
  - 理解 ECD 证据推理链设计

Phase 2: 推理链设计（2-3 周）
  - 设计证据收集的数据结构
  - 设计能力推断的算法（可用 BKT 或规则）

Phase 3: 实现（3-4 周）
  - 重构 TeachingStrategyService，加入 ECD 推理链
```

---

## 10. 综合推荐与实施优先级

### 10.1 资源推荐矩阵（最终版）

| 资源 | 优先级 | 实施难度 | 预期收益 | 推荐决策 | 实施阶段 |
|------|--------|----------|----------|----------|----------|
| **Prober.ai** | **P0** | 低 | 高 | ✅ **立即实施** | Phase 1（本月）|
| **IntelliCode** | **P0** | 中高 | 高 | ✅ **立即实施** | Phase 1（本月）|
| **pyBKT** | **P1** | 中 | 中高 | ✅ **Phase 2 实施** | Phase 2（下月）|
| **Claw-STU** | **P1** | 低 | 中 | ✅ **Phase 2 实施** | Phase 2（下月）|
| **OATutor** | **P2** | 中高 | 中 | ⚠️ **部分借鉴** | Phase 2-3 |
| **OpenMAIC** | **P2** | 高 | 中 | ⚠️ **概念借鉴** | Phase 3（长期）|
| **GenMentor** | **P2** | 中 | 中 | ⚠️ **概念借鉴** | Phase 2-3 |
| **Stylus** | **P3** | 高 | 低 | ⏸️ **暂缓** | V2（3-6 个月）|
| **脚手架论文** | **P1** | 中高 | 中 | ✅ **理论指导** | Phase 2（设计阶段）|

### 10.2 三阶段实施路线图（更新版）

```
═════════════════════════════════════════════════════════════
Phase 1: 地基修复 + 立即收益（2-3 周，本月完成）
═════════════════════════════════════════════════════════════

Week 1: Prober.ai Challenge-Unlock 机制
  - 设计 Challenge 生成 Prompt + 回答评估 Prompt
  - 修改 teaching-state-machine.ts 新增 AWAITING_REFLECTION 状态
  - 修改 chat.handler.ts 注入新流程
  - 前端适配（UI 状态提示）
  
Week 2-3: IntelliCode 中心化学者状态
  - 设计 StudentModel TypeScript 接口（参照 LearnerState）
  - 实现 StudentModelService（内存版）
  - 修改 chat.handler.ts 注入更新逻辑
  - 实现 SQLite 持久化
  - 修改 PromptBuilder 读取学生模型


═════════════════════════════════════════════════════════════
Phase 2: 自适应升级（3-4 周，下月完成）
═════════════════════════════════════════════════════════════

Week 1: Claw-STU ZPD 校准流程
  - 设计 3 个校准问题
  - 实现 ZPDCalibrationService
  - 实现 CalibrationWizard 前端组件
  
Week 2-3: pyBKT 贝叶斯知识追踪
  - 用 TypeScript 实现 BKT 更新公式
  - 设计症候→BKT 的映射规则
  - 集成到 StudentModelService
  - 实现冷启动策略（前 3 次用规则，之后用 BKT）
  
Week 4: 脚手架理论指导设计
  - 阅读 arXiv:2508.01503
  - 设计 ECD 证据推理链
  - 重构 TeachingStrategyService（加入推理链）


═════════════════════════════════════════════════════════════
Phase 3: 智能化扩展 + 训练闭环（4-6 周，长期）
═════════════════════════════════════════════════════════════

Month 1: OATutor 自适应训练推荐
  - 设计训练内容数据模型（借鉴 OATutor skill_model.json）
  - 实现 TrainingRecommender（借鉴 OATutor 的"选最弱技能"启发式）
  - 创作/生成第一批训练题目（每个症候 5-10 题）
  
Month 2: OpenMAIC 动作引擎扩展
  - 扩展教学动作库 A001-A012 → A001-A020+
  - 设计 teaching-actions.json 配置格式
  
Month 3: GenMentor 路径调度
  - 实现 Learning Path Scheduler（weakest-first 策略）
  - 集成到 TeachingStrategyService
```

### 10.3 风险控制与应急预案

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| BKT 参数估计不准确（数据少）| 高 | 中 | 冷启动用 OATutor 启发式，数据积累后再启 BKT |
| Phase 1 改动影响现有功能 | 中 | 高 | 每个改动独立分支，充分测试后合并 |
| 训练内容创作瓶颈（人力）| 高 | 中高 | 用 LLM 生成初稿 + 人工审核 |
| 多阶段改造周期过长 | 中 | 中 | 每个 Phase 可独立发布，不阻塞业务 |

### 10.4 成功指标（KPI）

| 阶段 | 成功指标 | 目标值 |
|------|----------|--------|
| Phase 1 | Challenge-Unlock 使用率 | > 60% 诊断会话触发反思 |
| Phase 1 | 学生模型数据完整率 | > 90% 会话有完整学生模型 |
| Phase 2 | ZPD 校准完成率 | > 80% 新用户完成校准 |
| Phase 2 | BKT 掌握度预测准确度 | > 70% 和用户自评一致 |
| Phase 3 | 训练内容完成率 | > 50% 用户完成推荐训练 |
| Phase 3 | 用户写作能力进步率 | > 60% 用户 4 周内 severity 降低 |

---

## 11. 前置需求整合清单

### 11.1 架构层面前置需求（按优先级）

```
✅ 已完成：
  - P001-P010 症候 ID 体系统一（syndrome-manual.md 为权威来源）
  - A001-A012 动作定义统一（action-library.md 为权威来源）
  - SYNDROME_TO_ACTIONS 映射重建

⚠️ 待完成（P0 前置）：
  - [ ] 修复 Prompt 体系断裂（V1/V3 统一）
  - [ ] 修复 teaching-knowledge-bridge 方案中的 P0 问题（类型系统冲突等）
  - [ ] 修复前端硬编码映射（TeachingProgress.tsx + App.tsx）

🔴 阻塞 Phase 1：
  - [ ] 实现 StudentModelService（IntelliCode 方案）
  - [ ] 修复 diagnosis-parser 白名单（支持 H001/H002/E001/I001-I006）

🔴 阻塞 Phase 2：
  - [ ] 设计训练内容数据模型
  - [ ] 实现 SQLite 持久化（学生模型存储）
```

### 11.2 数据层面前置需求

```
✅ 已有：
  - P001-P010 症候定义（syndrome-manual.md）
  - A001-A012 动作定义（action-library.md）
  - SYNDROME_TO_ACTIONS 映射

⚠️ 待补充：
  - [ ] 每个症候的 sub-dimensions 定义（借鉴 Stylus，V2）
  - [ ] 训练题目库（每个症候 5-10 题，Phase 3）
  - [ ] BKT 四参数初始化值（基于专家经验 or 历史数据训练）
  - [ ] ZPD 校准问题设计（3-5 题，Phase 2）
```

### 11.3 技术栈前置需求

```
✅ 已有：
  - Electron + React + TypeScript
  - DeepSeek V3 LLM
  - better-sqlite3（日志存储）

⚠️ 待引入（可选）：
  - [ ] Python 环境（如需直接用 pyBKT 库，可用 TypeScript 重实现替代）
  - [ ] LangGraph（如需重构状态机为可视化，OpenMAIC 参考）
  - [ ] 训练题目生成 Pipeline（LLM 生成 + 人工审核）
```

---

## 12. 总结与下一步行动

### 12.1 三份文档的关系

```
                     ┌─────────────────────────────────┐
                     │   ai-writing-coach-survey       │
                     │   (初步调研，方向性)              │
                     └─────────────┬───────────────────┘
                                   ↓ 深化 + 扩展搜索
                     ┌─────────────────────────────────┐
                     │   integrated-resource-report     │
                     │   (资源整合，综述性)              │
                     │   → 给决策者看                    │
                     └─────────────┬───────────────────┘
                                   ↓ 详细剖析
                     ┌─────────────────────────────────┐
                     │   resource-detail-report         │
                     │   (分资源深析，技术性)            │
                     │   → 给开发人员看                  │
                     └─────────────────────────────────┘
```

### 12.2 立即行动（本周）

1. **审查并批准 Phase 1 实施计划**（Prober.ai + IntelliCode）
2. **修复 teaching-knowledge-bridge 方案中的 P0 问题**（类型系统冲突等）
3. **分配开发资源**（Phase 1 需要 1-2 名开发人员，2-3 周）

### 12.3 短期行动（2-3 周）

1. 实施 Prober.ai Challenge-Unlock 机制
2. 实施 IntelliCode 中心化学者状态
3. 验证 Phase 1 效果（Challenge-Unlock 使用率、学生模型完整率）

### 12.4 中期行动（1-2 个月）

1. 实施 Claw-STU ZPD 校准流程
2. 用 pyBKT 替代静态评分（或 TypeScript 重实现 BKT）
3. 设计 ECD 证据推理链（脚手架理论指导）

---

*本报告是动态文档，随项目实施进展和外部资源更新而迭代。*

---

## 附录 A：资源获取方式 + 许可证

| 资源 | 获取方式 | 许可证 | 月笙可用范围 |
|------|----------|---------|--------------|
| **Prober.ai** | arXiv:2605.05598（开放访问）| 学术使用 | ✅ 可借鉴思路，不可直接复制文字 |
| **IntelliCode** | GitHub: sirhanmacx/intellicode | 需确认（建议联系作者）| ⚠️ 建议参照设计思路，自己实现 |
| **pyBKT** | PyPI: pyBKT | 开源（大概率 MIT）| ✅ 可用，但建议用 TypeScript 重实现 |
| **OATutor** | GitHub: jaredkirby/oatutor | 开源（需确认）| ⚠️ 建议参照架构，不可直接复制代码 |
| **OpenMAIC** | GitHub: THU-MAIC/OpenMAIC | 开源（大概率 MIT）| ⚠️ 建议参照动作设计，不可直接复制代码 |
| **Claw-STU** | PyPI: clawstu | 开源 | ✅ 可借鉴思路 |
| **GenMentor** | GitHub: GeminiLight/gen-mentor | 开源 | ⚠️ 建议参照架构，不可直接复制代码 |
| **Stylus** | 商业产品 | 不可用于商业目的 | ❌ 仅概念启发 |
| **脚手架论文** | arXiv:2508.01503 | 学术使用 | ✅ 可借鉴理论框架 |

### 重要提醒：许可证合规

**月笙作为商业项目，引入开源代码/思路时需注意许可证**：

1. **pyBKT**：如果用 TypeScript 重实现算法（不复制 Python 代码），无许可证风险
2. **OATutor / OpenMAIC**：如果参照架构自己实现，无许可证风险；如果直接复制代码，需遵守其许可证
3. **Prober.ai**：arXiv 论文，可借鉴思路，不可直接复制文字到产品文档

**建议**：所有外部资源都采取"**参照设计思路，自己重新实现**"的策略，避免许可证风险。

---

*报告结束*
