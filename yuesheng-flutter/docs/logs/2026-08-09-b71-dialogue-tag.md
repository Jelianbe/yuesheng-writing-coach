# B71 F02 对话标签过度（B62j 后续·内容层）— 交付提交日志

**日期**：2026-08-09
**类型**：功能（F02 对话标签过度检测，并入 P011 对话疲劳症增强）
**前置**：`71e58e4`（批次 70，F12 文法与重复用词）

---

## 背景与立项

B58 内容层立项执行顺序 F10 → F12 → F02 → F09：F10（并入 B62f）、F12（批次 70）已交付，
本批次补齐 **F02 对话标签过度**（V2.0 §3.3 检测方法「对话行/非'说'类标签比例」，Lv1）。
按 B58 规划**并入 P011 对话疲劳症增强**，不新建症候（症候数保持 20）。

## 改动内容

### 检测器（新建）
- [dialogue_tag_detector.dart](../lib/services/dialogue_tag_detector.dart)：
  - `DialogueTagIssueKind.tagRepeat`：同一修饰性对话标签重复
  - 规则（保守防误报）：
    - 提取对话片段（「」/『』/双引号），对话行数 ≥3 才启用检测（`_minDialogueLines = 3`）
    - 对话后 10 字窗口内匹配「词根（的）?后缀」标签模式（词根白名单 20 个：低声/轻声/呢喃/低语/喃喃/冷冷/淡淡/沉声/厉声等；后缀：说/道/问/喊/应/答/开口/出声）
    - 同一词根出现 ≥2 次 → 观察项（`_tagRepeatThreshold = 2`，对齐 V2.0 示例「12 个'低声'」）
    - **刻意不做「修饰标签密度比例」规则**（用户确认）：词库覆盖敏感、误报风险高，先验证同标签重复稳定后再增强

### 症候知识库增强（P011，不新建症候）
- [syndrome_knowledge_base.dart](../lib/services/syndrome_knowledge_base.dart)：P011 手册补充
  - 判断原则 +1：对话标签是否依赖修饰性副词（「低声说」「呢喃道」）而非动作/表情/语境支撑？同一修饰标签是否反复出现？
  - 严重度 +1（L1）：同一修饰性对话标签重复 ≥2 次，情感全靠标签标注
  - 例外 +2：低声密语场景的功能性需要 / 人物固定的口头式说话方式（需结合人物塑造判断）
  - 诊断锚点 +1（L1 命中 F02）：3 处「低声说」标签重复示例

### 诊断链路挂接
- [chat_context_builder.dart](../lib/services/chat_context_builder.dart)：`buildDialogueTagContext`（「## 对话标签观察（F02 补充）」挂 P011 甄别措辞，空返回 null）
- [chat_service.dart](../lib/services/chat_service.dart)：5.1.7 区块——诊断标记 + 章节主引用 → 纯规则检测 → 非空注入（仿 5.1.6）

### 测试（净 +12）
- [dialogue_tag_detector_test.dart](../test/services/dialogue_tag_detector_test.dart)（+9）：空输入 / 纯叙述不误报 / 单次标签不报 / 「低声说」×3 观察项 / 对话行 <3 不报 / 中性「说道应答」不报 / 多词根不报 / 上下文空与非空
- [chat_service_dialogue_tag_injection_test.dart](../test/services/chat_service_dialogue_tag_injection_test.dart)（+3）：含重复标签注入 / 干净章节不注入 / 非诊断不注入

## 关键设计

- **并入不新建**：F02 是 P011 的检测维度增强（B58 规划「并入 P011 增强」），症候数保持 20，索引表/层级表/技术映射零改动
- **纯规则零幻觉**：与 F12 同构，检测器不调用 LLM，事实性观察与症候定义分离
- **AI 自主甄别**：注入措辞给出「低声密语功能性需要 / 人物口头式说话方式」例外，观察作为软引导非硬拦截
- **保守防误报**：对话行门槛 + 词根白名单 + 仅同标签重复规则，密度比例规则留待验证后增强
- **零新依赖零迁移**：无新表、无 schemaVersion 变更

## 四闸验证

- `dart format`：全过（范围外 `chat_service_intent_injection_test.dart`、`grammar_lexical_detector_test.dart` 格式化改动已还原——后者为批次 70 手动修 lint 后遗留的格式债，不影响 analyze）
- `flutter analyze`：0 error 0 warning（32 info 全历史存量，本批零新增）
- `flutter test`：全量 **990 全绿 + 4 skipped**（较批次 70 净 +12：检测器 9 用例 + 注入 3 用例）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次71 F02 对话标签过度（B62j 后续：DialogueTagDetector 同词根标签重复检测 + P011 对话疲劳症增强（判断原则/few-shot/例外）+ 5.1.7 诊断挂接 + 12 新用例）+ 本日志 |
