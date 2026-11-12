// platform_quota_bridge_web.dart — 平台资源点通道的 web 实现（条件导入的 web 支）
//
// 【链路】
//   Dart(wasm) → window.WbcsBridge.chat(...) → window.WorkBuddyCloud（官方 SDK）
//   → 平台数据面（按调用扣资源点）
//
// 【为什么是 JS 桥而不是直接在 Dart 里用 SDK】
//   官方 SDK 的流式接口返回 JS async iterator。在 wasm 里手搓
//   `Symbol.asyncIterator` 既易碎又不可在 VM 里测（spike 实测踩过，见
//   `.ai/reports/2026-11-12-U1spike-浏览器wasm可用性.md`）。
//   把 `for await` 留在 `web/wbcs/bridge.js`，Dart 只收字符串 ⇒ 边界极窄。
//
// 【为什么这一支只做「搬运」不做「判断」】
//   JSON 解析与错误码分流都在 `platform_quota_channel.dart`（纯 Dart）。
//   本文件在 VM 下不可被测试导入，任何逻辑写在这里就等于放弃单测覆盖。
//
// 【SDK 从哪来】`web/wbcs/index.global.js` 是 vendored 产物
//   （`@tencent-ai/workbuddy-cloud-sdk@0.1.4-dev.ca27990.202610161713`
//   的 `lib/index.global.js`，md5 `c52b7ce1534b3ad118d567fbfcc77365`）。
//   不由 CDN 加载：线上 CSP 与离线可用性都不允许运行时依赖外部域名。
//   仓库已有同类 vendored 先例（`web/drift_worker.js`、`web/sqlite3.wasm`）。

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'platform_quota_channel.dart';

/// `web/wbcs/bridge.js` 挂载的全局对象；脚本未加载时为 `undefined` ⇒ null。
///
/// 用 `JSAny?` 而非 `JSObject`：非 nullable 的 JS 类型遇到 `undefined` 会在
/// 取值处抛错，而「桥没加载」是本实现必须优雅处理的正常状态。
@JS('WbcsBridge')
external JSAny? get _bridgeAny;

/// web：配置齐全且桥已加载时返回通道，否则 null（⇒ 退回离线示例）。
PlatformQuotaChannel? createPlatformQuotaChannel() {
  if (!PlatformQuotaConfig.isConfigured) return null;
  if (_bridgeAny == null) return null;
  return const WebPlatformQuotaChannel();
}

class WebPlatformQuotaChannel implements PlatformQuotaChannel {
  const WebPlatformQuotaChannel();

  @override
  bool get isAvailable =>
      PlatformQuotaConfig.isConfigured && _bridgeAny != null;

  @override
  Future<PlatformQuotaResult> chat({
    required List<PlatformQuotaMessage> messages,
    required void Function(String delta) onDelta,
    bool Function()? isCancelled,
    int? maxTokens,
  }) async {
    final fn = _chatFunction();
    final payload = _encodeParams(messages, maxTokens);

    // 取消由 Dart 侧消费：已取消则丢弃后续增量，但**不中断底层流**
    // （资源点已扣，中断省不下钱 —— 取舍见 PlatformQuotaChannel.chat 注释）。
    final onDeltaJs = ((JSString s) {
      if (isCancelled?.call() ?? false) return;
      onDelta(s.toDart);
    }).toJS;

    final promise =
        fn.callAsFunction(_bridgeAny as JSObject, payload.toJS, onDeltaJs)
            as JSPromise<JSString>;

    final raw = (await promise.toDart).toDart;
    return parsePlatformQuotaPayload(raw);
  }

  /// 取 `WbcsBridge.chat`；缺失时抛结构化错误（不抛 StateError ——
  /// 上层只认 [PlatformQuotaException]，混入别的类型会落到「未知错误」文案）。
  JSFunction _chatFunction() {
    final bridge = _bridgeAny;
    final fn = bridge == null ? null : (bridge as JSObject)['chat'];
    if (fn != null && fn.isA<JSFunction>()) return fn as JSFunction;
    final missing = 'bridge_llm_missing';
    throw PlatformQuotaException(
      code: missing,
      userMessage: platformQuotaUserMessage(missing),
    );
  }

  /// 组装单 JSON 载荷（参数展开会撞 `callAsFunction` 的位置参数上限）。
  String _encodeParams(List<PlatformQuotaMessage> messages, int? maxTokens) =>
      jsonEncode({
        'endpoint': PlatformQuotaConfig.endpoint,
        'publishableKey': PlatformQuotaConfig.publishableKey,
        'model': PlatformQuotaConfig.model,
        'maxTokens': maxTokens ?? 0,
        'messages': [
          for (final m in messages) {'role': m.role, 'content': m.content},
        ],
      });
}
