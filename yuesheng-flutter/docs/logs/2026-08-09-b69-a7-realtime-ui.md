# B69 A7 双模型分级·实时通道 UI 入口（B62j）— 交付提交日志

**日期**：2026-08-09
**类型**：功能（A7 双通道第二步：快速观察按钮）
**前置**：`6bea990`（批次 68，A7 服务层拆分）

---

## 背景与立项

A7 双模型分级（延续批次 68）：双通道 = **实时通道只跑 Editor 观察（轻 prompt）+ 复盘通道全量（重）**。
批次 68 完成服务层拆分（RealtimeObservationService）；批次 69 接上 **WritingCoachPanel「快速观察」按钮**——实时通道的 UI 出口。

## 改动内容

### UI 入口（WritingCoachPanel）
- [writing_coach_panel.dart](../lib/widgets/writing_coach_panel.dart)：
  - 按钮行新增「快速观察」（⚡ 图标，置于「诊断本章」左侧）——实时通道入口
  - `_handleRealtimeObserve()`：等待会话初始化 → 读当前章节内容（writingStore.localContent）→ **字数校验 ≥50 字**（短文本观察无意义，SnackBar 拦截）→ 调 `realtimeObservationServiceProvider.observe`（targetRefType=chapter / targetRefId=chapterId）→ 流式显示（appendStreamingContent）→ 完成后刷新消息列表（observe 内部已写 assistant 消息 + R1 入库）
  - 流式/诊断中按钮统一禁用（沿用 isStreaming）

### 复盘通道
- 「诊断本章」（全量 ChatService）保持现状——轻/重双通道在面板内并置，用户按需选择

### 测试（净 +3）
- [writing_coach_panel_test.dart](../test/widgets/writing_coach_panel_test.dart)：
  - #7 「快速观察」按钮渲染（A7 实时通道入口存在）
  - #8 点击快速观察 → 实时观察反馈写入消息列表（轻通道，不触发全量诊断）
  - #9 字数不足（<50 字）→ SnackBar 拦截，不写入观察消息

## 关键设计

- **双通道并置**：面板按钮行「快速观察（轻）| 诊断本章（重）」——用户按需选择；轻通道低延迟不阻断创作流
- **字数门槛 50 字**：介于选段诊断（20）与整章诊断（100）之间，短文本观察无意义
- **零新依赖**：复用批次 68 的 RealtimeObservationService + ChatStore 流式接口，无新表/无迁移
- **AI 自主判断优先**：观察结果作为轻量反馈呈现，不做硬拦截

## 四闸验证

- `dart format`：全过（范围外文件格式化后已还原）
- `flutter analyze`：0 error 0 warning（32 info 全历史存量，未新增）
- `flutter test`：全量 **965 全绿 + 4 skipped**（较批次 68 净 +3：快速观察 3 用例）
- 文档同步：本日志

## 提交

| Commit | 日期 | 标题 |
|--------|------|------|
| （本次） | 2026-08-09 | feat: 批次69 A7 实时通道 UI 入口（B62j：WritingCoachPanel「快速观察」按钮 + RealtimeObservationService 接入，轻/重双通道并置，字数门槛 50）+ 本日志 |
