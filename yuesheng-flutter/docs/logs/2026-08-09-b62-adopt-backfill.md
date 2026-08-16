# B62 采纳回写 + 措辞约束 — 交付提交日志

**日期**：2026-08-09
**类型**：功能增强（研究落地 V2.0 §3.3 触发三问第2问 + V2.0 §1.4 TombWriter 措辞层 / A1 立项）
**前置**：`（批次 61 选择权+依赖度指标）`

---

## 背景与立项

1. **B62a 采纳回写**（V2.0 §3.3 Just-in-Time 触发三问第 2 问）：
   - 报告原文：*"YES（但已过30分钟+用户未采纳）→ 不触发（用户选择忽略）"*
   - 现状差距：`TeacherSuggestions` 表无 adopted/dismissed 字段，去重 3600s 一刀切，不论用户是否采纳
   - 目标：采纳回写闭环——「开始练习」记 adoptedAt，「跳过此建议」记 dismissedAt；去重按采纳语义升级：未采纳 → 窗口内不再触发；已采纳 → 冷却期后可触发新的/进阶反馈点
2. **B62c 措辞约束**（A1 措辞层立项落地，V2.0 §1.4 + V1.0 原则2 声线保护）：
   - 报告原文：TombWriter「AI 应定位为工具而非合作者」+ V1.0 原则2（先肯定独特性、教原理不教标准答案）
   - 现状差距：prompt 无措辞硬约束
   - 目标：L1 常驻 skill 固化三条措辞约束

## 改动内容

### 表结构（B62a）
- [tables.dart](../lib/data/database/tables.dart)：`TeacherSuggestions` 加 `adopted_at` / `dismissed_at`（INTEGER 可空）
- [database.dart](../lib/data/database/database.dart)：
  - `schemaVersion` 13 → 14
  - 新增 v14 幂等迁移块 `add_adopted_dismissed_to_teacher_suggestion`
  - **守卫修正**：`onUpgrade` 早退守卫由 `from >= 12` 上移至 `from >= 14`。原守卫会令 v13 块对 from=12 存量库失效；上移后 v13/v14 块对存量库均可达（两块均幂等 PRAGMA 检查，无数据风险）
- `database.g.dart`：build_runner 重新生成（+adoptedAt/dismissedAt）

### 数据层（B62a）
- [teacher_suggestion_repository.dart](../lib/data/repositories/teacher_suggestion_repository.dart)：
  - 新增 `markAdopted`（置 resolved + adoptedAt）
  - 新增 `markDismissed`（置 resolved + dismissedAt；卡片跳过改用此方法）
  - `hasDuplicateSuggestion` 升级采纳语义：窗口内最近一条同症候建议 → 未采纳（adoptedAt 空）返回 true；已采纳距采纳 < `adoptedWindowSec`（默认 1800s）返回 true，≥ 返回 false（可触发新反馈点）
  - `markResolved` 保留（FIFO/历史语义）

### 触发层（B62a）
- [chat_gates.dart](../lib/services/chat_gates.dart)：
  - 新增 `kAdoptedDedupeWindowSec = 1800`
  - `persistTeacherSuggestion` 透传 `adoptedWindowSec` 给去重

### 交互层（B62a）
- [teacher_suggestion_card.dart](../lib/widgets/teacher_suggestion_card.dart)：
  - 「开始练习」→ 先回写 `markAdopted`（fire-and-forget，落库失败不影响练习启动）
  - 「跳过此建议」→ `markDismissed`（替代 markResolved）

### 措辞约束（B62c，A1 落地）
- [skill_registry.dart](../lib/services/skill_registry.dart)：`_coreProductIdentity` 新增「三、声线保护措辞约束」：
  - 措辞 1：AI 是工具不是合作者（「月笙分析发现……」开口，禁「我们一起写……」）
  - 措辞 2：先肯定独特性，再建议
  - 措辞 3：教原理，不教标准答案
  - estimatedTokens 900 → 1200

### 测试（+10）
- [chat_gates_test.dart](../test/services/chat_gates_test.dart)：
  - #19 已采纳且过冷却（adoptedWindowSec=0）→ 可再次触发
  - #20 已采纳但冷却期内 → 不触发
  - #21 已跳过 → 不触发（未采纳语义）
  - #D1-D6 hasDuplicateSuggestion 采纳语义直测（未采纳 true / 已采纳未冷却 true / 已采纳过冷却 false / 已跳过 true / 无记录 false / syndromeId 空 false）
- [teacher_suggestion_card_test.dart](../test/widgets/teacher_suggestion_card_test.dart)：
  - #5 升级断言：跳过 → dismissedAt 非空、adoptedAt 空
  - #10 新增：开始练习 → adoptedAt 非空、状态 resolved
- [widget_test.dart](../test/widget_test.dart)：user_version 断言 13 → 14

## 关键设计

- **采纳语义闭环**：去重不再"一刀切"——用户采纳过（adopted）说明教学起效，冷却后可触发新/进阶反馈点；用户见过但未采纳（含跳过）则不再骚扰，对齐报告"用户选择忽略则不再触发"
- **降频而非禁发**：已采纳后 30 分钟冷却，兼顾"不刷屏"与"继续教学"
- **向后兼容**：`hasDuplicateSuggestion` 保持 bool 签名 + 可选参数；`markResolved` 保留；迁移块幂等
- **措辞约束放 L1 常驻**：`core-product-identity` 为 P2+ 必加载，三条措辞全局生效

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **856 全绿 + 4 skipped**（+10：采纳语义 9 + 卡片 #10）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次62 采纳回写+措辞约束（Teacher 卡开始练习记 adopted / 跳过记 dismissed + 去重采纳语义升级 + core-product-identity 声线保护措辞三层 + v14 迁移）+ 本日志 |
