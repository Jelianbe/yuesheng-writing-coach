# SPEC_novel-profile_V1.0.md

> 版本：V1.0 | 创建：2026-06-02 | 依据：SESSION-2026-06-02-summary.md
> 核心认知：诊断对象不是小说，而是作者能力。小说只是作者能力的观测样本。

---

## 一、三层架构

```
Layer 1: Raw Novel（观测样本）
  └── novels 表 + chapters 表
  └── 存储：原始文本、章节结构
  └── 生命周期：随用户上传而累积

Layer 2: NovelProfile（诊断中间层）
  └── Projections（投影）+ Evidence（证据）
  └── 存储：诊断所需的结构化特征 + 证据片段
  └── 设计原则：只保留诊断需要的信息，不保存完整设定/剧情/人物档案
  └── 生命周期：随章节上传增量更新

Layer 3: AuthorProfile（核心资产）
  └── author_profiles 表
  └── 存储：作者能力评分、诊断历史、训练历史、能力变化曲线
  └── 设计原则：这是月笙真正的长期价值所在
  └── 生命周期：跨小说、跨会话持续累积
```

**关键区分**：
- `NovelProfile` = "这本小说里有什么教学相关特征"
- `Novel Knowledge Base` = "这本小说的完整设定/剧情/人物档案"（独立存储，诊断不直接读取）
- `AuthorProfile` = "这个作者的能力水平如何变化"

---

## 二、核心概念定义（三件事）

### 2.1 Projection 是什么

**定义**：Projection 是从原始小说中抽取的、**诊断 Agent 可直接读取的结构化特征**。它是小说的"降维投影"——保留诊断需要的维度，丢弃无关细节。

**设计原则**：
1. **诊断驱动**：Projection 中只包含症候诊断需要的字段，不预存所有可能的特征
2. **数值化优先**：特征尽量用数值表示，方便诊断 Agent 做阈值判断
3. **只读**：Projection 由 Extractor Agent 生成，Diagnosis Agent 只读不写

**当前三种 Projection**：

```typescript
// CharacterProjection — 人物相关特征
interface CharacterProjection {
  novelId: string;
  updatedAt: string;
  mainCharacters: Array<{
    name: string;
    initiativeScore: number;      // 0-100，主动性评分（P002诊断用）
    goalClarity: number;          // 0-100，目标清晰度（P002诊断用）
    choiceCount: number;          // 主动选择次数（P002诊断用）
    tagCount: number;             // 标签化描述次数（P010诊断用）
    contradictionScore: number;   // 0-100，内在矛盾深度（P010诊断用）
    relationshipCount: number;    // 关系线数量
  }>;
  protagonistPassiveRatio: number; // 主角被动/主动场景比（P002诊断用）
}

// WorldProjection — 世界观相关特征
interface WorldProjection {
  novelId: string;
  updatedAt: string;
  settingDensity: number;         // 设定投放密度（P001/P008诊断用）
  showVsTellRatio: number;        // 展示/告知比例（P004/P008诊断用）
  expositionCount: number;        // 说明性段落数（P004诊断用）
  dailyDetailCount: number;       // 日常细节数（P001诊断用）
  naturalLawMentioned: boolean;   // 是否提到自然法则（世界观基础）
}

// PlotProjection — 剧情/节奏相关特征
interface PlotProjection {
  novelId: string;
  updatedAt: string;
  pacingScore: number;            // 0-100，节奏得分（P006诊断用）
  hookPresence: boolean;          // 是否有钩子（开篇诊断用）
  conflictDensity: number;        // 冲突密度（P006诊断用）
  foreshadowingCount: number;     // 伏笔数量
  perspectiveSwitches: number;    // 视角切换次数（P005诊断用）
  emotionalLabelCount: number;    // 情绪标签次数（P003诊断用）
}
```

**未来扩展**：新增 Projection 类型时，不需要修改现有表结构，直接新增一张 `xxx_projections` 表即可。

### 2.2 Evidence 是什么

**定义**：Evidence 是支持诊断结论的**原始文本片段**。Diagnosis Agent 读取 Projection 做判断，但 Projection 只给数值，不给"为什么是这个数值"。Evidence 补充了"病历"——让诊断有据可查。

**设计原则**：
1. **按需关联**：每个 Projection 字段可以关联 0-N 条 Evidence
2. **片段化**：Evidence 不是完整章节，而是具体段落（通常 < 500 字）
3. **可追溯**：Evidence 记录来源章节、位置、抽取时间
4. **可展示**：前端诊断面板可以展示 Evidence，让用户看到"问题在哪里"

**数据结构**：

```typescript
interface Evidence {
  id: string;
  novelId: string;
  chapterId: string;        // 来源章节
  projectionType: string;   // 'character' | 'world' | 'plot'
  fieldName: string;        // 关联的 Projection 字段，如 'initiativeScore'
  content: string;          // 原始文本片段（< 500 字）
  context: string;          // 上下文说明（AI 生成的简短注释）
  extractedAt: string;
}
```

**使用场景**：
- Diagnosis Agent 判断 P002（角色工具人化）时，读取 `CharacterProjection.initiativeScore` + 关联的 Evidence
- 输出诊断结果时，附带 Evidence："你的主角在以下场景中缺乏主动选择：[片段1] [片段2]"
- 用户质疑诊断时，展示 Evidence 作为依据

### 2.3 AuthorProfile 如何从诊断结果更新

**定义**：AuthorProfile 是作者能力的长期追踪档案。它不是实时计算的，而是在**每次诊断完成后增量更新**的。

**更新触发时机**：

```
Diagnosis Agent 完成诊断
  ↓
生成 DiagnosisResult（含 disease, confidence, evidence）
  ↓
触发 AuthorProfile Update
  ↓
读取当前 AuthorProfile
  ↓
根据诊断结果更新对应能力分数
  ↓
记录诊断历史
  ↓
保存更新后的 AuthorProfile
```

**能力映射规则**：

| 症候 | 影响的能力 | 更新逻辑 |
|------|-----------|---------|
| P001 世界观膨胀 | 结构控制 (ABL-001) | 根据严重度调整分数 |
| P002 角色工具人化 | 角色塑造 (ABL-003) | 根据严重度调整分数 |
| P003 情绪标签化 | 表达能力 (ABL-007) | 根据严重度调整分数 |
| P004 信息硬塞 | 场景构建 (ABL-002) + 结构控制 (ABL-001) | 多能力联动调整 |
| P005 视角漂移 | 视角控制 (ABL-006) | 根据严重度调整分数 |
| P006 节奏停滞 | 结构控制 (ABL-001) + 场景构建 (ABL-002) | 多能力联动调整 |
| P007 阅读结构单一 | 阅读素养 (ABL-008) | 根据严重度调整分数 |
| P008 世界观说明书 | 结构控制 (ABL-001) + 世界观工程 (ABL-005) | 多能力联动调整 |
| P009 角色动机缺失 | 角色塑造 (ABL-003) + 角色逻辑链 (ABL-004) | 多能力联动调整 |
| P010 OC 平面化 | 角色塑造 (ABL-003) | 根据严重度调整分数 |

**分数更新算法**：

```
新分数 = 旧分数 × (1 - α) + 本次诊断分数 × α

其中：
- α = 学习率（默认 0.3，表示新诊断占 30% 权重）
- 本次诊断分数 = 100 - 严重度映射值（L1→15, L2→45, L3→80）

示例：
- 旧分数 = 70
- 本次诊断 P002 = L2（映射 45）
- 新分数 = 70 × 0.7 + (100-45) × 0.3 = 49 + 16.5 = 65.5
```

**诊断历史记录**：

```typescript
interface DiagnosisHistoryEntry {
  diagnosisId: string;
  timestamp: string;
  novelId: string;
  chapterIds: string[];
  syndromes: Array<{
    syndromeId: string;
    severity: 'L1' | 'L2' | 'L3';
    confidence: number;
  }>;
  affectedAbilities: string[];
  scoreChanges: Record<string, number>; // abilityId -> delta
}
```

**训练历史关联**：

```typescript
interface TrainingHistoryEntry {
  trainingId: string;
  timestamp: string;
  taskId: string;
  syndromeId: string;
  status: 'assigned' | 'completed' | 'skipped';
  effectiveness: number; // 训练效果评估（完成后由 AI 评分）
  relatedAbility: string; // 关联的能力 ID
}
```

**AuthorProfile 完整结构**：

```typescript
interface AuthorProfile {
  authorId: string;
  
  // 能力评分（8 项能力）
  abilities: Record<string, AbilityScore>; // key: abilityId
  
  // 弱点标签（当前活跃的症候）
  weakPoints: WeakPoint[];
  
  // 能力变化曲线（用于趋势分析）
  abilityHistory: Array<{
    timestamp: string;
    scores: Record<string, number>;
  }>;
  
  // 诊断历史
  diagnosisHistory: DiagnosisHistoryEntry[];
  
  // 训练历史
  trainingHistory: TrainingHistoryEntry[];
  
  // 统计
  totalNovels: number;
  totalChapters: number;
  totalDiagnoses: number;
  totalTrainingsCompleted: number;
  
  // 元数据
  createdAt: string;
  updatedAt: string;
}
```

---

## 三、数据模型

### 3.1 表结构

```sql
-- Layer 1: Raw Novel
CREATE TABLE novels (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  title TEXT,
  genre TEXT,              -- 题材类型
  word_count INTEGER,
  chapter_count INTEGER,
  status TEXT CHECK(status IN ('draft', 'completed', 'ongoing')),
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE chapters (
  id TEXT PRIMARY KEY,
  novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
  chapter_index INTEGER NOT NULL,
  title TEXT,
  content TEXT,            -- 原始文本（短篇存全文，长篇存摘要+文件路径）
  content_hash TEXT,       -- 用于去重
  word_count INTEGER,
  storage_mode TEXT CHECK(storage_mode IN ('full', 'chunks', 'summary')),
  file_path TEXT,          -- 长文本时的文件系统路径
  is_processed INTEGER DEFAULT 0 CHECK(is_processed IN (0, 1)),
  created_at TEXT NOT NULL,
  UNIQUE(novel_id, chapter_index)
);

-- Layer 2: Projections（拆表，每张 Projection 类型独立）
CREATE TABLE character_projections (
  id TEXT PRIMARY KEY,
  novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
  data TEXT NOT NULL,      -- JSON: CharacterProjection
  version INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE world_projections (
  id TEXT PRIMARY KEY,
  novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
  data TEXT NOT NULL,      -- JSON: WorldProjection
  version INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE plot_projections (
  id TEXT PRIMARY KEY,
  novel_id TEXT NOT NULL REFERENCES novels(id) ON DELETE CASCADE,
  data TEXT NOT NULL,      -- JSON: PlotProjection
  version INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

-- Layer 2: Evidence
CREATE TABLE evidence (
  id TEXT PRIMARY KEY,
  novel_id TEXT NOT NULL,
  chapter_id TEXT NOT NULL,
  projection_type TEXT NOT NULL CHECK(projection_type IN ('character', 'world', 'plot')),
  field_name TEXT NOT NULL,
  content TEXT NOT NULL,   -- 原始文本片段
  context TEXT,            -- AI 注释
  created_at TEXT NOT NULL
);

-- Layer 2: Profile Changes（增量变更记录，NovelHistory 雏形）
CREATE TABLE profile_changes (
  id TEXT PRIMARY KEY,
  novel_id TEXT NOT NULL,
  change_type TEXT NOT NULL,    -- 'character_add' | 'character_change' | 'world_expand' | 'plot_shift'
  target TEXT NOT NULL,         -- 变更对象，如角色名/设定名
  before_value TEXT,            -- 变更前
  after_value TEXT,             -- 变更后
  chapter_id TEXT,              -- 触发变更的章节
  created_at TEXT NOT NULL
);

-- Layer 3: AuthorProfile（核心资产）
CREATE TABLE author_profiles (
  id TEXT PRIMARY KEY,
  author_id TEXT NOT NULL UNIQUE,  -- 与 user/session 关联
  abilities TEXT NOT NULL,         -- JSON: Record<string, AbilityScore>
  weak_points TEXT NOT NULL,       -- JSON: WeakPoint[]
  ability_history TEXT NOT NULL,   -- JSON: Array<{timestamp, scores}>
  diagnosis_history TEXT NOT NULL, -- JSON: DiagnosisHistoryEntry[]
  training_history TEXT NOT NULL,  -- JSON: TrainingHistoryEntry[]
  stats TEXT NOT NULL,             -- JSON: { totalNovels, totalChapters, ... }
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
```

### 3.2 索引

```sql
-- chapters 表索引
CREATE INDEX idx_chapters_novel ON chapters(novel_id, chapter_index);
CREATE INDEX idx_chapters_processed ON chapters(novel_id, is_processed);

-- evidence 表索引
CREATE INDEX idx_evidence_novel ON evidence(novel_id, projection_type);
CREATE INDEX idx_evidence_field ON evidence(novel_id, projection_type, field_name);

-- profile_changes 表索引
CREATE INDEX idx_changes_novel ON profile_changes(novel_id, created_at);
```

---

## 四、Agent 流水线

```
用户上传章节
  ↓
[同步] 存入 chapters 表
  ↓
[异步] Extractor Task 入队
  ↓
Reader Agent（阅读）
  ├─ 输入：章节原始文本
  ├─ 职责：理解内容，不做判断
  └─ 输出：结构化的章节摘要（人物出场、事件、设定提及）
  ↓
Extractor Agents（并行）
  ├─ Character Extractor → 生成/更新 character_projections
  ├─ World Extractor → 生成/更新 world_projections
  └─ Plot Extractor → 生成/更新 plot_projections
  ↓
Evidence Collector（证据收集）
  ├─ 为每个 Projection 字段关联 Evidence 片段
  └─ 存入 evidence 表
  ↓
Profile Change Detector（变更检测）
  ├─ 对比新旧 Projection，检测变化
  └─ 生成 profile_changes 记录
  ↓
Diagnosis Agent（诊断）
  ├─ 输入：最新 Projections + 关联 Evidence
  ├─ 职责：识别症候，不做教学
  └─ 输出：DiagnosisResult（含 disease, confidence, evidence_ids）
  ↓
AuthorProfile Updater（能力档案更新）
  ├─ 输入：DiagnosisResult
  ├─ 职责：更新能力评分、记录诊断历史
  └─ 输出：更新后的 AuthorProfile
  ↓
Training Agent（训练设计）
  ├─ 输入：DiagnosisResult + AuthorProfile
  ├─ 职责：设计训练任务
  └─ 输出：TrainingPlan
```

**教学隔离原则**：
- Reader Agent：只读小说，看不到诊断规则
- Extractor Agents：只负责抽取特征，看不到症候定义
- Diagnosis Agent：只看 Projection + Evidence，看不到原始文本全文
- Training Agent：只接收诊断码 + 能力档案，看不到小说内容
- 各 Agent 之间传递的是**结构数据**（几KB），不是原文（百万字）

---

## 五、增量更新机制

### 5.1 Projection 增量更新

**原则**：新章节上传后，只分析新章节，然后合并到现有 Projection，不重新分析全书。

```
现有 CharacterProjection
  ↓
新章节上传
  ↓
Character Extractor 分析新章节
  ↓
合并逻辑：
  - 新角色出场 → 新增角色条目
  - 现有角色出现 → 更新该角色的统计字段
  - 全局字段（protagonistPassiveRatio）→ 重新计算
  ↓
版本号 + 1
```

### 5.2 全量重建触发条件

以下情况触发全量重建（而非增量更新）：
- 用户明确请求"重新分析全书"
- Projection 数据结构升级（Schema 变更）
- 检测到数据不一致（校验失败）

---

## 六、事件驱动架构（简化版 V1）

V1 不使用持久化消息队列，使用**内存队列 + 定时轮询**：

```typescript
// 内存队列（进程级）
const extractorQueue: ExtractorTask[] = [];

// 定时轮询（每 5 秒）
setInterval(() => {
  const task = extractorQueue.shift();
  if (task) {
    processExtractorTask(task);
  }
}, 5000);

// 用户上传章节时入队
function onChapterUpload(chapter: Chapter) {
  extractorQueue.push({
    chapterId: chapter.id,
    novelId: chapter.novelId,
    priority: 'normal',
    enqueuedAt: new Date().toISOString(),
  });
}
```

**V2 升级路径**：替换为持久化队列（SQLite 表或 Redis）。

---

## 七、NovelProfile 边界原则

**NovelProfile 中不保存的内容**：
- ❌ 完整人物档案（背景故事、详细性格描述）
- ❌ 完整世界观设定（所有宗门、境界体系、地图）
- ❌ 完整剧情大纲（所有事件、转折、结局）
- ❌ 完整对话记录

**NovelProfile 中保存的内容**：
- ✅ 人物主动性评分（P002 诊断用）
- ✅ 设定投放密度（P001/P008 诊断用）
- ✅ 展示/告知比例（P004 诊断用）
- ✅ 节奏得分（P006 诊断用）
- ✅ 视角切换次数（P005 诊断用）

**完整结构化内容存储位置**：Novel Knowledge Base（独立模块，V2 实现）。

---

## 八、与现有系统的衔接

### 8.1 兼容现有诊断系统

当前 `diagnosis_results` 表保留，作为 Diagnosis Agent 的输出记录。新增 `diagnosis_results.evidence_ids` 字段，关联到 `evidence` 表。

### 8.2 兼容现有能力画像

`ability-profile.service.ts` 从"实时聚合 diagnosis_results"改为"读取 author_profiles 表"。V1 过渡期保留实时聚合作为 fallback。

### 8.3 兼容现有教学状态机

`TeachingState.activeProblems` 数据来源从 diagnosis_results 改为 `syndrome_instances`（已有）+ `AuthorProfile.weakPoints`（新增）。

---

## 九、DoD（定义完成标准）

1. 8 张新表（novels, chapters, character_projections, world_projections, plot_projections, evidence, profile_changes, author_profiles）创建成功
2. Projection 数据结构（CharacterProjection / WorldProjection / PlotProjection）TypeScript 接口定义完整
3. Evidence 数据结构定义完整，支持关联 Projection 字段
4. AuthorProfile 更新算法实现（含能力映射、分数更新、历史记录）
5. Extractor Agents 框架实现（Character / World / Plot 三个 Extractor）
6. 事件驱动队列（内存队列 + 定时轮询）实现
7. 增量更新逻辑实现（新增章节 → 更新 Projection，非全量重建）
8. `npm run typecheck` 和 `npm test` 全部通过

---

## 十、回退方案

删除 008 迁移文件，移除所有新增 Service，恢复 diagnosis.handler.ts 到直接从原文分析的模式。
