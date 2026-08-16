# B63 意图分类器 + 标注位置自查 — 交付提交日志

**日期**：2026-08-09
**类型**：功能增强（研究落地 V2.0 §3.2 L1 意图识别分类器 + V1.0 原则1 反馈三层结构「选择」A 选项 / A2、A7 立项）
**前置**：`62848ab`（批次 62 采纳回写 + 措辞约束）

---

## 背景与立项

1. **B62b 意图分类器**（V2.0 §3.2 L1「意图识别分类器（创作/修改/询问/闲聊）」+ 信息流动）：
   - 现状差距：全项目无交互意图分类器（仅 `agent_skills.dart` 的作者意图对齐，属诊断语义非交互分类），全部消息走同一对话流
   - 目标：四分类（compose/revise/ask/smalltalk）→ 决定 prompt 构造与触发策略；L1 记录最近 3 次意图向量
2. **B62d 标注位置自查**（V1.0 原则1 反馈三层结构「选择」的 A 选项："我帮你标注这三处位置，你自己修改"）：
   - 现状差距：B61 已补 D 选项（教我原理），A 选项无出口——AI 只给建议不给位置，学员无法自查定位
   - 目标：Teacher 输出位置清单（段落 + 原文摘录），建议卡「标注位置」动作展开自查；AI 只标注、不改写（声线保护 + 反代写）

## 改动内容

### B62b 意图分类器
- [intent_classifier.dart](../lib/services/intent_classifier.dart)（新建）：
  - `UserIntent` 枚举（compose/revise/ask/smalltalk）+ `fromValue`
  - `classifyUserIntent` 规则判定：smalltalk（短句 ≤20 字 + 社交信号）→ ask（问号/疑问词）→ revise（修改动作动词）→ compose（默认）；ask 先于 revise（"这段怎么改更好"→ 询问）
  - `buildIntentInstruction`：按意图生成注入文本（compose 返回 null 不注入），附最近意图序列
- [chat_service.dart](../lib/services/chat_service.dart)：
  - `_recentIntentsBySession`：每 session 最近 3 次意图向量（L1 数据模型）
  - 步骤 5.0.1：入口分类 → 更新意图向量 → 非 compose 注入 system 指令
  - 触发联动：smalltalk → 不发起诊断/教学；ask → 不展开新诊断；revise → 降诊断强度 + 不替写正文

### B62d 标注位置自查
- [teacher_validator.dart](../lib/services/teacher_validator.dart)：`TeacherResult` 加 `locationMarks`（默认空）；schema 宽松解析——合法字符串数组采纳，缺失/非法静默忽略（可选字段不阻断整条建议）
- [agent_skills.dart](../lib/services/agent_skills.dart)：Teacher skill [YS_TEACHER] 输出协议加 `location_marks` 字段 + 「七、location_marks」说明（格式/建议/红线：只定位不改写）
- [message_card_service.dart](../lib/services/message_card_service.dart)：`TeacherSuggestionCardPayload` 加 `locationMarks`（默认空），fromJson/toJson 往返
- [chat_service.dart](../lib/services/chat_service.dart)：建议卡 payload 构建传入 `teacherResult.locationMarks`
- [teacher_suggestion_card.dart](../lib/widgets/teacher_suggestion_card.dart)：locationMarks 非空时第二行追加「标注位置」按钮（竹青描边）；点击展开位置清单（"问题位置（自查修改，月笙不改写你的正文）"），按钮切换「收起位置」

### 测试（+29）
- [intent_classifier_test.dart](../test/services/intent_classifier_test.dart)（新建）：13 用例——闲聊短句/长句不误判/疑问/请求分析/修改动作/创作默认/空串/ask 优先/指令注入（compose null、小talk 含意图序列、ask、revise）/fromValue 兜底
- [chat_service_intent_injection_test.dart](../test/services/chat_service_intent_injection_test.dart)（新建）：5 用例——smalltalk/ask/revise 注入、compose 不注入、意图向量保留最近 3 条
- [teacher_validator_location_test.dart](../test/services/teacher_validator_location_test.dart)（新建）：6 用例——合法解析/多条保留/缺失默认/非法对象忽略/含非字符串忽略/空数组
- [teacher_suggestion_card_test.dart](../test/widgets/teacher_suggestion_card_test.dart)（+3）：#11 渲染按钮 / #12 展开位置清单 / #13 无位置不渲染（向后兼容）
- [message_card_service_test.dart](../test/services/message_card_service_test.dart)（+2）：#4 payload JSON 往返含 locationMarks / #5 缺失默认空（向后兼容）

## 关键设计

- **意图注入即触发联动**：不改触发代码结构，通过 system 指令实现"smalltalk/ask 不诊断、revise 降强度"——AI 自主判断优先（软引导非硬拦截），符合项目红线
- **意图向量留内存**：L1 最近 3 次意图序列存会话内存（无新表），随注入文本进 prompt，低成本起步
- **宽松解析保健壮**：location_marks 是可选装饰字段，AI 输出非法时不整条丢弃建议（防回归）；只做定位与摘录，绝不代改（声线保护）
- **向后兼容**：payload/TeacherResult 新增字段均有默认值；无 locationMarks 时卡片四按钮布局不变

## 四闸验证

- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter analyze --no-pub`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **885 全绿 + 4 skipped**（+29：意图 13 + 注入 5 + location 校验 6 + 卡片 3 + payload 2）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次63 意图分类器+标注位置（四分类 compose/revise/ask/smalltalk + L1 意图向量注入触发联动 + Teacher location_marks 位置清单 + 建议卡「标注位置」自查按钮）+ 本日志 |
