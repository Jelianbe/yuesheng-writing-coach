# T3 训练系统闭环交付提交日志

**日期**：2026-08-07
**批次**：T3 训练系统（练习任务闭环）
**范围**：训练系统 UI 闭环 + persistAttitude 事务双写修复

---

## 变更概述

将「Teacher 建议 → 开始练习」从占位打通为完整练习闭环，对齐 RN 端（yuesheng-android）的 `practice-store.ts` / `PracticeTaskCard.tsx` / `PracticeResultIndicator.tsx` 接线方式：

1. **练习状态管理**（`practiceStoreProvider`）：activePracticeTask / trainingResult / isSubmitting
2. **练习任务卡**：症候名 chip + 任务描述 + 练习目标 + 作答输入 + 跳过/提交
3. **结果指示器**：passed（竹青）/ partial（矿物黄）/ failed（矿物红，可再试）
4. **提交作答闭环**：复用 `sendMessage` 链路，强制 `subphase=FEEDBACK`，触发 chat_service 步骤 11 的 `parseTrainingResult` + `appendTeachingHistory` 落库，`onTrainingResult` 回调回写练习结果
5. **双入口接线**：WritingCoachPanel（作品诊断入口）+ ChatPage/MessageList（对话入口）

## 提交日志

| Commit | 日期 | 标题 | 摘要 |
|--------|------|------|------|
| `persistAttitude` 修复 | 2026-08-07 | fix: persistAttitude 事务双写 | teaching_state.attitude_level + student_model.attitude_preference 事务内双写，student_model 不存在时自动建行，任一失败整体回滚（对齐 RN persistAttitudeTx） |

## 本次改动明细（训练系统闭环）

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/providers/practice_providers.dart` | 新增 | PracticeTask / PracticeState / PracticeStore（StateNotifier）+ practiceStoreProvider 全局单例，复刻 RN practice-store.ts |
| `lib/widgets/practice_task_card.dart` | 新增 | 练习任务卡片：Header「练习任务」+ 症候名 chip + 任务描述 + 练习目标 + 3-4 行作答输入 + 跳过/提交作答；submitting 时禁用输入 + 按钮转 loading |
| `lib/widgets/practice_result_indicator.dart` | 新增 | 练习结果指示器：passed/partial/failed 三态配色与文案；failed 时可「再试一次」，始终可「关闭」 |
| `lib/services/chat_service.dart` | 修改 | `SendMessageCallbacks` 新增 `onTrainingResult` 字段，步骤 11 训练落库后接线回调 |
| `lib/widgets/teacher_suggestion_card.dart` | 修改 | `_handleStartPractice` 从 SnackBar 占位改为 `startPractice` 启动练习任务（syndromeId / syndromeName / taskDescription / taskGoal） |
| `lib/widgets/writing_coach_panel.dart` | 修改 | `_handleSend` 支持 subphase + onTrainingResult 透传；新增 `_submitPractice`（强制 FEEDBACK）；消息列表底部渲染练习卡 + 结果指示器 |
| `lib/widgets/chat_page.dart` | 修改 | `_handleSend` 支持 subphase + onTrainingResult；新增 `_submitPractice`；`_buildBody` 读取 practiceStoreProvider 并传给 MessageList |
| `lib/widgets/message_list.dart` | 修改 | 新增 activePracticeTask / trainingResult / isPracticeSubmitting / onSubmitPractice / onSkipPractice / onDismissResult 参数，列表底部渲染练习卡 + 结果指示器 |

## 测试改动

| 文件 | 改动 | 说明 |
|------|------|------|
| `test/widgets/practice_task_card_test.dart` | 新增 | 5 测试：渲染 / 空提交不触发 / 输入提交（trim）/ 跳过 / submitting 禁用+loading |
| `test/widgets/practice_result_indicator_test.dart` | 新增 | 5 测试：passed / partial / failed+onRetry / 关闭 / details |
| `test/services/chat_service_send_message_test.dart` | 修改 | 新增 #8（FEEDBACK+达标 → onTrainingResult passed）/ #9（未达标 → failed） |
| `test/widgets/teacher_suggestion_card_test.dart` | 修改 | #3 从断言 SnackBar 改为断言 practiceStore.activePracticeTask 已设置 |

## 补充提交（failed「再试一次」闭环）

| Commit | 日期 | 标题 | 摘要 |
|--------|------|------|------|
| `feat: T3 补「再试一次」闭环` | 2026-08-07 | PracticeStore.retryPractice | failed 结果可重新打开上次练习任务（清空结果），对齐 RN onRetry 语义（清结果 + 回 PRACTICE） |

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/providers/practice_providers.dart` | 修改 | `PracticeStore` 新增 `_lastTask` + `retryPractice()`（重新打开上次任务并清空结果）；`resetPractice` 一并清空 `_lastTask` |
| `lib/widgets/message_list.dart` | 修改 | 新增 `onRetryPractice` 参数，透传给 PracticeResultIndicator |
| `lib/widgets/chat_page.dart` | 修改 | MessageList 传入 `onRetryPractice` → `retryPractice()` |
| `lib/widgets/writing_coach_panel.dart` | 修改 | PracticeResultIndicator 新增 `onRetry` → `retryPractice()` |
| `test/providers/practice_providers_test.dart` | 新增 | 7 测试：start / submit / skip / setTrainingResult / retry（恢复任务+清结果）/ retry（无任务不变）/ reset 后不可 retry |

## 补充提交（态度切换 UI 入口，打通 persistAttitude 全链路）

二次验收发现 `chat_service.persistAttitude / loadAttitudeState` 无调用方（Flutter 端态度切换无 UI 入口，ChatPage 硬编码 doubao）。补齐入口打通 UI → service → 双写全链路：

| Commit | 日期 | 标题 | 摘要 |
|--------|------|------|------|
| `feat: 态度切换 UI 入口` | 2026-08-07 | AttitudeIndicator + ChatPage 接线 | AppBar 态度档位指示器 + 底部选择面板，乐观更新 + persistAttitude 失败回滚 |

| 文件 | 改动 | 说明 |
|------|------|------|
| `lib/widgets/attitude_indicator.dart` | 新增 | 复刻 RN AttitudeIndicator：顶部指示器（色点+当前档位）→ 底部面板三档选择；档位配置对齐 attitude-rhythm.json（豆包/月笙如歌/sensei + 语气说明），配色用月色竹青矿物色（l1Text/l2Text/l3Text） |
| `lib/widgets/chat_page.dart` | 修改 | `_attitude` 状态（默认 doubao）；bootstrap 完成后 `loadAttitudeState` 恢复；`_handleAttitudeChange` 乐观更新 → persistAttitude → 失败回滚+SnackBar；AppBar actions 挂 AttitudeIndicator；`_handleSend` 用当前档位替代硬编码 doubao |
| `test/widgets/attitude_indicator_test.dart` | 新增 | 5 测试：渲染当前档位 / 面板三档名称与说明 / 选择回调 / 当前档位勾选 / 选择后面板关闭 |
| `test/widgets/chat_page_test.dart` | 修改 | 新增 #13：切换态度 → UI 更新 + teaching_state/student_model 双写（自动建行）验证 |

## 四闸验证

- `dart analyze`：0 error（8 个 info 均为 ChatService 构造函数 pre-existing lint，非本次引入）
- `dart format --set-exit-if-changed`：全过（0 changed）
- `flutter test`：全量 **387 个测试全绿**
- 文档同步：本日志
