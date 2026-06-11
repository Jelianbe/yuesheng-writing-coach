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
