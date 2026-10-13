// ─────────────────────────────────────────────────────────────
// svc_copy — L-SVC 层用户可见话术单一真源（R-027 任务 A · 2026-10-13）
//
// 背景：D7 溯源发现服务层「失败/稍后重试/再试」族、LLM 错误码→用户文案、
// 熔断/流式超时/兜底提示散落在 llm_error_codes / llm_circuit_breaker /
// stream_guard / editor_service / message_assembly_service /
// diagnosis_flow_handler / progress_service 等多处手抄，且 recycle 族与
// llm_error_codes rateLimited 用「再试」、其余用「重试」——同一 App 两种收尾。
//
// 本文件 = L-SVC 层唯一真源：
//   - 统一模板 kOperationFailed(action, {next})：「$action失败，请稍后重试…」
//     统一用「重试」，消灭「再试」；
//   - LLM 错误码 → 用户可操作文案辅助（llm_error_codes.dart 组合消费）；
//   - 熔断开路 / 流式两段超时 / 编辑观察兜底 / 会话缺失 / 空输出占位 /
//     学习报告尾等服务层生成消息的文案常量与参数化函数。
//
// 边界：
//   - 只收「用户可见」话术；error_logs 内部留痕文案（captureError 的
//     message/context）、debugPrint、注入链 prompt 片段不进本文件；
//   - 严重度 L1-L3 / 教学状态徽标等枚举→中文映射归 L-UI
//     （ui_copy / teaching_labels），不在本层；
//   - 字符串逐字保持既有行为（既有回归测试按原文冻结），改的是「落点」。
// ─────────────────────────────────────────────────────────────

/// 统一「操作失败」模板：$action失败，请稍后重试[$next]。
///
/// 全 App 统一收尾「请稍后重试」，消灭「请稍后再试」变体。
/// [next] 为可选追加句（如「请到设置页检查」），调用方按需拼。
String kOperationFailed(String action, {String? next}) =>
    '$action失败，请稍后重试${next ?? ''}';

// ── LLM 错误码 → 用户可操作文案（llm_error_codes.dart 组合消费）──

/// 请求超时（[seconds] 秒无响应）。
String kLlmTimeoutMessage(int seconds) => '请求超时（$seconds秒无响应），请稍后重试';

/// 网络连接失败。
const String kLlmNetworkMessage = '网络连接失败，请检查网络后重试';

/// API Key 无效或已过期。
const String kLlmUnauthorizedMessage = 'API Key 无效或已过期，请到设置页检查';

/// 请求过于频繁（限流）。统一「重试」——原 llm_error_codes 误写「再试」。
const String kLlmRateLimitedMessage = '请求过于频繁，请稍后重试';

/// 服务端异常（HTTP [status]）。
String kLlmServerMessage(int? status) => '服务端异常（HTTP $status），请稍后重试';

/// 请求被拒绝（HTTP 400）。
const String kLlmInvalidRequestMessage = '请求被拒绝（HTTP 400），请检查模型名称与请求参数';

// ── 熔断开路（llm_circuit_breaker.dart 消费）──

/// 熔断开路提示：连续失败熔断，[seconds] 秒后自动恢复。
String kCircuitOpenMessage(int seconds) => '服务暂时不可用（连续失败熔断），$seconds 秒后自动恢复';

// ── 流式两段超时（stream_guard.dart 消费）──

/// 首字已到达后的空闲断流提示。
String kStreamIdleInterruptMessage(int seconds) =>
    '模型响应中断（超过 $seconds 秒未收到新内容）';

/// 首字到达前的连接超时提示。
String kStreamConnectTimeoutMessage(int seconds) =>
    '模型响应超时（超过 $seconds 秒未返回首个字符）';

// ── 服务层兜底 / 异常提示 ──

/// 编辑观察统一兜底（API/解析/校验失败时给用户，取消除外）。
const String kEditorObservationFailed = '审稿通过，但生成编辑观察失败，请稍后重试';

/// 会话不存在或已被删除（过期会话 ID 直写时抛给 UI）。
const String kSessionMissingReopen = '会话不存在或已被删除，请重新打开教练面板';

/// 空输出占位（S4b）：数据已落库但模型没给文字点评时的诚实说明。
///
/// [syndromeCount] 非空 = 有诊断块；否则按大纲实体 [entityCount] 分型。
String kEmptyContentSavedNotice({int? syndromeCount, int? entityCount}) {
  final saved = syndromeCount != null
      ? '诊断数据已保存（$syndromeCount 条症候）'
      : '大纲实体已保存（${entityCount ?? 0} 条）';
  return '$saved，但这次教练没有附上文字点评——通常是网络或模型临时故障。';
}

/// 诊断空输出硬兜底（FIX-1 留痕路径；优先走 [kEmptyContentSavedNotice]）。
const String kDiagnosisEmptyFallback = '诊断完成';

// ── 学习报告（progress_service.dart 消费）──

/// 学习报告结尾。
const String kReportFooter = '✨ 继续加油，坚持写作！';
