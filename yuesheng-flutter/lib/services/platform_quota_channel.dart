// platform_quota_channel.dart — 平台资源点通道的**纯 Dart 契约**（无 js 依赖）
//
// 【本文件解决什么问题】
//   web 访客没有自己的 API Key 时，此前一律退化成离线示例文案
//   （`llm_client.dart` 的 `_kFreeTestReply`）。本通道是「无 key 也能真诊断」
//   的唯一出口：用平台资源点垫付（`§4-488 ③` 已裁的受控例外）。
//
// 【为什么接口单独成文件、不放进 web 实现里】
//   实现支（`platform_quota_bridge_web.dart`）必须 `import 'dart:js_interop'`，
//   而该库在 VM（`flutter test`）下**不存在** ⇒ 测试无法直接引用其类型。
//   把契约抽到纯 Dart 文件后，VM 测试可以注入假通道做计次断言
//   （A2「BYOK 不倒挂」/ A4「恰 1 次」/ A5「恰 2 次」全靠这一点才可断言）。
//
// 【为什么不自建计量/计费】资源点由平台按调用自动扣，SDK 无余额查询接口
//   （官方 `management.md`：usage / quota / billing 无 SDK surface）
//   ⇒ 我方只做「接上 + 接住错误」，不做账本（`§4-503 ⑦`）。

import 'dart:convert';

/// 一条对话消息（平台通道侧的最小形态）。
///
/// 刻意不复用 `ChatMessage`：`llm_client.dart` 会 import 本文件，
/// 反向依赖会形成循环导入。转换在 `llm_client` 一侧完成（走 `toJson`）。
class PlatformQuotaMessage {
  final String role;
  final String content;

  const PlatformQuotaMessage({required this.role, required this.content});
}

/// 一次平台调用的结果（流式结束后聚合）。
///
/// [finishReason] 是 `chatCompletionWithContinuation` 判断是否续接的唯一依据
/// （`isTruncated` 依赖 `'length'`）⇒ 桥层必须从末帧带回，不可省。
class PlatformQuotaResult {
  final String content;
  final String? finishReason;

  /// 本次调用实际扣减的资源点；桥层未回传时为 null（**不得当 0 处理**）。
  final double? credit;

  const PlatformQuotaResult({
    required this.content,
    this.finishReason,
    this.credit,
  });
}

/// 平台通道错误（结构化，非「网络错误」黑盒）。
///
/// ★ [toString] **直接返回中文文案**：上层诊断链路的写法是
/// `catch (e) { handleError(e.toString()); }`（`writing_coach_panel_diagnosis_runner.dart:92`）
/// ⇒ 这里返回什么，用户就看到什么。故不得带 `Exception: ` 前缀，
/// 否则额度耗尽会被渲染成一句像 bug 的机器文本。
class PlatformQuotaException implements Exception {
  /// 官方稳定的错误码前缀式取值，如 `quota_exhausted` / `quota_rate_limited`
  /// / `auth_origin_denied` / `gateway_stream_interrupted`。可能为 null（非 SDK 错误）。
  final String? code;

  /// 仅 `quota_rate_limited` 会带（官方文档：只有它建议重试）。
  final int? retryAfterMs;

  /// 直接可展示的中文文案（见 [platformQuotaUserMessage]）。
  final String userMessage;

  const PlatformQuotaException({
    required this.code,
    required this.userMessage,
    this.retryAfterMs,
  });

  /// 额度已耗尽：重试无意义（重试只会继续撞墙，且额度是硬停 `§4-503 ⑦ ②`）。
  bool get isExhausted => code == 'quota_exhausted';

  /// 限流：**唯一**允许重试的形态，且只重试一次（A5）。
  bool get isRateLimited => code == 'quota_rate_limited';

  @override
  String toString() => userMessage;
}

/// 平台资源点通道（web 支实现 = 调官方 SDK；非 web 支 = 不存在）。
abstract class PlatformQuotaChannel {
  /// 通道是否可用：配置齐全 + 桥已加载 + 运行在 web 端面。
  ///
  /// **不做网络探测**：探测会白花资源点，且可用性只有真调用才知道。
  bool get isAvailable;

  /// 流式调用。增量文本经 [onDelta] 逐字回调；结束态以返回值聚合。
  ///
  /// 失败一律抛 [PlatformQuotaException]（含可判定的 [PlatformQuotaException.code]）。
  /// [isCancelled] 由实现周期性查询：已取消时**停止回调**，但**不保证中断底层流**
  /// —— 资源点已扣，中断省不下钱，因此不做 abort（这条是取舍，不是遗漏）。
  Future<PlatformQuotaResult> chat({
    required List<PlatformQuotaMessage> messages,
    required void Function(String delta) onDelta,
    bool Function()? isCancelled,
    int? maxTokens,
  });
}

/// 平台通道的静态配置（构建期注入，不落盘）。
///
/// 取值为空 ⇒ 通道不可用 ⇒ 行为与接入前**逐字节一致**（离线示例文案）。
/// 这一条是 A3「手机端零变更」的实现基础：非 web 支根本不创建通道。
class PlatformQuotaConfig {
  const PlatformQuotaConfig._();

  /// 云服务应用端点，如 `https://xxx.app.workbuddy.host`
  static const String endpoint = String.fromEnvironment('WB_PLATFORM_ENDPOINT');

  /// 可发布密钥（publishable key）——**设计上**即面向浏览器公开，非服务端密钥。
  static const String publishableKey = String.fromEnvironment(
    'WB_PLATFORM_KEY',
  );

  /// 模型标识；平台目录里 `deepseek-v4.1-flash` 为 `x0.11` 档（实测口径）。
  static const String model = String.fromEnvironment(
    'WB_PLATFORM_MODEL',
    defaultValue: 'deepseek-v4.1-flash',
  );

  static bool get isConfigured =>
      endpoint.isNotEmpty && publishableKey.isNotEmpty;
}

/// 把桥返回的 JSON 字符串解析成结果或异常。
///
/// **为什么解析必须在纯 Dart 侧而不是 web 支**：错误码判定（`quota_exhausted`
/// 与 `quota_rate_limited` 的分流）是本卡最关键的判据，而 web 支文件在 VM 下
/// 无法被测试导入 ⇒ 若解析写在那边，A4/A5 就只能靠真浏览器验证，无法在
/// `flutter test` 里变红。放这里 ⇒ 两条判据都能在 VM 单测里断言。
///
/// 输入契约见 `web/wbcs/bridge.js`：
///   成功 `{ok:true, text, finishReason, credit}`
///   失败 `{ok:false, code, retryAfterMs, ...}`
PlatformQuotaResult parsePlatformQuotaPayload(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    throw PlatformQuotaException(
      code: null,
      userMessage: platformQuotaUserMessage(null),
    );
  }
  if (decoded is! Map) {
    throw PlatformQuotaException(
      code: null,
      userMessage: platformQuotaUserMessage(null),
    );
  }
  if (decoded['ok'] == true) {
    return PlatformQuotaResult(
      content: decoded['text'] is String ? decoded['text'] as String : '',
      finishReason: decoded['finishReason'] is String
          ? decoded['finishReason'] as String
          : null,
      credit: decoded['credit'] is num
          ? (decoded['credit'] as num).toDouble()
          : null,
    );
  }
  final code = decoded['code'] is String ? decoded['code'] as String : null;
  return _throwPlatformError(code, decoded['retryAfterMs']);
}

/// 抛结构化错误（抽出来只为让 [parsePlatformQuotaPayload] 守住行数上限）。
Never _throwPlatformError(String? code, Object? retryAfterMs) {
  throw PlatformQuotaException(
    code: code,
    retryAfterMs: retryAfterMs is num ? retryAfterMs.toInt() : null,
    userMessage: platformQuotaUserMessage(code),
  );
}

/// 错误码 → 用户可见文案。
///
/// 分档依据 = 官方 `references/llm/code-generation.md` §Error Handling 的
/// 稳定前缀表。原则：**额度类必须与网络类区分**（A4 明令不得显示「网络错误」），
/// 否则用户会去查自己的网，而真正原因是额度用完。
String platformQuotaUserMessage(String? code) {
  if (code == null) {
    return '免费体验通道这次没能返回内容。你可以改用自己的 API Key 继续，'
        '或在「设置」里填入 Key 后再试。';
  }
  if (code == 'quota_exhausted') {
    return '本月免费体验额度已用完。这不影响你的写作、保存和导出——'
        '想继续用 AI 诊断，可以在「设置」里填入自己的 API Key。';
  }
  if (code == 'quota_rate_limited') {
    return '免费体验通道当前使用的人比较多，稍等一下再试。'
        '写作、保存和导出不受影响。';
  }
  if (code == 'bridge_image_unsupported') {
    return '免费体验通道暂不支持图片，只能读文字。想连图一起看，'
        '可以在「设置」里填入自己的 API Key。';
  }
  if (code.startsWith('auth_')) {
    return '免费体验通道当前不可用（来源校验未通过）。'
        '这不是你的网络问题；可以先用自己的 API Key 继续。';
  }
  if (code.startsWith('request_')) {
    return '免费体验通道的请求被拒绝了（参数或模型不匹配）。'
        '这属于配置问题，改用自己的 API Key 可以绕过。';
  }
  if (code.startsWith('gateway_') || code.startsWith('model_')) {
    return '免费体验通道暂时连不上模型服务，可以稍后重试，'
        '或改用自己的 API Key。';
  }
  return '免费体验通道暂时不可用。写作、保存和导出不受影响。';
}
