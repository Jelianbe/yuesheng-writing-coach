# B59 Just-in-Time 触发增强 — 交付提交日志

**日期**：2026-08-09
**类型**：功能增强（研究落地——V2.0 §3.3 教学触发三问第 2/3 问）
**前置**：`5dce9a9`（批次 58 研究盘点与避坑核查）

---

## 背景与立项

1. **研究引入**：四份前置研究报告入库（`ee726be`）。V2.0 §3.3 定义教学触发的 Just-in-Time 三问逻辑：
   - ① 反馈层级 ≤ 用户层级+1（未实施，依赖技能层级体系）
   - ② **会话内该类型反馈是否已触发过** → 5 分钟内不触发（避免骚扰）
   - ③ **是否心流模式**（持续快速输入）→ 延迟触发（不打断创作）
2. **现状缺口**：现有 Teacher 建议触发（`persistTeacherSuggestion`）只有 FIFO 淘汰（active ≤3），无会话内去重、无心流感知——同一症候反复诊断会反复出建议卡。
3. **立项决策**（用户确认「Just-in-Time 触发增强」）：落地第 2 问（会话内同症候去重）+ 第 3 问（心流延迟反馈）。

## 改动内容

### lib/services/chat_gates.dart
- 新增常量 `kRapidFireWindowSec = 60`、`kDedupeRecencyWindowSec = 3600`
- 新增纯函数 `isRapidFireSend(lastSendAtSec, nowAtSec, {windowSec})`——第 3 问心流判定（距上一条 < 60s 视为心流）
- `persistTeacherSuggestion` 新增可选参数 `isRapidFire`（默认 false）与 `dedupeRecencyWindowSec`（默认 3600）：
  - `isRapidFire` → 本次不写入（延迟反馈，返回 null）
  - 同 session 同症候窗口内已有建议 → 不重复写入（返回 null）

### lib/data/repositories/teacher_suggestion_repository.dart
- 新增 `hasDuplicateSuggestion(sessionId, syndromeId, {recencyWindowSec})`：窗口内同症候建议查询；syndromeId 为空（维度型建议）→ 不去重

### lib/services/chat_service.dart
- 新增 `_lastUserSendAtSec`（session → 秒）记录上次用户消息发送
- `sendMessage` 开头计算 `rapidFire`（复用 `isRapidFireSend`）并记录时间
- Editor / Diagnosis 两处 `persistTeacherSuggestion` 调用均传 `isRapidFire`

### test/services/chat_gates_test.dart
- persistTeacherSuggestion 新增 5 个用例：#14 isRapidFire 不写入 / #15 同症候窗口内去重 / #16 不同症候各可写 / #17 窗口=0 可再触发 / #18 syndromeId 空不去重
- 新增「isRapidFireSend 心流判定」group 4 用例（#J1-J4）

## 关键设计

- **行为默认变更**：同症候建议 1 小时内不重复（无论 active/resolved——用户已见过），为向后兼容可传 `dedupeRecencyWindowSec: 0` 关闭
- **心流语义**：距上一条用户消息 < 60s 视为快速交互，本次建议跳过（下次诊断自然再评估），不缓存不补发——实现"延迟"的简化版
- **不影响既有链路**：encourage/defer 不入库、task=null、DB 异常降级等既有行为全部保留（全量测试回归通过）

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **826 全绿 + 4 skipped**（chat_gates_test 22 个，其中 9 个为本批新增）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次59 Just-in-Time 触发增强（会话内同症候去重 + 心流延迟反馈 isRapidFireSend）+ 本日志 |
