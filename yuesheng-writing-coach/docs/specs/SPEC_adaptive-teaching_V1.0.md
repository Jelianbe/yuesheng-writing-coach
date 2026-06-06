# 自适应教学调度系统设计规范

> 版本：V1.0 | 创建：2026-06-04  
> 依据：  
> - design-philosophy_V1.0.md → 第五章「诊断表 + 长期能力表单」  
> - EDUCATION_INSIGHTS_2026-06-04.md → 反异化教学路径、对话式微任务、身体指令  
> - EDUCATION_FRAMEWORK_V2_2026-06-04.md → 学生模型驱动、ZPD 自适应、诊断→干预→微练→校验闭环  
> - teaching-strategy-notes.md → 教学策略层分析、用户类型矩阵  
> - research/ai-writing-coach-survey_V1.0.md → IntelliCode LearnerState、Claw-STU ZPD 校准、Prober.ai Challenge-Unlock  
> 回退方案：保留现有 AbilityProfileService，删除新增的 student-model.service.ts 和相关迁移文件

---

## 一、目标

将教学策略从"提示词里写死的态度选择器"升级为**基于学生模型的自适应教学调度系统**，实现：

1. **学生模型驱动**——AI 行为由数据结构精准驱动，而非盲目表演
2. **ZPD 自适应教学**——根据学生实时状态自动切换支架/引导/挑战模式
3. **诊断→干预→微练→校验闭环**——一次只解决一个核心问题
4. **身体指令替代任务面板**——训练内嵌在对话中自然生长

---

## 二、核心概念

### 2.1 从"提示词驱动"到"学生模型驱动"

**旧思路（提示词里写死）：**
> "你是一位精通支架式教学的教练。当学生遇到困难时，你应该先提供示范，再逐步撤除帮助。"

**问题：** AI 不知道"现在是不是该提供示范"，也不知道"撤除帮助"的时机。

**新思路（从学生模型实时读取）：**
> "你是一位写作教练。当前学生的【悬念设置】能力值为45分，处于【模仿期】，上次对'对比案例法'响应良好。本次诊断发现其'惯于过早揭示答案'。请调用你关于'悬念制造'的知识，先用对比案例进行示范教学。"

### 2.2 三种教学模式（ZPD 自适应）

| 模式 | 名称 | 适用场景 | 示例 |
|------|------|---------|------|
| 1 | **支架模式** (Scaffolding) | 学生遇到完全陌生的概念，或反复在同一错误上跌倒 | "一个强动机通常包含三个零件——深刻的创伤、直接的威胁、和道德上的正当性。你可以试着把这三个零件，分别写一句话，填进你的大纲里。" |
| 2 | **引导模式** (Guiding) | 学生掌握基础，但应用不熟，需要启发 | "你的主角决定复仇，但他内心最恐惧的是什么？是再次失败，还是害怕自己变得和仇人一样？这个恐惧，会如何阻碍他当下的行动？" |
| 3 | **挑战模式** (Challenging) | 学生已熟练掌握，需要内化和创造 | "你的复仇故事大纲已经很完整了。现在，请把'一场暴雨'作为唯一的环境元素，重写这段对峙戏。要求：用雨势的变化来外化主角的心理，不准直接描写情绪。" |

### 2.3 问题三级分类（一次只说一个核心问题）

| 优先级 | 类型 | 定义 | 示例 |
|--------|------|------|------|
| 最高 | **致命伤** | 必须立即解决 | 逻辑矛盾、人设崩塌。"主角是盲人，但你写他'一眼就认出了对方'。" |
| 中等 | **结构病** | 优先解决 | 影响后续所有内容的宏观问题。"开篇三章，主角一直被动挨打，没有主动做任何选择。" |
| 最低 | **皮肤症** | 可以暂缓 | 语句、修辞、节奏等局部问题。等骨架搭好了再慢慢润色。 |

**铁律：一次诊断，只反馈优先级最高的那一个。**

---

## 三、学生模型（StudentModel）

### 3.1 设计原则

学生模型是真正的"教学大脑"，它动态记录的不是分数，而是**认知状态**。

**设计依据：**
- IntelliCode 的 LearnerState Schema（中心化学习者状态）
- EDUCATION_FRAMEWORK_V2 的"学生模型字段示例"
- EDUCATION_INSIGHTS 的"从症候编码到作者定位"

### 3.2 数据结构

```typescript
interface StudentModel {
  // === 身份标识 ===
  authorId: string;
  createdAt: string;
  updatedAt: string;

  // === 能力维度（按能力追踪，不是按症候） ===
  abilities: Record<string, AbilityState>;

  // === 认知与学习风格 ===
  learningStyle: LearningStyle;

  // === 教学策略偏好 ===
  teachingStrategy: TeachingStrategy;

  // === 错误模式记录 ===
  errorPatterns: ErrorPatternRecord[];

  // === 教学历史 ===
  teachingHistory: TeachingInteraction[];

  // === 元数据 ===
  version: number; // 模型版本号，用于数据迁移
}

interface AbilityState {
  abilityId: string;       // 如 "ABL-001" (结构控制)
  score: number;           // 0-100，能力评分
  zpdLower: string;        // 最近发展区下限，如 "铺垫"
  zpdUpper: string;        // 最近发展区上限，如 "悬念"
  cognitivePhase: 'imitation' | 'understanding' | 'creation'; // 模仿期/理解期/创造期
  commonErrors: string[];  // 常见错误模式 ID 列表，如 ["ERR-PREMATURE-REVEAL"]
  effectiveStrategies: string[]; // 有效教学策略 ID，如 ["STR-CONTRAST-DEMO"]
  lastAssessedAt: string;
}

interface LearningStyle {
  thinkingStyle: 'analytical' | 'emotional' | 'mixed'; // 理工型/感性型/混合型
  confidenceLevel: 'low' | 'medium' | 'high';          // 信心水平
  frustrationThreshold: number;                         // 连续失败几次会放弃（默认 3）
  preferredModality: 'case_study' | 'guided_discovery' | 'free_exploration'; // 偏好模态
  // 自动推断字段
  userType: 'beginner' | 'intermediate' | 'advanced';  // 新手/老手/进阶
}

interface TeachingStrategy {
  currentMode: 'scaffolding' | 'guiding' | 'challenging'; // 当前教学模式
  modeHistory: Array<{
    mode: 'scaffolding' | 'guiding' | 'challenging';
    triggeredAt: string;
    reason: string; // 切换原因
  }>;
  strategyWeights: Record<string, number>; // 策略 ID → 有效性权重
  lastModeSwitchAt: string;
}

interface ErrorPatternRecord {
  errorId: string;        // 错误模式 ID
  abilityId: string;      // 关联能力
  firstDetected: string;  // 首次检测时间
  lastDetected: string;   // 最后检测时间
  occurrenceCount: number; // 出现次数
  severity: 'fatal' | 'structural' | 'cosmetic'; // 致命伤/结构病/皮肤症
  status: 'active' | 'improving' | 'resolved' | 'recurred';
  // 教学响应记录
  strategiesTried: Array<{
    strategyId: string;
    attemptedAt: string;
    outcome: 'success' | 'partial' | 'failure';
  }>;
}

interface TeachingInteraction {
  interactionId: string;
  sessionId: string;
  timestamp: string;
  // 触发原因
  trigger: 'diagnosis' | 'user_question' | 'training_result';
  // 教学动作
  mode: 'scaffolding' | 'guiding' | 'challenging';
  strategyId: string;       // 使用的策略
  abilityId: string;        // 针对的能力
  errorId: string;          // 针对的错误
  // 结果
  outcome: 'completed' | 'partial' | 'abandoned';
  studentResponse: 'engaged' | 'neutral' | 'frustrated';
  // 更新
  abilityScoreDelta: number; // 能力变化（可为 0）
}
```

### 3.3 与现有 AbilityProfile 的关系

| 维度 | 现有 AbilityProfile | 新 StudentModel |
|------|---------------------|-----------------|
| 定位 | 能力评分统计（面向展示） | 认知状态追踪（面向决策） |
| 数据来源 | diagnosis_results 实时聚合 | 持久化存储，增量更新 |
| 关键字段 | score, trend, weakPoints | zpdLower/Upper, cognitivePhase, errorPatterns, effectiveStrategies |
| 用途 | 右栏雷达图展示 | 驱动教学决策（模式切换、策略选择） |
| 保留/替换 | **保留为展示层** | **作为决策层** |

**关键决策：** StudentModel 不替换 AbilityProfile，而是作为其**上游**。StudentModel 负责教学决策，AbilityProfile 负责能力展示。

---

## 四、教学决策回路

### 4.1 四步循环

```
感知 → 决策 → 行动 → 更新
```

### 4.2 详细流程

```
用户提交文本
  ↓
┌─────────────────────────────────────┐
│ 1. 感知（Perceive）                  │
│ - Diagnosis Agent 分析文本           │
│ - 提取错误特征（error pattern）      │
│ - 确定问题优先级（致命伤>结构病>皮肤症）│
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│ 2. 决策（Decide）                    │
│ - 查询 StudentModel                  │
│   · 这个错误是新的还是屡犯的？       │
│   · 学生当前的认知阶段是什么？       │
│   · 历史上哪种教学方式对他最有效？   │
│ - 选择教学模式（支架/引导/挑战）     │
│ - 选择教学策略（从策略库匹配）       │
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│ 3. 行动（Act）                       │
│ - 填充 System Prompt 模板            │
│   · 注入学生模型关键信息             │
│   · 注入匹配的教学策略               │
│   · 注入策略库中的"药方"             │
│ - Teaching Agent 生成教学回应        │
│ - 包含微训练指令（身体指令）         │
└──────────────┬──────────────────────┘
               ▼
┌─────────────────────────────────────┐
│ 4. 更新（Update）                    │
│ - 分析学生回应                       │
│ - 更新 StudentModel                  │
│   · 能力评分变化                     │
│   · 策略有效性权重                   │
│   · 错误模式状态                     │
│   · 教学模式是否需要切换             │
└─────────────────────────────────────┘
```

### 4.3 决策逻辑伪代码

```typescript
function decideTeachingMode(
  error: ErrorPatternRecord,
  student: StudentModel,
): TeachingMode {
  const ability = student.abilities[error.abilityId];

  // 规则 1：屡犯 + 低分 → 支架模式
  if (error.occurrenceCount >= 3 && ability.score < 40) {
    return 'scaffolding';
  }

  // 规则 2：模仿期 → 支架模式
  if (ability.cognitivePhase === 'imitation') {
    return 'scaffolding';
  }

  // 规则 3：理解期 + 中等分 → 引导模式
  if (ability.cognitivePhase === 'understanding' && ability.score >= 40 && ability.score < 70) {
    return 'guiding';
  }

  // 规则 4：创造期 + 高分 → 挑战模式
  if (ability.cognitivePhase === 'creation' && ability.score >= 70) {
    return 'challenging';
  }

  // 规则 5：挫折信号 → 降级到支架
  if (student.learningStyle.confidenceLevel === 'low') {
    return 'scaffolding';
  }

  // 默认：引导模式
  return 'guiding';
}

function selectTeachingStrategy(
  error: ErrorPatternRecord,
  mode: TeachingMode,
  student: StudentModel,
): string {
  // 优先使用历史上有效的策略
  const effectiveStrategies = student.teachingStrategy.strategyWeights;
  const sorted = Object.entries(effectiveStrategies)
    .sort((a, b) => b[1] - a[1]);

  for (const [strategyId] of sorted) {
    if (isStrategyCompatible(strategyId, mode, error)) {
      return strategyId;
    }
  }

  // 回退：使用模式默认策略
  return DEFAULT_STRATEGIES[mode];
}
```

---

## 五、教学策略库

### 5.1 策略定义

```typescript
interface TeachingStrategyDef {
  id: string;
  name: string;
  mode: 'scaffolding' | 'guiding' | 'challenging';
  description: string;
  // 适用条件
  applicablePhases: Array<'imitation' | 'understanding' | 'creation'>;
  applicableErrorTypes: Array<'fatal' | 'structural' | 'cosmetic'>;
  // 教学动作模板
  promptTemplate: string; // 包含占位符 {student_info}, {error_desc}, {example}
  // 微训练指令模板
  microExerciseTemplate: string; // 包含占位符 {target}, {constraint}
}
```

### 5.2 策略-问题-阶段映射表

| 问题 | 认知阶段 | 最有效策略 | 策略 ID |
|------|---------|-----------|---------|
| 动机不明 | 模仿期 | 错误示范法（给学生一个动机薄弱的版本，让他批评） | STR-ERROR-DEMO |
| 动机不明 | 理解期 | 提问引导法（问"他最怕失去什么？"） | STR-QUESTION-GUIDE |
| 信息硬塞 | 模仿期 | 对比案例法（好 vs 差的描写对比） | STR-CONTRAST-DEMO |
| 信息硬塞 | 理解期 | 填空写作法（给框架，让学生填关键细节） | STR-FILL-IN |
| 情绪标签化 | 任何 | 身体指令法（"用嘴读出来，感受哪里卡"） | STR-BODY-READ |
| 角色工具化 | 创造期 | 随机变量插入法（加入意外元素，锻炼应变） | STR-RANDOM-VAR |

### 5.3 策略库文件结构

```
resources/
  knowledge-graph/
    teaching-strategies.json     # 策略定义
    strategy-problem-phase-map.json  # 映射表
    error-pattern-library.json   # 错误模式库
```

---

## 六、错误模式库

### 6.1 核心设计理念

**错误是有限的**（约 50 条核心错误模式），大模型擅长处理变体。

| 概念 | 性质 |
|------|------|
| 核心错误模式 | 抽象的、结构性的规则偏离 |
| 具体错误变体 | 核心模式在千万种具体文本中的实例化 |

### 6.2 错误模式定义

```typescript
interface ErrorPatternDef {
  id: string;              // 如 "ERR-PREMATURE-REVEAL"
  name: string;            // 如 "过早揭示答案"
  abilityId: string;       // 关联能力
  description: string;     // 结构化特征描述
  severity: 'fatal' | 'structural' | 'cosmetic';
  // 检测特征
  detectionSignals: string[]; // 可被 AI 识别的信号
  // 配套教学策略
  recommendedStrategies: Array<{
    strategyId: string;
    phase: 'imitation' | 'understanding' | 'creation';
  }>;
}
```

---

## 七、数据库设计

### 7.1 复用现有表

| 现有表 | 用途 | 修改 |
|--------|------|------|
| `diagnosis_results` | 诊断记录 | 保留，作为感知层数据源 |
| `teaching_state` | 教学状态 | 扩展，增加 student_model_id |

### 7.2 新增表

```sql
-- 学生模型主表
CREATE TABLE IF NOT EXISTS student_models (
    author_id TEXT PRIMARY KEY,
    learning_style TEXT NOT NULL DEFAULT '{}',
    teaching_strategy TEXT NOT NULL DEFAULT '{}',
    version INTEGER DEFAULT 1,
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
);

-- 能力状态表（按能力追踪认知状态）
CREATE TABLE IF NOT EXISTS ability_states (
    id TEXT PRIMARY KEY,
    author_id TEXT NOT NULL,
    ability_id TEXT NOT NULL,
    score INTEGER NOT NULL DEFAULT 100,
    zpd_lower TEXT,
    zpd_upper TEXT,
    cognitive_phase TEXT CHECK(cognitive_phase IN ('imitation', 'understanding', 'creation')),
    common_errors TEXT NOT NULL DEFAULT '[]',
    effective_strategies TEXT NOT NULL DEFAULT '[]',
    last_assessed_at TEXT,
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_as_author ON ability_states(author_id);

-- 错误模式记录表
CREATE TABLE IF NOT EXISTS error_pattern_records (
    id TEXT PRIMARY KEY,
    author_id TEXT NOT NULL,
    error_id TEXT NOT NULL,
    ability_id TEXT NOT NULL,
    first_detected TEXT NOT NULL,
    last_detected TEXT NOT NULL,
    occurrence_count INTEGER DEFAULT 1,
    severity TEXT CHECK(severity IN ('fatal', 'structural', 'cosmetic')),
    status TEXT CHECK(status IN ('active', 'improving', 'resolved', 'recurred')),
    strategies_tried TEXT NOT NULL DEFAULT '[]',
    updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_epr_author ON error_pattern_records(author_id);

-- 教学交互记录表
CREATE TABLE IF NOT EXISTS teaching_interactions (
    id TEXT PRIMARY KEY,
    author_id TEXT NOT NULL,
    session_id TEXT NOT NULL,
    trigger TEXT CHECK(trigger IN ('diagnosis', 'user_question', 'training_result')),
    mode TEXT CHECK(mode IN ('scaffolding', 'guiding', 'challenging')),
    strategy_id TEXT NOT NULL,
    ability_id TEXT NOT NULL,
    error_id TEXT NOT NULL,
    outcome TEXT CHECK(outcome IN ('completed', 'partial', 'abandoned')),
    student_response TEXT CHECK(student_response IN ('engaged', 'neutral', 'frustrated')),
    ability_score_delta INTEGER DEFAULT 0,
    timestamp TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ti_author ON teaching_interactions(author_id);
CREATE INDEX IF NOT EXISTS idx_ti_session ON teaching_interactions(session_id);
```

---

## 八、接口定义

### 8.1 StudentModelService

```typescript
interface StudentModelService {
  // 初始化/获取
  getModel(authorId: string): StudentModel;
  initModel(authorId: string): StudentModel;

  // 感知层更新
  updateAfterDiagnosis(
    authorId: string,
    diagnosis: DiagnosisEntry,
  ): void;

  // 决策层查询
  getTeachingMode(
    authorId: string,
    errorId: string,
  ): 'scaffolding' | 'guiding' | 'challenging';

  getRecommendedStrategy(
    authorId: string,
    errorId: string,
  ): string;

  // 更新层
  recordInteraction(
    authorId: string,
    interaction: TeachingInteraction,
  ): void;

  updateStrategyWeight(
    authorId: string,
    strategyId: string,
    outcome: 'success' | 'partial' | 'failure',
  ): void;

  // 展示层输出
  toPromptContext(authorId: string): string;
}
```

### 8.2 System Prompt 注入模板

```
你是月笙，一位写作教练。

【当前学生状态】
{student_info_block}

【本次诊断】
{diagnosis_info_block}

【教学决策】
- 教学模式：{mode}
- 教学策略：{strategy_name}
- 策略说明：{strategy_description}

【教学要求】
1. 一次只聚焦一个核心问题
2. 使用{mode}模式的教学方式
3. 给出一个具体的身体指令（如"读出来""回忆一次..."）
4. 不要替学生写，只引导
5. 评估让学生自己发现问题
```

---

## 九、与现有系统的衔接

### 9.1 保留模块

| 模块 | 修改后用途 |
|------|-----------|
| AbilityProfileService | 保留为展示层，从 StudentModel 读取数据生成能力画像 |
| DiagnosisService | 保留为感知层数据源 |
| diagnosis_results 表 | 保留，作为诊断原始记录 |
| Agent Prompt V3.1 | 增强：注入学生模型上下文 |

### 9.2 删除/降级模块

| 模块 | 建议 | 理由 |
|------|------|------|
| 009_author_profile.sql 的 author_profiles 表 | **删除或延后** | 设计了但无 Service 实现，是空壳 |
| NovelProfile | **删除** | 系统不需要结构化理解小说（EDUCATION_INSIGHTS 6.3） |
| Pattern Detector | **删除** | 核心错误模式库替代（EDUCATION_INSIGHTS 6.3） |
| 独立 Training Service 面板 | **删除** | 微练内嵌在对话中（EDUCATION_INSIGHTS 4.1） |
| Evaluation Service 打分 | **删除** | 校验只判断完成度，不评判好坏（EDUCATION_FRAMEWORK_V2 4.4） |

### 9.3 新增模块

| 模块 | 用途 |
|------|------|
| StudentModelService | 学生模型管理（核心） |
| TeachingStrategyLibrary | 教学策略库加载和匹配 |
| ErrorPatternLibrary | 错误模式库加载和匹配 |
| TeachingDecisionEngine | 教学决策引擎（模式选择+策略匹配） |

---

## 十、DoD

1. StudentModel 数据结构定义完整，含 abilities/learningStyle/teachingStrategy/errorPatterns/teachingHistory
2. 教学决策回路（感知→决策→行动→更新）逻辑文档化
3. 教学模式切换规则完整（支架/引导/挑战的触发条件）
4. 策略-问题-阶段映射表至少包含 6 条映射
5. 错误模式库结构定义完整
6. 数据库表结构定义完整（student_models + ability_states + error_pattern_records + teaching_interactions）
7. StudentModelService 接口定义完整
8. System Prompt 注入模板定义完整
9. 与现有系统衔接方案文档化（保留/删除/新增）

---

## 十一、实施优先级

### Phase 1：Prompt 注入（立即）

**目标：** 不建数据库，不写 Service，只在 System Prompt 中注入学生模型概念

**做法：**
1. 在前端维护一个简单的 `studentContext` JSON（localStorage）
2. 每次聊天请求时，将 `studentContext` 注入 System Prompt
3. 手动维护关键字段：userType、confidence、lastErrors、effectiveStrategies

**交付物：**
- 修改 `yuesheng-prompt-v3.md`，增加学生模型注入区
- 前端 `studentContext` 状态管理（Zustand）
- chat.handler.ts 中注入逻辑

### Phase 2：Service 层（V1.1）

**目标：** 创建 StudentModelService，持久化到 SQLite

**交付物：**
- `student-model.service.ts`
- 数据库迁移文件
- IPC handlers
- 决策引擎

### Phase 3：策略库建设（V1.2）

**目标：** 扩充教学策略库和错误模式库

**交付物：**
- `teaching-strategies.json`
- `error-pattern-library.json`
- 策略匹配逻辑

---

## 变更记录

| 版本 | 日期 | 变更内容 | 变更人 |
|------|------|---------|--------|
| V1.0 | 2026-06-04 | 初始版本，定义自适应教学调度系统 | 月笙团队 |
