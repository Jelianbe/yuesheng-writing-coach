# SPEC_Evidence_V1.md

> 版本：V1.0 | 创建：2026-06-02 | 核心原则：没有 Evidence 的诊断就是玄学
> 核心认知：诊断只引用 Evidence，不直接引用小说。

---

## 一、设计原则

1. **诊断必须可审计**：每个诊断结论必须有 Evidence 支撑，能回答"为什么判这个病"。
2. **四级证据体系**：从单一文本到成长对比，形成完整的证据链。
3. **证据与病症分离**：Evidence 记录"观察到了什么"，Diagnosis 记录"判断是什么"。
4. **证据可展示**：用户质疑诊断时，系统能展示 Evidence，让用户自己看到问题。

---

## 二、四级 Evidence

### Level 1：文本证据（Text Evidence）

**定义**：从用户原始文本中抽取的具体段落，通常 < 500 字。

**用途**：证明"这里有问题"。

**示例**：
```json
{
  "evidenceId": "EVD-000001",
  "type": "text",
  "level": 1,
  "source": {
    "novelId": "novel-001",
    "chapterId": "ch-12",
    "paragraphIndex": 5
  },
  "content": "他很愤怒。",
  "context": "主角发现被背叛后的反应",
  "extractedBy": "OBS-001",
  "createdAt": "2026-06-02T10:00:00Z"
}
```

**特点**：
- 最基础的证据单位
- 直接从原文抽取
- 一个文本证据只支撑一个观察点

---

### Level 2：模式证据（Pattern Evidence）

**定义**：多个文本证据形成的模式，证明"这不是偶然，是习惯"。

**用途**：证明"这个问题是系统性的"。

**示例**：
```json
{
  "evidenceId": "EVD-000101",
  "type": "pattern",
  "level": 2,
  "source": {
    "novelId": "novel-001",
    "chapterRange": "ch-12 ~ ch-19"
  },
  "pattern": "连续8次出现情绪标签",
  "occurrences": [
    { "text": "他很愤怒。", "chapter": "ch-12" },
    { "text": "她十分悲伤。", "chapter": "ch-14" },
    { "text": "他异常开心。", "chapter": "ch-15" },
    { "text": "她非常害怕。", "chapter": "ch-17" }
  ],
  "relatedDisease": "P003",
  "relatedAbility": "OBS-001",
  "createdAt": "2026-06-02T10:00:00Z"
}
```

**特点**：
- 由多个 Level 1 证据聚合而成
- 证明问题的系统性，不是偶发
- 是诊断"高置信度"的关键支撑

---

### Level 3：统计证据（Statistical Evidence）

**定义**：量化指标，证明"这个问题有多严重"。

**用途**：提供客观数据支撑，避免主观判断。

**示例**：
```json
{
  "evidenceId": "EVD-000201",
  "type": "statistical",
  "level": 3,
  "source": {
    "novelId": "novel-001",
    "sampleRange": "ch-1 ~ ch-20"
  },
  "metric": "emotion_label_ratio",
  "value": 0.18,
  "unit": "percentage",
  "benchmark": {
    "industryAverage": 0.06,
    "recommendedMax": 0.10
  },
  "interpretation": "情绪标签句占比18%，超过行业平均3倍",
  "relatedDisease": "P003",
  "relatedAbility": "OBS-001",
  "createdAt": "2026-06-02T10:00:00Z"
}
```

**特点**：
- 可量化、可对比
- 有基准线（行业平均 / 推荐值）
- 是诊断"严重程度"的关键依据

**当前统计指标库**：

| 指标名 | 定义 | 行业基准 | 用于诊断 |
|--------|------|---------|---------|
| `emotion_label_ratio` | 情绪标签句占比 | 6% | P003 |
| `setting_density` | 设定投放密度（字/章） | < 500 | P001 |
| `show_vs_tell_ratio` | 展示/告知比例 | > 2:1 | P004 |
| `protagonist_passive_ratio` | 主角被动场景占比 | < 30% | P002 |
| `perspective_switch_count` | 视角切换次数/章 | < 1 | P005 |
| `pacing_variance` | 节奏变化方差 | > 0.3 | P006 |
| `exposition_paragraph_ratio` | 说明性段落占比 | < 15% | P008 |
| `character_action_without_motivation_ratio` | 无动机角色行为占比 | < 20% | P009 |
| `character_depth_score` | 角色维度评分（0-10） | > 3 | P010 |
| `reading_diversity_score` | 阅读体裁多样性 | > 3 体裁 | P007 |

> **P007 指标说明**：`reading_diversity_score` 无法从小说文本中自动提取，需要用户自报或通过训练交互推断。该指标仅作为辅助参考，不参与核心能力评分。

---

### Level 4：对比证据（Comparison Evidence）

**定义**：同一能力维度在不同时间点的作品样本对比。

**用途**：证明"你成长了"。这是最有价值的证据类型。

**示例**：
```json
{
  "evidenceId": "EVD-000301",
  "type": "comparison",
  "level": 4,
  "comparisonType": "temporal",
  "snapshots": [
    {
      "snapshotId": "S-000001",
      "date": "2026-06-01",
      "sample": {
        "chapter": "ch-12",
        "context": "主角发现背叛",
        "text": "他很愤怒。"
      },
      "relatedDiagnosis": "DIAG-000001"
    },
    {
      "snapshotId": "S-000008",
      "date": "2026-09-01",
      "sample": {
        "chapter": "ch-87",
        "context": "主角发现背叛",
        "text": "他的指节一点点收紧，掌心被指甲掐出白痕。"
      },
      "relatedDiagnosis": "DIAG-000003"
    }
  ],
  "relatedAbility": "OBS-001",
  "relatedDisease": "P003",
  "improvement": "从情绪标签 → 感官细节",
  "createdAt": "2026-09-01T10:00:00Z"
}
```

**特点**：
- 同一能力维度、相似场景、不同时间
- 展示"过去的自己 → 现在的自己"
- 是成长可视化的核心素材

---

## 三、Evidence 数据结构

```typescript
interface Evidence {
  evidenceId: string;           // EVD-XXX
  type: 'text' | 'pattern' | 'statistical' | 'comparison';
  level: 1 | 2 | 3 | 4;
  
  // 来源
  source: {
    novelId: string;
    chapterId?: string;
    chapterRange?: string;
    paragraphIndex?: number;
    sampleRange?: string;
  };
  
  // 内容（根据 type 不同，结构不同）
  content?: string;             // Level 1: 文本片段
  pattern?: PatternData;        // Level 2: 模式数据
  metric?: StatisticalData;     // Level 3: 统计数据
  snapshots?: SnapshotPair[];   // Level 4: 对比快照
  
  // 关联
  relatedDisease: string;       // 关联的症候
  relatedAbility: string;       // 关联的子能力
  relatedObservations?: string[]; // 关联的 OBS 事件
  
  // 元数据
  extractedBy: string;          // 哪个 Extractor 生成的
  createdAt: string;
}
```

---

## 四、Evidence 生成流程

```
Reader Agent 读取章节
  ↓
Extractor Agents 分析
  ├─ Character Extractor → 生成 Level 1 文本证据
  ├─ World Extractor → 生成 Level 1 文本证据
  └─ Plot Extractor → 生成 Level 1 文本证据
  ↓
Pattern Detector 聚合
  ├─ 检测重复模式 → 生成 Level 2 模式证据
  └─ 计算统计指标 → 生成 Level 3 统计证据
  ↓
Evidence Store 存储
  ↓
Diagnosis Agent 读取 Evidence → 生成诊断
  ↓
用户完成训练后 → 生成 Level 4 对比证据
```

---

## 五、Evidence 使用规则

### 诊断时使用

```
Diagnosis Agent 诊断 P003
  ↓
读取：
  - Level 1 文本证据（具体片段）
  - Level 2 模式证据（系统性证明）
  - Level 3 统计证据（严重程度）
  ↓
输出诊断结果，附带 evidenceIds
```

### 用户质疑时展示

```
用户：你凭什么说我 P003？
  ↓
月笙：
  诊断编号：DIAG-001
  基于证据：
    【文本证据】第12章："他很愤怒。"
    【文本证据】第14章："她十分悲伤。"
    【模式证据】连续8次出现情绪标签
    【统计证据】情绪标签占比18%，行业平均6%
```

### 成长可视化时展示

```
月笙展示 P003 改善轨迹：

2026.06  诊断
━━━━━━━━━━━━━━━━━━━━━━━━
"他很愤怒。"

2026.08  训练后
━━━━━━━━━━━━━━━━━━━━━━━━
"他的指节一点点收紧，掌心被指甲掐出白痕。"

2026.09  再次诊断
━━━━━━━━━━━━━━━━━━━━━━━━
"他望着空荡荡的房间，许久没有说话。"
```

---

## 六、DoD

1. 四级 Evidence 类型定义完整，各有明确的生成规则和使用场景
2. Evidence 数据结构（TypeScript 接口）定义完整
3. Evidence 生成流程文档化（从 Reader 到 Extractor 到 Pattern Detector）
4. Evidence 使用规则文档化（诊断/质疑/可视化三种场景）
5. 统计指标库定义完整（至少 6 个核心指标 + 基准线）
6. 数据库存储方案文档化（evidence 表 + diagnosis_evidence 关联表 + 索引）
7. 四级 Evidence 的 `content_json` 结构分别给出示例
8. 核心查询接口定义完整（按症候/按能力/证据链/对比生成）

---

## 七、数据库存储方案

### 7.1 Evidence 表

```sql
CREATE TABLE IF NOT EXISTS evidence (
    evidence_id TEXT PRIMARY KEY,           -- EVD-XXXXXX
    type TEXT NOT NULL CHECK(type IN ('text', 'pattern', 'statistical', 'comparison')),
    level INTEGER NOT NULL CHECK(level IN (1, 2, 3, 4)),
    
    -- 来源
    novel_id TEXT NOT NULL,                 -- 关联小说（应用层校验，V1 阶段 novels 表未创建前存为纯文本 ID）
    chapter_id TEXT,
    chapter_range TEXT,
    paragraph_index INTEGER,
    sample_range TEXT,
    
    -- 内容（JSON，根据 type 不同结构不同）
    content_json TEXT NOT NULL,
    
    -- 关联
    related_disease TEXT NOT NULL,          -- P001~P0XX
    related_ability TEXT NOT NULL,          -- OBS-001 等
    related_observations TEXT,              -- JSON 数组 [OBS-001, OBS-002]
    
    -- 元数据
    extracted_by TEXT NOT NULL,             -- Extractor 标识
    created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_evidence_disease ON evidence(related_disease);
CREATE INDEX IF NOT EXISTS idx_evidence_ability ON evidence(related_ability);
CREATE INDEX IF NOT EXISTS idx_evidence_novel ON evidence(novel_id);
CREATE INDEX IF NOT EXISTS idx_evidence_level ON evidence(level);
```

> **外键说明**：`novel_id` 的外键约束 `REFERENCES novels(id)` 需等 `novels` 表创建后添加。V1 阶段 `novel_id` 存为纯文本，由应用层保证一致性。

### 7.2 Evidence 与 Diagnosis 关联表

```sql
CREATE TABLE IF NOT EXISTS diagnosis_evidence (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    diagnosis_id TEXT NOT NULL,             -- DIAG-XXX
    evidence_id TEXT NOT NULL,              -- EVD-XXX
    relevance TEXT CHECK(relevance IN ('primary', 'supporting', 'contextual')),
    
    FOREIGN KEY (diagnosis_id) REFERENCES diagnosis_results(id) ON DELETE CASCADE,
    FOREIGN KEY (evidence_id) REFERENCES evidence(evidence_id) ON DELETE CASCADE,
    UNIQUE(diagnosis_id, evidence_id)
);

CREATE INDEX IF NOT EXISTS idx_de_diagnosis ON diagnosis_evidence(diagnosis_id);
CREATE INDEX IF NOT EXISTS idx_de_evidence ON diagnosis_evidence(evidence_id);
```

### 7.3 content_json 结构示例

**Level 1（文本证据）**：
```json
{
  "text": "他很愤怒。",
  "context": "主角发现被背叛后的反应",
  "characterCount": 5
}
```

**Level 2（模式证据）**：
```json
{
  "pattern": "连续8次出现情绪标签",
  "occurrence_count": 8,
  "occurrences": [
    {"text": "他很愤怒。", "chapter": "ch-12", "paragraph": 5},
    {"text": "她十分悲伤。", "chapter": "ch-14", "paragraph": 3}
  ],
  "frequency": "平均每章1.2次"
}
```

**Level 3（统计证据）**：
```json
{
  "metric": "emotion_label_ratio",
  "value": 0.18,
  "unit": "percentage",
  "sample_size": 45000,
  "benchmark": {
    "industry_average": 0.06,
    "recommended_max": 0.10,
    "percentile": 85
  },
  "interpretation": "情绪标签句占比18%，超过行业平均3倍"
}
```

**Level 4（对比证据）**：
```json
{
  "comparison_type": "temporal",
  "snapshots": [
    {
      "snapshot_id": "S-000001",
      "date": "2026-06-01",
      "novel_id": "novel-001",
      "chapter": "ch-12",
      "text": "他很愤怒。",
      "diagnosis_id": "DIAG-000001"
    },
    {
      "snapshot_id": "S-000008",
      "date": "2026-09-01",
      "novel_id": "novel-003",
      "chapter": "ch-87",
      "text": "他的指节缓缓收紧，掌心被指甲掐出白痕。",
      "diagnosis_id": "DIAG-000003"
    }
  ],
  "improvement_summary": "从情绪标签 → 感官细节"
}
```

---

## 八、查询接口

### 8.1 按症候查询 Evidence（诊断时使用）

```typescript
async function getEvidenceByDisease(
  diseaseId: string,
  novelId: string,
  options?: { minLevel?: number; maxLevel?: number }
): Promise<Evidence[]>;

// 使用示例
const evidence = await getEvidenceByDisease('P003', 'novel-001', { minLevel: 2 });
```

### 8.2 按能力查询 Evidence（成长可视化时使用）

```typescript
async function getEvidenceByAbility(
  abilityId: string,
  authorId: string,
  options?: { fromDate?: string; toDate?: string }
): Promise<Evidence[]>;

// 使用示例
const evidence = await getEvidenceByAbility('OBS-001', 'user-001', { 
  fromDate: '2026-06-01' 
});
// 返回该作者所有与 OBS-001 相关的 Evidence
```

### 8.3 获取诊断的证据链（用户质疑时使用）

```typescript
async function getEvidenceChainForDiagnosis(
  diagnosisId: string
): Promise<{
  diagnosis: DiagnosisResult;
  primaryEvidence: Evidence[];      // 主要证据
  supportingEvidence: Evidence[];   // 辅助证据
  statistics: StatisticalEvidence[]; // 统计数据
}>;

// 使用示例
const chain = await getEvidenceChainForDiagnosis('DIAG-000001');
// 返回完整证据链，用于回答"为什么判我P003"
```

### 8.4 生成对比 Evidence（训练完成后）

```typescript
async function createComparisonEvidence(
  abilityId: string,
  earlierSnapshotId: string,
  laterSnapshotId: string
): Promise<ComparisonEvidence>;

// 使用示例
const comparison = await createComparisonEvidence(
  'OBS-001',
  'S-000001',   // 三个月前的样本
  'S-000008'    // 现在的样本
);
// 返回 Level 4 对比证据，自动计算改善描述
```

---

## 九、与现有系统的衔接

| 现有组件 | 衔接方式 | 优先级 |
|---------|---------|--------|
| `evidence` 表 | 按本规范升级表结构，新增 `level`、`content_json` 字段 | P0 |
| `diagnosis_results` | 新增 `evidence_ids` 字段，关联到 Evidence | P0 |
| `diagnosis_evidence` | 新建关联表，支持多对多关系 | P0 |
| `observations`（OBS 事件） | Level 1 Evidence 的来源，Reader Agent 生成 | P1 |
| `snapshots`（SNAPSHOT 层） | Level 4 Evidence 的数据源，训练前后采样 | P1 |
| Extractor Agents | 新增 `extracted_by` 字段标识来源 | P1 |
