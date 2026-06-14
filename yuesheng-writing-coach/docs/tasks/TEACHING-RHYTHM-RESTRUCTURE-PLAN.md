# 教学节奏重构方案 · 完整任务清单

> **状态**: 待审查 | **创建**: 2026-06-13 | **审查修正**: 2026-06-14
> **来源**: 真实教学案例分析 + 前端系统性代码审查 + 数据流向审计
> **审查通过后执行**: 各任务按依赖顺序推进
> **覆盖**: 零 + A/B/C/D/E/F/G/H/I 共 9 阶段（零为教学方法定位，不包含任务）
> **自评两轮**: 2026-06-14 | 6 项修正全部采纳 ✅

---

## 核心前提：引导发现教学法的适用边界

本节定义 S2_GUIDE（引导发现阶段）的准入/退出条件，作为后续所有阶段的设计基调。

### 当前问题

| 观察项 | 表现 | 根源 | 优先级 |
|--------|------|------|:------:|
| **T-诊断结论** | 诊断后直接进入教学，"缺失感和治疗感"而非"发现感和掌控感" | 缺少引导发现阶段 | P0 |
| **T-教学节奏** | 所有症候用同一节奏推进，不分"适合发现的"和"适合直接传授的" | 缺少 discoverable 机制 | P0 |
| **T-训练内容** | 经典语文教学方法（朗读法/仿写/缩写法等）未被吸收 | 训练与标准教学脱节 | P1 |
| **T-训练时机** | 右侧栏训练卡一直挂着，不考虑用户是否准备好 | 训练与教学进度不同步 | P1 |
| **T-输出风格** | 豆包/月笙/sensei 只是语气区别，教学策略没有本质差异 | 态度档位功能弱化 | P1 |
| **T-训练形式** | 缺少观察/阅读类任务，只有写作练习 | task_type 单一 | P2 |

### 三块地基代码验证结果（2026-06-14）

| 验证项 | 结论 | 对方案的影响 |
|--------|------|-------------|
| **panelStore 当前状态** | 无 `sidebarPhase`/`sidebarMode` 字段 | F-01（sidebarPhase）和 I-03（sidebarMode）均需从零创建 |
| **training_records 表** | `score: number|null`，1-10 范围，非 0-100 | MasteryGate 映射：>9.0=快进，<4.0=回退，无需迁移 |
| **teaching-state-machine 子阶段定位** | 使用 `indexOf()` 动态计算，非硬编码 index | **G-06 不需要**，S2_GUIDE 插入后自动适配 |

---

## §一 方案概览

### 总目标

在现有教学循环中插入"引导发现阶段"（S2_GUIDE），使教学节奏从"诊断→告诉→训练"转变为"诊断→引导发现→告诉→训练"，同时满足不同学习阶段和不同学习态度的灵活切换。

### 9 阶段总览

| 阶段 | 名称 | 性质 | 任务数 |
|:----:|------|:----:|:------:|
| A | Prompt Skill化 — 规则提取与配置化 | Prompt 架构重构 | 5 |
| B | 教学状态机改造 | 状态机核心逻辑 | 2 |
| C | 训练/阅读库扩充 | 内容生产（骨架+填充） | 4 |
| D | 第三次蒸馏 | 内容生产（核心前置） | 7 |
| E | 遗留问题 | 跨领域修复 | 8 |
| F | 右边栏渐进式披露 | 前端 UI 范式切换 | 4 |
| G | 数据层改造 | 后端 DB + 配置 + 常量 | ~~6~~ 5（G-06 已移除） |
| H | 右边栏标签页重构 | 前端 UI 重组 | 3 |
| I | 对话栏按钮精简 + 模板辅助 | 前端 UI 精简 | 4 |

---

## §二 阶段详述

### 阶段 A：Prompt Skill化 — 规则提取与配置化（独立，可先做）

> **核心逻辑**: 当前 yuesheng-prompt-v3.md（~7200 字）是一个单体巨人，承担 6 项职责。修改任何一项都波及全文。趁重构窗口，将规则从 Prompt 文本提取为结构化 JSON 配置，将角色从一段文字提取为 Skill 边界定义。

| ID | 任务 | 改动位置 | 描述 |
|:--:|------|---------|------|
| **A-01** | teaching-rules.json 规则提取 | `resources/config/teaching-rules.json`（新建） | 将 V-01~V-09 共 9 条输出校验规则从 v3.md §八 提取为结构化 JSON 配置。每条规则包含 id/level/description/detectPattern/applicableRoles/examples/testCases |
| | | `resources/prompts/yuesheng-prompt-v3.md` | §八 从 ~1500 字精简为 ~200 字引用段 + `{teaching_rules_ref}` 占位符 |
| | | `src/main/domains/prompt/prompt-loader.ts` | 新增 injectRulesConfig()：读取 JSON → 按角色过滤 → 替换占位符 |
| **A-02** | attitude-rhythm.json 规则提取 | `resources/config/attitude-rhythm.json`（新建） | 态度↔教学节奏映射从 v3.md §五 提取为配置。三种档位（豆包/月笙/sensei）各含 6 项节奏参数：教学节奏(slow/medium/fast)、引导强度(0-1)、阅读前置(must/recommend/skip)、每轮最大提问数、反思门控轮次上限 |
| | | `resources/prompts/yuesheng-prompt-v3.md` | §五 从 ~400 字精简为 ~100 字 + `{attitude_rhythm_ref}` 占位符 |
| | | `src/main/domains/prompt/prompt-builder.ts` | 新增 buildAttitudeRhythmSection(attitude)：读取 JSON → 格式化节奏指令注入 |
| **A-03** | feedback-structure.json 规则提取 | `resources/config/feedback-structure.json`（新建） | 三明治反馈法话术结构提取为配置。三段式（praise/question/direction）各含 goal/forbiddenBehaviors/allowedPatterns/maxTokens/applicableRoles |
| | | `resources/prompts/yuesheng-prompt-v3.md` | 三明治规则文本 → 占位符 |
| | | `resources/prompts/teaching-agent-prompt.md` | 同步引用 |
| | | `src/main/domains/prompt/prompt-builder.ts` | 新增 buildFeedbackStructureSection() |
| **A-04** | 角色 Skill 拆分 | `resources/config/role-skills/teacher.skill.json`（新建） | Teacher Skill：严肃准确风格，知识源=症候+技法+策略，Token 预算=高（6轮），上下文保留全部症候段落 |
| | | `resources/config/role-skills/assistant.skill.json`（新建） | Assistant Skill：亲和引导风格，知识源=训练库+症候概要，Token 预算=中（4轮），上下文保留训练相关段落 |
| | | `resources/config/role-skills/clown.skill.json`（新建） | Clown Skill：幽默温暖风格，知识源=仅激励话术，Token 预算=低（2轮），上下文裁诊断/教学历史 |
| | | `resources/config/role-schedules.json`（新建） | 状态机阶段→角色映射表 + 上下文裁剪规则 |
| | | `resources/prompts/teacher-prompt.md`（新建） | 角色身份声明 + 占位符引用 |
| | | `resources/prompts/assistant-prompt.md`（新建） | 同上 |
| | | `resources/prompts/clown-prompt.md`（新建） | 同上 |
| | | `src/shared/types.ts` | 新增 TeachingRole 类型、RoleSkillConfig 接口 |
| | | `src/main/domains/prompt/prompt-loader.ts` | 新增 selectRoleSkill()：读取 schedule → 匹配 subphase → 获取 roleId → 读 skill.json → 只注入该角色允许的知识 |
| | | `resources/prompts/teaching-agent-prompt.md` | 保留为索引/降级入口 |
| **A-05** | 配置驱动输出验证器 | `src/main/services/output-validator.ts`（新建） | 读取 teaching-rules.json / attitude-rhythm.json / feedback-structure.json 作为检测依据，纯函数实现 |
| | | `tests/output-validator.test.ts`（新建） | 每条配置规则至少 2 个测试用例（1 正例 + 1 反例），覆盖率 100% |
| | | CI 配置 | 新增 `pnpm test:output-validation` 命令 |

#### A 阶段 DoD 检查清单

- [ ] teaching-rules.json 定义全部 9 条规则（V-01~V-09），含 id/level/description/detectPattern/applicableRoles/examples/testCases
- [ ] attitude-rhythm.json 定义三种档位的 6 项节奏参数
- [ ] feedback-structure.json 定义三段式结构 + 通用规则
- [ ] 3 个 skill.json 文件各定义清晰的角色边界（knowledgeBoundary/tokenBudget/contextRetention）
- [ ] role-schedules.json 定义状态机阶段↔角色映射
- [ ] 3 个 Prompt 文件各为角色身份声明 + 占位符，不包含具体规则
- [ ] prompt-loader.ts 新增 selectRoleSkill() 实现角色 Skill 动态选取，角色切换时执行上下文裁剪
- [ ] prompt-builder.ts 新增 buildAttitudeRhythmSection() / buildFeedbackStructureSection()
- [ ] output-validator.ts 配置驱动，覆盖全部 9 条规则
- [ ] 所有新建 JSON 配置在 `resources/config/` 下
- [ ] types.ts 新增 TeachingRole 和 RoleSkillConfig 类型
- [ ] tsc 0 错误

---

### 阶段 B：教学状态机改造（依赖 A 完成 + G-03 前置）

| ID | 任务 | 改动位置 | 描述 |
|:--:|------|---------|------|
| **B-01** | S2_GUIDE 子阶段 + MasteryGate | `src/main/domains/teaching/teaching-state/teaching-state-machine.constants.ts` | `PHASE_SUBPHASES[PRACTICE_LOOP]` 序列中于 IDENTIFY(0) 和 REFLECTION(1) 之间插入 S2_GUIDE |
| | | `src/main/domains/teaching/teaching-state/teaching-state-machine.ts` | 新增 `transitionToGuide()`、`exitGuide()` 方法；GUIDE 阶段内支持子级状态：`discover`→`try`→`reflect`→`confirm` |
| | | `src/main/domains/teaching/teaching-state/teaching-state-machine.guide.ts`（新建） | 引导发现专用过渡逻辑：按症候 discoverable 字段决定是否进入 GUIDE；敷衍检测（连续 3 次、总超时 >=5 轮、用户要求跳过）→ exitGuide |
| | | `src/main/domains/teaching/teaching-state/mastery-gate.ts`（新建） | 纯函数路由：训练记录 score 映射 0-100 → >90% 快进（skip next GUIDE） / <40% 回退（re-enter GUIDE） / 3 次敷衍降档 |
| | | `src/main/domains/teaching/teaching-state/teaching-state-machine.navigation.ts` | 导航逻辑适配新子阶段（使用 indexOf 动态计算，无需硬编码） |
| **B-02** | 阅读前置决策点 | `src/main/services/teaching-strategy-router.ts` | 在 assign 之前判断是否需要阅读前置。判断依据：豆包档位（must read）、月笙档位（recommend）、sensei 档位（skip）。阅读前置完成后自动跳转 assign |
| | | `resources/config/teaching-strategies.json` | 新增 readingStrategy 配置 |

#### B 阶段 DoD 检查清单

- [ ] S2_GUIDE 插入 PRACTICE_LOOP 序列后 navigation 和 reflection gate 自动适配（indexOf）
- [ ] GUIDE 子级状态（discover→try→reflect→confirm）完整实现
- [ ] 敷衍检测正确触发退出条件
- [ ] MasteryGate 纯函数实现，可脱离 LLM 做单元测试
- [ ] 阅读前置决策点按态度档位分流
- [ ] tsc 0 错误

---

### 阶段 C：训练/阅读库扩充（与 D 阶段并行，但内容填充等待 D 产出）

| ID | 任务 | 改动位置 | 描述 |
|:--:|------|---------|------|
| **C-01a** | 通用训练库结构骨架 | `resources/config/training-library.json`（新建） | 定义训练库 JSON Schema：id, name, description, difficulty, relatedSyndromes, taskType, steps[] |
| | | `src/renderer/shared/types-training.ts` | 新增 TrainingTask 接口 |
| **C-01b** | 训练库内容填充 | `resources/config/training-library.json` | 填充实际内容（等待 D 阶段蒸馏产出，C-01a 骨架就绪后直接填条目） |
| **C-02a** | 阅读任务库结构骨架 | `resources/config/reading-library.json`（新建） | 定义阅读库 JSON Schema，含 READING_STEPS（read_guide / analyze / submit） |
| | | `src/renderer/shared/types-training.ts` | READING_STEPS 常量已存在，验证可用 |
| **C-02b** | 阅读库内容填充 | `resources/config/reading-library.json` | 填充实际内容（等待 D 阶段产出） |

#### C 阶段 DoD 检查清单

- [ ] training-library.json 和 reading-library.json Schema 定义完成
- [ ] TrainingTask 接口类型定义完成
- [ ] READING_STEPS 常量验证可用
- [ ] 内容填充标记 READY 状态（哪些条目填充完成，哪些等待 D）

---

### 阶段 D：第三次蒸馏（核心前置）

> **背景**: 当前诊断/技法/教学库的准确性和覆盖率不足以支撑 S2_GUIDE 和 discoverable 判断。需通过第三次蒸馏（网络搜索 + 交叉验证）来提升。

| ID | 任务 | 描述 |
|:--:|------|------|
| **D-01** | 蒸馏先导探测 | 网络搜索约 100 条真实写作教学案例/素材，评估搜索质量、分类可用性、覆盖缺口。输出素材库+评估报告 |
| **D-02** | 症候映射蒸馏 | 以 D-01 素材库为基础，验证/扩展 `syndrome-type-map.json` 的症候定义和 mapping |
| **D-03** | 手法库交叉验证 | 验证/扩展 `technique-library.json` 条目 |
| **D-04** | 教学策略库验证 | 验证/扩展 `teaching-strategies.json` |
| **D-05** | 训练库验证 | 验证 C-01a/C-02a 骨架中的训练条目 |
| **D-06** | 症候↔技法映射验证 | 验证 `syndrome-action-map.json` 的症候↔技法映射完整性 |
| **D-07** | 教学法↔症候映射验证 | 验证 `teaching-strategies.json` 的教学策略↔症候关联 |

#### D 阶段 DoD 检查清单

- [ ] D-01 输出 100 条素材库 + 评估报告
- [ ] D-02~D-07 每个阶段输出对应 JSON 的更新 patch
- [ ] 蒸馏产物放入 `resources/distillation-versions/v3.1+/`
- [ ] 每次产物更新 manifest

---

### 阶段 E：遗留问题（穿插执行，与 A/B/C/D/F/G/H/I 并行无冲突）

| ID | 任务 | 改动位置 | 优先级 | 描述 |
|:--:|------|---------|:------:|------|
| **E-01** | `src/main/services/prompt-loader.ts` 行数超标 | `src/main/domains/prompt/` | P2 | 拆分 |
| **E-02** | `src/main/services/prompt-builder.ts` 行数超标 | `src/main/domains/prompt/` | P2 | 拆分 |
| **E-03** | `src/renderer/services/chat.service.ts` 行数超标 | `src/renderer/services/` | P2 | 拆分 |
| **E-04** | WCAG AA 对比度修复 + CI a11y 检测 | CSS 全局调色板 + axe-core CI | P1 | 颜色对比度修复 |
| **E-05** | 安装/构建脚本兼容性 | 待定 | P2 | 待排查 |
| **E-06** | 设置页面音色预览按钮失效 | 前面板设置 | P2 | 修复 |
| **E-07** | 阅读推荐闭环 | B-02 就绪后 | P1 | 阅读完成后自动推荐下一个训练 |
| **E-08** | 三 store 协调协议 + IPC 契约统一 + feature-flags | `src/shared/`, `src/renderer/stores/` | **P0** | **已提前到第一波** |

#### E-08 详细描述

**三 store 协调协议**: panelStore（右侧栏）、sessionStore（会话）、trainingStore（训练）之间的状态同步规则。每次状态变更时通过 IPC 广播 `store:sync` 事件，各 store 选择性消费。

**IPC 契约统一**: 清理 ConfigApi Contract 与 Handler 不匹配的问题。当前 Contract 是"未来设计"，Handler 是"当前实现"，两者 payload 格式不一致导致运行时错误。

**feature-flags**: 为所有本次重构的新功能添加 feature-flag 开关，支持逐功能灰度上线和回退。每个 feature-flag 在 `resources/config/feature-flags.json` 中定义。

#### E 阶段 DoD 检查清单

- [ ] E-01~E-03 文件拆分后单文件 <= 300 行
- [ ] E-04 WCAG AA 对比度检测通过
- [ ] E-06 音色预览按钮功能恢复
- [ ] E-07 阅读推荐闭环：阅读完成触发训练推荐
- [ ] E-08 三 store 协调协议文档完成 + IPC Contract 对齐 + feature-flags 配置就绪

---

### 阶段 F：右边栏渐进式披露（依赖 B 阶段 teachingState:updated 事件）

| ID | 任务 | 改动位置 | 描述 |
|:--:|------|---------|------|
| **F-01** | 侧边栏阶段管理（sidebarPhase） | `src/renderer/stores/panel-session.store.ts` | 新增 `sidebarPhase: 'guide' | 'reading' | 'training' | 'complete'`；消费 `teachingState:updated` 事件；按 phase 控制展示粒度 |
| **F-02** | "常见问题"渐进披露 | `src/renderer/components/panel/SyndromeCard.tsx` | 诊断结论附近加"常见问题"链接，点击展开。根据 B-01 的 needsGuidePhase 标志决定直接展示或 blurred 模式 |
| **F-03** | 训练卡延期 + 阅读提醒 | `src/renderer/components/panel/TrainingRecommendCard.tsx` + `ReadingTaskCard.tsx` | TEACHING 完成 → base_actions 解锁训练卡但不自动展开；ASSIGN_TASK → 训练卡自动展开；B-02 reading:assign 事件 → 阅读卡展开 |
| **F-04** | 分级提示 + 战争迷雾 | `src/renderer/components/panel/SyndromeCard.tsx` | 诊断结论初始完全遮罩隐藏，学生需点击「查看报告」并先写一段自我反思（>=50 字）后才擦除遮罩 |
| | | `src/renderer/components/panel/HintPanel.tsx` | 分级提示：训练阶段提示按三级解锁（L1 概念 → L2 策略 → L3 答案/范例），每级消耗提示点 |
| | | `src/renderer/stores/hint-store.ts`（新建） | 管理提示点数（初始 3，每级消耗 1/2/3 点） |

**F 阶段与 B 阶段的联动说明**:
- B-01 输出 `teachingState:updated` 事件 → F-01 消费，设置 sidebarPhase
- B-01 输出 `needsGuidePhase` 标志 → F-02 决定直接 or blurred 模式
- B-02 输出 `reading:assign` 事件 → F-03 切换到阅读卡

#### F 阶段 DoD 检查清单

- [ ] sidebarPhase 四种状态切换正确
- [ ] 诊断结论遮罩+反思擦除功能正常
- [ ] 分级提示三级解锁正常
- [ ] 提示点数管理正确

---

### 阶段 G：数据层改造（后端 DB + 配置 + 常量）

> **背景**: 2026-06-13 数据层兼容性审查结论——8 个数据层中仅训练记录需做 DB migration，其余均为 JSON 配置或 TypeScript 常量扩展。

| ID | 任务 | 改动位置 | 描述 |
|:--:|------|---------|------|
| **G-01** | DB Migration（task_type 列） | `src/main/core/app-initializer.ts` | `user_training_records` 表定义新增 `task_type TEXT NOT NULL DEFAULT 'writing' CHECK(task_type IN ('writing','reading','reflection','technique'))` |
| | | `src/main/db/020_db_add_task_type.sql`（新建） | `ALTER TABLE user_training_records ADD COLUMN task_type TEXT NOT NULL DEFAULT 'writing'` |
| | | `src/renderer/shared/types-training.ts` | TrainingRecord 接口新增 `taskType?: 'writing' | 'reading' | 'reflection' | 'technique'` |
| **G-02** | 训练记录契约/类型同步 | `src/shared/api-contracts/training.contract.ts` | TrainingRecord 类型同步新字段 |
| | | IPC handler | 读写路径覆盖新列 |
| **G-03** | TeachingState 常量层扩展（B-01 前置） | `src/shared/constants.ts` | 新增 `PRACTICE_GUIDE: 'S2_GUIDE'` 常量；`S2_SUBPHASES` 序列插入 `S2_GUIDE` |
| | | `src/shared/mappings.ts` | `SUBPHASE_TO_ACTIONS` 新增 S2_GUIDE 的动作映射 |
| **G-04** | 症候配置 discoverable 字段 | `resources/config/syndrome-action-map.json` | 每个症候 mapping 新增 `"discoverable": true/false/partial` |
| | | `resources/config/syndrome-type-map.json` | 同步增加 discoverable |
| **G-05** | 技法库 discoverable 字段 | `resources/config/technique-library.json` | 逐条标注 discoverable |
| **~~G-06~~** | ~~反思门控 index 偏移~~ | — | 🔴 **已移除** — indexOf() 动态计算确认无需修正 |
| **G-07** | 操作审计日志 | `src/main/services/audit-log.service.ts`（新建） | 记录每次诊断/训练/阅读操作的完整链路 |
| | | SQLite 表 `audit_logs` | 审计日志独立存储 |

**G 阶段依赖说明**:
- G-01/G-02（DB Migration）—— 独立，可最先执行
- G-03（常量层）—— 是 B-01 的前置依赖
- G-04/G-05（JSON 配置）—— 独立，可与 G-03 并行
- G-06（反思门控）—— 🔴 已移除
- G-07（审计日志）—— 独立，建议在 E-08 IPC 契约统一后执行

#### G 阶段 DoD 检查清单

- [ ] G-01: DB migration 脚本存在（ALTER TABLE + 默认值），TaskType 枚举 4 种，类型同步
- [ ] G-02: Contract 与 Handler 对齐
- [ ] G-03: 常量定义正确，SUBPHASE_NAMES 含"引导发现"
- [ ] G-04/G-05: 症候和技法全部完成 discoverable 标注（30-40% true，其余 false/partial）
- [ ] G-07: 审计日志异步写入不阻塞主流程

---

### 阶段 H：右边栏标签页重构（前端 UI）

| ID | 任务 | 改动位置 | 描述 |
|:--:|------|---------|------|
| **H-01** | 删除「教学任务」标签页 | 右边栏 TabBar 组件 | 直接移除空标签 |
| **H-02** | 重命名「成长记录」为「诊断对比」 | 右边栏 TabBar 组件 | 展示学员症候地图纵向对比 |
| **H-03** | 实现「诊断对比」视图 | 右边栏 `DiagnosisComparisonView` | 渲染症候地图纵向对比图表 |

#### H 阶段 DoD 检查清单

- [ ] H-01: 空标签页已删除，无残留
- [ ] H-02: 标签重命名完成
- [ ] H-03: 诊断对比视图渲染正确

---

### 阶段 I：对话栏按钮精简 + 模板辅助系统（前端 UI）

| ID | 任务 | 改动位置 | 描述 |
|:--:|------|---------|------|
| **I-01** | 删除四个无效按钮 | 对话栏按钮组件 | 移除「提问」「上传片段」「可立即练习」「持续进步」，保留「模板辅助」 |
| **I-02** | 模板辅助弹出模板选择 | 对话栏 + 右边栏 | 点击弹出 5 类模板选择 |
| **I-03** | 模板驱动 sidebar 状态管理 | `panel-session.store.ts` | 新增 `sidebarMode: 'default' | 'template' | 'comparison'` |
| **I-04** | 模板表单随对话渐进填充 | 模板表单视图 | 表单字段随对话上下文逐步自动填充 |

#### I 阶段 DoD 检查清单

- [ ] I-01: 对话栏仅保留一个按钮
- [ ] I-02: 模板选择弹出正常
- [ ] I-03: sidebarMode 与 sidebarPhase（F-01）正交
- [ ] I-04: 表单字段自动填充正确

---

## §三 依赖关系与执行顺序

### 完整依赖图

```
A-01 teaching-rules.json ─── 独立 ───→ 可立即执行
A-02 attitude-rhythm.json ── 独立 ───→ 可立即执行
A-03 feedback-structure.json ── 独立 ─→ 可立即执行
A-04 角色 Skill 拆分 ── 独立 ───→ 可立即执行
A-05 配置驱动验证器 ── 独立 ───→ 可立即执行（依赖 A-01~A-04 规则就绪后编写用例）
     │
     ├──→ G-01/G-02 DB Migration ── 独立，可先执行
     ├──→ G-03 常量层 ── 是 B-01 的前置，B-01 编码前完成
     ├──→ G-04/G-05 JSON 配置 ── 独立，与 G-03 并行
     ├──→ G-07 审计日志 ── 独立，建议在 E-08 IPC 契约统一后执行
     │
     ├──→ B-01 S2_GUIDE 状态机 ──→ B-02 阅读前置决策点 ──→ F 右边栏渐进式披露 ←──→
     │         （依赖 G-03 + B-01 teachingState:updated 事件）
     │               └──→ B-02 reading:assign 事件
     │
     ├── D-01~D-07 第三次蒸馏（核心前置，与 A/B 并行）
     │   │
     │   └──→ C-01b 训练库内容填充（等待 D 核心产出）
     │   └──→ C-02b 阅读库内容填充（等待 D 核心产出）
     │
     ├── C-01a 通用训练库结构骨架（独立，内容填充等 D）
     ├── C-02a 阅读任务库结构骨架（独立，内容填充等 D）
     │
     └── E 系列
           ├── E-04（P1，WCAG AA 对比度修复 + CI a11y 检测）
           ├── E-07（P1，依赖 B-02 阅读前置落地后实现阅读推荐闭环）
           └── E-08（P0，三 store 协调协议 + IPC 契约统一 + feature-flags 渐进上线）

H-01 删除空标签页 ── 零依赖，第一波执行
H-02/H-03 ── 无强依赖，与 F 阶段并行

I-01~I-04 对话栏按钮精简 + 模板辅助 ── 独立
   I-03 sidebarMode 与 F-01 sidebarPhase 正交
   建议在 E-08 store 协调协议落地后再改 panelStore
```

### 推荐执行顺序

```
第一波（全并行）：
  A-01 + A-02 + A-03 + A-04 + A-05 + G-01 + G-02 + G-04 + G-05 + H-01
  （Skill化 规则提取 + 配置化 + DB Migration + JSON 配置 + 右边栏空标签页删除）
  H-01（删除空标签页）零依赖，提前到第一波

第二波（顺序）：
  G-03（常量层，B-01 的前置依赖）

第三波（并行）：
  B-01 + C-01a + C-02a
  （状态机改造 + 训练/阅读库结构骨架，内容填充等待 D）
  D-01 蒸馏先导探测（网络搜索，可提前）

第四波（并行）：
  B-02 + F-01
  （阅读前置 + 侧边栏阶段管理）
  原先的 G-06 反思门控已移除 — indexOf 动态计算无需修正

第五波（并行）：
  F-02 + F-03 + F-04 + C-01b + C-02b + H-02 + H-03 + G-07
  （渐进式披露 + 分级提示/战争迷雾 + 训练/阅读库内容填充 + 诊断对比视图 + 审计日志）

第六波（并行）：
  I-01 + I-02 + I-03 + I-04 + E-07 + E-08
  （模板辅助系统 + 阅读推荐闭环 + 三 store 协调协议 + IPC 契约统一）

E-01~E-06（含 E-04 WCAG AA 修复）穿插在间隙执行
```

---

## §四 自评审查要点

### 审查通过条件

- 每个任务的 DoD 完成即可视为该任务完成
- 无跨阶段阻塞绿灯：A 不阻塞 B（B 只依赖 G-03），D 不阻塞 B（B 的 discoverable 阈值独立于 D）
- 每个 feature-flag 独立开关，可逐功能上线和回退
- DB Migration 可逆向回滚（保留 rollback 脚本）

### 审查通过后可即刻开始执行

---

## §五 当前状态

| 阶段 | 状态 | 备注 |
|:----:|:----:|------|
| A-01 【Skill化】teaching-rules.json 规则提取 | 待审查 | 将 V-01~V-09 从 v3.md 提取为结构化配置；v3.md §八 精简为引用段 |
| A-02 【Skill化】attitude-rhythm.json 规则提取 | 待审查 | 态度↔节奏映射从 v3.md §五 提取为配置；PromptBuilder 从配置读取 |
| A-03 【Skill化】feedback-structure.json 规则提取 | 待审查 | 三明治反馈话术结构提取为配置；v3.md 改为占位符引用 |
| A-04 【Skill化】角色 Skill 拆分 | 待审查 | 三分 Prompt → 三 Skill 边界定义（skill.json + 知识范围 + 上下文裁剪） |
| A-05 【Skill化】配置驱动输出验证器 | 待审查 | 读取 A-01~A-04 配置做验证，新增规则只需改配置无需改代码 |
| B-01 S2_GUIDE 状态机 | 已审查 | 按症候选择性进 GUIDE；新增敷衍检测退出条件；DoD 新增纯函数路由 |
| B-02 阅读前置决策点 | 已审查 | 依赖 B-01 就绪 |
| C-01a 训练库结构骨架 | 已审查 | 独立，不依赖 D；与 C-01b 分开 DoD |
| C-01b 训练库内容填充 | 已审查 | 等待 D 核心产出 |
| C-02a 阅读库结构骨架 | 已审查 | 独立，不依赖 D；与 C-02b 分开 DoD |
| C-02b 阅读库内容填充 | 已审查 | 等待 D 核心产出 |
| D-01 蒸馏先导（网络搜索） | 已审查 | D-01 先行探测，搜索结果决定后续细节 |
| D-02~D-07 蒸馏全量 | 已审查 | 等待 D-01 结果后细化方案 |
| F-01 侧边栏阶段管理 | 已审查 | sidebarPhase 与 sidebarMode 正交 |
| F-02 "常见问题"渐进披露 | 已审查 | 依赖 F-01 + B-01 needsGuidePhase 标志 |
| F-03 训练卡延期 + 阅读提醒 | 已审查 | 依赖 F-01 + B-02 reading:assign 事件 |
| F-04 分级提示 + 战争迷雾 | 待审查 | 依赖 F-01 + F-02 |
| G-01 DB Migration（task_type） | 已审查 | 独立，可最先执行 |
| G-02 训练记录契约/类型同步 | 已审查 | 依赖 G-01 |
| G-03 TeachingState 常量层扩展 | 已审查 | B-01 的前置依赖 |
| G-04 症候配置 discoverable | 已审查 | 独立，JSON 配置 |
| G-05 技法库 discoverable | 已审查 | 独立，JSON 配置 |
| G-07 操作审计日志 | 待审查 | 独立，建议在 E-08 IPC 契约统一后执行 |
| E-01~E-08 遗留问题 | 已审查 | E-04 为 P1（WCAG AA + CI a11y），E-07/E-08 上调至 P1/P0 |
| H-01 删除空标签页 | 已审查 | 提前到第一波执行，零依赖 |
| H-02 重命名成长记录 | 已审查 | 无强依赖 |
| H-03 诊断对比视图 | 已审查 | 需补充数据源预研步骤 |
| I-01~I-04 对话栏按钮/模板辅助 | 已审查 | I-03 sidebarMode 与 F-01 sidebarPhase 正交确认 |
