# 2026-06-02 上午 session 完整总结

> 本文件用于防止讨论成果遗忘，记录所有已实施代码和待实现功能。

---

## 一、已完成代码实施（3项）

### 1. T-006：聚焦方向与过渡邀请机制 ✅

| 文件 | 改动 |
|------|------|
| `docs/specs/SPEC_focus-area-transition_V1.0.md` | 新增规格文档 |
| `docs/tasks/T-006-focus-area-transition.md` | 新增任务文档 |
| `src/renderer/shared/types.ts` | 新增 `FocusArea`/`FocusAreaValue` 类型；`TeachingState` 增加 `focusArea` + `transitionOffered` |
| `src/main/services/teaching-state.types.ts` | `TeachingStateRow` 增加 `focus_area` + `transition_offered` |
| `src/main/services/teaching-state-machine.ts` | 新增 `FOCUS_AREA_WORLD_SUBPHASES`、`TRANSITION_PROMPTS`、`shouldOfferTransition`、`buildFocusAreaPrompt`；`getNextSubphase` 支持 focusArea 过滤 |
| `src/main/services/teaching-state.store.ts` | `create()`/`update()`/`rowToState`/`stateToRow` 增加新字段 |
| `src/main/services/recommendation-engine.ts` | 新增 `FOCUS_AREA_SYNDROMES`、`sortByFocusArea` |
| `src/main/services/transition-prompt-loader.ts` | 新增话术加载器（支持模板变量、多版本轮询） |
| `resources/config/transition-prompts.json` | 新增外部话术配置 |
| `src/main/db/006_add_focus_area.sql` | 新增数据库迁移 |
| `src/main/index.ts` | 注册 006 迁移 |
| `src/preload/index.ts` | 白名单（已有通道，未新增） |
| `src/main/ipc/__tests__/merge-diagnosis.test.ts` | 更新 TeachingState 默认值 |

**核心机制**：
- 用户可选择 `worldbuilding` / `character` / `general` 聚焦方向
- `character` 模式 WORLD 阶段只走 `WORLD_PROTAGONIST` 子阶段
- 专精用户完成核心教学后，收到一次性过渡邀请反问
- 话术外置配置，支持模板变量和多版本轮询

---

### 2. T-005：能力画像系统 ✅

| 文件 | 改动 |
|------|------|
| `docs/specs/SPEC_ability-profile_V1.0.md` | 新增规格文档 |
| `docs/tasks/T-005-ability-profile.md` | 新增任务文档 |
| `src/main/db/007_user_training.sql` | 新增训练记录表迁移 |
| `src/renderer/shared/types.ts` | 新增 `AbilityProfile`/`AbilityScore`/`WeakPoint`/`TrainingStats`/`DiagnosisTrend`；新增 IPC channel `ability:getProfile` |
| `src/main/services/ability-profile.service.ts` | 新增核心聚合引擎（实时计算能力评分/弱点/趋势） |
| `src/main/services/training-record.service.ts` | 新增训练记录 CRUD |
| `src/main/ipc/ability-profile.handler.ts` | 新增 IPC handler |
| `src/preload/index.ts` | 白名单加入 `ability:getProfile` |
| `src/main/index.ts` | 注册 007 迁移 + 初始化服务 + 注册 handler |

**核心算法**：
- 能力评分：L1→85, L2→55, L3→20（非线性映射）
- 弱点判定：≥3次 或 (≥2次 且 最大严重度 ≥ L2)
- 趋势：最近5次 vs 之前5次平均严重度对比
- 实时聚合，不缓存

---

### 3. DeepSeek V4 配置更新 ✅

| 文件 | 改动 |
|------|------|
| `src/main/services/config.service.ts` | 默认模型 `deepseek-chat` → `deepseek-v4-pro` |
| `src/main/api-proxy.ts` | `max_tokens` 4096 → 8192 |
| `src/renderer/stores/config.store.ts` | 前端默认模型同步更新 |
| `src/renderer/stores/__tests__/config.store.test.ts` | 测试默认值同步更新 |

**关键参数更新**：
- 模型名：`deepseek-v4-pro` / `deepseek-v4-flash`
- 上下文：128K → **1M tokens**
- 旧模型 `deepseek-chat` 将于 2026-07-24 停用

---

## 二、讨论确定待实现功能

### 1. 诊断模块结构化重构（三层数据架构）

```
Layer 1: Raw Novel（原始小说）
  └── novels 表 + chapters 表

Layer 2: NovelProfile + NovelHistory（小说数字孪生）
  └── novel_profiles 表（当前快照）
  └── profile_changes 表（增量变更）
  └── projections 表（Character/World/Plot 投影）

Layer 3: AuthorProfile（作者能力档案）
  └── author_profiles 表（能力评分/诊断历史/训练历史）
```

**新增表清单**：
- `novels` — 小说主表
- `chapters` — 章节表（Raw Novel）
- `characters` — 人物核心实体
- `character_traits` — 人物特征（JSON扩展）
- `world_settings` — 世界观设定
- `novel_profiles` — 小说Profile快照
- `profile_changes` — 增量变更记录
- `projections` — 投影表（Character/World/Plot）
- `author_profiles` — 作者能力档案（预留）

**设计原则**：
- 关系型存核心实体，JSON 存扩展属性
- Projection 层让诊断按需读取，不用加载全量
- 增量更新，不用全量重建

---

### 2. 多 Agent 教学流水线架构

```
用户上传
  ↓
Raw Storage（chapters 表）
  ↓
Reader Agent（阅读抽取）
  ├─ 输入：原始章节文本
  ├─ 输出：CharacterProjection / WorldProjection / PlotProjection
  └─ 看不到：诊断规则 / 教学规则
  ↓
Projection Layer（projections 表）
  ↓
Diagnosis Agent（病症识别）
  ├─ 输入：Projection 数据
  ├─ 输出：{ disease: "P002", confidence: 0.82 }
  └─ 看不到：原始文本 / 训练方法
  ↓
Training Agent（训练设计）
  ├─ 输入：诊断结果
  ├─ 输出：训练任务
  └─ 看不到：原始文本 / 结构化数据
  ↓
Evaluation Agent（效果评估）
  ↓
Author Profile（能力档案更新）
```

**教学隔离原则**：
- Reader Agent：只读小说，不知道 P001 是什么
- Diagnosis Agent：只看 Projection，不看原文
- Training Agent：只接收诊断码，不接触小说内容
- Agent 之间传递的是**结构数据**（几KB），不是原文（百万字）

---

### 3. 长文本处理策略（三手准备）

| 场景 | 处理方式 |
|------|---------|
| < 4000 tokens（~3000字） | 直接分析 |
| 4000-20000 tokens | 直接分析，提示"内容较长" |
| 20000-60000 tokens | 战略抽样（时间轴采样：开篇/10%/30%/50%/80%/结尾） |
| > 60000 tokens（~5万字以上） | 告知风险，让用户选择抽样或全文 |

**战略抽样 vs 随机抽样**：
- 随机抽3章 → 可能抽到日常/日常/日常 → 误判节奏很好
- 时间轴采样 → 能看到节奏变化曲线、人物成长轨迹、文风一致性

---

### 4. 事件驱动架构

```
用户上传章节
  ↓
[同步] 存入 chapters 表
  ↓
[异步] Profile Update Task 入队
  ↓
Extractor Agent（后台处理）
  ├─ 增量分析新章节
  ├─ 更新 characters / world_settings
  ├─ 生成 profile_changes 记录
  ├─ 更新 novel_profiles（version + 1）
  └─ 更新 projections
  ↓
诊断 Agent 读取最新已完成的 Projection → 诊断
```

**关键设计**：
- 用户体验：上传立即成功
- 系统体验：后台慢慢处理
- 诊断 Agent 永远只读最新已完成的 Profile

---

### 5. 核心认知转变（已确定）

| 旧认知 | 新认知 |
|--------|--------|
| 月笙 = 超级 Prompt | 月笙 = 数据库 + Agent + 教学系统 |
| 诊断对象是小说 | 诊断对象是**作者能力** |
| AI 记住所有东西 | 系统知道什么时候把什么东西拿给 AI |
| 小说分析系统 | **作者成长操作系统** |
| NovelProfile 是终点 | **AuthorProfile 是终点** |

---

## 三、V1 实施范围（待确认）

### Phase 1：数据层（新增 9 张表 + 基础 Service）
- [ ] `008_novel_structure.sql` 迁移文件
- [ ] `NovelService` / `ChapterService` / `CharacterService` / `WorldSettingService`
- [ ] `NovelProfileService`（框架 + 增量更新逻辑）
- [ ] `ProjectionService`（框架）
- [ ] `AuthorProfileService`（预留空表 + 框架）

### Phase 2：Extractor Agent（异步抽取）
- [ ] 事件队列机制（简化版，可用定时轮询或内存队列）
- [ ] Reader Agent（章节 → 结构化抽取）
- [ ] Projection 生成（Character / World / Plot）

### Phase 3：诊断接入
- [ ] 修改 `diagnosis.handler.ts`，从 Projection 读取而非原文
- [ ] `ability-profile.service.ts` 扩展，支持从新的结构化数据聚合

### Phase 4：长文本处理
- [ ] 文本长度检测
- [ ] 战略抽样算法（时间轴采样）
- [ ] 用户选择界面（告知消耗和风险）

---

## 四、已创建但未完全利用的资产

| 资产 | 状态 | 说明 |
|------|------|------|
| `ability-atlas.json` | 已创建 | 能力↔症候↔训练映射，尚未接入 recommendation-engine |
| `SPEC_ability-profile_V1.0.md` | 已创建 | 能力画像设计规格（旧版，基于 ABL 体系） |
| `SPEC_focus-area-transition_V1.0.md` | 已创建 | 聚焦方向设计规格 |
| `transition-prompts.json` | 已创建 | 过渡邀请话术配置 |

---

## 五、三个核心规范填充成果（本次 session）

本次 session 完成了三个核心规范的定义和填充，它们将决定 Reader/Diagnosis/Training Agent 的输入输出标准。

### 5.1 SPEC_Ability_Map_V1.md — 能力映射体系

| 补充内容 | 状态 |
|---------|------|
| 19 个子能力的完整训练任务映射（21 条映射） | ✅ |
| 新增症候的训练任务扩展规则 | ✅ |
| 核心能力评分权重（算术平均） | ✅ |
| 新旧能力体系映射（ABL → OBS/CHAR/PLOT/EMO/WORLD/STYLE） | ✅ |
| 迁移策略（V1 并行 → V1.5 升级 → V2 废弃） | ✅ |

**核心决策**：V1 冻结 6 核心能力 + 19 子能力，新增症候只能映射到现有子能力。

### 5.2 SPEC_Evidence_V1.md — 证据体系

| 补充内容 | 状态 |
|---------|------|
| evidence 表 SQLite DDL | ✅ |
| diagnosis_evidence 关联表 DDL | ✅ |
| 四级 Evidence 的 content_json 结构示例 | ✅ |
| 核心查询接口（按症候/按能力/证据链/对比生成） | ✅ |
| 与现有系统的衔接方案 | ✅ |

**核心决策**：诊断必须附带 Evidence，没有 Evidence 的诊断不允许写入。

### 5.3 SPEC_AuthorProfile_V1.md — 成长记录格式

| 补充内容 | 状态 |
|---------|------|
| author_profiles 表 SQLite DDL | ✅ |
| growth_chain_events 展开表 DDL | ✅ |
| 与 Evidence 系统的显式关联（evidence_ids 引用机制） | ✅ |
| AuthorProfile Service 接口定义 | ✅ |
| 三种可视化数据接口（Radar/Timeline/Comparison） | ✅ |

**核心决策**：AuthorProfile 只存 Evidence 引用，不冗余存储内容。

### 5.4 SPEC_ThreeSpecs_Integration_V1.md — 三规范集成

| 内容 | 状态 |
|------|------|
| 三个规范的定位与关系图 | ✅ |
| 完整数据流（小说上传 → 成长记录） | ✅ |
| 每个 Agent 的输入输出规范 | ✅ |
| 跨规范 ID 命名统一 | ✅ |
| 数据一致性约束（外键 + 应用层检查） | ✅ |
| 接口协作图（读取 + 写入） | ✅ |

**核心决策**：三个规范统一后，Agent 的接口会"自动长出来"。

---

## 六、下步决策点

1. **是否现在写 `SPEC_novel-profile_V1.0.md` 规格文档？**
2. **是否现在创建 `T-007-novel-profile.md` 任务文档？**
3. **V1 先做 Phase 1（数据层），还是一次性做完全部？**
4. **事件队列用简化版（内存队列）还是直接上持久化队列？**
