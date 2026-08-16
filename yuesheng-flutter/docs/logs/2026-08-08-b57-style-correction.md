# B57 风格错误纠正（学员纠错入口）— 交付提交日志

**日期**：2026-08-08
**类型**：小改进（Sudowrite 二轮借鉴点 D——Style Memory 可纠错防固化）
**前置**：`0457d47`（批次 56 动作场景化）

---

## 背景与立项

1. **Sudowrite 二轮审视借鉴点 D**：Sudowrite Style Memory 自动学习风格，但画像一旦固化即被"锁死"；对照文档 §7.3「证据驱动」红线要求画像可纠错防固化。
2. **现状缺口**：批次 53 落地写作风格画像后，成长页风格卡只读展示五维坐标，学员无法纠正 AI 误判。
3. **立项决策**（用户确认「立项小改进」）：风格卡加学员纠正入口，约束为**纠错非重写**——仅纠正五维坐标，summary 保留 AI 描述只读。

## 改动内容

### lib/data/repositories/student_model_repository.dart
- 新增 `updateLatestStyleProfile(profile)`：更新最新一条有 style_profile 的记录（`updated_at DESC, rowid DESC`，与 `getLatestStyleProfile` 语义一致）；无有效记录 → no-op 不创建新画像

### lib/providers/growth_providers.dart
- `GrowthStore` 新增 `correctStyleProfile(updated)`：调 repository 更新最新画像后重新 `loadGrowthData()` 刷新页面

### lib/widgets/growth_detail_page.dart
- 写作风格卡标题行右侧新增「纠正」TextButton（仅 styleProfile 非空时渲染）
- 新增 `_StyleCorrectionSheet` 底部弹层：AI 描述只读 + 五维坐标 ChoiceChip 单选 +「保存纠正」按钮；保存后调用 store 并关闭弹层
- 五维中文 label 函数（`_sensoryLabel` 等）从 State 提升为模块级顶层函数（供 State 与 sheet 复用）

### 测试
- `student_model_style_profile_test.dart` +2：#B57-D1 更新最新一条（后写 session 被纠正，先前的不动）/ #B57-D2 无记录 no-op 不抛出
- `growth_detail_page_test.dart` +3：#D7 纠正按钮 → 弹层 / #D8 纠正一维 → 落库且 summary 保留 → 页面刷新 / #D9 无画像无按钮

## 关键设计

- **纠错非重写**：学员只改五维坐标；summary（AI 描述）只读展示，弹层注明"下次诊断仍会按你的新文本重新识别"——满足 §7.3 证据驱动红线，防"学员自填画像"漂移
- **跨会话语义**：纠正作用于最新一条画像（与成长页展示口径一致），不新建画像、不覆盖历史诊断记录
- **向后兼容**：无 style_profile 时不渲染按钮；无有效记录时更新 no-op

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **817 全绿 + 4 skipped**（+5：B57 仓库 2 + 页面 3）
- 文档同步：本日志 + 对照文档 §10-D 状态更新为已落地

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-08 | feat: 批次57 风格错误纠正（成长页风格卡纠正入口：五维 ChoiceChip 单选弹层 + updateLatestStyleProfile + store 刷新）+ 本日志 |
