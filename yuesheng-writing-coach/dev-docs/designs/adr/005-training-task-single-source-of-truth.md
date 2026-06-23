# ADR-005: 训练任务单一真相源 + 蒸馏素材三层消费链

> **编号**: ADR-005
> **状态**: 提议（2026-06-23）
> **作者**: AI 架构师
> **关联**: Sprint 15 计划（Issue #23）/ D-033 / 修复设计文档

---

## 一、背景

Sprint 9~14 完成后（PR #19/#21/#22 merged），核心教学链路（诊断→教学→训练→能力）存在 3 个断裂点：

1. **能力图谱消费链断裂**：ability-atlas loader 实现了 10 个 API，但 5 个预期消费方只接入了 2 个
2. **461 条蒸馏素材无索引**：3 个 MD 文件散落，AI 无法检索
3. **训练任务三个断层**：T001-T020 / TRAIN-PXXX / CH-PXXX 三套并行无 ID 关联

D-033 Reflect 复盘登记 D-DEBT-13/14/15 三个新债务。

---

## 二、决策

### 2.1 训练任务单一真相源

**决议**: 选 `resources/02-prescription/training-library.json` 中的 **TRAIN-PXXX-XXX** 格式作为唯一主源。

**理由**:
- 信息最完整（techniques / exercises / classicalBasis / developmentStage / mode / tier 全部字段都有）
- 已是 P0 任务（29 条），可直接复用
- 与教学工坊（TrainingWorkshop）UI 直接对应

**对应动作**:
- T001-T020（`ability-atlas.json` 占位任务）→ 合并为 `related_abilities` 字段，删除独立 ID
- CH-PXXX-XXX（`challenge-templates.json`）→ 通过 `relatedChallengeIds` 字段引用，ID 不变
- 副本 `04-validation/mastery/challenge-templates.json` → **删除**（R-021 不留死代码）

### 2.2 ID 命名规范

| 层 | ID 格式 | 例子 | 说明 |
|:---|:--------|:-----|:-----|
| 能力图谱 | `ABL-XXX` | ABL-001 | 能力节点（8 个） |
| 教学原子 | `AB-XXX` | AB-003 | 教学原子（5 个） |
| 症候 | `P-XXX` | P001 | 写作症候（10 个） |
| 训练任务 | `TRAIN-PXXX-XXX` | TRAIN-P001-001 | **唯一训练任务 ID** |
| 蒸馏素材 | `DST-XXX-NNN` | DST-001-001 | 蒸馏素材（461 条） |
| 技法 | `TQ-XXX` | TQ-025 | 写作技法 |
| 经典原则 | `(slug)` | CHEKHOV_GUN | 文学原则 |

**T15-D 横切落地**：每个 Sprint 15 Task commit 末尾加 ID 规范检查（不强制重命名旧 ID）

### 2.3 三层消费链架构

```
[蒸馏素材层] 461 条素材
   ↓ 索引化（distillation-index.json + distillation.loader.ts）
[能力图谱层] ABL-XXX + AB-XXX + syndrome-action
   ↓ Loader（ability-atlas.loader.ts，已实现）
[训练任务层] TRAIN-PXXX（唯一主源）
   ↓ 双向 ID 映射（task-id-mapping.json）
[消费方] 诊断展示 / 教学状态机 / 训练推荐 / 能力画像
```

**消费方接入清单（5/5 目标）**:
1. ✅ training-recommendation.service.ts:146 — 症候→能力
2. ✅ prompt-loader.ts:331 — 症候→能力（已展示）
3. 🆕 ProgressWorkspace — 能力画像展示
4. 🆕 teaching-state.handler — 能力进度感知
5. 🆕 TrainingRecommendation — 完整"症候→能力→任务"链

### 2.4 素材标注流程

**决议**: LLM 预标 + 人工校核 10%

**流程**:
1. LLM 批量预标 461 条素材（结构化：id/tags/related_syndrome/related_ability/difficulty）
2. 写入 `distillation-index.json`
3. 抽样 10%（约 46 条）人工校核
4. 一致性检查：人工与 LLM 标注冲突时人工为准
5. 校核通过后入 `distillation.loader.ts`

**预估节省**: 6-8h 人工（vs 全人工标注 461 条）

---

## 三、数据流

### 3.1 诊断→能力→训练任务全链路

```
[用户提交章节]
  ↓ chapter-orchestrator
[AI 诊断]
  ↓ diagnosis.handler → 症候列表 P-XXX
[能力图谱 loader] getAbilitiesBySyndrome(P-XXX) → ABL-XXX
  ↓
[ProgressWorkspace] 能力画像展示（雷达图/进度条）
  ↓
[teaching-state.handler] 注入能力进度 → 状态机决策
  ↓
[TrainingRecommendation] getTrainingTasksByAbility(ABL-XXX) → TRAIN-PXXX
  ↓
[distillation.loader] getBySyndrome(P-XXX) → DST-XXX-NNN（反馈素材）
  ↓
[AI 反馈] Prompt 注入素材 + 训练任务建议
```

### 3.2 task-id-mapping.json 双向映射

```json
{
  "TRAIN-P001-001": {
    "syndromeId": "P001",
    "syndromeName": "世界观膨胀",
    "title": "聚焦一个场景",
    "relatedChallengeIds": ["CH-P001-001", "CH-P001-002", "CH-P001-003"],
    "deprecatedAliases": []
  },
  "T001": {
    "mappedTo": "TRAIN-P003-001",
    "note": "T001 占位任务，实际属 P003 情绪标签化"
  }
}
```

---

## 四、边界

### 4.1 模块边界

| 模块 | 职责 | 不做 |
|:-----|:-----|:-----|
| distillation.loader.ts | 素材查询 API | 不做 AI 反馈生成 |
| ability-atlas.loader.ts | 能力图谱查询 | 不做训练推荐 |
| training-recommendation.service.ts | 训练推荐 | 不做能力画像 UI |
| ProgressWorkspace (UI) | 能力画像展示 | 不做诊断逻辑 |
| teaching-state.handler | 教学状态机 | 不做素材检索 |

### 4.2 数据边界

- **素材层**: 只读（distillation-index.json 不在运行时修改）
- **能力图谱层**: 只读（运行时通过 loader API 访问）
- **训练任务层**: 单一主源（training-library.json），其他两个 ID 体系通过 mapping 引用

### 4.3 依赖边界

- 能力图谱不依赖训练任务（独立可工作）
- 训练任务不依赖蒸馏素材（独立可工作）
- 蒸馏素材不依赖训练任务（独立可工作）
- **3 层之间通过 syndromeId (P-XXX) + abilityId (ABL-XXX) 两个共享键关联**

---

## 五、风险

| 风险 | 等级 | 缓解 |
|:-----|:-----|:-----|
| 461 条素材 LLM 标注质量 | 中 | 抽样 10% 人工校核 + 一致性检查 |
| 旧代码硬编码 T001/CH-PXXX | 中 | 全面 grep + 回归测试 + 兼容别名 |
| ProgressWorkspace UI 改动 | 中 | 软回退：先 IPC 暴露数据，UI 渐进接入 |
| 任务主源争议（C 派） | 低 | 文档明确 B 优势，用户已确认 |
| T15-D 横切遗漏 | 低 | 每个 Task commit 末尾自动检查 |

---

## 六、回退

- **T15-A (素材索引)**: 索引文件标记 `partial: true`，按批次提交，不阻塞
- **T15-B (任务断层)**: 保留副本 1 个版本（git tag `pre-T15-B-2026-06-23`）作为回退锚点
- **T15-C (消费链)**: 软回退 — 先在 IPC handler 暴露数据，UI 暂不消费
- **T15-D (ID 规范)**: 仅规范文档 + lint 警告，不强制修复旧 ID

---

## 七、依据

- **D-033**: Sprint 9~14 Reflect 复盘
- **D-DEBT-13/14/15**: 3 个新债务
- **dev-docs/designs/2026-06-23-diagnosis-library-remediation.md**: 完整修复方案
- **dev-docs/designs/sprint-15-plan.md**: Sprint 15 计划
- **Issue #23**: Sprint 15 GitHub Issue
- **ADR-003**: ai-readwrite-pipeline（truncation 复用）
- **ADR-004**: x02-writeback（AI 写回协议）
- **R-004** (DoD ≥ 3) / **R-010** (原子化) / **R-018** (变更溯源) / **R-021** (AI 边界) / **R-027** (四道门禁)

---

## 八、状态

🟡 提议（待 Sprint 15 Plan 阶段完成 → 接受）
