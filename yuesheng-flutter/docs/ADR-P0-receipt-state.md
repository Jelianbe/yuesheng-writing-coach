# ADR-P0：机器回执态（Reply Receipt State）

- 状态：Proposed → Accepted（2026-08-18）
- 关联：设计借鉴文档 `yuesheng-design-borrow-2026-08-18.md` 选项 A；福帮手「质量态三档」设计思想
- 改动范围：`lib/services/reply_receipt_guard.dart`（新增）、`lib/services/chat_service_send.dart`（接入一处）、`test/services/reply_receipt_guard_test.dart`（新增）

## 背景

「月笙写作教练」的定位是「只定位、不代改、不替决定」。但在实际 LLM 输出中，模型偶尔会自称「已保存 / 已导出 / 已应用 / 已修改」——这些动作教练本回合并未真实执行（保存/导出/应用/修改正文是学员或 UI 的职责，不是教练的职责）。这会造成「我已替你做过」的虚假承诺，违背诚实原则，也偏离「不替写」红线。

福帮手（长文档改稿专家）提出的「质量态三档」——`advisory`（建议）/ `machine_receipt_present`（机器回执已出具）/ `human_review_pending`（等待人工复核）——正是为解决这个问题：凡声称已完成某动作，必须有底层动作的**真实回执**，否则只能说「建议」。

## 决策

新增**纯函数式守护** `ReplyReceiptGuard.sanitize`，在 assistant 回复落库前扫描文本：

- 定义 `ReceiptAction`（saved/exported/applied/modified）与 `ReceiptStatus`（receipt_ok / human_review_pending）。
- 仅匹配字面「已X」连续写法（如「已保存」）。若该动作不在本回合真实落库动作的 `receipts` 集合中，则改写为「建议X」。
- 真实回执由调用方（chat_service_send）依据本次 service 实际 DB 写入情况构造：
  - 诊断提交（diagnosis != null）→ 诊断作为结构化数据已落库，允许「已保存」；
  - Editor observation 落库 → 允许「已保存」；
  - Teacher suggestion 落库 → 允许「已保存」。
- 「已应用 / 已修改」属于「替正文做改动」的动作，教练永不执行，故默认不在 receipts 中，任何此类声明一律降级。

## 理由

1. **零侵入**：不改动诊断/教学/引用链路，仅在落库前对文本做一次降级，风险最低。
2. **对齐红线**：与「不替写 / 不替决定」天然契合——教练不能声称自己做了对用户文件有副作用的事。
3. **可测试**：纯函数，独立单测覆盖升降级路径；不依赖网络/IO。
4. **保守安全**：只匹配「已X」连续形态，不以「为你/帮你」等主语猜测，避免误伤正常教学文本（如学员原文讨论「已保存」场景）。

## 影响与边界

- **不处理**：多智能体「写手→评审」回路（违反「不替写」，明确不采纳）。
- **不处理**：跨会话项目级记忆（列为 P1 `writing_asset_repository`，见设计文档）。
- **已知局限**：「已为你保存」等「已+代词+动作」非连续写法暂不拦截（保守优先，避免误伤）；后续若发现此类高频误声称，可扩展主语正则。
- **测试**：新增 `reply_receipt_guard_test.dart`；接入点位于 `chat_service_send.dart` 步骤 10 落库前，对 `finalContent` 做降级后写入。

## 验收

- `dart analyze` 无 error；`flutter test` 全绿（含新增单测）。
- 现有 1793 测试不受影响（教练回复文本断言不涉及「已应用/已修改」声明）。
