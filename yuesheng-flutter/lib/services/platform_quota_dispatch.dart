// platform_quota_dispatch.dart — 「无 key」整条路径的**唯一实现**（web 垫付 / 非 web 离线示例）
//
// 【为什么这些代码不在 `llm_client.dart` 里】
//   R-019 的文件级棘轮（`tool/check_r019.py`，`FILE_LINE_TOLERANCE = 0`）
//   卡的是「基线登记行数不许变胖」，而 `llm_client.dart` 已在基线里登记了
//   1293 行。本批若把平台通道逻辑就地塞进去，等于给那个 1448 行的文件再加
//   一截 —— 门禁 5 必红，且**靠重生成基线换绿属于宽松红线**（R-009 须舰长批）。
//   ⇒ 正解是把「无 key」这一整个职责域抽出来：它原本就与「有 key」主链路
//   互斥，搬家后内聚性更好，`llm_client` 只留一个分流调用。
//
// 【本文件不 import `llm_client.dart`，也不 import `dio`】
//   刻意用 `List<Map<String, dynamic>>` 收消息、用「帧回调」出结果。
//   若反过来 import，会形成 `llm_client ⇄ dispatch` 循环导入；用 dio 的
//   `CancelToken` 也会把本文件绑死在网络层。代价只是调用方多做一次
//   `messages.map((m) => m.toJson())` —— 那行本来就该在调用方。

import 'platform_quota_bridge.dart';
import 'platform_quota_channel.dart';

/// 免费测试模式教学文案（原 `LlmClient._kFreeTestReply`，随本职责域迁入）。
///
/// 语义不变：无次数限制、无开关——判定 = 未配置 API Key 且平台通道不可用；
/// 不伪造诊断，固定文案由解析类调用方走各自现有失败兜底。
const String kFreeTestReply =
    '（免费测试模式）我现在处于离线示例模式，本次未进行诊断——没有调用真实模型。'
    '配置 API Key 后，我就能为你做真实的写作诊断与编辑观察，去「设置」中填入即可。';

/// 离线示例的分块文案（逐字拆开是为了模拟流式节奏，不是分段语义）。
const List<String> _kFreeTestChunks = <String>[
  '（免费测试模式）我现在处于离线示例模式，本次未进行诊断——',
  '没有调用真实模型。配置 API Key 后，我就能为你做真实的写作诊断与编辑观察，',
  '去「设置」中填入即可。',
];

/// 解析平台通道；null = 本端无通道（手机端恒为 null，见 `_stub` 支）。
///
/// 非 web 支 `createPlatformQuotaChannel()` 恒返回 null ⇒ 手机端行为由
/// 「通道不存在」结构性保证，不需要任何 `kIsWeb` 判断。
PlatformQuotaChannel? resolvePlatformChannel({PlatformQuotaChannel? injected}) {
  final ch = injected ?? createPlatformQuotaChannel();
  if (ch == null || !ch.isAvailable) return null;
  return ch;
}

/// 无 key 的**流式**统一出口。
///
/// 返回 `true` = 正常收尾（已投递 done 帧）；`false` = 用户已取消
/// （**不**投递 done 帧，由调用方抛取消异常）。
///
/// 【为什么由本函数发 done 帧而不由调用方发】取消语义与真实流一致：
/// 已取消时不得再投递任何帧。两处都判断会让「谁负责收尾」变得含糊，
/// 那正是并发/取消类 bug 的温床。
Future<bool> emitNoKeyStream({
  required PlatformQuotaChannel? platform,
  required List<Map<String, dynamic>> messages,
  required void Function(String chunk, bool done) onFrame,
  required bool Function() isCancelled,
  int? maxTokens,
}) async {
  if (platform == null) {
    await _emitFreeTestStream(onFrame, isCancelled);
    return true;
  }
  await callPlatform(
    platform,
    messages,
    maxTokens: maxTokens,
    isCancelled: isCancelled,
    onDelta: (delta) => onFrame(delta, false),
  );
  if (isCancelled()) return false;
  onFrame('', true);
  return true;
}

/// 无 key 的**非流式**统一出口（平台通道只收流式 ⇒ 此处本地聚合）。
///
/// 返回 null = 无通道可用 ⇒ 调用方回退 [kFreeTestReply]。
Future<PlatformQuotaResult?> completeNoKey({
  required PlatformQuotaChannel? platform,
  required List<Map<String, dynamic>> messages,
  required bool Function() isCancelled,
  int? maxTokens,
}) async {
  if (platform == null) return null;
  return callPlatform(
    platform,
    messages,
    maxTokens: maxTokens,
    isCancelled: isCancelled,
    onDelta: null,
  );
}

/// 调用平台通道并按官方错误码分流重试（验收标准 A4 / A5）。
///
/// ★ **重试策略在这里是资金安全问题，不是体验细节**：无限重试会持续烧资源点，
/// 而额度耗尽是「云停 + 数据保留 15 天」的硬停（`§4-503 ⑦ ②`）。
/// ⇒ `quota_exhausted` 零重试；`quota_rate_limited` **且带 `retryAfterMs`**
/// 才最多重试 1 次（调用总数恰为 2），第 2 次仍失败直接上抛。
///
/// ★ 2026-11-12 A10 真浏览器取证修正：官方 `code-generation.md` 明文
/// 「`quota_` = Creator quota exhausted **or** rate-limited；only
/// `quota_rate_limited` **with `retryAfterMs`** suggests retry」。
/// 真实平台确实会回**不带 `retryAfterMs`** 的 `quota_rate_limited`（两次实测），
/// 这类可能是额度耗尽而非临时限流 ⇒ **不得重试**。原实现只看 code，
/// mock 用例又都带 `retryAfterMs`，故该洞只有真调用能照出来。
Future<PlatformQuotaResult> callPlatform(
  PlatformQuotaChannel platform,
  List<Map<String, dynamic>> messages, {
  required bool Function() isCancelled,
  void Function(String delta)? onDelta,
  int? maxTokens,
}) async {
  _rejectImagePayload(messages);
  var calls = 0;
  while (true) {
    calls++;
    try {
      return await platform.chat(
        messages: messages.map(_toQuotaMessage).toList(),
        onDelta: onDelta ?? (String _) {},
        maxTokens: maxTokens,
        isCancelled: isCancelled,
      );
    } on PlatformQuotaException catch (e) {
      // 无 retryAfterMs = 官方不建议重试（可能是额度耗尽，见上方 ★ 注）。
      if (!e.isRateLimited ||
          e.retryAfterMs == null ||
          calls > 1 ||
          isCancelled()) {
        rethrow;
      }
      await Future<void>.delayed(_retryDelay(e.retryAfterMs));
    }
  }
}

/// 图片输入在免费通道不被支持 ⇒ **明确报错，不悄悄丢图**。
///
/// 悄悄丢的后果是「用户贴了图、拿到一份装作看过的诊断」——那比报错更坏。
void _rejectImagePayload(List<Map<String, dynamic>> messages) {
  for (final m in messages) {
    final content = m['content'];
    if (content is List &&
        content.any((b) => b is Map && b['type'] == 'image_url')) {
      const code = 'bridge_image_unsupported';
      throw PlatformQuotaException(
        code: code,
        userMessage: platformQuotaUserMessage(code),
      );
    }
  }
}

PlatformQuotaMessage _toQuotaMessage(Map<String, dynamic> m) {
  final role = m['role'] is String ? m['role'] as String : 'user';
  final content = m['content'];
  if (content is String) {
    return PlatformQuotaMessage(role: role, content: content);
  }
  // content blocks（已排除图片）⇒ 只拼文本块
  if (content is List) {
    return PlatformQuotaMessage(
      role: role,
      content: content
          .whereType<Map<String, dynamic>>()
          .map((b) => b['text'] is String ? b['text'] as String : '')
          .join(),
    );
  }
  return PlatformQuotaMessage(role: role, content: '');
}

/// 限流重试等待：优先服务端 `retryAfterMs`，缺省 800ms，夹在 200ms–5s。
Duration _retryDelay(int? retryAfterMs) {
  final ms = (retryAfterMs ?? 800).clamp(200, 5000);
  return Duration(milliseconds: ms);
}

/// 离线示例模拟流式：教学文案分块推送 + DONE（批次 E-1 原逻辑，语义未变）。
Future<void> _emitFreeTestStream(
  void Function(String chunk, bool done) onFrame,
  bool Function() isCancelled,
) async {
  if (isCancelled()) throw PlatformQuotaCancelled();
  for (final chunk in _kFreeTestChunks) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (isCancelled()) throw PlatformQuotaCancelled();
    onFrame(chunk, false);
  }
  onFrame('', true);
}

/// 「用户已取消」的内部信号。
///
/// 【为什么不直接用 `LlmRequestCancelledException`】那会迫使本文件 import
/// `llm_client.dart`（循环导入）。调用方接住本异常后换成自己的取消异常，
/// 转换只发生在一处，且类型语义不泄漏到平台层。
class PlatformQuotaCancelled implements Exception {
  const PlatformQuotaCancelled();
}
