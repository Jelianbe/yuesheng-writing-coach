// interaction_event_service.dart — App 端云端埋点（interaction_events INSERT）
//
// 【形态裁断来源】⑤ 探针 spike（§4-513）：Android 端纯 Dart HTTP（dart:io）
//   直连数据面 REST 写 interaction_events 成立（两写 201 + 云端回读 E1），
//   JS 桥 / WebView / 平台通道均不需要。本文件是该结论的正式接入。
//
// 【REST 形状（§4-513 考古 + 实测）】
//   POST {endpoint}/.cloud/database/rest/interaction_events
//   头: x-wb-webapp-access-key: {publishableKey} + Prefer: return=minimal
//   体: JSON 数组（PostgREST 语义，supabase-js .insert() 等效）
//   云端 CHECK：event_type ∈ {diagnosed, anchor_ack, exclusion}；
//   source ∈ {web, app}（本服务恒 'app'）。
//
// 【配置源】复用 PlatformQuotaConfig（构建期 dart-define 注入）。
//   裸构建（无 WB_PLATFORM_ENDPOINT/KEY）⇒ isConfigured=false ⇒ record
//   静默 no-op，行为与接入前逐字节一致；埋点只在带 define 的构建里生效。
//
// 【隐私口径】对齐 web 先例（diagnose.html sendEvent 注释）：只传结构化
//   标识（症候 ID / 章节与消息 ID），**不传稿件文本**。
//
// 【失败语义】埋点失败不阻断：全路径 catch + debugPrint 留痕（对齐
//   `diagnosis_card.dart` anchor_ack 本地埋点先例），绝不向上抛。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'platform_quota_channel.dart';

/// 数据面 REST 路径（§4-513 实测口径；无代理前缀，App 直连）。
const String kInteractionEventsPath =
    '/.cloud/database/rest/interaction_events';

/// 一行云端埋点事件（行形状与 web `sendEvent` 逐字段同构，便于统一分析）。
class InteractionEventRow {
  /// 事件类型（云端 CHECK 白名单：diagnosed / anchor_ack / exclusion）。
  final String eventType;

  /// 结构化标识载荷（不传稿件文本）。
  final Map<String, Object?> payload;

  /// 会话标识（与 web `session_tag` 同义，App 传 sessionId）。
  final String sessionTag;

  /// 客户端时间（ISO8601 UTC）。
  final String clientCreatedAt;

  const InteractionEventRow({
    required this.eventType,
    required this.payload,
    required this.sessionTag,
    required this.clientCreatedAt,
  });

  Map<String, Object?> toJson() => <String, Object?>{
    'event_type': eventType,
    'payload': payload,
    'source': 'app',
    'session_tag': sessionTag,
    'client_created_at': clientCreatedAt,
  };
}

/// 构造一行埋点（纯函数，可测）。[createdAtIso] 测试注入用，缺省取当前 UTC。
InteractionEventRow buildInteractionEventRow({
  required String eventType,
  required Map<String, Object?> payload,
  required String sessionTag,
  String? createdAtIso,
}) {
  return InteractionEventRow(
    eventType: eventType,
    payload: payload,
    sessionTag: sessionTag,
    clientCreatedAt: createdAtIso ?? DateTime.now().toUtc().toIso8601String(),
  );
}

/// HTTP 发送抽象（测试注入假 sender；默认实现走 dart:io）。
typedef InteractionEventSender =
    Future<int> Function(Uri uri, Map<String, String> headers, List<int> body);

/// App 端云端埋点服务（fire-and-forget，永不阻断主流程）。
class InteractionEventService {
  InteractionEventService._();

  static const String _kTag = '[interaction_event]';

  /// 测试注入口：VM 测试无 dart-define ⇒ 真值恒 false，
  /// 注入 true 才能走通 record → sender 全链。
  @visibleForTesting
  static bool? debugConfiguredOverride;

  /// 测试注入假 sender（null = 恢复默认 dart:io 实现）。
  @visibleForTesting
  static InteractionEventSender? debugSenderOverride;

  /// 测试注入口：VM 测试无 dart-define ⇒ endpoint/key 恒空串。
  @visibleForTesting
  static String? debugEndpointOverride;

  @visibleForTesting
  static String? debugKeyOverride;

  /// 配置齐全才启用；裸构建恒 false ⇒ record 为 no-op。
  static bool get isConfigured =>
      debugConfiguredOverride ?? PlatformQuotaConfig.isConfigured;

  /// 记录一条埋点（同步返回，内部 fire-and-forget）。
  ///
  /// [eventType] 必须是云端 CHECK 白名单值（diagnosed / anchor_ack /
  /// exclusion）；未配置时静默跳过；失败仅 debugPrint（不阻断）。
  static void record({
    required String eventType,
    required Map<String, Object?> payload,
    required String sessionTag,
  }) {
    if (!isConfigured) return;
    unawaited(
      _send(eventType: eventType, payload: payload, sessionTag: sessionTag),
    );
  }

  static Future<void> _send({
    required String eventType,
    required Map<String, Object?> payload,
    required String sessionTag,
  }) async {
    try {
      final uri = Uri.parse(
        '${debugEndpointOverride ?? PlatformQuotaConfig.endpoint}'
        '$kInteractionEventsPath',
      );
      final headers = <String, String>{
        'x-wb-webapp-access-key':
            debugKeyOverride ?? PlatformQuotaConfig.publishableKey,
        'Content-Type': 'application/json',
        'Prefer': 'return=minimal',
      };
      final row = buildInteractionEventRow(
        eventType: eventType,
        payload: payload,
        sessionTag: sessionTag,
      );
      final sender = debugSenderOverride ?? _postViaHttpClient;
      final status = await sender(
        uri,
        headers,
        utf8.encode(jsonEncode(<Map<String, Object?>>[row.toJson()])),
      );
      if (status >= 300) {
        debugPrint('$_kTag $eventType 云端返回 HTTP $status（不阻断）');
      }
    } catch (e) {
      debugPrint('$_kTag $eventType 埋点失败（不阻断）: $e');
    }
  }

  /// 默认实现：dart:io HttpClient 单次 POST（§4-513 探针同形状）。
  static Future<int> _postViaHttpClient(
    Uri uri,
    Map<String, String> headers,
    List<int> body,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      headers.forEach(request.headers.set);
      request.add(body);
      final response = await request.close();
      // 排空响应体：防连接池悬挂。
      await response.transform(utf8.decoder).join();
      return response.statusCode;
    } finally {
      client.close();
    }
  }
}
