// ─────────────────────────────────────────────────────────────
// diagnosis_failure_reason — 诊断失败原因码（A2）
//
// 任务来源：`.ai/reports/2026-11-16-SCREENING-REPORT.md` A2 节
//   「诊断失败原因不可区分」—— 落库卡片只有 `failureCount`，
//   无法判断是 LLM 调用失败 / 结构化输出解析失败 / 症候匹配为空 / 超时。
//
// ★ 本文件只做**分类**，不做判定：
//   ① 不改变 `_recordDiagnosisOutcome` 的 success 口径（`diagnosis != null`）；
//   ② 不改变失败卡文案与阈值（`diagnosis_failed_card.dart` 一字不动）；
//   ③ 不新增用户可见文案 ⇒ **不触 R-027**（改的是内部日志语义）。
//
// 为什么要独立成文件而不是塞进 `diagnosis_flow_handler.dart`：
//   解析侧（`diagnosis_flow_handler`）与发送侧（`chat_service`）**都要写同一个
//   event 键**，两侧各自内联一份码表 ⇒ 必然漂移（本项目「同一事实多处表述」
//   已吃过多次亏）。**单一真源 = 本文件**。
//
// 与本文件同型的既有先例：`diagnosis_parser.dart` 的 `kDiagnosisRejectReasons`
//   （12 处 `return ParseResult(rejectReason: ...)` 与之一一对应）。
//   本文件是其**上位归类**——那 12 个码归入 [kDiagnosisFailureParseFailed] 一类，
//   保留原码在 `detail` 里，不丢信息。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:dio/dio.dart' show DioException, DioExceptionType;
import 'package:writingcoach/services/error_handler.dart';

/// LLM 调用失败（网络 / 鉴权 / 供应商 5xx / 空流出错等，非超时）。
const String kDiagnosisFailureLlmCallFailed = 'llm_call_failed';

/// 结构化输出解析失败（诊断块缺失 / JSON 非法 / 字段校验不过）。
///
/// 对应 `diagnosis_parser.dart` 的 `kDiagnosisRejectReasons` 全 12 个码。
const String kDiagnosisFailureParseFailed = 'parse_failed';

/// 症候匹配结果为空（解析通过但一条症候都没有，或被排除集全部剥掉）。
///
/// ★ 语义边界：这是**观测项**，不是失败计数项 —— 现有判定 `diagnosis != null`
/// 仍算成功（一条症候都没报也是模型的有效输出）。A2 只让它**可被看见**，
/// 不改它是否计入 `failureCount`。
const String kDiagnosisFailureEmptyMatch = 'empty_match';

/// 超时（连接 / 首 token / idle）。
const String kDiagnosisFailureTimeout = 'timeout';

/// 无法归类时的兜底码（**不吞**：出现即说明分类器需要补一类）。
const String kDiagnosisFailureUnknown = 'unknown';

/// 失败原因码全集（A2 要求至少四类，本表五类）。
///
/// 顺序 = 报告呈现顺序，与 [classifyDiagnosisFailureError] 的判定优先级无关。
const List<String> kDiagnosisFailureReasons = [
  kDiagnosisFailureLlmCallFailed,
  kDiagnosisFailureParseFailed,
  kDiagnosisFailureEmptyMatch,
  kDiagnosisFailureTimeout,
  kDiagnosisFailureUnknown,
];

/// `error_logs.context.event` 的唯一取值。
///
/// 解析侧与发送侧**写同一个键** ⇒ 一次查询即可看到全部诊断失败，
/// 再用 `path` 字段区分是哪条路径产生的（`parse` / `send`）。
const String kDiagnosisFailureEvent = 'diagnosis_failure';

/// 把发送侧抛出的异常归类为 [kDiagnosisFailureTimeout] 或
/// [kDiagnosisFailureLlmCallFailed]。
///
/// 判定顺序：先看类型（精确），再看字符串（兜底）。**不做语义猜测**——
/// 归不了类就返回 [kDiagnosisFailureUnknown]，让「分类器缺一类」暴露出来，
/// 而不是塞进 `llm_call_failed` 假装已知。
///
/// ★ 为什么用 `Set.contains` 而不是 `switch`：`DioExceptionType` 是**第三方枚举**，
/// 上游新增成员会让穷举 `switch` 直接编译失败（本轮实测就撞上
/// `transformTimeout`）⇒ 门禁 1 红而与本任务无关。集合判定对上游扩展**免疫**：
/// 新类型会被默认归入 `llm_call_failed`（调用确实失败了，归大类不撒谎），
/// 只要把它加进 `_kDioTimeoutTypes` 即可升级为精确超时。
const Set<DioExceptionType> _kDioTimeoutTypes = {
  DioExceptionType.connectionTimeout,
  DioExceptionType.sendTimeout,
  DioExceptionType.receiveTimeout,
};

String classifyDiagnosisFailureError(Object error) {
  if (error is TimeoutException) return kDiagnosisFailureTimeout;
  if (error is DioException) {
    return _kDioTimeoutTypes.contains(error.type)
        ? kDiagnosisFailureTimeout
        : kDiagnosisFailureLlmCallFailed;
  }
  // 兜底：本项目超时链（`stream_guard.dart:38`）抛的是 TimeoutException，
  // 已被上面接住；走到字符串判断的只剩包装过的传输层错误。
  final msg = error.toString().toLowerCase();
  if (msg.contains('timeout') || msg.contains('timed out')) {
    return kDiagnosisFailureTimeout;
  }
  if (error is Exception) return kDiagnosisFailureLlmCallFailed;
  return kDiagnosisFailureUnknown;
}

/// 把解析侧的 `rejectReason` / 症候条数归类为
/// [kDiagnosisFailureParseFailed] 或 [kDiagnosisFailureEmptyMatch]。
///
/// [rejectReason] 非 null ⇒ 解析被拒（**任何** reject 码都归这一类，原码进 `detail`）；
/// 否则若 [syndromeCount] 为 0 ⇒ 空匹配；两者都不是 ⇒ 返回 null（不写日志）。
String? classifyParseOutcome({
  required String? rejectReason,
  required int? syndromeCount,
}) {
  if (rejectReason != null) return kDiagnosisFailureParseFailed;
  if (syndromeCount != null && syndromeCount == 0) {
    return kDiagnosisFailureEmptyMatch;
  }
  return null;
}

/// 诊断失败原因落库留痕的唯一真源（`event='diagnosis_failure'`）。
///
/// **为什么收口到顶层函数而不是两个类各自内联**：解析侧（`DiagnosisFlowHandler`）
/// 与发送侧（`ChatService`）**写的是同一个 event 键**，各写一份 ⇒ 键名/字段名
/// 必然漂移（本项目「同一事实多处表述」已吃过多次亏）。本函数即两侧共用的落点。
///
/// **为什么必须落库而不是只 `debugPrint`**：release 下 `debugPrint` 不可见
/// （与 `chat_service.dart` 的 `recordBudgetOutcomeLog` 同型理由），而 A2 要回答的
/// 正是「历史导出里这条失败是什么原因」——只在内存里等于没有。
///
/// **只放码与计数，绝不放诊断正文 / 证据原文**（R-029；A12 脱敏由 captureError 兜第二层）。
/// [path] 取值：`parse`（诊断解析链路）/ `send`（发送链路，含 LLM 调用失败与超时）。
void recordDiagnosisFailureLog({
  required String reason,
  required String path,
  int? failureCount,
  String? detail,
  int? syndromeCount,
  bool hasSession = true,
}) {
  ErrorHandler.instance.captureError(
    level: path == 'send' ? 'error' : 'warn',
    category: 'diagnosis',
    message:
        '[diagnosis_failure] path=$path reason=$reason'
        '${failureCount != null ? " failureCount=$failureCount" : ""}',
    context: <String, dynamic>{
      'event': kDiagnosisFailureEvent,
      'path': path,
      'reason': reason,
      ?failureCount != null ? 'failureCount' : null: failureCount,
      ?detail != null ? 'detail' : null: detail,
      ?syndromeCount != null ? 'syndromeCount' : null: syndromeCount,
      // 不落 sessionId 原文（可反查到用户），只落是否存在，够定位即可。
      'hasSession': hasSession,
    },
  );
}

/// 发送侧失败留痕（ADR-C84，A2 扩展）。
///
/// 【为什么从 `chat_service.dart` 搬到本文件】
///   ① 发送失败与解析失败**写同一个 event 键**，两条落点分处两个文件时，
///     键名/字段名各改一半即漂移；收进本文件后两侧形状由同一处定义。
///   ② `chat_service.dart` 已是 1105 行存量超限文件，且 `ChatServiceSend`
///      extension 块实测 302 行 > 300 阈值（门禁 13 全量卡口）——
///      任何内联追加都会直接红。搬出后块行数回落。
///
/// 【口径：逐字不变】
///   `level` / `category`（DioException ⇒ network，其余 ⇒ api）/ `message`
///   模板与改造前**逐字相同**；只在 context 上追加 event/path/reason 三键。
///   **仍是一行日志**，不是同一次失败落两条。
void recordSendFailureLog({
  required Object error,
  required String phase,
  required String attitude,
}) {
  final msg = error is Exception ? error.toString() : '发送失败';
  ErrorHandler.instance.captureError(
    level: 'error',
    category: error is DioException ? 'network' : 'api',
    message: 'sendMessage 失败: $msg',
    context: {
      'phase': phase,
      'attitude': attitude,
      'event': kDiagnosisFailureEvent,
      'path': 'send',
      'reason': classifyDiagnosisFailureError(error),
    },
  );
}
