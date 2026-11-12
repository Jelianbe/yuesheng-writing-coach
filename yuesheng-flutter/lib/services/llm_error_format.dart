// ─────────────────────────────────────────────────────────────
// LLM 错误响应格式化 —— 逐字外迁自 llm_client.dart（零行为变更）。
//
// 外迁理由（T-20261112-01）：本批为「web 无 key 体验装」新增的分流逻辑使
// llm_client.dart 超出 R-019 文件行数基线登记值，而 FILE_LINE_TOLERANCE=0
// （门禁 5 卡「变胖」）。这 4 个函数均为**无实例状态的纯格式化工具**，
// 与 HTTP 客户端本身无耦合 ⇒ 按项目既有「数据/逻辑分离」手法拆为独立库，
// 而非机械搬行刷绿。全仓检索确认：除 llm_client.dart 外无任何引用点。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';

import '../config/shared_constants.dart';
import 'llm_error_codes.dart';

/// 把响应体归一化为 JSON 对象（供用量上报取 `usage`）。
///
/// Dio 只在对端返回 `application/json` 时才自动解析；实测既有链路里
/// `response.data` 可能是**未解析的 String**（`_postChatCompletion` 亦
/// 因此保留了 `data is String` 分支）⇒ 此处统一兜住，解析不出对象
/// 一律返回 null（静默跳过，不影响主流程）。
Map<String, dynamic>? asJsonMap(Object? data) {
  if (data is Map<String, dynamic>) return data;
  if (data is String) {
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// 把 [DioException] 转成用户可操作文案（401/403/429/超时/连接等）。
Future<String> buildDioError(DioException e) async {
  // 批次 3：统一走错误分类（llm_error_codes.dart），替代裸 "HTTP N"。
  final kind = classifyLlmError(e);
  if (kind == LlmErrorKind.timeout) {
    // 区分：流式 3 分钟兜底 vs 非流式 1 分钟兜底
    final t =
        e.requestOptions.receiveTimeout?.inMilliseconds ??
        LlmConfig.chatTimeoutMs;
    return llmErrorMessage(kind, timeoutSeconds: t ~/ 1000);
  }
  final status = e.response?.statusCode ?? 0;
  final data = e.response?.data;
  String? preview;
  final dataStr = await errorDataAsString(data);
  if (dataStr.isNotEmpty) {
    final raw = dataStr.length > LlmConfig.errorPreviewLengthLong
        ? dataStr.substring(0, LlmConfig.errorPreviewLengthLong)
        : dataStr;
    // B22/R-029：防御性脱敏——OpenAI 错误响应通常不含 Authorization，
    // 但代理/网关可能 echo 请求头到错误响应体；此层作为防御纵深。
    preview = redactAuth(raw);
  }
  return llmErrorMessage(kind, status: status, preview: preview);
}

/// 错误响应体 → 字符串（W-18 调试增强，2026-10-15）。
///
/// - dio 对 application/json 非流式响应自动解析成 Map ⇒ 原判
///   `data is String` 恒 false，body 丢失；Map 时 jsonEncode 回字符串。
/// - 流式通道错误时 data 是 ResponseBody 原始流对象（既非 String 亦非
///   Map），jsonEncode 会抛异常并吞掉原始 400 ⇒ 手动汇字节再 utf8 解码
///   （dio 5.x 无 asString()；utf8.decoder 作 StreamTransformer 与
///   `Stream<Uint8List>` 泛型不兼容）。读失败降级为空串，不吞原错误。
Future<String> errorDataAsString(Object? data) async {
  if (data is ResponseBody) {
    try {
      final buf = <int>[];
      await data.stream.forEach(buf.addAll);
      return utf8.decode(buf, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }
  if (data is String) return data;
  if (data == null) return '';
  try {
    return jsonEncode(data);
  } catch (_) {
    return data.toString();
  }
}

/// R-029 安全：脱敏可能泄露的 Authorization / Bearer 凭证
///
/// 覆盖两种形式：
///   1. `Bearer xxx`（OAuth 2.0 标准格式，含 JWT）
///   2. `Authorization: xxx` / `"Authorization":"xxx"`（头部键值形式）
///
/// 不影响其他无关字段；保留请求头名以方便排查，仅屏蔽值。
String redactAuth(String text) {
  final bearerRe = RegExp(r'[Bb]earer\s+[A-Za-z0-9_\-\.]+');
  final headerRe = RegExp(
    r'''["']?Authorization["']?\s*[:=]\s*["']?[A-Za-z0-9_\-\.]+''',
    caseSensitive: false,
  );
  return text
      .replaceAll(bearerRe, 'Bearer ***')
      .replaceAll(headerRe, 'Authorization=***');
}
