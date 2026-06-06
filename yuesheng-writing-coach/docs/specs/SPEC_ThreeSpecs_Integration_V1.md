# SPEC_ThreeSpecs_Integration_V1.md

> 版本：V1.0 | 创建：2026-06-02 | 核心原则：三个规范必须统一，否则 Agent 越多系统越乱
> 核心认知：Reader 读 Evidence → Diagnosis 判症候 → Training 练能力 → AuthorProfile 记成长

---

## 一、三个规范的定位

```
┌─────────────────────────────────────────────────────────────┐
│                    SPEC_Ability_Map_V1                       │
│                   （能力映射体系）                            │
│                                                             │
│  回答：训练什么？                                            │
│  输出：6 核心能力 → 19 子能力 → 训练任务映射                   │
│  稳定性：能力树 V1 冻结，病症可扩展                           │
└─────────────────────────────────────────────────────────────┘
                              ↑
                              │ 映射到
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                     SPEC_Evidence_V1                         │
│                     （证据体系）                              │
│                                                             │
│  回答：凭什么这么判？                                        │
│  输出：四级 Evidence（文本→模式→统计→对比）                    │
│  原则：没有 Evidence 的诊断就是玄学                           │
└─────────────────────────────────────────────────────────────┘
                              ↑
                              │ 支撑
                              ↓
┌─────────────────────────────────────────────────────────────┐
│                   SPEC_AuthorProfile_V1                      │
│                   （成长记录格式）                            │
│                                                             │
│  回答：作者成长了多少？                                       │
│  输出：三层档案（评分→轨迹→证据链）                           │
│  核心：用户看到的不是"45→72"，而是"过去的自己→现在的自己"      │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、跨规范数据流

### 2.1 完整数据流（从小说上传到成长记录）

```
用户上传小说章节
    ↓
[Reader Agent] 读取文本
    ↓
生成 Level 1 Evidence（文本证据）
    ├── EVD-000001: "他很愤怒。" → OBS-001
    ├── EVD-000002: "她十分悲伤。" → OBS-001
    └── EVD-000003: 世界观大段说明 → WORLD-002
    ↓
[Pattern Detector] 聚合
    ↓
生成 Level 2/3 Evidence
    ├── EVD-000101: 连续8次情绪标签（模式）→ P003
    └── EVD-000201: 情绪标签占比18%（统计）→ P003
    ↓
[Diagnosis Agent] 读取 Evidence
    ↓
查询 SPEC_Ability_Map：P003 → OBS-001 + EMO-001
    ↓
输出诊断：P003（L3），附带 evidence_ids: ["EVD-000001", "EVD-000101", "EVD-000201"]
    ↓
[Training Agent] 查询 SPEC_Ability_Map
    ↓
OBS-001 → T001 感官替换
EMO-001 → T005 情绪冰山
    ↓
分配训练任务 T001
    ↓
用户完成训练 → 提交作品
    ↓
[Evaluation Agent] 评估
    ↓
生成 Level 4 Evidence（对比）
    └── EVD-000301: 三个月前"他很愤怒" → 现在"指节收紧"
    ↓
[AuthorProfile Update]
    ├── Layer 1: OBS 分数 +5
    ├── Layer 2: 轨迹追加新数据点
    └── Layer 3: growthChain 追加 EVAL 事件，引用 EVD-000301
```

### 2.2 每个 Agent 的输入输出规范

| Agent | 输入（来自） | 输出（去往） | 依据的规范 |
|-------|-------------|-------------|-----------|
| Reader Agent | 用户小说文本 | Level 1 Evidence | SPEC_Evidence（Level 1 格式） |
| Pattern Detector | Level 1 Evidence | Level 2/3 Evidence | SPEC_Evidence（Level 2/3 格式） |
| Diagnosis Agent | Evidence 集合 | DiagnosisResult | SPEC_Evidence（证据链）+ SPEC_Ability_Map（病症映射） |
| Training Agent | DiagnosisResult | TrainingTask | SPEC_Ability_Map（子能力→训练任务） |
| Evaluation Agent | 用户训练成果 | EvaluationResult + Level 4 Evidence | SPEC_Evidence（Level 4 格式） |
| Profile Service | Diagnosis/Training/Evaluation | AuthorProfileV2 | SPEC_AuthorProfile（三层结构） |

---

## 三、跨规范引用规则

### 3.1 引用链（必须可追溯）

```
AuthorProfileV2.growthChains[].timeline[].evidence_ids
    ↓ 引用
Evidence.evidence_id
    ↓ 包含
Evidence.related_disease → P003
    ↓ 映射到（通过 Ability Map）
Syndrome(P003) → Ability(OBS-001 + EMO-001)
    ↓ 训练（通过 Ability Map）
Ability(OBS-001) → TrainingTask(T001)
```

**规则**：任何一层断裂，整个追溯链失效。

### 3.2 ID 命名规范（跨规范统一）

| 实体 | ID 格式 | 示例 | 定义规范 |
|------|---------|------|---------|
| 核心能力 | [A-Z]{3} | OBS, CHAR | SPEC_Ability_Map |
| 子能力 | [A-Z]{3}-[0-9]{3} | OBS-001 | SPEC_Ability_Map |
| 症候 | P[0-9]{3} | P003 | SPEC_Ability_Map |
| 训练任务 | T[0-9]{3} | T001 | SPEC_Ability_Map |
| Evidence | EVD-[0-9]{6} | EVD-000001 | SPEC_Evidence |
| 诊断 | DIAG-[0-9]{6} | DIAG-000001 | SPEC_AuthorProfile |
| 训练事件 | TRAIN-[0-9]{6} | TRAIN-000001 | SPEC_AuthorProfile |
| 评估事件 | EVAL-[0-9]{6} | EVAL-000001 | SPEC_AuthorProfile |
| 快照 | S-[0-9]{6} | S-000001 | SPEC_Evidence |
| 成长链 | CHAIN-[0-9]{6} | CHAIN-000001 | SPEC_AuthorProfile |

> **编号位数说明**：核心能力、子能力、症候、训练任务使用 3 位编号（数量有限，不会超过 999）。Evidence、诊断、训练事件、评估事件、快照、成长链使用 6 位编号（长期累积可能超过 999）。

---

## 四、数据一致性约束

### 4.1 跨表外键约束

```sql
-- Evidence 必须关联到有效的症候和能力
CHECK (related_disease IN ('P001', 'P002', ..., 'P010', ...))
CHECK (related_ability IN ('OBS-001', ..., 'STYLE-003'))

-- growth_chain_events 必须关联到有效的 Evidence
FOREIGN KEY (evidence_ids) REFERENCES evidence(evidence_id)

-- diagnosis_evidence 关联诊断和证据
FOREIGN KEY (diagnosis_id) REFERENCES diagnosis_results(id)
FOREIGN KEY (evidence_id) REFERENCES evidence(evidence_id)
```

### 4.2 应用层一致性检查

```typescript
// 诊断生成时检查
function validateDiagnosis(diagnosis: DiagnosisResult): boolean {
  // 1. 症候必须在 Ability Map 中有映射
  const abilityMapping = AbilityMap.getSyndromeMapping(diagnosis.syndromeId);
  if (!abilityMapping) throw new Error(`未知症候: ${diagnosis.syndromeId}`);
  
  // 2. 诊断必须有 Evidence 支撑
  if (!diagnosis.evidenceIds || diagnosis.evidenceIds.length === 0) {
    throw new Error('诊断必须附带 Evidence');
  }
  
  // 3. Evidence 必须存在且关联到同一症候
  for (const eid of diagnosis.evidenceIds) {
    const evidence = EvidenceStore.get(eid);
    if (evidence.relatedDisease !== diagnosis.syndromeId) {
      throw new Error(`Evidence ${eid} 与症候 ${diagnosis.syndromeId} 不匹配`);
    }
  }
  
  return true;
}
```

---

## 五、接口协作图

### 5.1 核心接口调用链

```
前端请求能力雷达图
    ↓
GET /api/author-profile/{authorId}/radar
    ↓
AuthorProfileService.getAbilityScores(authorId)
    ├── 读取 author_profiles.ability_scores
    └── 返回 Layer 1 数据
    ↓
前端渲染雷达图

用户点击"为什么 OBS 是 61？"
    ↓
GET /api/author-profile/{authorId}/growth-chain?ability=OBS
    ↓
AuthorProfileService.getGrowthChain(authorId, 'OBS')
    ├── 读取 growth_chain_events
    └── 返回 Layer 3 数据
    ↓
前端请求 Evidence 详情
    ↓
GET /api/evidence?ids=EVD-000001,EVD-000101,EVD-000201
    ↓
EvidenceService.getEvidenceByIds(['EVD-000001', 'EVD-000101', 'EVD-000201'])
    ├── 读取 evidence 表
    └── 返回四级 Evidence 完整数据
    ↓
前端渲染成长时间轴（带证据详情）
```

### 5.2 写入接口调用链

```
Diagnosis Agent 完成诊断
    ↓
POST /api/diagnosis
    ├── 写入 diagnosis_results
    ├── 写入 diagnosis_evidence（关联 Evidence）
    └── 触发 AuthorProfile Update
        ↓
        AuthorProfileV2Service.updateAfterDiagnosis(authorId, diagnosis, evidenceIds)
        ├── 更新 author_profiles.ability_scores
        ├── 追加 author_profiles.ability_trajectories
        ├── 写入 growth_chain_events（DIAG 事件）
        └── 更新 author_profiles.growth_chains
```

---

## 六、DoD

1. 三个规范的数据流完整，每个 Agent 的输入输出有据可依
2. 跨规范 ID 命名统一，无冲突
3. 数据一致性约束文档化（外键 + 应用层检查）
4. 核心接口调用链文档化（读取 + 写入）
5. 引用链可追溯，从 AuthorProfile → Evidence → Syndrome → Ability → TrainingTask

---

## 七、变更溯源

| 日期 | 版本 | 变更内容 |
|------|------|---------|
| 2026-06-02 | V1.0 | 初始创建。定义三个规范的交叉引用和协作关系。 |
