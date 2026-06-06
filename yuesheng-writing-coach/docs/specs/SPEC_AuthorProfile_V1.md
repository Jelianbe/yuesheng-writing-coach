# SPEC_AuthorProfile_V1.md

> 版本：V1.0 | 创建：2026-06-02 | 核心原则：能力值只是索引，成长证据才是核心资产
> 核心认知：用户看到的不是"45 → 72"，而是"过去的自己 → 现在的自己"。

---

## 一、设计原则

1. **三层结构**：能力评分（快速展示）→ 能力轨迹（成长追踪）→ 成长证据（解释）。
2. **证据中心**：能力值只是索引，指向背后的成长证据链。
3. **规则计算 V1**：V1 用简单规则计算能力值，不碰机器学习/复杂权重。
4. **跨小说累积**：AuthorProfile 跨会话、跨小说持续累积，是作者的长期档案。

---

## 二、三层结构

### Layer 1：能力评分（Ability Scores）

**用途**：快速展示当前能力水平。

**示例**：
```json
{
  "abilities": {
    "OBS": { "score": 61, "trend": "up", "status": "developing" },
    "CHAR": { "score": 73, "trend": "stable", "status": "proficient" },
    "PLOT": { "score": 55, "trend": "down", "status": "struggling" },
    "EMO": { "score": 48, "trend": "up", "status": "developing" },
    "WORLD": { "score": 70, "trend": "stable", "status": "proficient" },
    "STYLE": { "score": 52, "trend": "up", "status": "developing" }
  }
}
```

**分数区间含义**：

| 分数 | 状态 | 说明 |
|------|------|------|
| 0-40 | struggling | 需要重点训练 |
| 41-60 | developing | 正在成长 |
| 61-80 | proficient | 已经掌握 |
| 81-100 | master | 可以教学他人 |

**计算方式（V1 规则 — 子能力基础方案）**：
```
初始分数：
  每个子能力初始分数 = 50（新用户默认值）

子能力分数更新（每次诊断后）：
  如果症候解决 → 对应子能力 +5
  如果症候改善（L3→L2 或 L2→L1） → 对应子能力 +3
  如果症候恶化（L1→L2 或 L2→L3） → 对应子能力 -2
  如果新发现症候 → 对应子能力 -3

核心能力分数 = 其下属子能力分数的算术平均
  例：OBS = (OBS-001 + OBS-002 + OBS-003 + OBS-004) / 4

边界：0-100
```

> **V1 刻意简化**：不搞平滑算法、不碰权重矩阵。等能力树稳定后，V2 再优化算法。
> 
> **与 SPEC_Ability_Map 的对齐**：本算法与 SPEC_Ability_Map 第六章的"算术平均"权重定义一致。核心能力分数由子能力分数聚合，子能力分数由诊断事件驱动。

---

### Layer 2：能力轨迹（Ability Trajectory）

**用途**：展示能力随时间的变化曲线。

**示例**：
```json
{
  "trajectories": {
    "OBS": [
      { "date": "2026-06-01", "score": 42, "eventId": "DIAG-000001" },
      { "date": "2026-07-15", "score": 48, "eventId": "EVAL-000001" },
      { "date": "2026-08-20", "score": 55, "eventId": "DIAG-000002" },
      { "date": "2026-09-10", "score": 61, "eventId": "DIAG-000003" }
    ],
    "CHAR": [
      { "date": "2026-06-01", "score": 65, "eventId": "DIAG-000001" },
      { "date": "2026-09-10", "score": 73, "eventId": "DIAG-000003" }
    ]
  }
}
```

**特点**：
- 每个能力一条时间线
- 每个数据点关联一个事件（诊断/评估）
- 用于绘制成长曲线

---

### Layer 3：成长证据（Growth Evidence）

**用途**：解释"为什么是这个分数"，展示"过去的自己 → 现在的自己"。

**示例**：
```json
{
  "growthChains": [
    {
      "chainId": "CHAIN-000001",
      "abilityId": "OBS",
      "syndromeId": "P003",
      "status": "resolved",
      "timeline": [
        {
          "eventType": "diagnosis",
          "eventId": "DIAG-000001",
          "date": "2026-06-01",
          "severity": "L3",
          "snapshotId": "S-000001",
          "sampleText": "他很愤怒。",
          "evidenceIds": ["EVD-000001", "EVD-000002", "EVD-000101"]
        },
        {
          "eventType": "training",
          "eventId": "TRAIN-000001",
          "date": "2026-06-15",
          "exerciseId": "T005",
          "description": "感官替换训练"
        },
        {
          "eventType": "evaluation",
          "eventId": "EVAL-000001",
          "date": "2026-07-15",
          "score": 68,
          "snapshotId": "S-000003",
          "sampleText": "他的指节一点点收紧，掌心被指甲掐出白痕。"
        },
        {
          "eventType": "training",
          "eventId": "TRAIN-000002",
          "date": "2026-08-01",
          "exerciseId": "T021",
          "description": "情绪层次训练"
        },
        {
          "eventType": "diagnosis",
          "eventId": "DIAG-000003",
          "date": "2026-09-10",
          "severity": "L1",
          "snapshotId": "S-000008",
          "sampleText": "他望着空荡荡的房间，许久没有说话。窗台上的绿萝枯了，他也没换。",
          "evidenceIds": ["EVD-000301"]
        }
      ],
      "improvement": "从情绪标签 → 感官细节 → 环境映射",
      "scoreFrom": 42,
      "scoreTo": 61
    }
  ]
}
```

**特点**：
- 每个成长链对应一个"问题 → 训练 → 改善"的完整周期
- 包含作品片段对比（SNAPSHOT）
- 是"成长可视化"的核心数据源

---

## 三、AuthorProfile 完整数据结构

> **与现有代码的兼容性说明**：当前 `types.ts` 中的 `AbilityProfile` 是基于 session 的实时聚合接口（使用 ABL 体系）。本规范定义的新接口命名为 `AuthorProfileV2`，基于 author 的持久档案（使用 OBS/CHAR/PLOT/EMO/WORLD/STYLE 体系）。V1 阶段两者并存，V1.5 迁移完成后替换。

```typescript
interface AuthorProfileV2 {
  authorId: string;
  
  // Layer 1: 能力评分
  abilities: Record<string, {
    score: number;
    trend: 'up' | 'down' | 'stable';
    status: 'struggling' | 'developing' | 'proficient' | 'master';
  }>;
  
  // Layer 2: 能力轨迹
  trajectories: Record<string, Array<{
    date: string;
    score: number;
    eventId: string;
  }>>;
  
  // Layer 3: 成长证据链
  growthChains: Array<{
    chainId: string;
    abilityId: string;
    syndromeId: string;
    status: 'active' | 'improving' | 'resolved' | 'recurred';
    timeline: Array<{
      eventType: 'diagnosis' | 'training' | 'evaluation';
      eventId: string;
      date: string;
      severity?: 'L1' | 'L2' | 'L3';
      snapshotId?: string;
      sampleText?: string;
      evidenceIds?: string[];
      exerciseId?: string;
      description?: string;
      score?: number;
    }>;
    improvement: string;
    scoreFrom: number;
    scoreTo: number;
  }>;
  
  // 统计
  stats: {
    totalNovels: number;
    totalChapters: number;
    totalDiagnoses: number;
    totalTrainingsCompleted: number;
    totalTrainingsAssigned: number;
    averageTrainingEffectiveness: number;
    firstDiagnosisAt: string;
    lastDiagnosisAt: string;
  };
  
  // 学员画像（V2.2 新增）
  studentProfile: {
    tier: 'beginner' | 'intermediate' | 'advanced';
    selfCensorshipFrequency: number;
    emotionEscalationTendency: number;
    crossContextResponsiveness: number;
    autonomyNeed: number;
    preferredAttitude: 'gentle' | 'direct' | 'sharp';
  };
  
  // 元数据
  createdAt: string;
  updatedAt: string;
}
```

---

## 四、成长可视化场景

### 场景 1：能力雷达图

```
用户打开月笙首页
  ↓
展示 Layer 1：能力雷达图
  OBS: 61 (developing)
  CHAR: 73 (proficient)
  PLOT: 55 (struggling) ← 标红提示
  EMO: 48 (developing)
  WORLD: 70 (proficient)
  STYLE: 52 (developing)
```

### 场景 2：成长时间轴

```
用户点击 P003 情绪标签化
  ↓
展示 Layer 3：成长时间轴

2026.06.01  诊断 P003（L3）
━━━━━━━━━━━━━━━━━━━━━━━━
证据："他很愤怒。"
问题：情绪标签化，读者无法感受

2026.06.15  训练 T005
━━━━━━━━━━━━━━━━━━━━━━━━
内容：感官替换训练

2026.07.15  评估
━━━━━━━━━━━━━━━━━━━━━━━━
改善："他的指节一点点收紧..."
效果：有进步，但还可以更深

2026.08.01  训练 T021
━━━━━━━━━━━━━━━━━━━━━━━━
内容：情绪层次训练

2026.09.10  诊断 P003（L1）
━━━━━━━━━━━━━━━━━━━━━━━━
证据："他望着空荡荡的房间..."
结论：显著改善，能力稳定

【系统提示】P003 已解决！观察能力从 42 提升到 61。
```

### 场景 3：作品对比

```
用户点击"看看我的成长"
  ↓
展示 Layer 3：作品对比

【同一个场景：主角发现背叛】

三个月前：
━━━━━━━━━━━━━━━━━━━━━━━━
"他很愤怒。"

现在：
━━━━━━━━━━━━━━━━━━━━━━━━
"他的指节一点点收紧，掌心被指甲掐出白痕。"

【系统提示】你从"告诉读者情绪"变成了"让读者自己感受情绪"。这是观察能力的质变。
```

---

## 五、更新触发机制

```
Diagnosis Agent 完成诊断
  ↓
生成 DiagnosisResult
  ↓
触发 AuthorProfile Update
  ↓
1. 读取当前 AuthorProfile
2. 根据诊断结果更新 Layer 1（能力评分）
3. 追加 Layer 2（能力轨迹）
4. 更新/创建 Layer 3（成长证据链）
   - 如果是已知症候 → 追加到现有 growthChain
   - 如果是新症候 → 创建新 growthChain
5. 更新 stats
6. 保存 AuthorProfile
```

---

## 六、数据库存储方案

### 6.1 author_profiles 表

```sql
CREATE TABLE IF NOT EXISTS author_profiles (
    author_id TEXT PRIMARY KEY,
    
    -- Layer 1: 能力评分（JSON）
    ability_scores TEXT NOT NULL DEFAULT '{}',
    -- 结构: {"OBS": {"score": 61, "trend": "up", "status": "developing"}, ...}
    
    -- Layer 2: 能力轨迹（JSON）
    ability_trajectories TEXT NOT NULL DEFAULT '{}',
    -- 结构: {"OBS": [{"date": "2026-06-01", "score": 42, "eventId": "DIAG-001"}, ...]}
    
    -- Layer 3: 成长证据链（JSON）
    growth_chains TEXT NOT NULL DEFAULT '[]',
    -- 结构: [{"chainId": "CHAIN-001", "abilityId": "OBS", ...}]
    
    -- 统计
    total_novels INTEGER DEFAULT 0,
    total_chapters INTEGER DEFAULT 0,
    total_diagnoses INTEGER DEFAULT 0,
    total_trainings_completed INTEGER DEFAULT 0,
    total_trainings_assigned INTEGER DEFAULT 0,
    first_diagnosis_at TEXT,
    last_diagnosis_at TEXT,
    
    -- 元数据
    created_at TEXT NOT NULL,
    updated_at TEXT NOT NULL,
    
    -- 学员画像（V2.2 新增，JSON）
    student_profile TEXT NOT NULL DEFAULT '{}'
    -- 结构: {"tier":"beginner","selfCensorshipFrequency":0,"emotionEscalationTendency":0,"crossContextResponsiveness":0,"autonomyNeed":0,"preferredAttitude":"gentle"}
);

CREATE INDEX IF NOT EXISTS idx_author_profile_updated ON author_profiles(updated_at);
```

### 6.2 growth_chain_events 表（Layer 3 展开存储）

为了支持按时间、按能力、按症候的高效查询，Layer 3 的 timeline 事件单独存储：

```sql
CREATE TABLE IF NOT EXISTS growth_chain_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    chain_id TEXT NOT NULL,
    author_id TEXT NOT NULL,
    event_type TEXT NOT NULL CHECK(event_type IN ('diagnosis', 'training', 'evaluation')),
    event_id TEXT NOT NULL,              -- DIAG-XXXXXX / TRAIN-XXXXXX / EVAL-XXXXXX
    date TEXT NOT NULL,
    ability_id TEXT NOT NULL,            -- OBS / CHAR / PLOT 等
    syndrome_id TEXT,                    -- P001~P0XX（训练事件可能无症候）
    severity TEXT CHECK(severity IN ('L1', 'L2', 'L3')),
    snapshot_id TEXT,                    -- 关联快照
    sample_text TEXT,                    -- 作品片段（< 500字）
    evidence_ids TEXT,                   -- JSON 数组 ["EVD-000001", "EVD-000002"]，应用层校验引用完整性
    exercise_id TEXT,                    -- T001~T0XX
    description TEXT,
    score INTEGER,                       -- 评估时的能力分数
    
    FOREIGN KEY (author_id) REFERENCES author_profiles(author_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_gce_author ON growth_chain_events(author_id);
CREATE INDEX IF NOT EXISTS idx_gce_ability ON growth_chain_events(ability_id);
CREATE INDEX IF NOT EXISTS idx_gce_syndrome ON growth_chain_events(syndrome_id);
CREATE INDEX IF NOT EXISTS idx_gce_chain ON growth_chain_events(chain_id);
CREATE INDEX IF NOT EXISTS idx_gce_date ON growth_chain_events(date);
```

> **外键说明**：`evidence_ids` 是 JSON 数组，SQLite 不支持 JSON 字段的外键约束。Evidence 引用完整性由应用层校验（见 SPEC_ThreeSpecs_Integration 4.2）。

### 6.3 与 Evidence 系统的显式关联

```
AuthorProfile.Layer 3（成长证据链）
  ├── timeline[].evidence_ids → 引用 Evidence 表
  │     └── ["EVD-001", "EVD-101", "EVD-201"]
  │           ↓
  │     这些 Evidence 来自 SPEC_Evidence 定义的四级证据体系
  │
  ├── timeline[].snapshot_id → 引用 snapshots 表
  │     └── 用于 Level 4 对比证据的数据源
  │
  └── timeline[].event_id → 引用诊断/训练/评估事件
        └── DIAG-001 / TRAIN-001 / EVAL-001
```

**关键设计决策**：
- `evidence_ids` 以 JSON 数组存储，因为单个事件通常关联 1-5 个 Evidence
- Evidence 的详细内容存储在 `evidence` 表（SPEC_Evidence 定义）
- AuthorProfile 只存储 Evidence 的引用（ID），不冗余存储内容

---

## 七、接口定义

### 7.1 AuthorProfile Service 接口

```typescript
interface IAuthorProfileService {
  // 读取
  getProfile(authorId: string): Promise<AuthorProfile>;
  getAbilityScore(authorId: string, abilityId: string): Promise<AbilityScore>;
  getAbilityTrajectory(authorId: string, abilityId: string): Promise<TrajectoryPoint[]>;
  getGrowthChain(authorId: string, syndromeId: string): Promise<GrowthChain | null>;
  
  // 更新（由诊断触发）
  updateAfterDiagnosis(
    authorId: string,
    diagnosis: DiagnosisResult,
    evidenceIds: string[]
  ): Promise<AuthorProfile>;
  
  // 更新（由训练完成触发）
  recordTraining(
    authorId: string,
    trainingEvent: TrainingEvent
  ): Promise<AuthorProfile>;
  
  // 评估（由用户提交训练成果触发）
  recordEvaluation(
    authorId: string,
    evaluation: EvaluationResult
  ): Promise<AuthorProfile>;
  
  // 成长可视化
  getGrowthVisualization(
    authorId: string,
    type: 'radar' | 'timeline' | 'comparison',
    options?: { abilityId?: string; syndromeId?: string; fromDate?: string }
  ): Promise<VisualizationData>;
}
```

### 7.2 可视化数据接口

```typescript
// 雷达图数据
interface RadarVisualization {
  abilities: Array<{
    abilityId: string;
    score: number;
    status: 'struggling' | 'developing' | 'proficient' | 'master';
  }>;
}

// 时间轴数据
interface TimelineVisualization {
  abilityId: string;
  events: Array<{
    date: string;
    type: 'diagnosis' | 'training' | 'evaluation';
    score: number;
    description: string;
    evidenceIds: string[];
  }>;
}

// 作品对比数据
interface ComparisonVisualization {
  abilityId: string;
  syndromeId: string;
  earlier: {
    date: string;
    text: string;
    snapshotId: string;
  };
  later: {
    date: string;
    text: string;
    snapshotId: string;
  };
  improvement: string;
  evidenceId: string;  // Level 4 对比 Evidence
}
```

---

## 八、与现有系统的衔接

| 现有组件 | 衔接方式 |
|---------|---------|
| `ability-profile.service.ts` | 从"实时聚合 diagnosis_results"改为"读取 author_profiles 表" |
| `diagnosis_results` | 保留作为 DIAG 事件记录，新增关联到 AuthorProfile |
| `user_training_records` | 保留作为 TRAIN 事件记录，新增关联到 AuthorProfile |
| `TeachingState.activeProblems` | 数据来源改为 AuthorProfile.growthChains（status = 'active'） |

---

## 九、DoD

1. Layer 1 能力评分结构定义完整，含 6 项能力 + 分数区间含义
2. Layer 2 能力轨迹结构定义完整，支持时间线绘制
3. Layer 3 成长证据链结构定义完整，支持"问题 → 训练 → 改善"全周期追踪
4. V1 能力评分算法文档化（简单规则，不含 ML）
5. 三种可视化场景文档化（雷达图 / 时间轴 / 作品对比）
6. 更新触发机制文档化
7. 数据库表结构定义完整（author_profiles + growth_chain_events）
8. 与 Evidence 系统的关联关系文档化（evidence_ids 引用机制）
9. AuthorProfile Service 接口定义完整（读取/更新/评估/可视化）
10. 三种可视化数据接口定义完整（Radar/Timeline/Comparison）

---

## 十、V2 升级方向（不实现，仅预留）

| 方向 | 说明 |
|------|------|
| 平滑算法 | 用 EMA（指数移动平均）替代简单加减 |
| 权重矩阵 | 不同子能力对核心能力的贡献权重 |
| 预测模型 | 基于历史轨迹预测能力变化趋势 |
| 跨作者对比 | 匿名化后与其他作者的能力分布对比 |
