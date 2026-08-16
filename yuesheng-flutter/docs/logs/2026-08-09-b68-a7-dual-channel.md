# B68 A7 双模型分级·服务层拆分（B62j）— 交付提交日志

**日期**：2026-08-09
**类型**：架构服务层拆分（A7 双通道第一步）
**前置**：`83e5fdb`（批次 67，A6 第二迭代 F07/F11）

---

## 背景与立项

B62j「A7 双模型分级」（规格权威来源：docs/2026-08-09-b58-research-audit.md L135 + V2.0 §4.1）：
- 双通道 = **实时通道只跑 Editor 观察（轻 prompt）+ 复盘通道全量（重）**
- 模型策略（V2.0 §4.1）：轻量模型 → 实时反馈（低延迟）；重量模型 → 章末深度分析（高质量）
- 落点：`writing_coach_panel.dart`、`evaluation_report_panel.dart`

**审计结论**：Editor 轻观察链路（`callEditorStream` + editor-observation skill）已存在，但只嵌在 Reviewer 门控对话流内（发消息时才跑），无独立「边写边教」实时出口；复盘通道（「诊断本章」全量 ChatService）已有。

**执行决策（用户确认）**：**仅服务层拆分**——抽出实时通道服务（轻 prompt + 入库），不接 UI 按钮（后续批次再接入口）。

## 改动内容

### 实时通道服务（新）
- [realtime_observation_service.dart](../lib/services/realtime_observation_service.dart)（新）：`RealtimeObservationService`（依赖 LlmClient + SessionRepository + EditorObservationRepository）
  - `kRealtimeObservationConstraint`：轻量观察约束（表达密度对齐）——一次只观察一个点 / 最小示范 ≤2 句 / 只定位不代改正文 / 提问式温和表达
  - `observe({sessionId, text, targetRefType, targetRefId, onStream, cancelToken})`：轻 prompt 调用（editor-observation skill + 轻量约束）→ displayContent 写为 assistant 消息 → observation 入库（R1：总是入库）→ 返回 `RealtimeObservationResult`（displayContent + observation + messageId）；失败兜底不抛出

### 轻通道扩展（复用层）
- [editor_service.dart](../lib/services/editor_service.dart)：`callEditorStream` 增加可选 `extraSystemMessages`（默认 `const []`，不影响既有 Reviewer 链路调用）——轻通道附加轻量约束 system 消息

### 装配
- [session_providers.dart](../lib/providers/session_providers.dart)：新增 `realtimeObservationServiceProvider`（注入 llmClient + SessionRepository + EditorObservationRepository）

### 复盘通道
- 保持现状：「诊断本章」全量 ChatService（重通道），本轮不动

### 测试（净 +5）
- [realtime_observation_service_test.dart](../test/services/realtime_observation_service_test.dart)（新，4 用例）：observe 成功 → 返回 + observation 入库 / 流式回调透传 + targetRef 入库 / LLM 失败 → 兜底不入库 / 轻量约束 system 消息已附加
- [editor_service_test.dart](../test/services/editor_service_test.dart)（+1，#8）：extraSystemMessages 追加到 system 消息（默认不影响既有调用）

## 关键设计

- **双通道语义**：实时通道 = 轻 prompt（Editor 观察 + 表达密度约束，低延迟）；复盘通道 = 全量诊断（重）；本轮先服务层就绪，UI 出口后续批次接
- **R1 原则延续**：实时观察总是入库（teacher_triggered=false），复用 editor_observation 表，不新增表/迁移
- **失败兜底不抛出**：API/解析失败 → observation=null + 兜底文案写会话（用户可见），不阻断创作流
- **无新 schema**：纯服务层 + 装配 + 测试，DB schemaVersion 不变（仍为 17）

## 四闸验证

- `dart format`：全过（批次文件 0 changed；范围外文件格式化后已还原）
- `flutter analyze`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **962 全绿 + 4 skipped**（较批次 67 净 +5：实时通道 4 + editor_service 1）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次68 A7 双模型分级服务层拆分（B62j：RealtimeObservationService 实时通道轻 prompt + 轻量约束 + R1 入库，callEditorStream extraSystemMessages 扩展，复盘通道保持全量）+ 本日志 |
