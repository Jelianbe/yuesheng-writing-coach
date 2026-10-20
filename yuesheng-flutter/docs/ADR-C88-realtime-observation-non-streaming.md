# ADR-C88：快速观察非流式化（规避流式首字超时）

- 状态：已实施
- 日期：2026-09-08
- 关联：ADR-C85（快速观察静默失败修复）、ADR-C87（停止生成按钮）、ADR-C80（分块诊断非流式单块）

## 背景

PGFM10（OPPO Find X6）真机验证发现两个问题：

1. **流式不实时上屏**：快速观察、诊断本章时，AI 内容不显示，点右下角暂停按钮后才出现反馈；
2. **快速观察失败**：出现「快速观察未生成有效结果，请稍后重试」（ADR-C85 兜底文案，a1980f8e 新增）。

### 数据流证据（app 内 SQLite 实测）

- messages 表：快速观察失败 2 次（「审稿通过，但生成编辑观察失败」= API 错误兜底；「快速观察未生成有效结果」= 解析失败兜底）；对话链路间歇性成功（3 次成功长回复）但最新一次发送无 assistant 回复落库；
- error_logs 表 = 0 条：所有失败静默（callEditorStream catch 与 _writeAssistantMessage 兜底均无留痕）；
- logcat：`[ChatService] 步骤8: 开始 streamChat 调用...` 后无 TTFT（`[批次55 TTFT]`）标记——流式 token 未到达回调。

### 业界比对（网搜 DeepSeek/OpenAI 兼容流式多来源）

- 项目 SSE 按行解析与业界一致（GitHub dio#2384 实证 DeepSeek chunk 会合并多个 `data:`，必须 buffer 按行拆分——项目已如此）；
- 差异点：① `callEditorStream` 用 `catch (_)` 把 `DioExceptionType.cancel` 也吞成「审稿通过…失败」误导文案；② 快速观察两处兜底不落 error_logs，失败不可观测；③ DeepSeek 流式首字延迟在真机网络下不稳定（项目注释自述「SSE 大响应深求索服务器可能 40s+ 后主动断」），60s 首字超时命中率高。

### 根因判断（区分已查证/推断）

**已查证**：快速观察两次失败 = LLM 流式未拿到有效内容（一次 API 错误兜底、一次解析失败兜底）；最新发送无回复落库。

**推断（高置信度）**：editor-observation 请求首 token 即 `[YS_EDITOR]` JSON 块（宿主流式探测确认，无自然语言导语），首字更慢；真机网络下 DeepSeek 流式首字延迟不稳定 → 60s 首字超时 → 零 token 重试再失败 → 快速观察失败率高；对话链路首字是自然语言（快）而间歇成功。「点暂停后内容才出现」= 用户等不及 → 取消 → 触发兜底文案/重发，非真正流式上屏。

## 决策

1. **`callEditorStream` 改非流式（`chatCompletion`）**：editor-observation 的 `[YS_EDITOR]` 块本就拦截不转发，流式展示无收益；非流式 60s 全响应超时远宽于流式首字 60s，且分块诊断单块已用 chatCompletion 实测可用。`onStream` 参数签名保留（兼容调用方），但不再回调增量。
2. **`chatCompletion` 增加 `CancelToken? cancelToken` 参数**：支持「停止生成」按钮对快速观察生效；取消（`DioExceptionType.cancel`）原样上抛（不转 `_buildDioError`、不触发重试——`isRetryableDioError` 已把 cancel 归为不可重试）。
3. **取消语义**：`callEditorStream` 区分取消（rethrow）与其他错误（兜底文案）；面板 `_handleRealtimeObserve` catch 区分取消（优雅复位 `cancelStreaming`，不标记失败不弹红错）。
4. **失败留痕（遗留项）**：兜底文案暂未接 captureError（error_logs 仍为零），列入后续观测增强。

## 影响面

- `lib/services/llm_client.dart`：`chatCompletion` 加可选 `cancelToken`（向后兼容，不影响既有调用方）。
- `lib/services/editor_service.dart`：`callEditorStream` 非流式化，删除 `_EditorStreamAccumulator`。
- `lib/services/realtime_observation_service.dart`：文档更新（取消除外）。
- `lib/widgets/writing_coach_panel_teaching.dart`：`_handleRealtimeObserve` 取消优雅复位。
- 测试：editor_service_test / realtime_observation_service_test / writing_coach_panel_test / writing_page_test / progressive_diagnosis_test 适配 chatCompletion override。

## 验证

- 针对性测试：editor_service_test 8 例 + realtime_observation_service_test 7 例全绿。
- 全量测试 + 六道门禁：见交付记录。
- 真机验证：待用户配合复现快速观察（预期不再出现「未生成有效结果」，取消按钮优雅复位）。
