# B64 定量指纹 + 声线漂移实时化 + 编辑器心流 — 交付提交日志

**日期**：2026-08-09
**类型**：功能增强（研究落地 V2.0 §3.2 L3 定量指纹 8 项 + L3→L1 声线漂移实时反馈 + V2.0 §3.3 第3问心流扩展 / A5、F10、B59 深化）
**前置**：`ba43e07`（批次 63 意图分类器 + 标注位置）

---

## 背景与立项

1. **B62f 定量指纹 + F10 实时化**（A5 执行，与内容层 F10 合并）：
   - 现状差距：`WritingStyleProfile` 仅五维**定性**坐标，定量指标全无；F10 原立项"新症候卡"形态已二次审计修正为"L3→L1 实时提示"
   - 目标：① 8 类定量指标从章节文本本地提取（纯规则无新依赖）；② 存 student_model.style_fingerprint；③ 诊断时当前指纹 vs 基线 → 漂移超阈值 → 例证式提示注入本轮 prompt，AI 以提问方式温和指出（软引导非硬拦截，不做症候卡）
2. **B62g 编辑器心流**（B59 深化，V2.0 §3.3 第3问）：
   - 现状差距：心流仅"距上一条消息 <60s"，用户长时间写作不发言时会误触发教学反馈
   - 目标：叠加"最近 120s 内有编辑输入"→ 判定心流中，延迟 Teacher 反馈

## 改动内容

### B62f 定量指纹
- [style_fingerprint.dart](../lib/services/style_fingerprint.dart)（新建）：
  - `StyleFingerprint` 数据类（8 类指标）：句长均值+方差 / 段落分布（短<50/中50-200/长>200）/ 对话占比+叙述占比（描写占比近似）/ 高频词指纹（2-gram TOP30）/ 简单句占比（句式）/ 比喻+反问密度（修辞）/ 省略号+感叹号密度（标点）+ 样本句数
  - `extractStyleFingerprint`：纯规则提取；样本不足（<60 字或 <5 句）返回 null
  - `detectVoiceDrift`：阈值检测（句长偏离 ≥40% / 对话占比 ≥0.15 / 简单句占比 ≥0.20 / 感叹号与省略号激增），返回例证式提示（≤3 条，带具体数字）
- [tables.dart](../lib/data/database/tables.dart) + [database.dart](../lib/data/database/database.dart)：
  - `student_model` 加 `style_fingerprint`（v15 幂等迁移）；`schemaVersion` 14 → 15；迁移守卫上移至 `from >= 15`
- [student_model_repository.dart](../lib/data/repositories/student_model_repository.dart)：`updateStyleFingerprint` / `getStyleFingerprint`（JSON 非法返回 null）
- [chat_service.dart](../lib/services/chat_service.dart) 步骤 5.1.2：
  - 触发时机：消息含「写作诊断分析」标记 且 主引用为章节
  - 基线策略：首次建立；无漂移时随最新文本滑动重锚（合法演化不误报）；漂移命中 → 注入 `_buildDriftHintContext`（引导 AI 一次只问一个点），不更新基线

### B62g 编辑器心流
- [app_providers.dart](../lib/providers/app_providers.dart)：`editorActivityProvider`（StateProvider<int?>，最后编辑时间秒）
- [writing_page.dart](../lib/widgets/writing_page.dart)：`_onContentChanged` 更新编辑器活动时间戳
- [chat_gates.dart](../lib/services/chat_gates.dart)：`kEditorActiveWindowSec=120` + `isEditorActive` + `isInFlow`（消息心流 或 编辑器活跃）
- [chat_service.dart](../lib/services/chat_service.dart)：`SendMessageOptions.lastEditorEditAtSec`；rapidFire 改用 `isInFlow`
- [writing_coach_panel.dart](../lib/widgets/writing_coach_panel.dart)：两处 SendMessageOptions 透传编辑器活动时间戳

### 测试（+23）
- [style_fingerprint_test.dart](../test/services/style_fingerprint_test.dart)（新建）9 用例：提取指标 / 对话占比 / 样本不足 null / JSON 往返 / 句长偏离提示 / 对话偏离提示 / 无偏离空 / 感叹号激增 / ≤3 条截断
- [chat_service_drift_injection_test.dart](../test/services/chat_service_drift_injection_test.dart)（新建）4 用例：首诊建基线不注入 / 有基线+偏离注入 / 非诊断消息门控 / 短文本不注入
- [student_model_style_fingerprint_test.dart](../test/services/student_model_style_fingerprint_test.dart)（新建）4 用例：存储往返 / 未存储 null / 列存在 / 非法 JSON 兜底
- [chat_gates_test.dart](../test/services/chat_gates_test.dart)（+6）：isEditorActive 3 + isInFlow 3
- [widget_test.dart](../test/widget_test.dart)：user_version 14 → 15

## 关键设计

- **漂移走实时通道非症候卡**：F10 二次审计修正落地——提示注入诊断 prompt（L3→L1），AI 用提问式语言（"是刻意加速，还是无意识的变化？"），软引导非硬拦截
- **基线滑动重锚**：无漂移时基线随最新文本更新（合法风格演化不误报）；漂移时保持旧基线作参照
- **规则近似降依赖**：高频词用 2-gram 指纹、描写占比用叙述占比近似——纯 Dart 无 jieba 等新依赖，保守可落地
- **向后兼容**：style_fingerprint 独立列（不动 AI 五维定性 style_profile）；SendMessageOptions 新参数可选（对话页不传仅用消息频率判定）
- **已知边界**：progressive 诊断链路（D4-A）未接漂移检测，留待后续批次；高频词为 2-gram 近似非语义分词

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **908 全绿 + 4 skipped**（+23：指纹 9 + 漂移注入 4 + 指纹存储 4 + 心流 6）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次64 定量指纹+声线漂移实时化+编辑器心流（L3 8 类定量指标 style_fingerprint + 诊断时漂移检测 L3→L1 提示注入 + student_model v15 迁移 + 编辑器 120s 活跃心流 isInFlow）+ 本日志 |
