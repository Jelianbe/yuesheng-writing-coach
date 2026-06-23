# Sprint 15 Plan — 诊断库漏洞修复（3 个断层）

> **创建日期**: 2026-06-23
> **状态**: Think 阶段，待用户审阅
> **关联**: Issue #21（Sprint 15）/ D-033 Reflect / dev-docs/designs/2026-06-23-diagnosis-library-remediation.md
> **基础**: main @ 6fec03a（PR #19+#21+#22 已合并）

---

## 一、目标

消除 3 个"世纪漏洞"，打通能力图谱 → 训练任务的完整消费链：

| 漏洞 | 当前 | 目标 |
|:-----|:-----|:-----|
| 漏洞 1：能力图谱消费链断裂 | Loader 已实现，但消费方仅 2/5 接入 | 5/5 消费方全链路打通 |
| 漏洞 2：461 条蒸馏素材无索引 | 3 个 MD 文件散落，无 TS loader | 结构化索引 + TS loader + 素材→能力/症候映射 |
| 漏洞 3：训练任务三个断层 | T001-T020 / TRAIN-PXXX / CH-PXXX 三套并行无 ID 关联 | 单一真相源 + 双向 ID 映射 |

---

## 二、范围（任务拆分）

### T15-A：蒸馏素材索引化（漏洞 2）
**目标**: 把 3 个 MD 文件中的 461 条素材结构化，建立索引 + TS loader

**任务清单**:
- T15-A.1: 解析 `写作蒸馏素材-200条-避雷与教学指导.md`（200 条）
- T15-A.2: 解析 `写作蒸馏素材-扩展第2批-实战困境与习惯养成200条.md`（200 条）
- T15-A.3: 解析 `写作蒸馏素材-扩展第3批-情节场景对话补充61条.md`（61 条）
- T15-A.4: 生成 `distillation-index.json`（结构化索引：id / 主题 / 适用症候 / 适用能力 / 关键词）
- T15-A.5: 实现 `distillation.loader.ts`（查询 API：getBySyndrome / getByAbility / getByKeyword / search）
- T15-A.6: 单元测试覆盖（解析正确性、查询 API、空值保护）

**预估**: 4 个 commit / 8 文件 / +500 行

### T15-B：训练任务断层消除（漏洞 3）
**目标**: 选定单一真相源，建立 3 套 ID 体系的双向映射

**任务清单**:
- T15-B.1: 决策任务主源（**已选**: `training-library.json` 的 `TRAIN-PXXX-XXX`，29 条信息最完整）
- T15-B.2: 生成 `task-id-mapping.json`（T0XX ↔ TRAIN-PXXX ↔ CH-PXXX 双向映射）
- T15-B.3: 给 `training-library.json` 每条增加 `relatedChallengeIds: string[]` 字段（指向 CH-PXXX）
- T15-B.4: 给 `ability-atlas.json` 中 T001-T020 占位任务增加 `mappingToTrainingLibrary: string`（指向 TRAIN-PXXX）
- T15-B.5: 训练任务消费方改造（TrainingRecommendation 优先用 TRAIN-PXXX，去重后推荐）
- T15-B.6: 删除 `resources/04-validation/mastery/challenge-templates.json` 双副本
- T15-B.7: 单元测试覆盖（映射完整性、消费方去重逻辑）

**预估**: 5 个 commit / 6 文件 / +300 行

### T15-C：能力图谱消费链补全（漏洞 1）
**目标**: 5/5 消费方全链路接入

**任务清单**:
- T15-C.1: **消费方 1**（已就位）: training-recommendation.service.ts — 验证接入正常
- T15-C.2: **消费方 2**（已就位）: prompt-loader.ts — 验证症候展示正常
- T15-C.3: **消费方 3**（新）: ProgressWorkspace — 展示能力画像（雷达图/进度条）
- T15-C.4: **消费方 4**（新）: teaching-state.handler — 注入能力进度到教学状态机
- T15-C.5: **消费方 5**（增强）: TrainingRecommendation — 补全任务→能力的反向推荐
- T15-C.6: 端到端测试：诊断触发 → 教学状态机 → 训练推荐 → 能力画像 全链路

**预估**: 6 个 commit / 10 文件 / +800 行

### T15-D：ID 命名规范落地（跨任务约束）
**目标**: 统一 ID 命名规范，避免后续再出现断层

**任务清单**:
- T15-D.1: 写 `dev-docs/standards/2026-06-23-id-naming-spec.md`（ABL-XXX 能力 / AB-XXX 教学原子 / P-XXX 症候 / TRAIN-PXXX-XXX 任务 / CH-PXXX-XXX 挑战 / DS-XXX 蒸馏素材 / TPL-XXX 模板 / R-XXX 规则）
- T15-D.2: 现有 ID 审计：标记不合规的 ID（如 P-XXX 应统一为 PXXX 数字格式）
- T15-D.3: 改造不合规 ID（增量式，不一次性重命名）

**预估**: 2 个 commit / 2 文件 / +200 行

---

## 三、依赖关系

```
T15-D (ID 规范) ── 先行（不阻塞 T15-A/B/C，但给后续提供规范）
   │
   ├── T15-A (素材索引) ── 独立
   │      │
   │      └── T15-C.4 (教学状态机) 依赖 T15-A 的 loader
   │
   ├── T15-B (任务断层) ── 独立
   │      │
   │      └── T15-C.5 (训练推荐) 依赖 T15-B 的 mapping
   │
   └── T15-C (消费链) ── 依赖 T15-A + T15-B
```

**推荐执行顺序**: T15-D → T15-A → T15-B → T15-C

---

## 四、DoD（Definition of Done）

按 R-004，至少 3 条可验证标准：

1. **蒸馏素材 100% 索引化**: 461 条素材全部入库 `distillation-index.json`，loader 查询 API 100% 覆盖
2. **训练任务 ID 100% 关联**: T0XX / TRAIN-PXXX / CH-PXXX 三套体系 100% 建立双向映射，无孤立任务
3. **能力图谱 5/5 消费方接入**: ProgressWorkspace / teaching-state.handler / TrainingRecommendation / prompt-loader / training-recommendation.service 全部通过端到端测试
4. **门禁全绿**: typecheck 0 / test 全部通过（新测试覆盖 80%+ 新代码）/ lint 0 errors / 安全 0 硬编码
5. **设计文档同步**: 文档（standards/2026-06-23-id-naming-spec.md + 修复设计文档）随代码同步提交

---

## 五、风险与缓解

| 风险 | 影响 | 缓解 |
|:-----|:-----|:-----|
| 461 条素材解析质量 | 索引可能漏标 | 单元测试 100% 覆盖 + 抽样人工核对 10% |
| 三套任务 ID 关联冲突 | 推荐重复 | 去重逻辑 + 主源优先级 + 单元测试 |
| 能力图谱消费方改造范围大 | UI 改动多 | 拆分 commit（每个消费方一个 commit），分批 review |
| ID 重命名影响范围 | 可能破坏现有引用 | 增量式重命名 + 兼容别名（`P001` ≡ `P-001`） |
| 网络阻塞（GitHub push） | 提交延迟 | 多次重试 + 离线 commit，事后 push |

---

## 六、依据

- **D-033**: Sprint 9~14 Reflect 复盘（明确 3 个债务）
- **D-013~D-015**: 蒸馏能力图谱思路
- **D-DEBT-2026-06-23-13**: 能力图谱消费链断裂
- **D-DEBT-2026-06-23-14**: 461 条素材无索引
- **D-DEBT-2026-06-23-15**: 训练任务三套体系断层
- **dev-docs/designs/2026-06-23-diagnosis-library-remediation.md**: 完整修复方案
- **R-004** (DoD ≥ 3) / **R-018** (变更溯源) / **R-019** (代码规范) / **R-027** (四道门禁)

---

## 七、状态

🟡 Think 阶段（待用户确认进入 Plan）

### 关键决策（2026-06-23 用户确认）

| # | 决策点 | 决议 | 依据 |
|:-:|:------|:----|:-----|
| 1 | 任务主源 | **B (TRAIN-PXXX)** | 信息最完整（techniques/exercises/classicalBasis） |
| 2 | 素材标注 | **LLM 预标 + 人工校核 10%** | 节省 6-8h 人工，抽样保证质量 |
| 3 | 副本处理 | **删除** `04-validation/mastery/challenge-templates.json` | R-021 不留死代码 + R-006 git tag 备份 |
| 4 | T15-D 时机 | **横切**（每个 Task 末尾加 ID 规范检查） | 避免大爆炸重命名 |

### 下一步（待用户确认）
- Plan 阶段：架构师（AI）锁定架构、数据流、边界 → 创建 ADR-005（任务单一真相源）
- Build 阶段：T15-D → T15-A → T15-B → T15-C 顺序实施
- Review 阶段：4 道门禁
- Test 阶段：端到端 + 边界测试
- Ship 阶段：PR merge + Reflect
