# Sprint 15+ 诊断库漏洞修复设计 — 能力图谱 + 素材索引 + 训练任务断层消除

> **创建日期**: 2026-06-23
> **状态**: Plan 阶段，待用户审阅
> **关联**: future-direction-distillation-capability-graph-assessment.md §6 + Yang 私聊（蒸馏聚类思路）
> **目标**: 消除 3 个"世纪漏洞"，打通能力图谱 → 训练任务的完整消费链

---

## 一、目标

| 漏洞 | 当前 | 目标 |
|:-----|:-----|:-----|
| 漏洞 1：能力图谱消费链断裂 | Loader 已实现，但消费方覆盖不全 | 教学状态机、诊断结果、训练推荐全链路消费 |
| 漏洞 2：461 条蒸馏素材无索引 | 3 个 MD 文件散落，无 TS loader | 结构化索引 + TS loader + 素材→能力/症候映射 |
| 漏洞 3：训练任务三个断层 | T001-T020 / TRAIN-PXXX / CH-PXXX 三套并行无 ID 关联 | 单一真相源 + ID 双向映射 |

---

## 二、现状盘点（数据基线）

### 2.1 能力图谱基础设施（[已落地但未完整接入]）

| 资产 | 路径 | 状态 |
|:-----|:-----|:-----|
| 能力图谱 JSON | `resources/knowledge-graph/ability-atlas.json` | ✅ 8 能力 + 10 症候 + 20 任务 |
| 能力节点原型 | `resources/02-prescription/ability-nodes/ability-node-prototypes.json` | ✅ 5 原子节点（AB-001~005） |
| 症候-动作映射 | `resources/01-diagnosis/syndromes/syndrome-action-map.json` | ✅ 10 症候 |
| 症候-经典映射 | `resources/01-diagnosis/syndromes/syndrome-classical-map.json` | ✅ 9 条 |
| **能力图谱 Loader** | `src/main/domains/02-prescription/ability-atlas/ability-atlas.loader.ts` | ✅ 10 个公开 API |
| **Loader 单测** | `__tests__/ability-atlas.loader.test.ts` | ✅ |
| **消费方 1** | `training-recommendation.service.ts:146` | ✅ 已调用 getAbilitiesBySyndrome |
| **消费方 2** | `prompt-loader.ts:331` | ✅ 已调用 getAbilitiesBySyndrome（症候展示） |
| 消费方 3：诊断结果展示 | `diagnosis` → ProgressWorkspace | ❌ 缺能力画像数据 |
| 消费方 4：教学状态机 | `teaching-state.handler` | ❌ 缺能力进度感知 |
| 消费方 5：训练推荐 | `TrainingRecommendation` → ability | ⚠️ 部分（仅症候→能力，无任务→能力） |

### 2.2 训练任务三套体系（[断层]）

| 体系 | 文件 | 条数 | ID 格式 | 详情 |
|:-----|:-----|:----:|:--------|:-----|
| 体系 A：能力图谱任务 | `resources/knowledge-graph/ability-atlas.json` | 20 | T001-T020 | 仅 ID + syndrome + difficulty |
| 体系 B：教学工坊 | `resources/02-prescription/training-library.json` | 29 | TRAIN-P001-001 ~ | 含 techniques/exercises/classicalBasis |
| 体系 C：挑战模板 | `resources/config/challenge-templates.json` | 31 | CH-P001-001 ~ | 含 challenge + mode + tier |
| 副本：体系 C | `resources/04-validation/mastery/challenge-templates.json` | 31 | 同上 | 双副本（与 config/ 重复） |

**断层证据**：同样针对 P001（世界观膨胀）症状：
- A 体系：T001（情绪描写）实际关联 ABL-007 表达能力 → 与 P001 关联弱
- B 体系：TRAIN-P001-001（聚焦一个场景）→ 关联 CHEKHOV_GUN
- C 体系：CH-P001-001（挑出具体场景）→ 实际语义与 B 体系高度重叠但无 ID 关联

### 2.3 蒸馏素材（[无索引]）

| 批次 | 文件 | 条数 |
|:-----|:-----|:-----|
| 1 | `resources/distillation-versions/v3.1+/写作蒸馏素材-200条-避雷与教学指导.md` | 200 |
| 2 | `写作蒸馏素材-扩展第2批-实战困境与习惯养成200条.md` | 200 |
| 3 | `写作蒸馏素材-扩展第3批-情节场景对话补充61条.md` | 61 |
| **合计** | | **461** |

**索引现状**：
- 仅有 MD 文件，无 TS loader
- 缺失：素材→能力节点映射、素材→症候映射、素材→训练任务映射
- 关联文件：`素材症候标签索引-D03.md` 有人工标签但未结构化

### 2.4 现有诊断 Prompt 资产（参考）

- `resources/01-diagnosis/diagnosis-agent-prompt-v2.md` — V2 诊断提示词
- `resources/prompts/teaching-agent-prompt-v2.md` — V2 教学提示词
- `resources/prompts/yuesheng-prompt-v3.md` — V4 Skill 工程化
- `resources/01-diagnosis/syndromes/syndrome-manual.md` — 症候详细手册

---

## 三、漏洞分类与根因

### 漏洞 1：能力图谱消费链断裂

**根因**：ability-atlas loader 实现完整（10 个 API），但 5 个预期消费方只接入了 2 个（且为部分调用）。具体表现：
- 教学状态机无法根据"当前能力短板"选择训练策略
- 诊断结果展示缺能力画像（只有症候列表）
- 训练推荐链路"症候→能力→任务" 中断在"症候→能力"（任务推荐仍走 templates）

**修复策略**：
- 在 ProgressWorkspace 注入 `getSyndromeDetail` 调用，展示能力画像
- 在 teaching-state.handler 注入 `getPrerequisites` 调用，构建能力依赖图
- 在 TrainingRecommendation 注入 `getTrainingTasksByAbility` 调用，补全"能力→任务"链

### 漏洞 2：461 条蒸馏素材无索引

**根因**：素材以 MD 形式散落，未被代码消费。导致：
- 训练任务"凭感觉设计"，不基于素材
- 诊断信号权重依赖人工调优
- 新批次素材无法被工程化纳入

**修复策略**（参照 Yang 私聊蒸馏思路）：
- 建立 `distillation-index.json`：每条素材含 {id, tags, related_syndrome, related_ability, difficulty}
- 编写 `distillation.loader.ts`：结构化查询 + 与 ability-atlas 联动
- 4 步蒸馏流程：素材结构化 → 能力标签 → 症候标签 → 训练任务衍生

### 漏洞 3：训练任务三个断层

**根因**：3 套体系在不同时间点由不同需求驱动产生：
- A（T001-T020）：能力图谱的"任务骨架"（仅占位）
- B（TRAIN-PXXX）：教学工坊的"完整教学单元"（含技法规格）
- C（CH-PXXX）：挑战式微练的"引导问题"（含 challenge 描述）

三套独立维护，无 ID 关联，导致：
- 同一概念有 3 个 ID（如 P001 训练在 A/B/C 中各有 ID）
- 学员看到一个训练，但诊断端、教学端、训练推荐端用的不是同一个 ID
- 训练内容"漂移"：更新一处无法同步到另两处

**修复策略**：单一真相源 + 双向 ID 映射
- 选择 B（TRAIN-PXXX）作为唯一主源（含最完整教学信息）
- 建立 `TRAIN-PXXX ↔ T0XX ↔ CH-PXXX` 双向映射表
- 标注 A（仅 20 条占位）合并入 B 的 related_abilities
- 副本（`04-validation/mastery/challenge-templates.json`）标记 DEPRECATED，删除

---

## 四、修复方案

### 4.1 架构：三层消费链

```
[蒸馏素材层] 461 条素材
   ↓ 索引化（distillation-index.json）
[能力图谱层] ABL-XXX + AB-XXX + syndrome-action
   ↓ Loader（ability-atlas.loader）
[训练任务层] TRAIN-PXXX（唯一主源）
   ↓ 双向 ID 映射
[消费方] 诊断展示 / 教学状态机 / 训练推荐 / 能力画像
```

### 4.2 ID 命名规范（统一）

| 层 | ID 格式 | 例子 | 说明 |
|:---|:--------|:-----|:-----|
| 能力图谱 | `ABL-XXX` | ABL-001 | 能力图谱节点（8 个） |
| 教学原子 | `AB-XXX` | AB-003 | 教学原子节点（5 个） |
| 症候 | `P-XXX` | P001 | 写作症候（10 个） |
| 训练任务 | `TRAIN-PXXX-XXX` | TRAIN-P001-001 | **唯一训练任务 ID** |
| 蒸馏素材 | `DST-XXX-NNN` | DST-001-001 | 蒸馏素材（461 条 → 索引化） |
| 技法 | `TQ-XXX` | TQ-025 | 写作技法 |
| 经典原则 | `CHEKHOV_GUN` | (slug) | 经典文学原则 |

### 4.3 实施步骤

#### 阶段 0：数据基线（无代码改动，仅设计）
- 现状盘点（已完成，§二）
- ID 命名规范（§4.2）
- 漏洞根因分析（§三）

#### 阶段 1：素材索引化（Sprint 15 task 1）
- 人工标注 461 条素材 → `distillation-index.json`
- 编写 `distillation.loader.ts`
- 单元测试 + Loader 单测

#### 阶段 2：训练任务断层消除（Sprint 15 task 2）
- 建立 `TRAIN-PXXX ↔ T0XX ↔ CH-PXXX` 双向映射表（`task-id-mapping.json`）
- 删除副本 `04-validation/mastery/challenge-templates.json`
- 更新 training-recommendation.service.ts：消费 task-id-mapping
- 更新所有引用 T001/CH-PXXX 的代码

#### 阶段 3：能力图谱消费链补全（Sprint 15 task 3）
- ProgressWorkspace 集成 `getSyndromeDetail`
- teaching-state.handler 集成 `getPrerequisites`
- TrainingRecommendation 补全 `getTrainingTasksByAbility` 调用
- E2E 测试验证"诊断→能力→任务"全链路

---

## 五、任务拆分（按 R-010 原子化）

> **说明**：每个 Task 独立可发布，DoD 至少 3 条可验证标准。复用 R-013 测试覆盖率要求。

### T15-A：蒸馏素材索引化（漏洞 2）

| 字段 | 内容 |
|:-----|:-----|
| **DoD** | 1. `distillation-index.json` 含 461 条素材结构化条目<br>2. `distillation.loader.ts` 提供至少 5 个查询 API<br>3. 单测覆盖率 ≥ 80%<br>4. 索引条目含 related_syndrome + related_ability 双向关联 |
| **范围** | 1 个新文件（index）+ 1 个新文件（loader）+ 1 个新文件（test）<br>人工标注可拆为 T15-A1（批次 1）/ T15-A2（批次 2）/ T15-A3（批次 3） |
| **风险** | 人工标注成本高（约 6-8 小时） |
| **回退** | 索引文件可标注 partial（按批次提交） |

### T15-B：训练任务断层消除（漏洞 3）

| 字段 | 内容 |
|:-----|:-----|
| **DoD** | 1. `task-id-mapping.json` 覆盖三套 ID 全部条目<br>2. training-recommendation.service.ts 改为消费 task-id-mapping<br>3. 副本 challenge-templates.json 删除<br>4. 回归测试覆盖三套 ID 互查 |
| **范围** | 1 个新映射文件 + 1 个 service 修改 + 1 个删除 + 1 个新测试 |
| **风险** | 旧代码可能硬编码 T001/CH-PXXX 引用，需全面 grep |
| **回退** | 保留副本 1 个版本（标注 DEPRECATED） |

### T15-C：能力图谱消费链补全（漏洞 1）

| 字段 | 内容 |
|:-----|:-----|
| **DoD** | 1. ProgressWorkspace 展示能力画像（来源 ability-atlas）<br>2. teaching-state.handler 感知能力依赖图<br>3. TrainingRecommendation 完整链路"症候→能力→任务"<br>4. E2E 测试覆盖 3 个消费方 |
| **范围** | 3 个文件修改 + 1 个新 E2E 测试 |
| **风险** | 修改 ProgressWorkspace 可能涉及 React 组件结构调整 |
| **回退** | 软回退：先在 IPC handler 暴露数据，UI 暂不消费 |

### T15-D：ID 命名规范落地

| 字段 | 内容 |
|:-----|:-----|
| **DoD** | 1. ID 命名规范文档（本文档 §4.2）<br>2. 各 JSON 文件 ID 字段一致性 grep 检查<br>3. 新增 ID 命名规范 lint 规则 |
| **范围** | 1 个新文件（规范）+ 1 个新 lint 规则 |
| **风险** | 现有 ID 命名混杂（ABL/AB/P/T0/TRAIN/CH/TQ/DST），完全清理需多 Sprint |
| **回退** | 软回退：仅规范文档 + lint 警告，不强制修复旧 ID |

---

## 六、依赖关系

```
T15-A 素材索引化（无依赖）
  ↓ 提供 DST-XXX 索引
T15-B 训练任务断层消除（依赖 T15-A 完成后 DST 索引）
  ↓ 提供 task-id-mapping
T15-C 能力图谱消费链补全（依赖 T15-B 提供的统一任务 ID）
  ↓
T15-D ID 命名规范（横切，可与 T15-A/B/C 并行）
```

**建议执行顺序**：T15-A → T15-B → T15-C → T15-D 横切清理

**预估工作量**：
- T15-A：1-1.5 Sprint（人工标注占大头）
- T15-B：0.5-1 Sprint
- T15-C：1-1.5 Sprint
- T15-D：0.5 Sprint（横切）

**总预估**：3-4.5 Sprint

---

## 七、门禁（每 Sprint 必须通过）

```bash
npm run typecheck  # 零错误
npm run test       # 全绿（含新增单测 + E2E）
npm run lint       # 零 error
# 安全
grep -r "sk-[a-zA-Z0-9]{20,}" src/  # 无硬编码密钥
```

**附加门禁**（T15-B/T15-C）：
- grep 旧 ID（T001/CH-PXXX）使用情况，确保无遗漏引用
- IPC 契约更新走 R-018 变更溯源

---

## 八、DoD（整体验收）

- [ ] 461 条蒸馏素材全部结构化索引化
- [ ] 能力图谱 loader 消费方从 2/5 提升到 5/5
- [ ] 训练任务单一真相源（TRAIN-PXXX），三套断层消除
- [ ] ID 命名规范文档化 + lint 规则落地
- [ ] 诊断→能力→任务全链路 E2E 测试通过
- [ ] typecheck 0 / test 全部绿 / lint 0 errors / 安全 OK
- [ ] 决策日志 D-035 记录

---

## 九、风险登记

| 风险 | 等级 | 缓解 |
|:-----|:-----|:-----|
| 461 条素材人工标注主观性 | 中 | 多人盲标 + 一致性检查（Kappa ≥ 0.7） |
| 修改 ProgressWorkspace 影响 UI | 中 | 软回退：先 IPC 暴露数据，UI 渐进式接入 |
| 旧代码硬编码 T001/CH-PXXX 引用 | 中 | 全面 grep + 回归测试 |
| 任务主源选择争议（B vs C） | 低 | B 含最完整教学信息（techniques/classicalBasis），明确优势 |
| 4.5K tokens 模型上下文限制 | 低 | 索引结构化后，loader 按需返回，不一次性加载 |

---

## 十、依据

- **GStack Think 阶段产物**：本文档
- **现状盘点**：future-direction-distillation-capability-graph-assessment.md §6（断层 1+2+3 + 不足 1+2+3+4）
- **Yang 私聊洞察**：通过综合上个世纪老辈子的经验 + 蒸馏网文常见问题做聚类去重 + 综合几个大类常见问题作为问题指标（与素材索引化方向一致）
- **Issue**：待 Sprint 15 Think 阶段创建
- **R-010** 最小化范围：3 个任务独立可发布
- **R-013** 测试覆盖率：每 Task ≥ 80% 单测覆盖
- **R-018** 变更溯源：先 ADR-005（待创建）再编码
- **R-029** 安全隐私：素材中不含硬编码密钥
- **AGENTS.md 核心禁止事项**：R-021 私造业务语义（不在 dispatcher 中硬编码 ID 映射）

---

## 十一、待用户决策

1. **任务主源选择**：选 B（TRAIN-PXXX）还是 C（CH-PXXX）作为唯一主源？建议 B（信息最完整）
2. **素材标注方式**：人工标注 vs LLM 辅助标注？建议 LLM 预标 + 人工校核
3. **副本处理**：副本 `04-validation/mastery/challenge-templates.json` 是删除还是保留 DEPRECATED 标记？建议删除
4. **T15-D 时机**：与 T15-A/B/C 一起做还是单独 Sprint？建议作为每个 Task 的横切项

---

## 十二、后续（不属本文档范围）

- ADR-005：训练任务单一真相源（待创建）
- Sprint 15 Think 阶段：建 GitHub Issue（网络恢复后）
- Sprint 15 Plan 阶段：基于本设计细化任务 DoD
- 评估是否启动"方向 C：UI 全面改版"（依赖本文档 T15-C 完成后）
