# B65 信息流动三分支评估回退 + 同类症候复发率 — 交付提交日志

**日期**：2026-08-09
**类型**：功能增强 + 设计回退（B62e 三分支沉淀经架构核对回退，保留写作/诊断隔离；B62h 同类症候复发率落地）
**前置**：`2cb2168`（批次 64 定量指纹 + 声线漂移实时化 + 编辑器心流）

---

## 背景与立项

1. **B62e 信息流动三分支 + 废弃草稿防污染**（A3 落地，V2.0 §3.2）：
   - 初始方案：WritingStore 字数计数器，每满 3000 新字 / 会话结束 / 显式保存 → 提取风格指纹写入 L2
   - **设计核对后回退**：styleFingerprint 是 L3 个人风格模型，其消费方是诊断（声线漂移比对）——更新应绑定「提交诊断」，写作编辑写它会双写抢同一档案，且草稿态内容会污染基线（为此打的防污染补丁正是设计问题的证据）
2. **B62h 同类症候复发率**（B61 深化，V1.0 原则4 / V1.1 建议6）：
   - 按已确认症候聚合「出现→好转→再犯」复发率，成长页展示（复用 active_problem 数据）

## 回退决策（B62e）

**写作端与诊断端隔离，各自只干自己的事：**
- 写作端：只管内容落库（L1→L2 固化 = 批次 31 即时保存 `saveChapterContent`，已有）+ 废弃草稿不参与任何知识链路（无写入路径，天然防污染）
- 诊断端：提交诊断时更新 L3 风格档案（批次 64 滑动重锚，不动）
- 回退内容：WritingStore 三分支计数器 + `_maybeSediment` + `updateLatestStyleFingerprint` 全部移除；写作端不写任何风格模型

**回退依据**：
- L2/L3 语义错位：「L1→L2 信息流动」应指草稿固化进作品库（已由即时保存实现），非「写作时更新 L3 风格档案」
- 单一写入源：风格档案只有诊断提交一个更新入口，避免双写与草稿污染
- 防污染由隔离本身达成：无写入路径 → 废弃内容（放弃草稿 / 删除章节）天然不会入库，无需专门标记

## 改动内容

### B62e 回退（删除写作端沉淀）
- [writing_providers.dart](../lib/providers/writing_providers.dart)：恢复 `updateContent` / `saveNow()` / `discardDraft` 原实现，删除三分支计数器、`_maybeSediment`、`_excludeFromExtraction` 及相关 import
- [writing_page.dart](../lib/widgets/writing_page.dart)：dispose 强制保存恢复 `saveNow()`（去掉 endOfSession 参数）
- [student_model_repository.dart](../lib/data/repositories/student_model_repository.dart)：删除 `updateLatestStyleFingerprint`（批次 65 引入的用户级落点，随回退移除）

### B62h 同类症候复发率（保留）
- [growth_service.dart](../lib/services/growth_service.dart)：`SyndromeRecurrence` 数据类 + `getSyndromeRecurrences`（跨会话按 syndrome_id 聚合，rejected 排除；按 created_at 时间序判定「再犯」——前一条已好转 → 本次出现计复发；复发率 = 再犯 / max(出现-1, 1)；复发率降序、同率按出现次数降序）
- [growth_providers.dart](../lib/providers/growth_providers.dart)：`GrowthState.syndromeRecurrences`；`loadGrowthData` 并行加载第 9 项
- [growth_detail_page.dart](../lib/widgets/growth_detail_page.dart)：新增「同类症候复发率」区块（`_RecurrenceRow`：症候名 + 出现/好转/再犯 + 复发率%，≥50% 警示色）；仅展示出现 ≥2 次的症候

### 测试（净 +5）
- [growth_service_test.dart](../test/services/growth_service_test.dart)（+4，#R1-R4）：空数据 / 「出现→好转→再犯」复发判定与排序 / rejected 排除 / 单次出现复发率 0
- [growth_detail_page_test.dart](../test/widgets/growth_detail_page_test.dart)（+1，#D6）：复发率区块展示（标题 + 明细 + 50%）
- [writing_providers_test.dart](../test/providers/writing_providers_test.dart)（-6）与 [student_model_style_fingerprint_test.dart](../test/services/student_model_style_fingerprint_test.dart)（-2）：随回退删除沉淀用例

## 关键设计

- **单一写入源**：L3 风格档案（styleFingerprint）仅由诊断提交链路更新（批次 64），写作编辑不写——写作/诊断互相隔离
- **信息流动语义对齐**：L1→L2 固化 = 章节内容即时落库（批次 31），三分支计数器无增量价值
- **防污染由隔离达成**：废弃草稿（放弃草稿 / 删除章节）因无写入路径天然不进入任何知识链路，无需专门标记代码
- **复发率语义**：严格「好转后再犯」才计复发；未好转的连续出现不虚增复发率；分母 max(出现-1,1) 避免除零
- **AI 自主判断优先**：复发率仅作成长页可视化信号，不接入硬拦截/强制教学分支
- **无 schema 迁移**：复用批次 64 style_fingerprint 列与既有 active_problem 表

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **913 全绿 + 4 skipped**（净 +5：复发率 4 + 展示 1；回退删除 8）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次，amend 至 bcb63f1） | 2026-08-09 | feat: 批次65 信息流动三分支回退+同类症候复发率（B62e 设计核对后回退写作端 L3 沉淀，保留写作/诊断隔离 + B62h growth_service 复发率聚合与成长页展示）+ 本日志 |
