# B73 大纲记忆确认卡片 UI — 交付提交日志

**日期**：2026-08-09
**类型**：功能（大纲层可交互确认入口：pending 印象三态确认卡）
**前置**：`855e70b`（批次 72，大纲层后端）

---

## 背景与立项

批次 72 落地大纲层后端（实体/印象表 + 提取协议 + 匹配/合并/冲突），全部新写入为 **pending 态**。
本批补上可交互确认入口：AI 自主提取的印象需用户确认后才 active——满足「自动提取→用户确认」约束与记忆可交互性。
经用户确认：**每实体一卡**（印象逐行操作）、**不含文本编辑**（后续批次增强）。

## 改动内容

### 确认操作（repository）
- [outline_repository.dart](../lib/data/repositories/outline_repository.dart)：
  - `approveImpression`：事务三动作——冲突旧印象 superseded（二选一）→ 印象 active → 实体 pending→active
  - `rejectImpression`：印象 rejected（冲突时拒绝即保留旧认知）

### 提取结果摘要（service）
- [outline_service.dart](../lib/services/outline_service.dart)：`applyOutlineExtraction` 返回 `List<OutlineExtractionResult>`（实体 + 新写入 pending 印象 id/text/conflict），供写确认卡

### 确认卡片消息 + 组件
- [message_card_service.dart](../lib/services/message_card_service.dart)：`OutlineConfirmationPayload` / `OutlineImpressionPayload` + `insertOutlineConfirmationCard`（system + outline_confirmation 类型，复用 D6 卡片模式）
- [outline_confirmation_card.dart](../lib/widgets/outline_confirmation_card.dart)（新建）：
  - 每实体一卡：标题「大纲记忆待确认」+ 实体类型 chip（人物/设定/情节）+ 新/已有标签 + 实体名
  - 印象逐行：冲突印象显示「与既有认知矛盾：接受将更新记忆，拒绝保留原有认知」横幅（warningBg 底）
  - 操作：接受（approveImpression）/ 拒绝（rejectImpression），操作后行收起 → 显示「已确认 n/m 条印象」
  - 视觉：月色竹青（左 4dp 竹青条 + primarySoft chip + primary 主按钮 + 描边次按钮）

### 链路挂接
- [chat_service.dart](../lib/services/chat_service.dart)：步骤 9.1 落库后，为含 pending 印象的实体写确认卡消息
- [message_list.dart](../lib/widgets/message_list.dart) / [writing_coach_panel.dart](../lib/widgets/writing_coach_panel.dart)：分派 `outline_confirmation` → OutlineConfirmationCard

### 测试（净 +8）
- [outline_service_test.dart](../test/services/outline_service_test.dart)（+3）：approve → active+实体 active / reject → rejected / 冲突二选一旧印象 superseded
- [outline_confirmation_card_test.dart](../test/widgets/outline_confirmation_card_test.dart)（+5，新建）：渲染三态 / 冲突横幅 / 接受落库+收起 / 拒绝落库+收起 / fromMessageContent 解析+兜底
- [chat_service_outline_test.dart](../test/services/chat_service_outline_test.dart)：断言确认卡消息写入

## 关键设计

- **每实体一卡**：卡数少、信息聚集；实体下印象逐行操作，冲突印象高亮
- **确认即生效**：接受 → active（供后续写作层/实体索引引用）；拒绝 → rejected；冲突接受 → 旧印象 superseded（二选一），印象来源仍可追溯
- **交互防丢**：落库失败仍本地收起（卡片消息仍在，可重现），仿 TeacherSuggestionCard dismissed 模式
- **零协议改动**：确认卡由系统事件确定性插入（步骤 9.1），不依赖 AI 输出

## 四闸验证

- `dart format`：全过（范围外历史存量文件已还原）
- `flutter analyze`：0 error 0 warning（32 info 全历史存量，本批零新增）
- `flutter test`：全量 **1015 全绿 + 4 skipped**（较批次 72 净 +8）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次73 大纲记忆确认卡片 UI（B62j 后续：OutlineConfirmationCard 每实体一卡·三态确认 + approve/reject/冲突二选一落库 + 步骤 9.1 写卡 + 8 新用例）+ 本日志 |
