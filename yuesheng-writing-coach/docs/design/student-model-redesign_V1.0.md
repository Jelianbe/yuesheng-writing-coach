# 月笙写作教练 - 用户画像重构设计 V1.0

> **文档性质**：架构设计  
> **目标读者**：项目架构师、开发人员  
> **生成时间**：2026-06-04  
> **前置依赖**：syndrome-manual.md / action-library.md / ability-atlas.json

---

## 一、现有系统全貌 — 为什么需要重构

### 1.1 当前数据流全景

```
┌─────────────────────────────────────────────────────────────┐
│                     渲染进程 (Renderer)                       │
│                                                             │
│  student-context.store.ts (Zustand + localStorage)          │
│  ┌──────────────────────────────────────────────┐          │
│  │ userType: beginner/intermediate/advanced     │ ← 死代码  │
│  │ confidenceLevel: low/medium/high             │ ← 死代码  │
│  │ thinkingStyle: analytical/emotional/mixed    │ ← 死代码  │
│  │ lastErrors: ErrorRecord[] (最近10条)          │ ← 死代码  │
│  │ effectiveStrategies: string[]                │ ← 死代码  │
│  │ frustrationCount: number                     │ ← 死代码  │
│  │                                               │          │
│  │ updateFromDiagnosis() → 从未被调用             │          │
│  │ updateFromInteraction() → 从未被调用           │          │
│  │ toJSON() → 从未被调用                         │          │
│  └──────────────────────────────────────────────┘          │
└─────────────────────────┬───────────────────────────────────┘
                          │ localStorage (不可靠、跨设备丢失)
                          │ ❌ 主进程无法读取
┌─────────────────────────┴───────────────────────────────────┐
│                     主进程 (Main)                            │
│                                                             │
│  SQLite 数据库                                              │
│  ┌──────────────────────────────────────────────┐          │
│  │ diagnosis_results 表                          │          │
│  │   session_id, syndromes (JSON), confidence    │ ← 有数据  │
│  │   但没有任何 Service 去聚合查询                │          │
│  │                                               │          │
│  │ teaching_state 表                             │          │
│  │   current_phase, active_problems (JSON)       │ ← 有数据  │
│  │   但只看当前会话                               │          │
│  │                                               │          │
│  │ user_training_records 表                      │          │
│  │   syndrome_id, status, effectiveness          │ ← 有数据  │
│  │   但 AbilityProfileService 只按单会话查询     │          │
│  └──────────────────────────────────────────────┘          │
│                                                             │
│  student-classifier.ts (Phase 2 骨架)                       │
│  ┌──────────────────────────────────────────────┐          │
│  │ classifyStudent() → 返回 'mixed' + confidence: 0│ ← 空壳  │
│  │ getThinkingOrientedStrategy() → 硬编码策略     │          │
│  │ getTechnicalOrientedStrategy() → 硬编码策略    │          │
│  └──────────────────────────────────────────────┘          │
│                                                             │
│  ability-profile.service.ts                                 │
│  ┌──────────────────────────────────────────────┐          │
│  │ computeProfile(sessionId) → AbilityProfile    │ ← 按单会话 │
│  │   只查 getBySession(sessionId)                │          │
│  │   不跨会话聚合                                │          │
│  │   计算结果没有被任何地方消费                   │          │
│  └──────────────────────────────────────────────┘          │
│                                                             │
│  chat.handler.ts                                            │
│  ┌──────────────────────────────────────────────┐          │
│  │ studentContext 参数 → 来自渲染进程             │ ← 透传    │
│  │   但渲染进程的 store 是死代码                  │          │
│  │   所以 studentContext 永远是 undefined         │          │
│  └──────────────────────────────────────────────┘          │
│                                                             │
│  prompt-loader.ts                                           │
│  ┌──────────────────────────────────────────────┐          │
│  │ {student_context} 占位符 → 替换为             │          │
│  │   '暂无学生状态数据。' (永远)                   │          │
│  └──────────────────────────────────────────────┘          │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 五个致命问题

| # | 问题 | 严重程度 | 说明 |
|---|------|----------|------|
| 1 | **student-context.store.ts 全是死代码** | 🔴 P0 | `updateFromDiagnosis()` 和 `updateFromInteraction()` 从未被调用，所有学生画像数据永远为默认值 |
| 2 | **V3 Prompt 的 `{student_context}` 永远是空** | 🔴 P0 | `studentContext` 参数在 chat.handler.ts 中从未被有效填充，V3 的学员分层和信心自适应永不生效 |
| 3 | **AbilityProfileService 只查单会话** | 🟡 P1 | `computeProfile(sessionId)` 用 `diagnosisService.getBySession(sessionId)` 只看当前会话，跨会话的"反复出现的问题"无法识别 |
| 4 | **三套用户类型系统互相冲突** | 🟡 P1 | store 用 beginner/intermediate/advanced，classifier 用 thinking/technical/mixed，方案又用 newbie/experienced/analytical/emotional |
| 5 | **诊断数据在 SQLite 但没人去读** | 🟡 P1 | `diagnosis_results` 表有完整数据，但没有 Service 做跨会话聚合 |

---

## 二、目标数据模型

### 2.1 设计原则

1. **单一数据源**（IntelliCode 中心化原则）：学生画像只存在于主进程 SQLite，渲染进程通过 IPC 获取只读视图
2. **两个正交维度**：能力等级 (proficiency) + 认知风格 (cognitiveStyle) 不揉成一个 enum
3. **跨会话聚合**：从所有 session 的诊断数据中构建用户画像，而非单会话
4. **不可靠存储不存储关键数据**：localStorage 只做 UI 偏好，不做学生模型

### 2.2 StudentModel 数据结构

```typescript
/**
 * 学生模型 — 月笙的核心用户画像
 * 
 * 设计理念：
 *   1. 由主进程 Service 从 SQLite 聚合计算，不依赖 localStorage
 *   2. 跨会话聚合（不是单会话快照）
 *   3. 两个正交维度：proficiency（能力等级）+ cognitiveStyle（认知风格）
 *   4. 可导出为 Prompt 注入文本
 */
export interface StudentModel {
  // === 身份标识 ===
  userId: string;                    // 当前为单用户，固定值 'default'
  updatedAt: string;                 // ISO 时间戳
  
  // === 维度一：能力等级 ===
  proficiency: ProficiencyLevel;     // beginner | intermediate | advanced
  proficiencyConfidence: number;     // 0-1，推断的置信度
  
  // === 维度二：认知风格 ===
  cognitiveStyle: CognitiveStyle;    // thinking | technical | mixed
  cognitiveStyleConfidence: number;  // 0-1
  
  // === 症候画像 ===
  syndromeProfile: SyndromeProfile;  // 每个症候的出现频率、严重度趋势
  
  // === 能力画像 ===
  abilityProfile: AbilityProfile;    // 8 项能力的评分、趋势
  
  // === 学习行为 ===
  learningBehavior: LearningBehavior; // 交互频率、放弃率、反思质量
  
  // === 教学偏好 ===
  teachingPreference: TeachingPreference; // 有效策略、态度偏好
}

// ── 能力等级 ──

export type ProficiencyLevel = 'beginner' | 'intermediate' | 'advanced';

/**
 * 推断规则：
 *   beginner:   L3 症候出现 >= 3 次，或 L2 症候出现 >= 5 次
 *   intermediate: 有 L2 症候但 < 5 次，或最近 3 次诊断趋势 = improving
 *   advanced:   最近 5 次诊断全是 L1，或大部分能力评分 > 80
 */

// ── 认知风格 ──

export type CognitiveStyle = 'thinking' | 'technical' | 'mixed';

/**
 * 推断规则（延用 student-classifier.ts 的设计，但实际实现）：
 *   thinking:  用户倾向问"为什么"、"怎么理解"，关注方向和框架
 *   technical: 用户倾向问"怎么做"、"给范例"，关注具体操作
 *   mixed:     两种模式交替出现，或数据不足以判断
 */

// ── 症候画像 ──

export interface SyndromeProfile {
  /** 每个症候的聚合数据 */
  syndromes: Record<SyndromeId, SyndromeAggregation>;
  
  /** 反复出现的问题（跨会话出现 >= 2 次的症候） */
  persistentProblems: SyndromeId[];
  
  /** 正在改善的问题（趋势 = improving） */
  improvingProblems: SyndromeId[];
  
  /** 恶化的问题（趋势 = worsening） */
  worseningProblems: SyndromeId[];
}

export interface SyndromeAggregation {
  /** 出现次数（跨所有会话） */
  occurrenceCount: number;
  
  /** 最近一次严重度 */
  latestSeverity: SeverityLevel;
  
  /** 严重度序列（按时间顺序，用于趋势计算） */
  severityHistory: SeverityLevel[];
  
  /** 趋势 */
  trend: 'improving' | 'worsening' | 'stable';
  
  /** 最近一次出现时间 */
  lastSeenAt: string;
  
  /** 涉及的会话列表 */
  sessionIds: string[];
}

// ── 能力画像（复用已有 AbilityProfile，但改为跨会话） ──

// 复用 src/renderer/shared/types.ts 中的 AbilityScore、WeakPoint 等类型
// 但 computeProfile 改为跨会话聚合

// ── 学习行为 ──

export interface LearningBehavior {
  /** 总对话次数 */
  totalSessions: number;
  
  /** 总诊断次数 */
  totalDiagnoses: number;
  
  /** 平均每次对话的字数 */
  avgWordsPerSession: number;
  
  /** 求助频率（每 10 轮对话中有几次主动要求帮助） */
  helpRequestRate: number;
  
  /** 放弃率（开始了练习但未完成的比例） */
  abandonRate: number;
  
  /** 反思质量（Challenge-Unlock 反思通过率） */
  reflectionPassRate: number | null;  // null = 尚未启用 Challenge-Unlock
  
  /** 挫折指标 */
  frustrationIndex: number;  // 0-1，综合计算
}

// ── 教学偏好 ──

export interface TeachingPreference {
  /** 历史上有效的教学动作（用户之后症候改善的动作） */
  effectiveActions: ActionId[];
  
  /** 态度模式偏好（用户最常选的模式） */
  preferredAttitude: AttitudeLevel;
  
  /** 聚焦方向偏好 */
  focusAreaPreference: FocusArea | null;
}
```

### 2.3 和现有数据结构的映射

| 新模型字段 | 数据来源 | 现有代码位置 |
|-----------|----------|-------------|
| `proficiency` | 从 `diagnosis_results` 聚合 L3/L2/L1 分布 | 新逻辑（替代 store 的 userType）|
| `cognitiveStyle` | 从 `messages` 表分析用户提问模式 | student-classifier.ts 的分类逻辑（需实现）|
| `syndromeProfile` | 从 `diagnosis_results` 聚合跨会话症候 | AbilityProfileService 的弱点逻辑（需扩展为跨会话）|
| `abilityProfile` | 从 `ability-atlas.json` 映射 + 聚合诊断 | AbilityProfileService（需改为跨会话）|
| `learningBehavior` | 从 `messages` + `user_training_records` 聚合 | 新逻辑（替代 store 的 frustrationCount）|
| `teachingPreference` | 从 `teaching_state` + `user_training_records` 聚合 | 新逻辑（替代 store 的 effectiveStrategies）|

---

## 三、StudentModelService 设计

### 3.1 架构位置

```
主进程服务架构

┌─────────────────────────────────────────────┐
│              chat.handler.ts                 │
│           (流程编排，不动核心逻辑)              │
└──────────────┬──────────────────────────────┘
               │
    ┌──────────┼──────────────────────┐
    ↓          ↓                      ↓
PromptLoader  DiagnosisService    StudentModelService ← 新增
    │          │                      │
    │          │              ┌───────┴───────┐
    │          │              ↓               ↓
    │          │     聚合查询(SQLite)    Prompt注入
    │          │     从所有 session     把 StudentModel
    │          │     的诊断数据中       转为文本注入
    │          │     构建用户画像       System Prompt
    ↓          ↓              
 diagnosis_results   teaching_state   user_training_records   messages
     (SQLite)          (SQLite)         (SQLite)            (SQLite)
```

### 3.2 Service 接口

```typescript
/**
 * 学生模型服务 — 单一数据源
 * 
 * 职责：
 *   1. 从 SQLite 聚合所有会话的诊断数据，构建用户画像
 *   2. 提供只读查询接口（不做缓存，实时计算，数据量小）
 *   3. 导出为 Prompt 注入文本
 *   4. 通过 IPC 同步到渲染进程（用于 UI 展示）
 * 
 * 不负责：
 *   - 不负责写入诊断结果（那是 DiagnosisService 的职责）
 *   - 不负责更新教学状态（那是 TeachingStateMachine 的职责）
 *   - 不负责 localStorage（废弃 localStorage 存储学生模型）
 */
export class StudentModelService {
  private db: Database.Database;
  private diagnosisService: DiagnosisService;
  private trainingService: TrainingRecordService;
  private sessionService: SessionService;
  
  constructor(
    db: Database.Database,
    diagnosisService: DiagnosisService,
    trainingService: TrainingRecordService,
    sessionService: SessionService,
  ) { ... }
  
  // ── 核心查询 ──
  
  /**
   * 获取当前用户的完整学生模型
   * 实时聚合计算（不缓存，数据量小，一致性优先）
   */
  getModel(): StudentModel;
  
  /**
   * 获取症候画像（核心功能）
   * 聚合所有会话的诊断数据
   */
  getSyndromeProfile(): SyndromeProfile;
  
  /**
   * 获取能力画像（跨会话版）
   * 替代 AbilityProfileService.computeProfile(sessionId) 的单会话版
   */
  getAbilityProfile(): AbilityProfile;
  
  /**
   * 获取学习行为指标
   */
  getLearningBehavior(): LearningBehavior;
  
  // ── Prompt 注入 ──
  
  /**
   * 导出为 Prompt 注入文本
   * 替代 student-context.store.ts 的 toJSON()
   * 这个方法的输出会替换 V3 Prompt 中的 {student_context} 占位符
   */
  toPromptText(): string;
  
  // ── 渲染进程同步 ──
  
  /**
   * 获取渲染进程需要的精简视图
   * 通过 IPC 传递给前端，用于 UI 展示
   */
  toRendererView(): StudentModelRendererView;
}
```

### 3.3 核心算法

#### 3.3.1 症候画像聚合

```typescript
/**
 * 从所有会话的诊断结果中聚合症候数据
 * 
 * SQL 查询：
 *   SELECT syndromes, timestamp, session_id 
 *   FROM diagnosis_results 
 *   ORDER BY timestamp ASC
 * 
 * 遍历所有行，解析 JSON，按症候 ID 聚合
 */
getSyndromeProfile(): SyndromeProfile {
  // 1. 查询所有诊断结果（不限 session_id）
  const allDiagnoses = this.db.prepare(
    'SELECT syndromes, timestamp, session_id FROM diagnosis_results ORDER BY timestamp ASC'
  ).all() as DiagnosisRow[];
  
  // 2. 解析并聚合
  const aggregations: Record<string, SyndromeAggregation> = {};
  
  for (const row of allDiagnoses) {
    const syndromes = JSON.parse(row.syndromes) as SyndromeResult[];
    for (const s of syndromes) {
      if (!aggregations[s.id]) {
        aggregations[s.id] = {
          occurrenceCount: 0,
          latestSeverity: s.severity,
          severityHistory: [],
          trend: 'stable',
          lastSeenAt: row.timestamp,
          sessionIds: [],
        };
      }
      
      const agg = aggregations[s.id];
      agg.occurrenceCount++;
      agg.latestSeverity = s.severity;
      agg.severityHistory.push(s.severity);
      agg.lastSeenAt = row.timestamp;
      if (!agg.sessionIds.includes(row.session_id)) {
        agg.sessionIds.push(row.session_id);
      }
    }
  }
  
  // 3. 计算趋势
  for (const agg of Object.values(aggregations)) {
    agg.trend = this.calcSyndromeTrend(agg.severityHistory);
  }
  
  // 4. 分类
  const persistent = Object.entries(aggregations)
    .filter(([_, agg]) => agg.sessionIds.length >= 2)
    .map(([id]) => id as SyndromeId);
    
  const improving = Object.entries(aggregptions)
    .filter(([_, agg]) => agg.trend === 'improving')
    .map(([id]) => id as SyndromeId);
    
  const worsening = Object.entries(aggregations)
    .filter(([_, agg]) => agg.trend === 'worsening')
    .map(([id]) => id as SyndromeId);
  
  return {
    syndromes: aggregations as Record<SyndromeId, SyndromeAggregation>,
    persistentProblems: persistent,
    improvingProblems: improving,
    worseningProblems: worsening,
  };
}

/**
 * 症候趋势计算
 * 
 * 将 L1/L2/L3 映射为数值 1/2/3，计算最近 5 次 vs 之前 5 次的平均值
 * 值下降 = 改善（severity 变低），值上升 = 恶化
 */
private calcSyndromeTrend(history: SeverityLevel[]): 'improving' | 'worsening' | 'stable' {
  if (history.length < 2) return 'stable';
  
  const toNum = (s: SeverityLevel) => s === 'L3' ? 3 : s === 'L2' ? 2 : 1;
  const nums = history.map(toNum);
  
  const recent = nums.slice(-5);
  const previous = nums.slice(-10, -5);
  
  if (previous.length === 0) return 'stable';
  
  const recentAvg = recent.reduce((a, b) => a + b, 0) / recent.length;
  const previousAvg = previous.reduce((a, b) => a + b, 0) / previous.length;
  
  // severity 下降 = 改善（数值变小）
  if (recentAvg < previousAvg * 0.8) return 'improving';
  if (recentAvg > previousAvg * 1.2) return 'worsening';
  return 'stable';
}
```

#### 3.3.2 能力等级推断

```typescript
/**
 * 推断用户能力等级
 * 
 * 规则：
 *   beginner:   L3 出现 >= 3 次，或 L2 出现 >= 5 次
 *   intermediate: 有 L2 但 < 5 次，或最近趋势 = improving
 *   advanced:   最近 5 次诊断全是 L1，或大部分能力评分 > 80
 */
inferProficiency(): { level: ProficiencyLevel; confidence: number } {
  const profile = this.getSyndromeProfile();
  const allSeverities: SeverityLevel[] = [];
  
  for (const agg of Object.values(profile.syndromes)) {
    allSeverities.push(...agg.severityHistory);
  }
  
  const l3Count = allSeverities.filter(s => s === 'L3').length;
  const l2Count = allSeverities.filter(s => s === 'L2').length;
  const l1Count = allSeverities.filter(s => s === 'L1').length;
  const total = allSeverities.length;
  
  if (total === 0) {
    return { level: 'beginner', confidence: 0 }; // 无数据，默认新手
  }
  
  // L3 出现 >= 3 次 → beginner（置信度随 L3 比例增加）
  if (l3Count >= 3) {
    const confidence = Math.min(1, l3Count / total + 0.3);
    return { level: 'beginner', confidence };
  }
  
  // L2 出现 >= 5 次 → beginner
  if (l2Count >= 5) {
    const confidence = Math.min(1, l2Count / total + 0.2);
    return { level: 'beginner', confidence };
  }
  
  // 最近 5 次全是 L1 → advanced
  const recent5 = allSeverities.slice(-5);
  if (recent5.length >= 5 && recent5.every(s => s === 'L1')) {
    return { level: 'advanced', confidence: 0.8 };
  }
  
  // 大部分能力评分 > 80 → advanced
  const abilityProfile = this.getAbilityProfile();
  const highAbilityCount = abilityProfile.abilities.filter(a => a.score > 80).length;
  if (highAbilityCount >= abilityProfile.abilities.length * 0.7) {
    return { level: 'advanced', confidence: 0.7 };
  }
  
  // 默认 → intermediate
  const confidence = Math.min(0.8, total / 10); // 10 次诊断后置信度较高
  return { level: 'intermediate', confidence };
}
```

#### 3.3.3 认知风格推断

```typescript
/**
 * 推断用户认知风格
 * 
 * 规则（基于用户消息中的提问模式）：
 *   thinking:  "为什么"、"怎么理解"、"本质"、"核心"、"逻辑" 出现频率高
 *   technical: "怎么做"、"给范例"、"改一下"、"示范" 出现频率高
 *   mixed:     两种模式交替出现，或数据不足
 */
inferCognitiveStyle(): { style: CognitiveStyle; confidence: number } {
  // 查询所有用户消息
  const userMessages = this.db.prepare(
    "SELECT content FROM messages WHERE role = 'user' ORDER BY timestamp ASC"
  ).all() as { content: string }[];
  
  if (userMessages.length < 5) {
    return { style: 'mixed', confidence: 0 }; // 数据不足
  }
  
  // 关键词统计
  const thinkingKeywords = ['为什么', '怎么理解', '本质', '核心', '逻辑', '意义', '深层', '框架', '方向', '理念'];
  const technicalKeywords = ['怎么做', '给范例', '改一下', '示范', '具体', '操作', '模板', '步骤', '练习', '例子'];
  
  let thinkingScore = 0;
  let technicalScore = 0;
  
  for (const msg of userMessages) {
    const content = msg.content;
    for (const kw of thinkingKeywords) {
      if (content.includes(kw)) thinkingScore++;
    }
    for (const kw of technicalKeywords) {
      if (content.includes(kw)) technicalScore++;
    }
  }
  
  const total = thinkingScore + technicalScore;
  if (total === 0) return { style: 'mixed', confidence: 0 };
  
  const thinkingRatio = thinkingScore / total;
  
  if (thinkingRatio >= 0.6) {
    return { style: 'thinking', confidence: thinkingRatio };
  }
  if (thinkingRatio <= 0.4) {
    return { style: 'technical', confidence: 1 - thinkingRatio };
  }
  return { style: 'mixed', confidence: 0.5 };
}
```

#### 3.3.4 Prompt 注入文本

```typescript
/**
 * 导出为 Prompt 注入文本
 * 替代 V3 Prompt 中的 {student_context} 占位符
 * 
 * 格式设计原则：
 *   1. 简洁 — 不超过 300 字（V3 Prompt 已经很长了）
 *   2. 可操作 — AI 能据此调整教学策略
 *   3. 动态 — 每次查询都反映最新状态
 */
toPromptText(): string {
  const model = this.getModel();
  const lines: string[] = [];
  
  // 1. 基础画像（2 行）
  const proficiencyMap = { beginner: '新手写作者', intermediate: '进阶写作者', advanced: '成熟写作者' };
  const styleMap = { thinking: '理性分析型', technical: '实操导向型', mixed: '混合型' };
  lines.push(`- 用户画像：${proficiencyMap[model.proficiency]}，${styleMap[model.cognitiveStyle]}`);
  
  // 2. 反复出现的问题（核心价值 — 这是从数据库聚合的）
  if (model.syndromeProfile.persistentProblems.length > 0) {
    const names = model.syndromeProfile.persistentProblems
      .map(id => SYNDROME_NAMES[id] ?? id)
      .join('、');
    lines.push(`- 反复出现的问题：${names}（跨 ${model.learningBehavior.totalSessions} 次对话）`);
  }
  
  // 3. 正在改善 / 恶化的信号
  if (model.syndromeProfile.improvingProblems.length > 0) {
    const names = model.syndromeProfile.improvingProblems
      .map(id => SYNDROME_NAMES[id] ?? id)
      .join('、');
    lines.push(`- 正在改善：${names}`);
  }
  if (model.syndromeProfile.worseningProblems.length > 0) {
    const names = model.syndromeProfile.worseningProblems
      .map(id => SYNDROME_NAMES[id] ?? id)
      .join('、');
    lines.push(`- 需要关注：${names}（最近有恶化趋势）`);
  }
  
  // 4. 挫折信号
  if (model.learningBehavior.frustrationIndex > 0.6) {
    lines.push(`- 用户当前可能感到挫折，建议先肯定进步再指出问题`);
  }
  
  // 5. 有效策略
  if (model.teachingPreference.effectiveActions.length > 0) {
    const actionNames = model.teachingPreference.effectiveActions
      .map(id => ACTION_NAMES[id] ?? id)
      .join('、');
    lines.push(`- 历史上有效的教学方式：${actionNames}`);
  }
  
  return lines.join('\n');
}
```

**注入效果对比**：

```
【之前】V3 Prompt 中的 {student_context}：
  → "暂无学生状态数据。"（永远）

【之后】V3 Prompt 中的 {student_context}：
  → - 用户画像：进阶写作者，理性分析型
    - 反复出现的问题：信息硬塞、角色工具人化（跨 5 次对话）
    - 正在改善：世界观膨胀
    - 需要关注：视角漂移（最近有恶化趋势）
    - 历史上有效的教学方式：现实锚点、五问法
```

---

## 四、改造方案 — 逐步替换

### 4.1 改造步骤（按安全顺序）

```
Step 1: 新建 StudentModelService（不改动任何现有代码）
  ↓
Step 2: 在 chat.handler.ts 中调用 StudentModelService.toPromptText()
        替代从渲染进程传入的 studentContext 参数
  ↓
Step 3: 修改 PromptLoader.loadSystemPrompt() 
        把 studentContext 参数改为由主进程自动填充
  ↓
Step 4: 添加 IPC 通道，让渲染进程能获取 StudentModel（UI 展示用）
  ↓
Step 5: 标记 student-context.store.ts 为 @deprecated
        保留文件但不再调用
  ↓
Step 6: 删除 student-context.store.ts 和 student-classifier.ts（V2 清理）
```

### 4.2 Step 1: StudentModelService 完整实现

```typescript
// src/main/services/student-model.service.ts

import Database from 'better-sqlite3';
import { DiagnosisService } from './diagnosis.service';
import { TrainingRecordService } from './training-record.service';
import { SessionService } from './session.service';
import { 
  StudentModel, ProficiencyLevel, CognitiveStyle,
  SyndromeProfile, SyndromeAggregation, LearningBehavior, 
  TeachingPreference, AbilityProfile 
} from '../../shared/student-model.types';
import { SYNDROME_NAMES, ACTION_NAMES } from '../../shared/mappings';
import { SeverityLevel, SyndromeId, ActionId, AttitudeLevel, FocusArea } from '../../renderer/shared/types';

export class StudentModelService {
  private db: Database.Database;
  private diagnosisService: DiagnosisService;
  private trainingService: TrainingRecordService;
  private sessionService: SessionService;
  private abilityProfileService: AbilityProfileService;

  constructor(
    db: Database.Database,
    diagnosisService: DiagnosisService,
    trainingService: TrainingRecordService,
    sessionService: SessionService,
    abilityProfileService: AbilityProfileService,
  ) {
    this.db = db;
    this.diagnosisService = diagnosisService;
    this.trainingService = trainingService;
    this.sessionService = sessionService;
    this.abilityProfileService = abilityProfileService;
  }

  /** 获取完整学生模型 */
  getModel(): StudentModel {
    const proficiency = this.inferProficiency();
    const cognitiveStyle = this.inferCognitiveStyle();
    const syndromeProfile = this.getSyndromeProfile();
    
    // 跨会话能力画像：查所有 session 的诊断
    const allSessionIds = this.getAllDiagnosedSessionIds();
    const abilityProfile = this.computeCrossSessionAbilityProfile(allSessionIds);
    
    const learningBehavior = this.computeLearningBehavior();
    const teachingPreference = this.computeTeachingPreference();
    
    return {
      userId: 'default',
      updatedAt: new Date().toISOString(),
      proficiency: proficiency.level,
      proficiencyConfidence: proficiency.confidence,
      cognitiveStyle: cognitiveStyle.style,
      cognitiveStyleConfidence: cognitiveStyle.confidence,
      syndromeProfile,
      abilityProfile,
      learningBehavior,
      teachingPreference,
    };
  }

  /** 导出为 Prompt 注入文本 */
  toPromptText(): string {
    // ... 见 3.3.4 节
  }

  /** 获取所有有过诊断的 session ID */
  private getAllDiagnosedSessionIds(): string[] {
    const rows = this.db.prepare(
      'SELECT DISTINCT session_id FROM diagnosis_results ORDER BY session_id'
    ).all() as { session_id: string }[];
    return rows.map(r => r.session_id);
  }

  /** 跨会话能力画像（核心改动：不再只查单个 session） */
  private computeCrossSessionAbilityProfile(sessionIds: string[]): AbilityProfile {
    // 聚合所有 session 的症候数据
    const allSyndromeOccurrences: Record<string, { severity: SeverityLevel; timestamp: string }[]> = {};
    
    for (const sid of sessionIds) {
      const diagnoses = this.diagnosisService.getBySession(sid);
      for (const d of diagnoses) {
        for (const s of d.syndromes) {
          if (!allSyndromeOccurrences[s.id]) allSyndromeOccurrences[s.id] = [];
          allSyndromeOccurrences[s.id].push({
            severity: s.severity,
            timestamp: d.timestamp,
          });
        }
      }
    }
    
    // ... 复用 AbilityProfileService 的计算逻辑，但用跨会话数据
  }

  // ... 其他方法见 3.3.x 节
}
```

### 4.3 Step 2: 改造 chat.handler.ts

```typescript
// 改动前：
const systemPrompt = promptLoader?.loadSystemPrompt(
  attitude,
  diagnosisAnalysis,
  diagnosisHistory,
  studentContext,  // ← 从渲染进程传入，永远为 undefined
  activeSessionId,
);

// 改动后：
const studentModelText = studentModelService?.toPromptText() ?? '暂无学生状态数据。';
const systemPrompt = promptLoader?.loadSystemPrompt(
  attitude,
  diagnosisAnalysis,
  diagnosisHistory,
  studentModelText,  // ← 从主进程 StudentModelService 生成
  activeSessionId,
);
```

### 4.4 Step 4: IPC 通道

```typescript
// 新增 IPC 通道
IPC_CHANNELS.STUDENT_MODEL_GET = 'student-model:get';

// 注册 handler
ipcMain.handle(IPC_CHANNELS.STUDENT_MODEL_GET, () => {
  return studentModelService?.toRendererView() ?? null;
});

// 渲染进程调用
const studentModel = await window.electron.invoke('student-model:get');
```

### 4.5 Step 5: 标记废弃

```typescript
// src/renderer/stores/student-context.store.ts
/**
 * @deprecated 使用 StudentModelService（主进程）替代
 * 此文件将在 V2 中删除
 * 渲染进程通过 IPC_CHANNELS.STUDENT_MODEL_GET 获取学生模型
 */
```

---

## 五、数据流对比

### 5.1 之前（断裂）

```
用户写文 → DiagnosisAgent → diagnosis-parser → DiagnosisService.save()
                                                         ↓
                                                   SQLite (有数据但无人读)
                                                        
student-context.store.ts (死代码，从未调用 updateFromDiagnosis)
                                                         ↓
                                                   localStorage (随时可能丢)
                                                         ↓
chat.handler.ts → studentContext = undefined → Prompt 里永远写"暂无"
```

### 5.2 之后（统一）

```
用户写文 → DiagnosisAgent → diagnosis-parser → DiagnosisService.save()
                                                         ↓
                                                   SQLite
                                                         ↓
                                              StudentModelService.getModel()
                                              (聚合所有 session 的诊断数据)
                                                         ↓
                                              StudentModelService.toPromptText()
                                              (转为 200-300 字的 Prompt 注入文本)
                                                         ↓
                                              PromptLoader.loadSystemPrompt()
                                              (替换 {student_context} 占位符)
                                                         ↓
                                              AI 收到真实的用户画像 → 自适应教学
```

---

## 六、前端 UI 适配

### 6.1 渲染进程数据获取

```typescript
// 新增 hook: useStudentModel
function useStudentModel() {
  const [model, setModel] = useState<StudentModelRendererView | null>(null);
  
  useEffect(() => {
    // 首次加载
    window.electron.invoke('student-model:get').then(setModel);
    
    // 监听更新（每次诊断后推送）
    window.electron.on('student-model:updated', (_event, newModel) => {
      setModel(newModel);
    });
  }, []);
  
  return model;
}
```

### 6.2 UI 组件映射

| UI 组件 | 当前数据来源 | 改造后数据来源 |
|---------|-------------|---------------|
| DiagnosisPanel | DiagnosisEntry (IPC) | 不变 |
| AbilityRadar | AbilityProfile (IPC) | StudentModel.abilityProfile (跨会话版) |
| GrowthTab | AbilityProfile (单会话) | StudentModel.abilityProfile (跨会话) |
| 态度模式切换 | ConfigService | StudentModel.teachingPreference.preferredAttitude (默认值) |
| 用户类型标签 | 无 | StudentModel.proficiency (新手/进阶/成熟) |

---

## 七、废弃清单

| 文件 | 状态 | 说明 |
|------|------|------|
| `src/renderer/stores/student-context.store.ts` | 🗑️ 标记废弃 | 所有逻辑迁移到 StudentModelService |
| `src/main/services/student-classifier.ts` | 🗑️ 标记废弃 | 分类逻辑合并到 StudentModelService.inferCognitiveStyle() |
| `src/main/services/ability-profile.service.ts` | 🔄 保留但重构 | computeProfile 改为跨会话聚合 |
| localStorage key `yuesheng-student-context` | 🗑️ 删除 | 不再依赖 localStorage |

---

## 八、实施排期

```
Day 1-2: 新建 StudentModelService（getModel + getSyndromeProfile + toPromptText）
Day 3:   修改 chat.handler.ts，用 StudentModelService 替代 studentContext 参数
Day 4:   修改 PromptLoader，确保 {student_context} 被正确替换
Day 5:   添加 IPC 通道 + 前端 hook
Day 6:   标记废弃旧文件 + 测试
Day 7:   端到端验证 + 修复边界情况
```

---

## 九、风险与缓解

| 风险 | 缓解 |
|------|------|
| 跨会话聚合查询可能慢 | 数据量小（单用户，最多几十个 session），毫秒级完成 |
| 新用户无数据，Prompt 注入为空 | 设计空状态提示："新用户，尚未建立画像。请先提交一段文字进行诊断。" |
| abilityProfileService 重构影响现有 UI | 先建新 Service，旧 Service 保留直到前端迁移完成 |
| 认知风格推断不准确 | 初版用简单关键词匹配，后续可用 LLM 辅助分类 |

---

*本设计文档为实施蓝图，开发时按 Step 1-6 逐步推进，每步可独立验证。*
