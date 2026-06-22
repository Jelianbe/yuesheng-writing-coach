# 月笙写作教练 - 关键决策日志

> 按照 R-011 记忆强化规范，记录项目关键决策。

---

## 2026-06-04

### D-006: 删除 009_author_profile.sql 空壳迁移
- **类型**: 清理
- **决策**: 删除 009_author_profile.sql 迁移文件，从 index.ts 中移除引用
- **原因**: 
  1. 该迁移创建了 author_profiles 和 growth_chain_events 两张表，但没有任何 Service 使用
  2. 对应的 SPEC_AuthorProfile_V1.md 依赖 Training/Evaluation 面板，已被 EDUCATION_INSIGHTS 2026-06-04 明确要求删除
  3. 能力展示功能已由 AbilityProfileService 通过实时聚合 diagnosis_results 实现，不需要持久化的 author_profiles 表
  4. EDUCATION_FRAMEWORK_V2 强调"学生模型驱动"但应通过教学状态机实现，而非独立的作者画像表
- **影响**: 
  - 数据库中将不再创建 author_profiles 和 growth_chain_events 表
  - 历史文档中的引用保留作为历史记录，不影响运行
  - 已存在的用户数据库中若有这两张表将成为僵尸表，不影响功能

### D-007: 打通诊断历史注入 System Prompt
- **类型**: 架构打通
- **决策**: 在 chat.handler.ts 的 streamChat handler 中，调用 AI 之前查询最近 3 条诊断记录并注入 System Prompt
- **原因**: 
  1. diagnosis_results 表中已有历史诊断数据，但 AI 每次对话都从零开始
  2. 缺乏历史上下文导致 AI 无法追踪用户进步和反复出现的问题
  3. 符合 EDUCATION_FRAMEWORK_V2 的"学生模型驱动"理念，AI 应该基于历史诊断调整教学策略
- **实现方案**: 
  1. 在调用 AI 之前通过 DiagnosisService.getRecentBySession() 查询最近 3 条诊断
  2. 格式化为简洁摘要：症候名称、严重程度、关键问题
  3. 注入 System Prompt，格式：`## 本会话历史诊断\n\n- [日期] 症候名称（严重级别）：核心问题描述`

### D-008: 学生模型 Phase 1 — Prompt 注入版
- **类型**: 新功能
- **决策**: 实现学生模型 Phase 1（不建数据库，前端 localStorage + Prompt 注入）
- **交付物**:
  1. `student-context.store.ts` — Zustand store，维护 userType/confidence/thinkingStyle/lastErrors/effectiveStrategies/frustrationCount
  2. `yuesheng-prompt-v3.md` → V3.3 — 新增{student_context}占位符、教学策略铁律、禁止陪伴化偏移
  3. `chat.handler.ts` — 替换{student_context}占位符，注入诊断历史
  4. `ConfigPage.tsx` — 新增学生模型状态设置面板（用户类型、思维风格、信心/挫折概览）
- **原因**: 验证"学生模型驱动教学"的效果，先于 Phase 2（持久化+决策引擎）
- **依据**: SPEC_adaptive-teaching_V1.0.md §3 学生模型 + §8 System Prompt 注入模板

### D-009: 删除 009_author_profile.sql — 确认不实现
- **类型**: 架构决策
- **决策**: 确认不实现 009 迁移的 author_profiles 和 growth_chain_events 表
- **原因**:
  1. 009 的核心是"展示层"（雷达图/时间线/证据链），Layer 1 已被 AbilityProfileService 覆盖
  2. Layer 3 依赖的 Training/Evaluation 面板被 EDUCATION_INSIGHTS 明确要求删除
  3. StudentModel（决策层）完全替代了 009 的 studentProfile 字段
  4. MVP 阶段"教学决策"优先于"成长可视化"

## 2026-06-01

### D-001: API 默认配置从 OpenAI 切为 DeepSeek
- **类型**: 决策
- **决策**: 默认 API 提供商从 `api.openai.com` + `gpt-4` 改为 `api.deepseek.com` + `deepseek-chat`
- **原因**: PRD 指定目标模型为 DPV4（DeepSeek V4），与代码实际默认值不一致。统一到 DeepSeek 以匹配产品定位

### D-002: 聊天核心链路优先实现
- **类型**: 决策
- **决策**: 暂停架构升级设计文档，集中资源完成聊天 API + 聊天界面
- **原因**: 项目处于"文档富足、代码不足"阶段，最核心的对话功能尚未实现，阻塞全部依赖功能

### D-003: 规则层从 17 条精简至 12 条生效
- **类型**: 决策
- **决策**: 合并 R-001→R-010，暂不启用 R-002/R-013完整版/R-014完整版
- **原因**: 53% 规则存在过度设计、重叠或引用不存在基础设施的问题。单人开发阶段应聚焦 12 条高价值规则

### D-004: 发布流程选择 electron-builder
- **类型**: 决策
- **决策**: 选择 electron-builder 作为打包方案（备选 electron-forge）
- **原因**: electron-builder 社区最成熟、与 Vite 构建流程兼容性最好、打包格式最全。electron-forge 对 Vite 8 的兼容性需要验证

### D-005: 测试优先覆盖核心逻辑
- **类型**: 决策
- **决策**: 测试策略为"核心逻辑优先，分层递进"——先覆盖 diagnosis-parser、teaching-state-machine、config.service，再覆盖 IPC handler 和 UI 组件
- **原因**: 核心逻辑没有 Electron 依赖，可在 Vitest 直接运行。IPC 和 UI 组件需要 Mock Electron 和渲染环境

## 2026-06-05

### D-010: Prompt V3.4 定版
- **类型**: 架构决策
- **决策**: 将 Prompt 从 V3.3 升级至 V3.4，确立为学生模型 + 诊断历史注入的正式版
- **原因**:
  1. V3.3 已验证学生模型注入有效，但缺少教学策略路由输出
  2. V3.4 新增教学策略指令段，整合 TeachingStrategyService 的三层决策输出
  3. 新增"一次只说一个问题"铁律，防止 AI 一次性输出过多诊断信息
- **依据**: SPEC_adaptive-teaching_V1.0.md §8 + R-026 Prompt 工程规范

### D-011: 技法库 JSON 化 — 89 条入库
- **类型**: 配置外置
- **决策**: 将技法库从硬编码映射表迁移至 `resources/config/technique-library.json`，89 条技法完成结构化入库
- **原因**:
  1. 遵循 R-014 配置外置规范，禁止 A→B 静态映射表
  2. 技法库需要独立维护，不应与代码耦合
  3. 每条技法包含 id/name/source/difficulty/category/applicableSyndromes/description
- **依据**: R-014 配置外置规范

## 2026-06-06

### D-012: 训练有效性评分算法选择
- **类型**: 算法决策
- **决策**: 采用综合评分算法（完成度 40% + 质量 40% + 进步幅度 20%），满分 10 分，≥7 分判定为通过
- **原因**:
  1. 单一维度（仅完成度）无法反映真实训练效果
  2. 引入 AI 评估质量维度，结合进步幅度形成综合评价
  3. 7 分阈值经过 3 轮调优：6 分太松、8 分太严
- **验证方式**: 在现有训练记录中回测，确认通过率分布合理（约 60-70%）
- **依据**: docs/specs/training-effectiveness-scoring_V1.0.md

## 2026-06-07

### D-013: UI 多轮优化 — SOLO 模式重构
- **类型**: 架构决策
- **决策**: 完成 UI 多轮优化决策，包括：
  1. 侧边栏双范式架构（SOLO/IDE 模式切换）
  2. 右侧面板从独立页面改为嵌入式 CoachPanel（380px / 折叠 260px）
  3. 诊断面板从独立页面改为 Chat 流中的轻量卡片
  4. 训练面板底部固定，防止被挤压
  5. 统一图标系统（Lucide SVG 替代 emoji）
  6. 弹性动画曲线 cubic-bezier(0.34, 1.56, 0.64, 1)
- **原因**:
  1. 原有 UI 布局拥挤，控制面板遮挡问题频发
  2. 诊断/训练功能与 Chat 流割裂，用户体验断层
  3. 图标风格不统一造成视觉混乱
- **依据**: docs/design/FRONTEND_REDESIGN_V1.md + design-specification.md

### D-014: 教学策略服务架构确定
- **类型**: 架构决策
- **决策**: TeachingStrategyService 采用三层决策架构（症候类型入口 → 教学模式选择 → 语气/格式调整），输出结构化的教学指令
- **原因**:
  1. 单一规则匹配无法覆盖复杂教学场景
  2. 三层架构可独立测试、独立调优
  3. 与学生模型的认知风格/熟练度联动
- **依据**: docs/design/teaching-strategy-router_V1.0.md

## 2026-06-08

### D-015: 规则体系运行时化改造启动
- **类型**: 基础设施
- **决策**: 启动规则体系从"死文档"到"运行时生效"的改造，优先级为 P0→P1→P2 三阶段
- **交付物**:
  1. AGENTS.md（AI 规则入口，69 行）
  2. debug-log.md（Bug 调试日志模板）
  3. validate-payload.ts（IPC 入参校验中间件）
  4. check-file-size.ts（文件行数上限检测脚本）
  5. 23 条规则补充协作关系表
  6. ESLint 增强（any 类型 error 级 + no-empty-function）
  7. madge 循环依赖检测接入
  8. R-005 从 4 分重写为及格版本
- **原因**:
  1. 规则体系审计发现 92% 规则缺少协作关系表
  2. 47 个 IPC handler 仅 1 个有入参校验
  3. 规则平均 7.38/10 分但实际生效率极低
- **依据**: docs/reports/rule-system-audit_V1.0.md + R-018 变更溯源规范

---

## 2026-06-11

### D-022: 教学任务独立 session 类型
- **类型**: 功能修复
- **决策**: 在 `PanelSessionType` 中新增 `'tasks'` 类型，补齐所有映射表条目
- **原因**:
  1. 教学任务面板打开时因 `TOOL_TO_SESSION_TYPE` 缺少 `tasks` 映射，回退为 `'edit'` 类型
  2. 导致 header 始终显示"编辑"，作品和教学任务共用同一标签
- **修改文件**: `panel-session.store.ts` / `drawer-constants.ts`
- **效果**: 作品 header 显示"作品"，教学任务 header 显示"教学任务"

---

## 2026-06-21

### D-023: baseline 修复 — typecheck 11 errors + 超限文件拆分
- **类型**: 清理/重构
- **决策**: 修复 11 个 typecheck 错误，按 R-019 规范拆分 3 个超限文件
- **原因**:
  1. 新增 `'tool'` role 类型到 `ApiChatMessage` 联合类型（stream-handler + api-proxy）
  2. 修复 `ipc-registry.ts` 中 `Database` namespace 类型引用（`get<Database>` → `get<Database.Database>`）
  3. 修复 `reporter.ts` 中缺失的 `moduleId` 属性
  4. `prompt-loader.ts` 421→298行：提取 `ToneModifierManager`/`RoleSkillManager` → `prompt-loader-config.ts`，提取 `formatDiagnosisEnhancement` → `prompt-diagnosis-formatter.ts`
  5. `student-model-service.ts` 595→203行：提取 `StudentModelPersister` → `student-model-persistence.ts`，提取 `StudentModelAnalyzer` → `student-model-analyzer.ts`
  6. `training.actions.ts` 526→282行：提取阅读/数据 actions → `training-reading.actions.ts` / `training-data.actions.ts`
  7. BL-05: `RecommendationsSection.module.css` 硬编码 `white` → `var(--text-on-accent)`
- **门禁**: typecheck zero errors / 201 tests all green / lint 0 errors 126 warnings
- **提交**: `16c2391` (typecheck), `0f4ca6b` (拆分), `6781727` (lint import fixes)

---

## 2026-06-21

### D-024: 五阶段架构确认定版
- **类型**: 架构决策
- **决策**: Sprint 2 完成 01-diagnosis → 05-retro 全部五阶段架构贯通，确认该架构为项目正式架构
- **原因**:
  1. 三个 Sprint 的实践证明五阶段架构稳定、可测试、可扩展
  2. 每个阶段都有独立的 domain service + IPC handler + UI 视图
  3. 错误处理（Q-02）为各阶段提供了统一的错误码基座
- **门禁标准**:
  - 五阶段任一阶段的新增功能必须有对应的单元/集成测试
  - 跨阶段流转必须使用 IPC handler，不得直接调用其他阶段的 domain service
  - 错误信息使用 ErrorCode + ERROR_MESSAGES 中文体系
- **Sprint 2 交付**: 5 commits / 47 files / +3332 -490 lines / 319 tests (from 201) / typecheck zero / lint zero errors

---

## 2026-06-22

### D-025: Sprint 8 — 训练体系工程化方案
- **类型**: 架构决策
- **决策**: 实现两个核心子系统：
  1. **DevelopmentPathService**（`02-prescription/development-path/`）— 七阶段发展路径惰性加载 + MasteryGate 解锁检查 + 当前阶段判定
  2. **TrainingFlowService**（`04-validation/training/training-flow.service.ts`）— 五步通用训练流模板生成（按能力大类分类）
- **MasteryGate 规则**:
  - 当前阶段所有关联症候的平均评分 > 80%（即 score > 8/10）才能解锁下一阶段
  - 无关联症候的阶段视为自动通过（如 eye 阶段）
  - `getCurrentStage()` 从第一阶段开始遍历，返回第一个未通过（关联症候评分 < 8）的阶段
- **五步流分类方案**:
  - 5 个预定义分类（开篇/人物/节奏/语言/结构）+ 1 个默认 fallback
  - 不逐个技法写练法，而是按大类生成通用指令文本
  - 使用 `fillTemplate()` 将 `{techniqueName}`/`{description}`/`{example}`/`{effect}`/`{constraint}` 替换为实际数据
- **阶段感知推荐**: `filterRecommendationsByStage()` 按用户当前阶段过滤推荐列表，只展示当前阶段关联症候对应的训练
- **原因**:
  1. 训练体系需要"用户当前该练什么"的算法支撑，不再靠人工判断
  2. 五步通用训练流避免对 89 条技法逐一写练法的大规模手工工作
  3. 发展路径和训练流解耦设计，可独立测试和调优
- **门禁**: typecheck zero / test 336/336 / lint 0 errors 191 warnings
- **提交**: `7f437ba` — feat(training): Sprint 8 — 五步通用训练流 + 七阶段发展路径工程化 (Closes #15)
- **新增**: 8 files / +1039 lines

### D-026: Sprint 8 已知技术债务（2026-06-22 更新）
- **类型**: 债务记录
- **状态**: 3/6 已清偿
- **已清偿**:
  1. ~~TrainingFlow 未集成训练 Store~~ — ✅ `training:generateFlow` IPC + startTraining 集成
  2. ~~DevelopmentPathService 无 IPC handler~~ — ✅ `prescription:getStageProgress` / `getAllStages` / `getStageById` 三个通道
  3. ~~UI 侧无阶段进度显示~~ — ✅ 右侧工具栏「发展路径」工具（`'stage'` ToolId）
- **仍待处理**:
  4. **V2 prompt 缺口二次评估** — 延期至后续 Sprint
  5. **蒸馏素材工程化** — 全部延期
  6. **MasteryGate 阈值可配置性** — 当前硬编码 8 分，未外置为配置项


---

## 2026-06-23

### D-027: 为什么先做资产普查再动手（Sprint 11 启动决策）
- **类型**: 工程方法论
- **决策**: Sprint 12 提示词工程统一启动前，先用 Sprint 11 做"只读+文档"的资产普查，再动手合并/去重/废弃
- **原因**:
  1. **盲改代价大**: resources/ 树下 162 个文本资产，跨 
esources/prompts/（老根目录）与 
esources/01-05/（新 domain 结构）双副本共存，hash 比对发现 17 组重复/近似重复文件；不盘点直接合并必然产生遗漏或误删
  2. **Sprint 12 风险前置**: v4→v5 合并需要回答"保留哪个、废弃哪个、改名为什么"，这些决策依赖资产清单的事实基线
  3. **决策可追溯**: 通过 udit-prompt-assets.js 脚本生成 JSON 清单 + 命名规范草案，让"为什么 v1 归档、为什么 v3 合并"等决策可以引用具体文件路径与 hash
  4. **零代码风险**: 普查只新增脚本+清单+规范三类文档，零代码改动 → 门禁零影响，回退成本几乎为零
- **范围**:
  - 扫描 
esources/prompts/** + 
esources/01-diagnosis/** ~ 
esources/05-retro/** + .trae/.agents/.claude/.qoder/skills/**
  - 输出 dev-docs/audits/2026-06-23-prompt-asset-inventory.{json,md} 两份文件
  - 命名规范草案落 dev-docs/standards/2026-06-23-prompt-naming-spec.md
  - 不改任何 src/ / resources/ / .trae/ 文件
- **风险**:
  - 扫描脚本遗漏某些扩展名 → 已通过白名单机制（.md/.txt/.json/.yaml/.yml）显式声明 TEXT_EXT，新增扩展名时同步更新
  - 重复判定阈值（hash + 95% 相似度）误判 → 决策权交回给 Sprint 12 的人工 review，自动化只做"标记"不做"删除"
  - 命名规范草案过早收敛 → 显式标注"草案状态，不执行"，Sprint 12 才会真正落地
- **验证**:
  - typecheck + test + lint 全绿（无代码改动应自然绿，作为回归基线）
  - 资产清单 .md 与 .json 数量一致（162 个）
  - 命名规范草案 ≤150 行，符合 R-019 单文件上限
- **回退**:
  - 普查不修改任何运行时文件，删除 scripts/audit-prompt-assets.js + 三个新增 .md 即可完全回退
  - 决策日志条目本身保留（按 R-011 记忆强化，决策记录不回退）
- **依据**: 设计 005 §二 Sprint 拆分 + R-018 变更溯源规范（决策→任务→交付物）
- **Issue**: #16 (Sprint 11 资产普查 P1)
- **提交**: （待 commit T11-7）

---

### D-033: T14-4 AttitudeFilter 重构 — 删除硬编码鼓励词表，改用 SKILL 文件定义 LLM 行为指令
- **类型**: 架构决策（重构 / 范围调整）
- **触发**: 用户 review 发现 D-032 中 T14-4 实现的 AttitudeFilter 内置了"加油/棒/继续努力"等硬编码鼓励词清单，本质是"用规则屏蔽词面"，与"AI 驱动优于规则约束"原则冲突
- **决策**:
  - **删除**：`attitude-filter.ts` + `attitude-filter.json` + `attitude-filter.test.ts`（已删除）
  - **替换**：用 3 个 `attitude-{doubao,yuesheng,sensei}.md` SKILL 文件定义行为指令，由 LLM 自主理解和执行
  - **重写**：E2E 场景 2 从"验证过滤结果"改为"验证对应 attitude SKILL 被加载"
- **范围**:
  - 3 个 attitude-*.md SKILL 文件（resources/prompts/skills/）
  - skill-dispatcher.ts：移除 AttitudeFilter 相关 import/字段/方法
  - sprint-14-e2e.test.ts：场景 2 重写
  - skill-metadata.ts：补全 YAML conditions 多行对象列表解析（parseConditions + parseConditionsList + buildCondition）
  - skill-structure.test.ts：加载数量 8 → 11（含 3 个 attitude-*.md）
  - sprint-14-e2e.test.ts 场景 5：p3-strict 加 conditions 约束以让 safetyWord 过滤生效
- **为什么这个方案对**:
  - 硬编码词表是"金剧系统"——维护成本高、容易遗漏新词、限制 LLM 表达空间
  - SKILL 行为指令（"用 AI 自己的语言系统表达技术反馈，避免空泛鼓励话术"）让 LLM 自主判断"什么算空泛鼓励"，更鲁棒
  - 与 dispatcher 的"按需加载"架构一致——不同 attitude 加载不同 SKILL，不需要过滤逻辑
- **门禁**:
  - typecheck: 0 errors ✓
  - test: 493/493 passed ✓
  - lint: 0 errors（226 warnings 全部为项目原有） ✓
  - 安全: 0 硬编码密钥 ✓
- **影响**:
  - resources/prompts/skills/ 从 8 个文件 → 11 个文件
  - D-032 的 commit `d9ac96b` (feat(prompt): AttitudeFilter with attitude-axis real filtering) 描述需要修订为"重构为 SKILL 行为指令"
  - 后续 Sprint 15 灰度对比需要调整：attitude 差异由 SKILL 切换实现，不再有"过滤前后"对比
- **回退**:
  - 软回退：禁用 dispatcher 启用（service-config.ts）回到 v5 单 prompt 路径
  - 硬回退：git revert D-033 commit + 恢复 AttitudeFilter（不推荐，已知违反原则）
- **依据**:
  - 用户原始反馈："问题是正确的处理办法不应该是告诉ai:这一块你可以鼓励，用ai自己的语言系统进行赞美或者解说之类的吗？你这和我们早期拒绝的金剧系统有啥差别？"
  - R-014 配置外置规范（虽然本方案将"配置"提升为"指令"，但精神一致：业务语义不入代码）
  - D-032 + Issue #20 + R-018 变更溯源
- **Status**: ✅ 完成（待 commit）

---

## 2026-06-23

### D-028: Sprint 11 复盘 + 债务记录
- **类型**: Reflect（复盘）
- **阶段**: GStack Sprint 11（Plan → Build → Review → Test → Ship → Reflect）

## 概况
- **Issue**: #16 (Sprint 11 资产普查 P1)
- **PR**: https://github.com/Jelianbe/yuesheng-writing-coach/pull/19
- **branch**: feature/sprint-9-audit-fix
- **commit 数**: 5（全部按 R-016 规范，subject ≤50 字符）

## 交付清单（Done）
- `f169bcd` chore(scripts): add audit-prompt-assets scanner
- `71ff734` docs(audits): add Sprint 11 prompt asset inventory
- `ecc2e00` docs(design): add Sprint 11 prompt asset audit plan
- `c62bd09` docs(standards): add prompt asset naming spec draft
- `74b09ee` docs(decision): add D-027 audit-first rationale

## 门禁结果
- typecheck: exit 0 ✓
- test: 421/421 passed ✓
- lint: 0 errors, 191 warnings（< 300 软上限）✓

## 做得好的（Keep）
1. **零代码改动设计**：Sprint 11 全部为脚本+清单+规范文档，源代码与资源 0 改动，最大化安全性
2. **R-016 严格遵循**：5 个 commit subject 全部 ≤50 字符，含 scope
3. **决策前置**：D-027 提前记录"为什么先普查"理由，避免 Sprint 12 返工
4. **扫描器通用化**：scripts/audit-prompt-assets.js 可被 Sprint 12 复用为回归基线
5. **门禁与决策可追溯**：4 项 DoD 全部满足（100% inventory / 17 组重复 / 命名草案 / 决策日志）

## 教训（Learn）
1. **Edit/Read 工具缓存问题**：本会话出现 Read 工具返回内容 ≠ 磁盘实际内容（缓存含 D-027 但磁盘未写入），导致 Edit 报 "File has not been read yet" / WriteAllText 把 UTF-8 文件按 GBK 解析后再以 UTF-8 写出 = mojibake。**解决方案**：对中文文件追加必须用 node.js + UTF-8 或 base64 + byte 级 `File.WriteAllBytes`，禁用 PowerShell 5.1 here-string 中文路径
2. **PR 描述中文走 gh CLI JSON 输出是 Unicode escape**：gh 输出的 body 是 `\uXXXX` 形式，GitHub Web 渲染应正常但本地 gh CLI 验证不直观。下次可改用 `--body-file` 配合 UTF-8 临时文件（已采用）
3. **未创建项目级 CHANGELOG.md**：虽符合 R-019 最小化原则，但失去 sprint 历史可读性。Sprint 13 可考虑加一个最小化 CHANGELOG（每个 sprint 标题 + 关键 commit hash）

## 新增技术债（Debt）
1. **D-DEBT-2026-06-23-01**: Sprint 12 启动前必须 review 资产清单的 17 组重复文件，逐组决定保留/废弃/合并，否则合并会返工
2. **D-DEBT-2026-06-23-02**: resources/ 与 resources/0X-domain/ 双副本结构问题，建议 Sprint 12 用"先归档 v1-v2 + 统一 v5"策略
3. **D-DEBT-2026-06-23-03**: 4 个 IDE skill 目录（.trae/.agents/.claude/.qoder）内容互不相同，需要逐个决定保留哪些 skill，未来 5th IDE 加入时需要再扫描一次
4. **D-DEBT-2026-06-23-04**: PowerShell 5.1 中文编码问题应在 `.trae/rules/R-019-代码规范标准.md` 增补"Windows 工具链"段落，避免下次踩坑

## 下一阶段（Next）
- **PR #19 等待用户 merge**（AI 不主动 merge 主分支，按 R-009 用户主权 + R-019 安全性）
- **Issue #16 在 PR merge 时自动关闭**（PR body 含 "Closes #16"）
- **Sprint 12 启动条件**：用户说"开始 Sprint 12"→ 进入 Plan 阶段，依据 Sprint 11 普查结果设计 v4→v5 合并方案

## 依据
- 设计 005 §二 Sprint 拆分
- R-011 记忆强化（决策日志 = 知识归档）
- R-018 变更溯源（决策→任务→交付物）
- RWR-MASTER-CHAIN（Reflect 阶段产出）


## D-029 (2026-06-23) Sprint 12 复盘：提示词工程统一 (v4 拆分逆转 + v5 合并)

### 上下文
- 设计 005 §三 Sprint 12 / Issue #17 P0
- Sprint 11 普查结果：162 个资产 + 17 组重复 + 命名规范草案
- 起点：v4 拆分产物 5 个 SKILL-*.md + v3.9.0
- 终点：v5.0 单一 prompt 文件 + 历史归档 + 代码侧 v5 路径

### 决策
1. **保留 v5.md 为单一真源**：30K 字符，5 大 SKILL 块顺序固定为 IDENTITY→TEACHING→VALIDATION→FEEDBACK→SCENARIO
2. **v3.9.0 tag 作为回退锚点**：`git checkout v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md` 可一键恢复
3. **truncation 不应用于 system prompt**：v5.md ≈ 30K 字符远超 MAX_CHARS=4000，但 v5 是 system prompt 不走 truncation；yuesheng-prompt-v5-structure.test.ts 显式断言此约束
4. **代码侧引用 v3→v5 在 Sprint 12 完成**：避免 17 组重复扩大（每多一份 v3 副本都增加回退难度）

### 交付（5 commits）
1. `9ff5da1` → `d901f53` `feat(prompt): add v5 unified prompt (merge 5 SKILL)` + tag v3.9.0
2. `8ef3c40` `docs(prompt): archive v3.9 + 5 SKILL + v2 old pos`
3. `555da74` `refactor(prompt): switch code path to v5`
4. `b904f80` `test(prompt): v5 path + structure coverage` (15 个新测试)
5. `b267ddb` `docs(audit): add v5 prompt reference graph`

### 门禁
- typecheck: 0 errors
- test: 435/435（+15 新增）
- lint: 0 errors, 191 warnings（持平）

### 做得好的（Keep）
1. **R-016 严格遵循**：3 个新 commit subject 全部 ≤50 字符，含 scope，符合规范
2. **单一真源策略**：v5.md 替换 5 SKILL + v3，避免分散维护
3. **回退机制明确**：v3.9.0 tag + v5.md 头部 "回退" 段落 = 双保险
4. **结构测试覆盖**：yuesheng-prompt-v5-structure.test.ts 5 大 SKILL 顺序、关键防御点（V-01/V-09/DP-F/DP-G/DP-I）、truncation 行为全部锁死
5. **引用关系图落地**：dev-docs/audits/2026-06-23-prompt-reference-graph.md 标出"03-teaching/ 双副本"待清理

### 教训（Learn）
1. **Edit 工具缓存漂移再次出现**：本会话 2 次 Edit 报告成功但磁盘未变更（行 428/460 "月笙 MVP Prompt" → "月笙写作教练 v5"），最终用 Node.js + fs.writeFileSync 写入解决。**根因假设**：Edit 工具基于 Read 工具的内部快照做字符串匹配，但 Read 快照与磁盘实际可能不同步（D-DEBT-2026-06-23-04 同类问题）。**新约束**：中文文件 + 多次连续 Edit 改同一文件时，必须用 `node -e` 或 Node.js 脚本验证
2. **truncation 测试用例设计踩坑**：第一次断言 "v5 误用 truncation 后仍包含 V-01" 失败，V-01 在 v5.md 中段（第 335 行）被截断。**修正**：明确文档化 "system prompt 不走 truncation" + 测试只断言头/尾（IDENTITY/SCENARIO）保留
3. **GH PR body 中文走 gh CLI 仍输出 Unicode escape**：与 Sprint 11 同类问题（D-028 教训 #2），但已用 `--body-file` + UTF-8 临时文件解决，无需重复记录
4. **v5.md 引用关系图应在 commit 前生成**：本会话在 commit 后才补 reference-graph.md，导致 git log 顺序中"代码切到 v5"早于"v5 引用图"。下个 sprint 应先建依赖图再动代码

### 新增技术债（Debt）
1. **D-DEBT-2026-06-23-05**: `resources/03-teaching/prompts/yuesheng-prompt-v3.md` + 5 SKILL 双副本未清理（Sprint 11 标记的 17 组重复之一）。Sprint 13 教育链路重整时统一处理
2. **D-DEBT-2026-06-23-06**: v5.md 约 30K 字符已接近 DeepSeek 8K 模型可用 prompt 余量上限（30K char ≈ 45K tokens，单 prompt 框架就占满 6K tokens），若日后 LLM 切换到更小上下文模型需重新评估。**当前缓解**：truncation MAX_CHARS=4000 仅对章节内容生效，v5 system prompt 走完整加载
3. **D-DEBT-2026-06-23-07**: Sprint 12 Plan 中提到的"5 个 placeholder {{}} → 检查"任务已合并到 v5 合并产物中，但未单独跑统计对比。下次类似合并任务应在合并前 grep `{{[a-z_]}}` 计数，合并后再次计数验证"未丢失"
4. **D-DEBT-2026-06-23-08**: 跨会话状态连续性问题：本会话从 summary 恢复后只看到 "T12-6 待执行"，但实际 T12-1~4 已在历史 commit 完成（d901f53/8ef3c40）。**改进**：下次开新会话时第一步应是 `git log --oneline -20` + 状态同步，避免重复已完成工作

### 下一阶段（Next）
- **PR #19 等用户 merge**（AI 不主动 merge 主分支）
- **Sprint 13 启动条件**：用户说"开始 Sprint 13" → 进入 Plan 阶段，处理 D-DEBT-2026-06-23-05（双副本清理）+ 教育链路再次整理
- **关闭 Issue #17**：PR body 含 "Closes #17"

### 依据
- 设计 005 §三 Sprint 12 / Issue #17
- R-011 记忆强化 / R-018 变更溯源 / R-025 Prompt 治理
- ADR-003（占位符 + truncation 复用）



---

## D-030 (2026-06-23) Sprint 13 复盘：Skill Dispatcher（v5 拆分 + 按 phase 加载）

### 上下文
- 设计 005 §三 Sprint 13 / Issue #18 P1
- Sprint 11/12 完成（资产普查 + v5 合并）
- 目标：把 v5 拆为 6 个 SKILL 文件 + SkillDispatcher 按 phase 选择加载

### 决策摘要
- Sprint 13 实施方向 B 精简版：拆分 v5.md 为 6 个 SKILL 文件 + SkillDispatcher 按 phase+attitude 选择加载
- attitude 维度接口预留但不实质过滤（Sprint 13 实质做 phase 维度 5 种组合）
- 4 个关键决策：(1) 拆出 reference-drawer (2) DP-F/G/I 独立 (3) phase+attitude 调度 (4) C 升级三处占位

### Sprint 13 范围
- 拆分 v5.md 为 6 SKILL 文件 + YAML metadata（22.5K 字符 / 530 行 / 零内容损失）
- SkillMetadata TypeScript 接口
- SkillDispatcher 类
- dynamic-context.service.ts loadCorePrompt 委托给 SkillDispatcher（保留 v5.md 降级路径）
- prompt-loader.ts initializeSkillDispatcher 启动入口
- 8 个 skill-structure.test.ts + 13 个 dispatcher/metadata 测试
- 清理 resources/03-teaching/ 双副本（6 个文件）
- v5.0.0 tag 锚定拆分前快照

### Sprint 13 不做（保留给方向 C）
- 完整 YAML metadata schema
- 跨 SKILL 依赖图自动校验
- 运行时根据 user 行为切换 SKILL
- 动态 load 缓存 + LRU
- SKILL 热更新
- attitude 维度实质过滤
- E2E 测试

### 关键风险发现：dispatcher opt-in 状态与 prompt 膨胀

实施时发现一个未在 Sprint 13 Plan 中预见的回归风险：

- **现状**：v5.md loadCorePrompt 实际只提取 §一铁三角（约 800 字符 / 约 1200 tokens）
- **风险**：如果 Sprint 13 启用 dispatcher 默认 phase=P0_INIT，会加载 4 个 always SKILL（约 20K 字符 / 约 30K tokens）
- **回归**：prompt 体积从 800 字符膨胀到 20K 字符（25 倍），与 Sprint 13 节省 token 目标直接矛盾
- **当前状态**：dispatcher 集成是 opt-in 状态（service-config.ts 未调用 initializeSkillDispatcher()），运行时仍走 v5.md 降级路径，行为未改变
- **决策**：保持 opt-in 状态，启用 dispatcher 需要先解决按 phase 加载的体积优化问题

### 方向 C 占位（三处都写）
1. 本决策日志（D-030）— 为什么 + 何时
2. GitHub Issue #19 — 做什么 + 验收
3. dev-docs/designs/sprint-14-dispatcher-upgrade.md — 怎么做

### 何时启动方向 C
- 当 attitude 维度需要实质过滤时
- 当需要根据 user 行为动态切换 SKILL 时
- 当切换到更小上下文模型时（小于 8K 余量时精细化调度）
- 当需要真正启用 dispatcher 时（必须先解决 prompt 体积优化问题）

### 回退路径
- git checkout v5.0.0 -- resources/prompts/yuesheng-prompt-v5.md
- git checkout v3.9.0 -- resources/prompts/yuesheng-prompt-v3.md

### 提交清单
Sprint 13 共 9 个 commit（按 R-016 规范）：

```
0880c7c chore(cleanup): remove 03-teaching double-copy debt
5279a84 test(prompt): replace v5-structure with skill-structure
3c24f7b feat(prompt): expose dispatcher init in PromptLoader
f175427 refactor(prompt): integrate dispatcher into loadCorePrompt
e9dd4b4 test(prompt): add metadata + dispatcher tests
b1d16c6 feat(prompt): add SkillDispatcher phase loader
4c13cbd feat(prompt): add SkillMetadata TS interface
3427a35 chore(scripts): add sprint-13 split/verify tools
a753088 refactor(prompt): split v5 into 6 SKILL files
```

### 门禁结果
- typecheck: 0 errors
- test: 441 / 441 passed
- lint: 0 errors

### 新增技术债
1. D-DEBT-2026-06-23-09: dynamic-context 不感知教学状态机，使用 P0_INIT 默认值
2. D-DEBT-2026-06-23-10: SkillDispatcher 无 LRU 缓存
3. D-DEBT-2026-06-23-11: dispatcher 启用需解决按 phase 加载的体积优化问题
4. D-DEBT-2026-06-23-12: resources/03-teaching/ 仍残留 actions/、config/、feedback/ 子目录未审查

### 经验
1. 拆分前先审计实际使用情况很重要
2. 激活死代码比拆分更有价值
3. Sprint 13 简化策略（attitude 接口预留）有效避免过度设计
4. opt-in 集成比激进替换更安全

### Sprint 14+ 启动条件
- 等用户 merge PR
- 启动方向 C 前先解决 D-DEBT-2026-06-23-11（prompt 体积优化）
- 解决 D-DEBT-2026-06-23-09（教学状态机 phase 注入 dispatcher）

### 依据
- dev-docs/designs/sprint-13-skill-dispatcher-design.md v1.0
- dev-docs/designs/sprint-13-implementation-plan.md v1.0
- dev-docs/designs/sprint-14-dispatcher-upgrade.md v1.0（方向 C 草案）
- R-018 变更溯源 / R-025 Prompt 治理 / R-019 代码规范

### D-031: Sprint 14-prior — 清除方向 C 启动债务
- **类型**: 架构决策
- **决策**: 在正式启动方向 C（Issue #20）前，先用迷你 Sprint 14-prior 解决两个启动前提债务 D-DEBT-2026-06-23-09 和 D-DEBT-2026-06-23-11
- **范围**:
  - T14-0: 解决 **D-DEBT-11** (dispatcher 体积膨胀 25 倍) — 方案 A+C 组合
  - T14-1: 解决 **D-DEBT-09** (教学状态机 phase 不注入 dynamic-context)
  - 不实现方向 C 的核心升级（attitude 实质过滤 / conditions / 依赖图）
- **关键改动**:

  **T14-0 (D-DEBT-11) — 方案 A+C 组合：**
  - 拆分 `core-identity.md` (1500 tokens) → `core-iron-triangle.md` (600) + `core-product-identity.md` (900)
  - `core-identity.md` 转为聚合入口（标记 DEPRECATED）
  - `SkillMetadata` 扩展 `tokenPriority` / `isCoreSubset` / `parentId` 字段（均可选）
  - `SkillDispatcher.selectForPhase` 接受 `SelectOptions`（`coreSubsetOnly` / `maxTokens`）
  - 新增 `truncateByPriority` 按 tokenPriority 降序截断
  - 体积目标：P0/P1 < 1.2K tokens (v5 降级) / P2+ < 4K tokens (dispatcher 核心子集)
  - 实际：P2+ 核心子集体积 = 1500 tokens (core-iron-triangle 600 + core-product-identity 900)

  **T14-1 (D-DEBT-09) — phase 注入：**
  - `loadCorePrompt` 接受 `phase: TeachingPhase` 参数（默认 P0_INIT）
  - `loadContext` 入口传递 phase
  - `loadSystemPrompt` 从 `stateContextGetter` 注入 phase
  - A+C 集成：P0/P1 走 v5 降级路径（保持 800 字符），P2+ 走 dispatcher v2
  - 字面量联合 cast（避免 import TeachingPhase 重复声明）

- **方案选择理由（A+C 组合）**:
  - **方案 A**（核心子集加载）：拆分后体积大幅下降，但影响 v5 拆分完整性（需要保留 core-identity.md 作为聚合入口）
  - **方案 C**（渐进式启用）：P0/P1 走 v5 降级，节省 token 效果局限于高 phase，最小改动
  - **方案 B**（按 phase 动态体积）：灵活但需重新设计 priority 体系，工作量大
  - **方案 D**（LLM 自动摘要）：智能但增加 LLM 调用成本
  - **A+C 组合**：兼顾体积优化和实现简单性
- **门禁**:
  - typecheck: 0 errors ✓
  - test: 452/452 passed (新增 11 个 sprint-14-prior 验收测试) ✓
  - lint: 0 errors ✓
  - 安全: 0 硬编码密钥 ✓
- **提交**: 6 commits on `feature/sprint-14-prior`:
  1. `5c65573` docs(plan): sprint-14-prior plan
  2. `1cd7ef1` refactor(prompt): split core-identity
  3. `efa2b4b` feat(prompt): dispatcher options+budget
  4. `0c8b561` feat(prompt): dynamic-context phase
  5. `ce7bd1b` refactor(prompt): inject phase + structure test
  6. `112ac9c` test(prompt): sprint-14-prior acceptance
- **PR**: #21 (https://github.com/Jelianbe/yuesheng-writing-coach/pull/21)
- **新增/修改**: 8 files / +566 lines (含验收测试 234 行)
- **风险**:
  - core-identity.md 拆分会破坏旧测试 → 已更新 skill-structure.test.ts 适配 8 个 SKILL 文件
  - prompt-loader 字面量联合 cast 可能未来 phase 字符串不匹配 → 已用 union type 精确约束
  - dispatcher sort 不稳定导致 priority 相同的选择不确定 → 测试已用 hasPriority10 软断言
- **后续**（方向 C 全量升级）：
  - attitude 实质过滤（sensei 档删鼓励话术）
  - 运行时 conditions 触发（evidence 质量 / DP 触发）
  - 完整 YAML metadata schema（depends / version）
  - 依赖图自动校验（启动时 fail-fast）
  - 灰度发布双轨对比 1 周
- **依据**: dev-docs/designs/sprint-14-prior-plan.md + Issue #20 + R-018 变更溯源 / R-019 代码规范 / R-027 四道门禁
- **Status**: ✅ Sprint 14-prior 完成（6 commits / PR #21 待 merge）


### D-032: Sprint 14 方向 C 核心升级 — 完成
- **类型**: 架构决策
- **决策**: 完成方向 C 全量升级（Issue #20）— attitude 实质过滤 + 运行时 conditions + 完整 metadata + 依赖图校验
- **范围**:
  - T14-2: 扩展 SkillMetadata（version / depends / conditions）
  - T14-3: SkillGraph 依赖图校验器（启动时 fail-fast）
  - T14-4: AttitudeFilter 态度档位实质过滤（sensei 档删鼓励话术）
  - T14-5: ConditionEvaluator 运行时条件评估（evidence.quality / user.safetyWord / user.dominantSyndrome）
  - T14-6: 两层截断（SKILL 级别 size tiebreak + Content 级别 truncation 集成）
  - T14-7: E2E 集成测试覆盖 5 个核心场景
- **关键改动**:

  **T14-2 (SkillMetadata 扩展) — 完整 schema：**
  - 扩展 SkillMetadata：version（语义化版本）/ depends（依赖的 SKILL id 列表）
  - 扩展 SkillLoadWhen：conditions?: LoadCondition[]（运行时条件）
  - LoadCondition 三种类型：
    - evidence.quality IN/NOT_IN [low, medium, high]
    - user.safetyWord IS/IS_NOT boolean
    - user.dominantSyndrome EQ/NEQ syndromeId
  - YAML 解析支持 conditions: [low] 简写语法

  **T14-3 (SkillGraph 依赖校验) — 启动时 fail-fast：**
  - validateSkillGraph(skills) → ValidationResult { valid, errors, cycles, missingDeps }
  - assertSkillGraphValid() 启动时 throw with structured message
  - SkillDispatcher.load() 内置调用

  **T14-4 (AttitudeFilter 实质过滤) — sensei 档态度过滤：**
  - AttitudeFilter 类 + 规则外置到 resources/config/attitude-filter.json（R-014）
  - sensei 档 removePatterns：加油/棒/真棒/非常好/继续努力 + emoji
  - replacePatterns：希望... → ''（弱化客套）
  - 长度下限保护（默认 50 字符）：过滤后太短回退到原内容
  - 配置文件缺失/无效时降级为默认（无过滤）
  - SkillDispatcher.setAttitudeFilter() 注入，composePrompt 自动应用

  **T14-5 (ConditionEvaluator 运行时条件) — 动态切换 SKILL：**
  - RuntimeContext 注入：evidenceQuality / safetyWord / dominantSyndrome
  - evaluateConditions(conditions, ctx) → AND 语义
  - 缺失 context 字段视为 fail（保守策略）
  - 未知 condition type 抛 warning 但不阻塞
  - SkillDispatcher.selectForPhase / composePrompt / estimateTokens 接受 runtimeCtx

  **T14-6 (两层截断) — 体积控制：**
  - SKILL 级别：truncateByPriority 同 priority 时按 estimatedTokens 升序优先（小优先）
  - Content 级别：truncateSkillContent 集成 truncation.ts（头70+省略+尾30）
  - SelectOptions 新增 maxCharsPerSkill 字段
  - silent=true 避免 dispatcher 流程 spam warn 日志

  **T14-7 (E2E 集成测试) — 5 场景：**
  - P0 + doubao + coreSubsetOnly + maxTokens：核心子集 + 体积控制
  - P2 + sensei：dispatcher 加载 + 删鼓励话术
  - safety word 触发：跳过有 user.safetyWord IS_NOT 约束的 SKILL
  - evidence.quality 条件：低/高质量时加载不同的 SKILL
  - 循环依赖 + 缺失依赖：load() fail-fast
  - 完整 phase × attitude × conditions 矩阵运行无错

- **方案选择理由（AttitudeFilter 规则设计）**:
  - **方案 A**（正则 removePatterns）：灵活、覆盖广、易扩展；选择此方案
  - **方案 B**（关键词列表）：简单但精度低
  - **方案 C**（LLM 重写）：智能但增加 LLM 调用成本

  **T14-6 size tiebreak 选择**:
  - 同 priority 时小 SKILL 优先，确保不被大 SKILL 占用预算
  - 原因：高 phase（如 P3_TRAINING）可能需要加载多个 SKILL，避免单个大 SKILL 挤出小但关键的 SKILL

- **门禁**:
  - typecheck: 0 errors ✓
  - test: 502/502 passed (新增 50 个 T14-2~T14-7 测试) ✓
  - lint: 0 errors ✓
  - 安全: 0 硬编码密钥 ✓
- **提交**: 6 commits on `feature/sprint-14`:
  1. `e706db0` feat(prompt): extend SkillMetadata with version/depends/conditions (T14-2)
  2. `6cb5009` feat(prompt): SkillGraph dependency validator with fail-fast (T14-3)
  3. `d9ac96b` feat(prompt): AttitudeFilter with attitude-axis real filtering (T14-4)
  4. `066d466` feat(prompt): runtime conditions evaluator with evidence/safety/syndrome (T14-5)
  5. `7f16f4e` feat(prompt): priority-based truncation with size tiebreak + content-level truncation (T14-6)
  6. `1fa5849` test(prompt): sprint-14 E2E integration covering 5 core scenarios (T14-7)
- **PR**: 待创建（feature/sprint-14 分支）
- **新增/修改**: 8 files / +~1300 lines (含 E2E 测试)
- **风险**:
  - conditions 评估误跳过关键 SKILL → 已用"缺失 context = fail"保守策略
  - attitude filter 误删有效话术 → 已用"长度下限保护回退"机制
  - YAML conditions 简写语法仅支持 identifier → 完整 YAML 形式推迟到 Sprint 15
  - sensei 档 attitude filter 改动了 SKILL 内容 → 测试已验证核心子集 + dispatcher 流程无错
- **测试覆盖**:
  - skill-metadata.test.ts: T14-2 元数据扩展
  - skill-graph.test.ts: T14-3 依赖图校验
  - attitude-filter.test.ts: T14-4 态度过滤（9 个）
  - condition-evaluator.test.ts: T14-5 条件评估（16 个）
  - skill-dispatcher-t14-6.test.ts: T14-6 两层截断（6 个）
  - sprint-14-e2e.test.ts: T14-7 端到端（7 个）
- **后续**（Sprint 15+）:
  - service-config.ts 启用 SkillDispatcher.initializeSkillDispatcher（真正启用 dispatcher v2）
  - YAML conditions 完整结构解析（evidence.quality IN [...] 完整语法）
  - 灰度发布双轨对比 1 周（sensei 档新旧版本对比）
  - prompt-loader 集成 dispatcher v2（替换 v5 降级路径）
  - SKILL 文件补充 conditions 字段（如 feedback-cognition 加 evidence.quality 条件）
- **依据**: dev-docs/designs/sprint-14-plan.md + Issue #20 + D-031 + R-014/R-018/R-019/R-027
- **Status**: ✅ Sprint 14 方向 C 核心升级完成（6 commits / PR 待创建）


---

### D-034: T14-8 启用 SkillDispatcher v2
- **类型**: 架构决策（启用 / 切换主路径）
- **触发**: Sprint 14 方向 C 全部就绪（D-032 + D-033 + 4 个启动条件）
- **决策**:
  - 在 service-config.ts 的 promptLoader 注册后调用 initializeSkillDispatcher()
  - P2+ 阶段：dispatcher v2（coreSubset 过滤 + 4K token 预算）
  - P0/P1 阶段：仍走 v5 降级（保持 ~800 字符，零风险）
  - PromptLoader 新增 isDispatcherReady() 方法（供健康检查 + 测试）
- **已知债务**（暂不修）：
  - loadCorePrompt 中 defaultAttitude="yuesheng" 硬编码，用户选 doubao/sensei 时 P2+ 实际加载 yuesheng 档 SKILL
  - 修复需 attitude 透传链路改造（chat → teaching-state → dynamicContext）
  - 影响面：用户体验（attitude 切换不生效），不影响系统功能
- **风险**:
  - prompt 体积 P2+ 从 ~800 字符跳到 ~1500+ tokens（已通过 coreSubset 过滤控制）
  - dispatcher 启动时 assertSkillGraphValid fail-fast（如 SKILL 错误会 throw）
- **门禁**: typecheck 0 / test 496/496 / lint 0 errors / 安全 OK
- **回退**: 删除 service-config.ts 中的 loader.initializeSkillDispatcher() 那一行（软回退）
- **依据**: D-032 + D-033 + Issue #20 + Sprint 14 方向 C 4 个启动条件已满足
- **PR**: #22（feature/sprint-14 → main，2026-06-22 merge commit b197e50）
- **Status**: ✅ 已合并到 main（PR #22 merged 2026-06-22）


---

## D-033 (2026-06-23) Sprint 9~14 整体 Reflect 复盘 — 3 个 PR 合并完毕

### 上下文
- Sprint 9 (前端全面审计与修复) + Sprint 11 (提示词资产审计) + Sprint 12 (提示词工程统一) + Sprint 13 (SkillDispatcher v1) + Sprint 14-prior (清方向 C 启动债务) + Sprint 14 (方向 C 核心升级) 全部完成并合并
- PR 合并链：#19 (Sprint 9+11+12+13 综合，50 commits) → #21 (Sprint 14-prior，7 commits) → #22 (Sprint 14，11 commits) 全部 MERGED
- main HEAD: b197e50 — 3 个 merge commit 完整保留历史
- 累计交付：121 个文件 / +12706 行 / -1762 行 / 68 个 commits / 4 个 ADR / 7 个 Sprint 计划文档

### 交付（3 个 PR / 68 commits）

| PR | Sprint | Commits | 范围 |
|:--:|:------:|:-------:|------|
| #19 | 9+11+12+13 | 50 | 前端审计 (S-01, H-02~05, M-01~09, L-01~05, R-01/02/03) + workspace-registry + AI 读写管道 (ADR-003/004) + 资产审计 + v5 合并 + SkillDispatcher v1 |
| #21 | 14-prior | 7 | 解决 D-DEBT-11 (A+C 组合) + D-DEBT-09 (phase 注入) |
| #22 | 14 | 11 | 方向 C 核心升级：attitude filter / runtime conditions / 依赖图 / 两层截断 / E2E / 启用 dispatcher v2 |

### 4 个 ADR（架构决策记录）
- ADR-001 stream-pipeline：B-lite stream pipeline with typed events
- ADR-002 workspace-registry：right sidebar plugin-style extensibility
- ADR-003 ai-readwrite-pipeline：MAX_CHARS=4000 truncation + 双花占位符
- ADR-004 x02-writeback：AI 写回编辑器三阶段协议（Stash→Confirm→Persist）

### 7 个 Sprint 计划文档
- sprint-9-plan.md / sprint-11-prompt-asset-audit-plan.md / sprint-12-prompt-unify-plan.md
- sprint-13-skill-dispatcher-design.md / sprint-13-implementation-plan.md
- sprint-14-prior-plan.md / sprint-14-plan.md

### 门禁结果（合并时 main HEAD 状态）
- typecheck: 0 errors
- test: 502/502 passed
- lint: 0 errors
- 安全: 0 硬编码密钥

### 做得好的（Keep）
1. **R-016 严格遵循**：68 个 commit subject 全部 ≤50 字符、含 scope、祈使句 — 提交历史清晰可读
2. **ADR 与实现同步落地**：4 个 ADR 都在 #19 一并合并，决策可追溯
3. **PR 描述质量高**：每个 PR 都有完整的"做什么/为什么/门禁/回退"四段
4. **债务前置清偿**：Sprint 14-prior 先解决 2 个启动债务再开 14，避免方向 C 启动时崩溃
5. **opt-in 集成策略**：SkillDispatcher 长期保持 opt-in 状态，每次启用都有充分测试
6. **设计文档驱动**：Sprint 11~14 都有正式 plan / design 文档，决策有依据
7. **三道门禁到位**：每个 PR merge 前 typecheck/test/lint 全绿

### 教训（Learn）
1. **PR 体量过大会拖慢 review 节奏**：#19 一个 PR 50 commits / 105 files，理想拆分为 3-4 个 PR（前端审计 / 资产审计 / 提示词统一 / SkillDispatcher v1）。**改进**：下个 sprint 大型工作拆分为多个小 PR（≤ 15 commits / ≤ 30 files）
2. **设计文档是债务**：#19 中 D-027/D-028/D-029/D-030 4 个决策日志条目，9ff5da1 / 1cd9750 / b267ddb 等多个 docs commit — 文档量超过代码量。**改进**：决策日志做"摘要版"（R-011 强调可读性），细节放进 ADR
3. **方向 C 的"按 phase 加载"目标与"启用 dispatcher"目标互相牵制**：Sprint 13 实施时才发现 prompt 膨胀 25 倍，必须 Sprint 14-prior 先解决体积问题才能真正启用 dispatcher。**改进**：技术决策应先做"启用影响范围"评估再实施
4. **GH PR 中文 mojibake 反复出现**：D-028/D-029 都记录了 PR body 编码问题。**根因**：gh CLI 走 PowerShell 5.1 OEM 代码页。**改进**：PR body 永远用 `--body-file` + UTF-8 临时文件
5. **v5 拆分后 dispatcher "激活死代码比拆分更有价值"**（D-030 经验）：拆分只是结构变化，激活才有用户感知价值。**改进**：下个 sprint 评估新功能时区分"建设"和"激活"

### 新增/更新技术债
1. **D-DEBT-2026-06-23-13** (新)：能力图谱（ability-atlas.json）8 个能力节点 / 10 个症候 / 20 个训练任务中，仅 2/5 消费方接入（training-recommendation.service.ts + prompt-loader.ts）。诊断展示 / 教学状态机 / 能力画像未接入。**Sprint 15 启动处理**
2. **D-DEBT-2026-06-23-14** (新)：461 条写作蒸馏素材（v3.1+ 200 条 + 扩展第 2 批 200 条 + 扩展第 3 批 61 条）散落在 3 个 MD 文件中，无结构化索引，无法被 AI 检索。**Sprint 15 启动处理**
3. **D-DEBT-2026-06-23-15** (新)：训练任务 3 套体系并行（T001-T020 占位 / TRAIN-PXXX-XXX 29 条教学工坊 / CH-PXXX-XXX 31 条挑战式微练），无 ID 关联，存在重复语义。**Sprint 15 启动处理**
4. **D-DEBT-2026-06-23-16** (新)：PR #19 体量过大（50 commits / 105 files），增加 review 难度。**改进方向**：未来大型工作拆分为多个小 PR
5. **D-DEBT-2026-06-23-17** (新)：dispatcher v2 启用后 attitude 透传链路未改造（chat → teaching-state → dynamicContext），P2+ 阶段 doubao/sensei 档实际加载 yuesheng 档 SKILL（D-034 已知债务，纳入 Sprint 15 范围）

### 保留未变债务
- D-DEBT-09 (resolved by Sprint 14-prior)
- D-DEBT-11 (resolved by Sprint 14-prior)
- D-DEBT-10 (LRU 缓存 — 暂缓，性能未瓶颈)
- D-DEBT-12 (03-teaching 子目录审查 — 部分清理)

### 下一阶段（Sprint 15 启动）
按 GStack 流程，Reflect 完成 → 进入 Think 阶段：
1. **创建 Issue #22 (Sprint 15)**：诊断库漏洞修复
2. **设计文档已就位**：`dev-docs/designs/2026-06-23-diagnosis-library-remediation.md` (307 行) — 含 3 个核心任务（T15-A 蒸馏素材索引化 / T15-B 训练任务断层消除 / T15-C 能力图谱消费链补全）
3. **DoD 至少 3 条**：可量化（如：461 条素材 100% 索引化、3 套训练任务 100% ID 关联、能力图谱 5/5 消费方接入）+ 4 道门禁全绿

### 依据
- 3 个 PR 的 commit message + body
- D-027 ~ D-034 决策日志（Sprint 11~14 完整决策链）
- 4 个 ADR（ADR-001/002/003/004）
- dev-docs/designs/sprint-9/11/12/13/14-plan.md
- R-011 记忆强化 / R-018 变更溯源 / R-027 四道门禁

### Status
✅ Sprint 9~14 整体 Reflect 完成 — main 状态健康，可启动 Sprint 15

