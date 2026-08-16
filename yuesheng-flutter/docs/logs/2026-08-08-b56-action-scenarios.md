# B56 动作场景化（Sudowrite 映射）— 交付提交日志

**日期**：2026-08-08
**类型**：功能改造（QuickChips 场景化分组）
**前置**：`a63a3a0`（批次 55 编辑反馈分层审计）

---

## 背景与立项

1. **Sudowrite 研究重新审视**：用户要求独立重读对照文档（[2026-08-08-sudowrite-product-comparison.md](../2026-08-08-sudowrite-product-comparison.md)），发现 4 个此前忽略的可借鉴点。
2. **动作场景化（A）**：Sudowrite 最好评功能集中在场景化工作流（Write/Describe/Rewrite/Brainstorm/Beta Reads），而非零散命令。月笙现有 QuickChips 为 3 个纯诊断入口，缺「主动练动作」的入口。
3. **立项决策**（用户确认「立项：动作场景化（推荐）」）：QuickChips 增加「写作动作」组——练习描写（Describe）/ 练习改写（Rewrite）/ 头脑风暴（Brainstorm）/ 读者视角（Beta Reads 映射），与「写作诊断」组并列。

## 改动内容

### lib/widgets/quick_chips.dart
- 新增 `actionQuickChips`：4 个动作 chip（练习描写/练习改写/头脑风暴/读者视角），prompt 内嵌三段式教学法（示范参考/常见错误/自查锚点）+ 人机协作（AI 引导、学员动手写、AI 点评）
- 新增组标题常量 `kActionGroupTitle = '写作动作'`、`kDiagnosticGroupTitle = '写作诊断'`
- `QuickChips` 组件新增 `actionChips`（默认 actionQuickChips）与 `showActionGroup`（默认 true）参数，向后兼容
- build 重构为 Column 分组渲染：动作组（标题 + `_ChipRow`）→ 诊断组（标题 + `_ChipRow`）；新增私有 `_ChipRow`（height 40 横向 ListView）与 `_GroupLabel`

### test/widgets/quick_chips_test.dart
- 新增「批次56: 动作场景化」group 4 个测试：#4 渲染动作组 / #5 点击动作 chip → onSelect 回调（断言 prompt 含三段式结构）/ #6 showActionGroup=false 隐藏 / #7 自定义 actionChips 覆盖默认

## 关键设计

- **动作 vs 诊断分组**：动作组给「我想练」的主动练习入口，诊断组保留「帮我查」的被动检查入口，语义边界清晰
- **prompt 内嵌教学结构**：三段式（示范参考/常见错误/自查锚点）+ 学员动手写 + AI 点评，符合「AI 引导、学员动手」人机协作原则，避免 AI 代写
- **向后兼容**：默认参数不破坏既有调用（3 诊断 chips 仍默认渲染，动作组默认显示）

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **812 全绿 + 4 skipped**（quick_chips_test 7 个全过，其中 4 个为本批新增）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-08 | feat: 批次56 动作场景化（QuickChips 写作动作组：描写/改写/头脑风暴/读者视角 + 三段式教学 prompt + 分组渲染）+ 本日志 |
