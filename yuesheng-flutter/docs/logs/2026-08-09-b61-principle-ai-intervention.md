# B61 选择权 + 依赖度指标 — 交付提交日志

**日期**：2026-08-09
**类型**：功能增强（研究落地 V1.0 §六 原则1 反馈三层结构「选择」+ 原则4 成长轨迹）
**前置**：`6670691`（批次 60 教学决策层）

---

## 背景与立项

1. **用户需求**：教学效率/品质建议立项（全部确认）。
2. **61a 选择权增强**（V1.0 反馈三层结构：观察/诊断/选择）：现有 Teacher 建议卡三按钮（开始练习/跳过/查看详情），缺报告示例的选项 D「教我原理」——学员想懂原理而非直接练时无出口。
3. **61b 依赖度指标**（V1.0 成长报告范例「AI 介入次数下降 = 学员更独立」）：成长页缺"AI 介入"信号，无法量化依赖下降。

## 改动内容

### 61a 选择权：Teacher 建议卡「教我原理」
- [teacher_suggestion_card.dart](../lib/widgets/teacher_suggestion_card.dart)：新增 `onTeachPrinciple` 回调（参数=症候名）；按钮改两行布局——第一行「开始练习 | 跳过此建议」，第二行「查看详情 | 教我原理」；无回调时 SnackBar 兜底
- [message_list.dart](../lib/widgets/message_list.dart)：透传 `onTeachPrinciple`
- [chat_page.dart](../lib/widgets/chat_page.dart)：`_handleTeachPrinciple` 发送原理讲解请求（复用 `_handleSend`）
- [writing_coach_panel.dart](../lib/widgets/writing_coach_panel.dart)：`_handleTeachPrinciple` 填入输入框发送（复用 `_handleSend` 链路）

### 61b 依赖度指标：AI 介入次数
- [growth_service.dart](../lib/services/growth_service.dart)：`GrowthOverview` 加 `aiInterventions`（默认 0）；`getGrowthOverview` 计算 = 诊断次数 + 训练次数（训练从 student_model teaching_history 聚合）
- [growth_overview_card.dart](../lib/widgets/growth_overview_card.dart)：加 `aiInterventions` 参数 + 第 4 统计项「AI 介入」
- [growth_detail_page.dart](../lib/widgets/growth_detail_page.dart)：总览卡传参

### 测试
- `teacher_suggestion_card_test.dart` +3：#7 四按钮渲染 / #8 回调传症候名 / #9 无回调 SnackBar 兜底
- `growth_service_test.dart` +1：#3 训练历史 → AI 介入 = 诊断+训练
- `growth_detail_page_test.dart`：#D3 加「AI 介入」断言

## 关键设计

- **教原理 = 反馈三层结构的 D 选项**：不打断训练流，直接向 AI 请求一次"它是什么/怎么判断/怎么避免"的原理讲解（一次只讲一个点，符合表达密度约束）
- **AI 介入语义**：诊断 + 训练（学员每次请求 AI 处理作品即一次介入）；学员独立后该指标下降，与字数/编辑量形成"依赖度"对比信号
- **向后兼容**：`aiInterventions` 默认 0；`onTeachPrinciple` 可选，宿主不传时 SnackBar 兜底

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **846 全绿 + 4 skipped**（+4：教我原理 3 + AI 介入 1）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次61 选择权+依赖度指标（Teacher 建议卡「教我原理」两行布局 + 成长页 AI 介入次数 = 诊断+训练）+ 本日志 |
