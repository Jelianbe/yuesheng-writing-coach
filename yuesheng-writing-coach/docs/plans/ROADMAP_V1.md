# 月笙写作教练 — 后续任务序列与里程碑计划

> 基准日期：2026-06-02  
> 文档状态：V1.0（正式版）  
> 用途：指导项目从当前阶段到 V1.0 最终交付的完整路径  
> 关联规则：R-003（里程碑节点管理）、R-018（变更溯源规范）  
> 关联文档：[REPORT-2026-06-02.md](../tasks/REPORT-2026-06-02.md)、[SESSION-2026-06-02-summary.md](../tasks/SESSION-2026-06-02-summary.md)

---

## 一、当前项目状态

### 完成链路 vs 缺失链路

```
已打通（5步）：
  对话 → 诊断 → 证据（Level 1） → AuthorProfile → 前端三标签页展示

待建设（5步）：
  Raw Novel → NovelProfile → Reader Agent → Pattern Detector → Training → Evaluation
```

### 资产盘点

| 类别 | 已有 | 缺失 |
|------|------|------|
| 设计哲学 | 四层架构、三层数据架构、认知追踪（OBS→DIAG→TRAIN→EVAL） | 无重大缺失 |
| 技术规格 | Ability Map V1、Evidence V1、AuthorProfile V1、三规范集成 V1 | NovelProfile、Agent 架构、长文本策略 |
| 数据库 | 9 张表（001-009 迁移） | 无缺失 |
| Service | EvidenceService、AuthorProfileV2Service、DiagnosisService、TeachingStateService、AbilityProfileService、TrainingRecordService、SessionService | ReaderService、PatternService、TrainingService、EvaluationService |
| 前端 | ChatPage、诊断面板（三标签）、教学进度面板、会话侧栏、雷达图/时间线/对比组件 | 训练执行界面、对比可视化增强 |
| 测试 | 81 个单元测试 | 组件测试、集成测试、Agent 测试 |
| Prompt | Agent Prompt V3.1、教学动作库 V3.1 | 无缺失 |
| 教学案例 | 阿元重生章节诊断（7 轮教学过程归档） | 更多教学案例 |

### 当前系统能力边界

```
已完成区域                         待建设区域
───────────────────────────       ───────────────────────────
✅ 用户会话管理                    ❌ NovelProfile 规格
✅ AI 流式对话                     ❌ Reader Agent（阅读抽取）
✅ 病症诊断（P001-P010）          ❌ Pattern Detector（模式聚合）
✅ 四级证据体系（Level 1 已通）   ❌ Training Agent（训练执行）
✅ 能力画像（雷达图）              ❌ Evaluation Agent（效果评估）
✅ 成长轨迹（时间线）              ❌ 长文本策略（>8000 token）
✅ 作品对比（之前/之后）           ❌ Agent 架构正式化
✅ 聚焦方向 + 过渡邀请             ❌ 训练执行界面
✅ 教学状态机                      ❌ 集成测试 + 组件测试
✅ 跨语境迁移库
```

### 关键设计决策（已确认，不再反复讨论）

| 决策 | 内容 | 依据 |
|------|------|------|
| 三层数据架构 | Raw Novel → NovelProfile → AuthorProfile | SESSION-2026-06-02-summary.md |
| 四级认知追踪 | OBS → DIAG → TRAIN → EVAL 事件流 | SPEC_AuthorProfile_V1.md |
| 四级证据层级 | 文本/模式/统计/对比 | SPEC_Evidence_V1.md |
| 六核心能力 | OBS/CHAR/PLOT/EMO/WORLD/STYLE，V1 冻结 | SPEC_Ability_Map_V1.md |
| 能力树稳定性 | V1 期间不新增/修改核心能力，只映射症候 | SPEC_Ability_Map_V1.md |
| 教学隔离 | Reader/Diagnosis/Training/Evaluation 关注点分离 | SPEC_ThreeSpecs_Integration_V1.md |
| 诊断对象 | 诊断的是**作者能力**，不是小说本身 | 设计哲学 |

---

## 二、任务序列

### Phase 1：补齐中间层（NovelProfile + Reader Agent）

**目标**：打通 Raw Novel → NovelProfile → Evidence 的提取链。这是 Agent 化的前提。  
**关联前序任务**：[T-003-worldbuilding-character-expansion.md](../tasks/T-003-worldbuilding-character-expansion.md)、[T-004-diagnosis-persistence.md](../tasks/T-004-diagnosis-persistence.md)  
**关联规格**：SPEC_Ability_Map_V1.md, SPEC_Evidence_V1.md

| ID | 任务 | 优先级 | 负责人 | 工时估 | 执行步骤 |
|----|------|--------|--------|-------|---------|
| P1.1 | 设计 NovelProfile 规格文档 | P0 | AI+用户 | 4h | ① 定义数据结构（角色列表/关键场景/对话密度/感官密度/视角分布/节奏特征）② 定义与 Level 1 Evidence 的转化规则 ③ 定义与 Ability Map 的映射关系 ④ 定义存储格式（叠加式 vs 快照式）⑤ 输出 `SPEC_NovelProfile_V1.md` |
| P1.2 | 实现 NovelProfile 类型定义 | P0 | AI | 2h | ① 在 types.ts 新增 `NovelProfile` 接口 ② 新增 `NovelProfileSection` / `NovelCharacter` / `KeyScene` 等子接口 ③ 新增 IPC_CHANNELS 通道 ④ 新增 DB 行类型 |
| P1.3 | 设计 Reader Agent 规格 | P0 | AI+用户 | 3h | ① 定义 Reader Agent 输入（raw text / 章节/ 长文本分片）② 定义 Reader Agent 输出（NovelProfile）③ 定义长文本处理策略（8000 token 采样 vs 滑动窗口 vs 用户选择章节）④ 定义从 NovelProfile 到 Level 1 Evidence 的转化规则 ⑤ 输出 `SPEC_ReaderAgent_V1.md` |
| P1.4 | 实现基础 Reader Service | P0 | AI | 6h | ① 创建 `reader.service.ts`（接收文本 → 调用 AI 提取结构数据 → 输出 NovelProfile）② 实现章节分割器（按字数/按章节标记分割）③ 实现采样策略（开头+结尾+随机中段 三手准备）④ 实现 NovelProfile → Evidence 转化 ⑤ 注册 IPC handler |
| P1.5 | 实现 NovelProfile 持久化 | P1 | AI | 2h | ① 创建 `010_novel_profile.sql` 迁移 ② 实现 `NovelProfileService`（save / getBySession）③ 接入 reader.handler |

**P1 输出**：
- 2 个设计文档（NovelProfile + Reader Agent）
- ReaderService（含长文本处理）
- NovelProfileService（含 DB 持久化）
- 端到端验证：用户上传文本 → Reader Agent 提取 NovelProfile → 生成 Level 1 Evidence
- **与现有系统集成**：ReaderService 的输出应接入现有 diagnosis.handler.ts 的 `processDiagnosisFromAI` 链路

**P1 DoD**：
1. [ ] SPEC_NovelProfile_V1.md 通过用户 review
2. [ ] SPEC_ReaderAgent_V1.md 通过用户 review  
3. [ ] TypeScript 编译零错误
4. [ ] 端到端测试：3000 字章节 → NovelProfile 结构完整 → Evidence 正确生成
5. [ ] 现有 81 个测试不因 P1 变更而失败

---

### Phase 2：Pattern Detector + Evidence 体系补全

**目标**：从 Level 1 的离散文本证据，自动聚合为 Level 2（模式）和 Level 3（统计）证据。  
**关联规格**：SPEC_Evidence_V1.md（统计指标库已定义，待实现）

| ID | 任务 | 优先级 | 负责人 | 工时估 | 执行步骤 |
|----|------|--------|--------|-------|---------|
| P2.1 | 设计 Pattern Detector 规格 | P0 | AI+用户 | 3h | ① 定义模式识别规则（同症候连续出现 N 次 → 模式证据）② 定义统计计算方法（情绪标签占比 = 标签句数 / 总句数）③ 定义阈值参数（行业基准线）④ 定义触发时机（Reader 完成后自动触发 / 定时触发）⑤ 输出 `SPEC_PatternDetector_V1.md` |
| P2.2 | 实现 Pattern Detection Service | P0 | AI | 4h | ① 创建 `pattern-detector.service.ts` ② 实现 Level 1→Level 2 聚合器（按症候/按时间窗口/按章节）③ 实现 Level 3 统计计算器（6 个核心指标：情绪标签占比 / 感官密度 / 对话比例 / 视角偏度 / 节奏方差 / 设定曝光比）④ 实现从 EvidenceService 批量读取 → 聚合 → 写入 |
| P2.3 | 实现统计指标基准线配置 | P1 | AI | 1h | ① 创建 `resources/config/statistical-benchmarks.json` ② 实现基准线加载服务 ③ 接入 Pattern Detector |
| P2.4 | 实现自动触发链路 | P1 | AI | 2h | ① 在 Reader 完成回调中触发 Pattern Detector ② 在 Diagnosis 完成回调中补充统计证据 ③ 验证两级自动触发的正确性 |

**P2 输出**：
- 1 个设计文档（Pattern Detector）
- PatternDetectionService（含模式识别 + 统计计算）
- 统计基准线配置（JSON 外置）
- 自动触发链路（Reader → Detector → Diagnosis）

**P2 DoD**：
1. [ ] Level 1→Level 2 聚合正确，能识别重复模式（3 次同症候→模式证据）
2. [ ] 6 个核心统计指标计算正确
3. [ ] 基准线配置可热更新（修改 JSON 无需重启）
4. [ ] 自动触发链路无阻塞，Reader 完成后 500ms 内触发 Detector
5. [ ] 新增测试 ≥ 10 个

---

### Phase 3：Training 执行链路

**目标**：让系统从一个"只会诊断的教练"变成"诊断完就带练的教练"。  
**关联规格**：SPEC_Ability_Map_V1.md（训练任务映射表 21 条）  
**关联数据库**：007_user_training.sql（表已存在，待扩展使用）

| ID | 任务 | 优先级 | 负责人 | 工时估 | 执行步骤 |
|----|------|--------|--------|-------|---------|
| P3.1 | 设计 Training Agent 规格 | P0 | AI+用户 | 3h | ① 定义 Training Agent 输入（DiagnosisResult + 能力画像）② 定义训练任务分配规则（症候→子能力→训练任务，依据 Ability Map 的 21 条映射）③ 定义训练执行流程（推送→用户完成→提交→评估→反馈）④ 定义训练任务的 UI 交互形式（卡片列表 / 聊天内嵌 / 独立面板）⑤ 输出 `SPEC_TrainingAgent_V1.md` |
| P3.2 | 实现 Training Service | P0 | AI | 4h | ① 创建 `training.service.ts` ② 实现任务分配器（getTasksForDiagnosis：按症候匹配训练任务，按优先级排序）③ 实现训练会话管理（createTrainingSession / submitWork / evaluate）④ 实现训练记录持久化（复用 007_user_training.sql，扩展字段 if needed） |
| P3.3 | 实现训练任务推送界面 | P0 | AI | 5h | ① 在 ChatPage 中接入训练任务推送 ② 创建 TrainingTaskCard 组件（展示任务名称/内容/目标/难度）③ 创建训练成果提交入口（文本输入 / 文件上传）④ 创建训练反馈展示区（评分 + 评语 + 下一步建议） |
| P3.4 | 实现 Evaluation Agent V1 | P0 | AI+用户 | 4h | ① 定义 Evaluation 规格（评估标准 = 是否达到训练目标）② 实现 evaluation.service.ts（调用 AI 评估用户提交的训练成果）③ 实现 Level 4 对比 Evidence 生成（训练前快照 vs 训练后作品）④ 实现能力评分更新（训练完成 → ability +3/+5，具体值由训练难度决定） |
| P3.5 | 打通 Training 完整链路 | P0 | AI | 3h | ① 在 Diagnosis 完成后自动触发 Training（推送训练任务）② 用户完成训练后自动触发 Evaluation ③ Evaluation 完成后自动触发 AuthorProfile 更新（记录 TRAIN 事件）④ 端到端验证：对话→诊断→训练→评估→画像更新 |

**P3 输出**：
- 1 个设计文档（Training Agent）
- TrainingService + EvaluationService
- 训练任务界面（TaskCard + 提交入口 + 反馈展示）
- Level 4 对比 Evidence 生成
- 完整链路：Diagnosis → Training → Evaluation → AuthorProfile

**P3 DoD**：
1. [ ] 训练任务能正确根据诊断结果分配（P001→T001/T002 等）
2. [ ] 训练成果评估能正常返回（评分 + 评语）
3. [ ] Level 4 对比 Evidence 生成正确（训练前 vs 训练后）
4. [ ] 能力评分随训练正确更新（+3/+5，日志可审计）
5. [ ] 前端训练交互流畅（推送→接收→提交→反馈 完整流程）
6. [ ] 新增测试 ≥ 15 个

---

### Phase 4：Agent 架构正式化 + 长文本优化

**目标**：将"写在函数里的 Agent 逻辑"真正抽离为可独立演进的 Agent 模块。  
**注意**：此 Phase 可前置一部分到 P1/P3 中（如 Reader Agent 的独立设计），避免后期大规模重构。

| ID | 任务 | 优先级 | 负责人 | 工时估 | 执行步骤 |
|----|------|--------|--------|-------|---------|
| P4.1 | 设计 Multi-Agent 架构 | P0 | AI+用户 | 4h | ① 定义 Agent 生命周期（输入→处理→输出→事件）② 定义 Agent 通信协议（事件总线 vs 消息队列：推荐内存事件总线，轻量可测试）③ 定义 Agent 调度器（同步链 vs 异步队列：建议 Reader 同步，Pattern/Training 异步）④ 定义每个 Agent 的边界和准入条件 ⑤ 定义错误处理和回退策略 ⑥ 输出 `SPEC_AgentArchitecture_V1.md` |
| P4.2 | 提取 Reader Agent 为独立模块 | P1 | AI | 3h | ① 将 reader.service.ts 中的逻辑封装为 ReaderAgent 类 ② 实现 Agent 生命周期方法（onInput / onProcess / onOutput）③ 注册到 Agent 调度器 |
| P4.3 | 提取 Pattern Detector 为独立模块 | P1 | AI | 2h | ① 将 pattern-detector.service.ts 封装为 PatternAgent ② 注册到 Agent 调度器 |
| P4.4 | 提取 Training Agent 为独立模块 | P1 | AI | 3h | ① 将 training.service.ts + evaluation.service.ts 封装为 TrainingAgent 和 EvaluationAgent ② 注册到 Agent 调度器 |
| P4.5 | 实现长文本处理增强 | P1 | AI | 4h | ① 实现滑动窗口策略（8000 token 窗口 + 步进 4000 + 关键信息融合）② 实现用户交互式章节选择 UI ③ 实现全文本状态记录（已读/未读/分析进度） |

**P4 输出**：
- 1 个设计文档（Agent 架构）
- 4 个独立 Agent 模块（Reader / Pattern / Training / Evaluation）
- Agent 调度器（内存事件总线）
- 长文本处理增强（滑动窗口 + 交互选择 + 状态追踪）

**P4 DoD**：
1. [ ] Agent 架构文档通过用户 review
2. [ ] 4 个 Agent 独立部署运行（单元测试可独立 mock）
3. [ ] 调度器能控制执行顺序（Reader→Pattern→Diagnosis→Training→Evaluation）和错误处理
4. [ ] 长文本处理三种模式（直接/采样/滑动窗口）都可用
5. [ ] 新增一个 Agent 的成本 ≤ 2 个文件
6. [ ] 现有测试不因重构而失败

---

### Phase 5：测试 + 边缘场景加固

**目标**：确保 V1.0 在真实使用场景下的稳定性。  
**注意**：单元测试可在各 Phase 开发过程中同步编写，不一定要等到此 Phase 才开始。

| ID | 任务 | 优先级 | 负责人 | 工时估 | 执行步骤 |
|----|------|--------|--------|-------|---------|
| P5.1 | 写前端组件测试 | P1 | AI | 4h | ① AbilityRadarChart 渲染测试（空数据/全0/满分的三种状态）② GrowthTimeline 数据渲染测试（空链/单链/多链）③ ComparisonView 对比逻辑测试（分数变化 + 颜色断言）④ DiagnosisPanel 标签页切换测试（禁用状态/正常切换） |
| P5.2 | 写新 Service 测试 | P1 | AI | 4h | ① EvidenceService CRUD 测试（save/link/query 三种操作）② AuthorProfileV2 updateAfterDiagnosis 逻辑测试（症候映射/能力加减/轨迹追加）③ PatternDetector 聚合逻辑测试（Level 1→2→3 各一条） |
| P5.3 | 写集成测试 | P2 | AI | 4h | ① 诊断→Evidence→AuthorProfile 全链路测试（mock AI 响应）② 长文本处理流程测试（<3000字 / 3000-20000字 / >20000字 三类）③ 多轮对话+多次诊断 画像追踪测试 |
| P5.4 | 边缘场景加固 | P2 | AI | 3h | ① 空文本输入处理 ② 诊断结果为空的路径（无症候的正常流程）③ 大文本（>10000 字）的截断和恢复 ④ 网络异常时的重试机制 ⑤ AI 返回格式异常的 fallback |

**P5 DoD**：
1. [ ] 前端组件测试 ≥ 10 个
2. [ ] Service 测试 ≥ 10 个
3. [ ] 集成测试 ≥ 5 个
4. [ ] 测试总覆盖率 > 70%（行覆盖率）
5. [ ] 5 个边缘场景全部覆盖

---

### Phase 6：V1.0 收尾

| ID | 任务 | 优先级 | 负责人 | 工时估 | 执行步骤 |
|----|------|--------|--------|-------|---------|
| P6.1 | CHANGELOG 更新 | P2 | AI+用户 | 1h | ① 回顾所有变更（从 V0.1 到 V1.0）② 编写符合 R-016 的 CHANGELOG ③ 确认版本语义（V1.0.0） |
| P6.2 | 文档完整性检查 | P2 | AI+用户 | 2h | ① 按 R-018 检查变更溯源链完整性 ② 按 R-017 检查文档分类和命名规范 ③ 修复发现的文档缺失 |
| P6.3 | 用户验收测试 | P0 | 用户 | 4h | ① 用户按 Phase-level DoD 逐条验收 ② 记录发现的问题 ③ 修复 P0/P1 级问题 |
| P6.4 | V1.0 版本发布 | P0 | AI+用户 | 1h | ① 最终打包构建 ② 发布到目标平台 ③ 标记 git tag v1.0.0 |

---

## 三、里程碑计划

### Milestone M1：中间层就绪

| 项目 | 内容 |
|------|------|
| **关键节点** | NovelProfile + Reader Agent 完成开发 |
| **达成标准** | ① 用户上传小说章节 → Reader Agent 提取 NovelProfile ② NovelProfile → Level 1 Evidence 自动生成 ③ 长文本处理策略（三手准备：直接/采样/滑动窗口）可用 ④ TypeScript 编译零错误 ⑤ 现有 81 个测试不失败 |
| **验收方式** | 端到端测试：输入一篇 3000 字小说章节 → 验证 NovelProfile 结构完整（角色/场景/视角/节奏）→ 验证 Evidence 正确生成（按症候匹配） |
| **预计时间** | 2026-06-09（1 周） |
| **依赖** | P1.1 → P1.2 → P1.3 → P1.4 → P1.5（严格串行） |
| **新增文件预估** | 6-8 个（规格×2 + service + handler + types + migration + test） |
| **风险** | 长文本处理效果不达预期 → 先保证"采样模式"可用，滑动窗口延后到 P4.5 |

### Milestone M2：证据体系完成

| 项目 | 内容 |
|------|------|
| **关键节点** | Pattern Detector 上线，四级 Evidence 全部可用 |
| **达成标准** | ① Level 1 文本证据 → Level 2 模式证据自动聚合 ② Level 3 统计证据自动计算 ③ 统计指标基准线可配置（JSON 外置） ④ 自动触发链路无阻塞 |
| **验收方式** | 输入同一章节 3 次诊断 → 验证是否生成模式证据（Level 2，同症候连续出现 ≥3 次）→ 验证统计指标计算准确（情绪标签占比 / 感官密度 / 对话比例 等） |
| **预计时间** | 2026-06-23（M1 + 2 周） |
| **依赖** | P2.1 → P2.2 → P2.3 → P2.4 |
| **新增测试要求** | ≥ 10 个 |

### Milestone M3：训练执行可用

| 项目 | 内容 |
|------|------|
| **关键节点** | 系统从"诊断工具"变成"成长系统" |
| **达成标准** | ① 诊断完成后自动推荐训练任务（按 Ability Map 的 21 条映射）② 用户可在界面中查看/完成训练任务 ③ 用户提交训练成果后获得评估（评分 + 评语）④ Level 4 对比 Evidence 自动生成（训练前 vs 训练后）⑤ AuthorProfile 能力评分随训练更新（+3/+5） |
| **验收方式** | 完整走一遍用户旅程：上传小说 → 诊断 → 接收训练任务 → 提交训练作品 → 查看评估反馈 → 查看能力画像变化 → 查看成长时间线新增 TRAIN 事件 |
| **预计时间** | 2026-07-21（M2 + 4 周） |
| **依赖** | P3.1 → P3.2 → P3.3 → P3.4 → P3.5 |
| **新增测试要求** | ≥ 15 个 |

### Milestone M4：Agent 架构正式化

| 项目 | 内容 |
|------|------|
| **关键节点** | 所有 Agent 独立化，架构可扩展 |
| **达成标准** | ① 4 个 Agent（Reader / Pattern / Training / Evaluation）独立运行 ② Agent 调度器统一管理生命周期和错误处理 ③ 新增一个 Agent 的成本 ≤ 2 个文件 ④ 长文本处理三种模式都可用 |
| **验收方式** | 模拟新增一个 "Summary Agent" → 验证从定义到注册到运行的完整流程 ≤ 2 文件（Agent 类 + 注册代码） |
| **预计时间** | 2026-08-04（M3 + 2 周） |
| **依赖** | P4.1 → P4.2 → P4.3 → P4.4 → P4.5 |
| **重要提醒** | P1.3 和 P3.1 设计阶段应预留 Agent 化接口，避免 M4 大规模重构 |

### Milestone M5：V1.0 正式发布

| 项目 | 内容 |
|------|------|
| **关键节点** | 项目达到可用状态，可发布 V1.0 |
| **达成标准** | ① 所有 P0/P1 任务完成 ② 测试覆盖率 > 70%（行覆盖率）③ 用户验收通过 ④ 文档完整性检查通过（R-017 / R-018） |
| **验收方式** | 用户按 Milestone-level DoD 逐条验收 + 全链路走一遍（上传→诊断→训练→评估→画像更新）→ 全部通过后签署发布确认 |
| **预计时间** | 2026-08-18（M4 + 2 周） |
| **依赖** | P5.1 → P5.2 → P5.3 → P5.4 → P6.1 → P6.2 → P6.3 → P6.4 |

---

## 四、甘特图（工作量视图）

```
2026年6月                     7月                      8月
───────────────────────────────────────────────────────────────
M1: 中间层就绪（06/09）
  ████████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
  P1.1 P1.2 P1.3 P1.4 P1.5

M2: 证据体系完成（06/23）
  ░░░░░░░░░░░░█████████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░
              P2.1 P2.2 P2.3 P2.4

M3: 训练执行可用（07/21）
  ░░░░░░░░░░░░░░░░░░░░░░░░████████████████████████░░░░░░░░░░░
                          P3.1 P3.2 P3.3 P3.4 P3.5

M4: Agent 架构正式化（08/04）
  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░████████████████░░░░░░
                                        P4.1-P4.5

M5: V1.0 发布（08/18）
  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░██████████████
                                                  P5.1-P6.4
```

### 依赖关系图

```
P1.1 → P1.2 → P1.3 → P1.4 → P1.5 ──── M1
                                        │
                                        ↓
                                  P2.1 → P2.2 → P2.3 → P2.4 ── M2
                                                              │
                                                              ↓
                                                        P3.1 → P3.2 → P3.3 → P3.4 → P3.5 ── M3
                                                                                            │
                                                                                            ↓
                                                                                      P4.1 → P4.2 → P4.3 → P4.4 → P4.5 ── M4
                                                                                                                            │
                                                                                                                            ↓
                                                                                                                      P5.1-P5.4 → P6.1-P6.4 ── M5
```

---

## 五、风险与应对

| 风险 | 影响 | 概率 | 应对策略 |
|------|------|------|---------|
| 长文本处理效果不达预期 | M1 延期 | 中 | 先实现"采样模式"快速可用（开头+结尾+随机中段），滑动窗口做 V1.1（P4.5） |
| AI 评估训练成果的质量不稳定 | M3 延期 | 中 | V1 用规则评估（关键字匹配 + 字数检查 + 症候命中率），ML/LLM 评估放 V2 |
| Agent 架构过度设计 | M4 延期 | 低 | 遵循 R-010 最小化范围，先提取再优化，不提前做复杂调度。V1 用简单的事件回调即可 |
| 用户验收发现设计方向问题 | M5 延期 | 中 | 每个 Milestone 结束后做用户反馈收集（M1→M4 各一次 review），不等到 M5 才验收 |
| 能力树（6 能力 + 19 子能力）在使用中被发现设计缺陷 | M3-M5 | 低 | 能力树 V1 冻结，经验证后再优化。能力树稳定前不改评分算法 |
| 测试集中在后期导致返工成本高 | P5 质量风险 | 中 | **建议**：每个 Phase 开发时同步编写单元测试，不等到 P5 才开始。P5 仅做补齐和集成测试 |
| 现有 81 测试因新代码被破坏 | 各 Phase | 低 | 每次提交前运行 `npm test`，确保现有测试全部通过 |

---

## 六、耗时汇总

| 阶段 | 开发工时 | 设计工时 | 最乐观 | 最悲观 | 预期 |
|------|---------|---------|--------|--------|------|
| P1 中间层 | 17h | 7h | 1 周 | 3 周 | 1 周 |
| P2 证据体系 | 7h | 3h | 1 周 | 2 周 | 2 周 |
| P3 训练链路 | 16h | 3h | 3 周 | 5 周 | 4 周 |
| P4 Agent 架构 | 12h | 4h | 2 周 | 4 周 | 2 周 |
| P5 测试加固 | 11h | 0h | 1 周 | 2 周 | 1 周 |
| P6 收尾发布 | 8h | 0h | 1 周 | 2 周 | 1 周 |
| **总计** | **71h** | **17h** | **9 周** | **18 周** | **11 周** |

> 注：  
> - 以上工时估算基于"AI 全职 + 用户每日 2-4h 配合"的工作模式  
> - 开发工时包含单元测试编写时间，不包含集成测试时间  
> - 总计 71h 开发 + 17h 设计 = 88h，按每周 8h（用户 2h+AI 6h）计算约 11 周

---

## 七、关键路径分析

```
关键路径（Critical Path）：
  P1.1 → P1.2 → P1.3 → P1.4 → P1.5 → P2.1 → P2.2 → P2.4 → P3.1 → P3.2 → P3.5 → P4.1 → P4.5 → P5.3 → P5.4 → P6.3 → P6.4

非关键路径（可并行）：
  P2.3（与 P2.2 并行）→ 不影响关键路径
  P3.3（与 P3.4 并行）→ 有 1 周缓冲
  P4.2/P4.3/P4.4（与 P4.1 部分并行）→ 提前设计好接口即可
  P5.1/P5.2（与 P5.3/P5.4 并行）
  P6.1/P6.2（与 P6.3 并行）

关键路径总长：~9 周（占总工期 82%）
```

---

## 八、后续行动

1. **用户 review 本文档** — 确认各 Milestone 的优先级、范围和验收标准
2. **时间校准** — 按用户实际可用时间调整里程碑日期（当前预估基于 AI 每日 6h + 用户 2h）
3. **Phase 1 启动** — 确认后立即从 P1.1（设计 NovelProfile 规格）开始
4. **更新项目规则** — 将里程碑计划纳入 R-003 里程碑节点管理规则的执行检查中
5. **创建 Phase 1 任务文档** — 按 R-018 要求创建 `T-007-novel-profile-reader.md` 任务文档

### 立即可以开始的行动

```
最优先（用户 review 完成后）：
  □ 创建 T-007-novel-profile-reader.md 任务文档
  □ 开始 P1.1：设计 NovelProfile 规格
  □ 与用户讨论 NovelProfile 的数据结构定义
```

### 各 Phase 对应的任务文档前缀

| Phase | 任务文档 | 创建时机 |
|-------|---------|---------|
| P1 | T-007-novel-profile-reader.md | 启动前创建 |
| P2 | T-008-pattern-detector.md | M1 通过后创建 |
| P3 | T-009-training-evaluation.md | M2 通过后创建 |
| P4 | T-010-agent-architecture.md | M3 通过后创建 |
| P5 | T-011-test-reinforcement.md | M4 通过后创建 |
| P6 | T-012-release-v1.md | M5 验收前创建 |
