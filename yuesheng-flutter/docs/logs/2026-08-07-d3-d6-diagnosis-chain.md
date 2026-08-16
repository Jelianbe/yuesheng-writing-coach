# D3–D6 诊断链路交付提交日志

**日期**：2026-08-06 ~ 2026-08-07
**批次**：D3（DiagnosisCard 呈现层）→ D4-B（GrowthStore 数据访问修复）→ D4-A（长文本分块诊断真链路）→ D5-A（教练面板卡片化）→ D5-B（诊断卡片交互闭环）→ D6（Teacher 建议卡片）
**基线**：`f6d0416`（UX 审计三批次修复）
**范围**：`f6d0416..HEAD`，16 个文件，+3160 / -143

---

## 变更概述

将诊断流程从"结果仅落库、对话流不可见"打磨为完整的端到端闭环：诊断结果以卡片形式渲染（D3）、长文本分块诊断接通真 LLM 链路（D4-A）、数据访问层合规化（D4-B）、教练面板卡片化与中间态优化（D5-A）、诊断症候确认/质疑交互闭环（D5-B）、Teacher 建议以三按钮卡片进入对话流（D6）。

**核心设计决策**：诊断链路按内容长度路由（≤4000 字单次 / >4000 字分块）；分块链路完成后复用 `sendMessage` 的解析+持久化步骤，保证两条路径产出同一结构的 `diagnosis_result` 卡片。

## 提交日志

| Commit | 日期 | 标题 | 摘要 |
|--------|------|------|------|
| `47ca64c` | 2026-08-06 | feat: D3 DiagnosisCard 呈现层 | 新增诊断卡片组件，对话流分派 `diagnosis_result` 渲染结构化诊断结果 |
| `a0316fd` | 2026-08-06 | fix: D4-B GrowthStore 数据访问层修复 | 取消裸查 `db.select`，改走 `diagRepo.listRecentDiagnoses` |
| `2267186` | 2026-08-06 | feat: D4-A D2 长文本分块诊断真链路 | `runProgressiveDiagnosis` 从占位改为真链路，注入 LlmClient，新增 `commitDiagnosisFromContent` |
| `4a11fd0` | 2026-08-06 | fix: D5-A 教练面板卡片化 + 中间态优化 | 面板渲染 DiagnosisCard、诊断中禁用按钮、流式"思考中"占位 |
| `1f1dcff` | 2026-08-06 | feat: D5-B 诊断卡片交互闭环 | 症候确认栏（pending→confirmed/partial/disputed），对齐 RN DiagnosisConfirmationBar |
| `464f1f1` | 2026-08-07 | feat: D6 Teacher 建议三按钮卡片进入对话流 | 新增 TeacherSuggestionCard，persist 成功后写卡片消息，支持标记已解决 |

## 各批次改动明细

### D3 — DiagnosisCard 呈现层（`47ca64c`）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/diagnosis_card.dart` | 新增 | 诊断卡片组件（症候列表 / 严重度色块 / 细节展开） |
| `lib/services/message_card_service.dart` | 修改 | 支持写 `diagnosis_result` 类型卡片消息 |
| `lib/widgets/message_list.dart` | 修改 | 分派 `diagnosis_result` → DiagnosisCard |
| `test/widgets/diagnosis_card_test.dart` | 新增 | 卡片渲染测试 |

### D4-B — GrowthStore 数据访问层修复（`a0316fd`）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/data/repositories/diagnosis_repository.dart` | 修改 | 新增 `listRecentDiagnoses({limit = 10})` 跨 session 查询（ORDER BY timestamp DESC + LIMIT） |
| `lib/providers/growth_providers.dart` | 修改 | 删除 `_listRecentDiagnoses` 裸查方法，改调 repo；移除 drift import |
| `test/data/repositories/diagnosis_repository_test.dart` | 修改 | 新增 3 测试（空 DB / 跨 session / limit 参数） |

### D4-A — 长文本分块诊断真链路（`2267186`）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/services/progressive_diagnosis.dart` | 修改 | `runProgressiveDiagnosis` 占位 → 真链路：splitContent 分块 → 逐块 `chatCompletion` 分析（失败计数）→ `streamChat` 流式合并 → ProgressiveResult；新增 `_parseChunkNotes` |
| `lib/providers/session_providers.dart` | 修改 | 新增 `llmClientProvider` 单例；`chatServiceProvider` 注入 llmClient |
| `lib/services/chat_service.dart` | 修改 | 新增 `commitDiagnosisFromContent(sessionId, fullContent)`，复用 sendMessage 步骤 9-11（parseDiagnosis → validate → 写 assistant 消息 → commitDiagnosisWithHistory → insertDiagnosisResultCard） |
| `lib/widgets/writing_coach_panel.dart` | 修改 | 分块链路完成后调 `commitDiagnosisFromContent` 并刷新 |
| `test/services/progressive_diagnosis_test.dart` | 修改 | 更新 #5 传 llmClient；新增 #6 长文本分块链路测试；新增 `_FakeLlmClient` |

### D5-A — 教练面板卡片化 + 中间态优化（`4a11fd0`）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/writing_coach_panel.dart` | 修改 | `_buildMessageList` 分派 `diagnosis_result` → DiagnosisCard；新增 `_ThinkingPlaceholder`（竹青头像+转圈+文案）；`_buildButtonRow(isStreaming)` 流式/诊断中禁用诊断按钮；`_handleDiagnose` 加 `_isDiagnosing` 置位/复位 + 完成 SnackBar"诊断完成" |
| `test/widgets/writing_coach_panel_test.dart` | 修改 | 新增 3 个 D5A 测试（诊断卡渲染/按钮禁用/思考中占位）；修复 D1-4 测试收尾被误删问题 |

### D5-B — 诊断卡片交互闭环（`1f1dcff`）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/providers/session_providers.dart` | 修改 | 新增 `diagnosisServiceProvider`（DiagnosisService 唯一 Owner） |
| `lib/widgets/diagnosis_card.dart` | 修改 | 改 `ConsumerStatefulWidget` + 新增 `sessionId` 参数；每症候块底部渲染 `_SyndromeConfirmationBar`（pending→confirmed/partial/disputed，调 DiagnosisService 落库 + 即时本地切换；认同=竹青底/部分认同=矿物黄边框/不认同=矿物红边框） |
| `lib/widgets/message_list.dart` / `writing_coach_panel.dart` | 修改 | `fromMessageContent` 增加 `sessionId` 透传 |
| `test/widgets/diagnosis_card_test.dart` | 修改 | 既有 4 测试加 ProviderScope 包装；新增 4 个 D5B 测试（三按钮渲染/认同落库/不认同/无 session 不渲染） |

### D6 — Teacher 建议卡片（`464f1f1`）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/teacher_suggestion_card.dart` | 新增 | 三按钮卡片（开始练习/跳过此建议/查看详情），症候名称 chip（非代号）、难度徽标（入门/进阶/挑战）、详情展开（任务类型/评估标准）；`fromMessageContent` JSON 解析 + 兜底；`_dismiss` 调 `markResolved` 落库 + 本地隐藏；无 onStartPractice 回调时 SnackBar"训练功能即将上线" |
| `lib/services/message_card_service.dart` | 修改 | 新增 `TeacherSuggestionCardPayload` + `insertTeacherSuggestionCard`（写 system + teacher_suggestion 消息） |
| `lib/services/chat_service.dart` | 修改 | `persistTeacherSuggestion` 成功后写卡片消息；从 `diagnosis.syndromes` 解析目标症候名称（非代号） |
| `lib/data/repositories/teacher_suggestion_repository.dart` | 修改 | 新增 `markResolved(suggestionId)`（status='resolved' + resolvedAt） |
| `lib/widgets/message_list.dart` / `writing_coach_panel.dart` | 修改 | 分派 `teacher_suggestion` → TeacherSuggestionCard |
| `test/widgets/teacher_suggestion_card_test.dart` | 新增 | 6 个测试 |

## 诊断链路全景

```
写作页触发 (WritingCoachPanel._handleDiagnose)
    │
    ├─ ≤4000 字 ──→ ChatService.sendMessage（单次诊断）
    │                    │
    │                    ├─ 流式拦截 [YS_DIAGNOSIS] → parseDiagnosis
    │                    ├─ validate → commitDiagnosisWithHistory
    │                    └─ insertDiagnosisResultCard → MessageList 渲染 DiagnosisCard
    │
    └─ >4000 字 ──→ runProgressiveDiagnosis(llmClient)   [D4-A 真链路]
                        ├─ splitContent 分块 → 逐块 chatCompletion 分析
                        ├─ streamChat 流式合并 → ProgressiveResult
                        └─ commitDiagnosisFromContent（复用 sendMessage 步骤 9-11）
```

卡片交互闭环（D5-B）：症候确认栏状态机 `pending → (confirmed | partial | disputed)`，落库到 DiagnosisService 并即时切换本地样式。

Teacher 建议（D6）：`shouldTriggerTeacherForDiagnosis` 触发（L2/L3 或症候数≥3）→ persist 成功 → 写 `teacher_suggestion` 卡片消息 → 对话流三按钮卡片；「跳过此建议」调 `markResolved` 落库。

## 影响分析

### 用户可见变化
- 写作页诊断结果以结构化卡片呈现，替代原始 JSON
- 长文本（>4000 字）诊断走真分块链路，不再回退单次
- 诊断中按钮禁用 + "思考中"占位，避免误触与空白等待
- 每个症候可确认/部分认同/不认同，反馈即时落库
- Teacher 建议以三按钮卡片进入对话流（症候名称而非代号）

### 数据层影响
- 新增 `listRecentDiagnoses` / `markResolved` / `commitDiagnosisFromContent`，均为增量方法，不破坏既有接口
- 会话隔离不变：写作页诊断走章节隔离会话（`getOrCreateSessionForChapter`），与 Tab2 主会话互不污染

### 回归风险
- 全量测试 361 通过，唯一失败为 pre-existing `persistAttitude`（与 D3–D6 无关）

## 验证结果

### 四闸验证（最终状态，2026-08-07）

| 闸门 | 命令 | 结果 |
|------|------|------|
| 闸 1 analyze | `flutter analyze` | ✅ 0 error（31 个 info 均为既有代码风格提示，含新增测试文件的 prefer_initializing_formals，无 error） |
| 闸 2 format | `dart format --set-exit-if-changed` | ✅ 各批次提交前均通过 |
| 闸 3 test | `flutter test` | ✅ 361 通过 / 1 pre-existing 失败（persistAttitude，非本批次范围） |
| 闸 4 文档 | 本文档 | ✅ 已同步 |

### 测试覆盖

| 组件 | 新增/更新测试 | 覆盖点 |
|------|--------------|--------|
| DiagnosisCard | 4（既有）+ 4（D5B） | 卡片渲染 / 三按钮 / 认同落库 / 不认同 / 无 session 不渲染 |
| WritingCoachPanel | 3（D5A）+ 既有回归 | 诊断卡渲染 / 按钮禁用 / 思考中占位 |
| TeacherSuggestionCard | 6 | 三按钮 / 症候名称 chip / 难度徽标 / 详情展开 / markResolved / 兜底 |
| progressive_diagnosis | #5 更新 + #6 新增 | 长文本分块真链路 / FakeLlmClient |
| listRecentDiagnoses | 3 | 空 DB / 跨 session / limit 参数 |
| **合计** | **20 新增 + 回归 341** | **361 通过 / 1 pre-existing 失败** |

## 关键技术决策

### 决策 1：分块链路复用持久化（D4-A）
- **问题**：分块诊断结果若走独立持久化路径，会与单次链路产出结构不一致
- **方案**：新增 `commitDiagnosisFromContent`，显式复用 `sendMessage` 步骤 9-11（解析+校验+写消息+提交+插卡）
- **收益**：两条路径产出同一结构的 `diagnosis_result` 卡片，呈现层无需分支

### 决策 2：确认栏状态机对齐 RN（D5-B）
- **问题**：Flutter 端 DiagnosisService 确认/质疑方法零 UI 调用
- **方案**：`_SyndromeConfirmationBar` 状态机 pending→(confirmed/partial/disputed)，对照 RN `DiagnosisConfirmationBar` 三按钮设计
- **配色**：认同=竹青底 / 部分认同=矿物黄边框 / 不认同=矿物红边框，对齐月色竹青规范

### 决策 3：Teacher 建议卡片化而非气泡（D6）
- **问题**：Teacher 建议已落库但对话流无可见交互入口
- **方案**：独立 `teacher_suggestion` 消息类型 + 三按钮卡片，满足记忆硬约束（开始练习/跳过此建议/查看详情 + 症候名称而非代号）

### 决策 4：llmClient 单例注入（D4-A）
- **问题**：`runProgressiveDiagnosis` 需要真 LLM 调用，但原实现零依赖
- **方案**：`llmClientProvider` 全局单例，ChatService 与分块链路共享同一客户端实例，测试注入 `_FakeLlmClient` 可完整断言

## 回滚步骤

如需回滚 D3–D6 批次：

```bash
# 1. 查看提交历史
git log --oneline | grep "D3\|D4\|D5\|D6\|DiagnosisCard\|TeacherSuggestion\|progressive"

# 2. 回退到 D3 前的提交（基线 f6d0416）
git reset --hard f6d0416

# 3. 涉及文件（手动核对）
# 新增：lib/widgets/diagnosis_card.dart、lib/widgets/teacher_suggestion_card.dart
# 修改：lib/services/{chat_service,message_card_service,progressive_diagnosis}.dart
#        lib/providers/{session_providers,growth_providers}.dart
#        lib/widgets/{message_list,writing_coach_panel}.dart
#        lib/data/repositories/{diagnosis_repository,teacher_suggestion_repository}.dart
# 测试：test/ 下对应 4 个测试文件
```

若仅需回退单个批次，按 commit 顺序逐个 `git revert`（存在提交间依赖，建议逆序处理）。

## 后续任务

- [ ] 修复 pre-existing `TeachingStateRepository persistAttitude` 失败（独立批次）
- [ ] 「开始练习」按钮接入训练系统（当前 SnackBar 占位"训练功能即将上线"）
- [ ] 真机测试：验证长文本（>4000 字）分块诊断在真实 LLM 下的流式体验与延迟
- [ ] 端到端验证：完整诊断 → 确认症候 → Teacher 建议卡片出现 → 标记已解决的闭环
