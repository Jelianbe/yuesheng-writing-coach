// interaction_event_service_test.dart — 批十六云端埋点服务单测。
//
// 判据设计（可变红）：
//   A 行形状：source 恒 'app'（云端 CHECK 白名单 {web,app}），五字段齐。
//   B no-op：未配置（VM 测试无 dart-define ⇒ 真值恒 false）⇒ sender 恰 0 次。
//   C 全链：override 配置 + 假 sender ⇒ 恰 1 次，uri / 头 / 体形状正确。
//   D 不阻断：sender 抛异常 ⇒ 不外抛（未处理异步错误会让测试区失败）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/interaction_event_service.dart';

void main() {
  tearDown(() {
    InteractionEventService.debugConfiguredOverride = null;
    InteractionEventService.debugSenderOverride = null;
    InteractionEventService.debugEndpointOverride = null;
    InteractionEventService.debugKeyOverride = null;
    // §4-516：全局静态字段，不重置会跨用例泄漏（C 的 payload 严格等判据会红）。
    InteractionEventService.anonId = null;
  });

  group('buildInteractionEventRow', () {
    test('A：五字段齐全且 source 恒 app', () {
      final row = buildInteractionEventRow(
        eventType: 'diagnosed',
        payload: const {'syndrome_count': 1},
        sessionTag: 'sess-1',
        createdAtIso: '2026-11-12T15:00:00.000Z',
      );
      final json = row.toJson();
      expect(json['event_type'], 'diagnosed');
      expect(json['payload'], const {'syndrome_count': 1});
      expect(json['source'], 'app');
      expect(json['session_tag'], 'sess-1');
      expect(json['client_created_at'], '2026-11-12T15:00:00.000Z');
    });

    test('A：缺省时间取当前 UTC（非空且可解析）', () {
      final row = buildInteractionEventRow(
        eventType: 'anchor_ack',
        payload: const {},
        sessionTag: 's',
      );
      expect(
        DateTime.parse(row.toJson()['client_created_at'] as String),
        isA<DateTime>(),
      );
    });
  });

  group('InteractionEventService.record', () {
    test('B：未配置 ⇒ sender 恰 0 次（裸构建行为与接入前一致）', () async {
      var calls = 0;
      InteractionEventService.debugSenderOverride = (uri, headers, body) async {
        calls++;
        return 201;
      };
      // debugConfiguredOverride 为 null ⇒ 走 PlatformQuotaConfig 真值
      // （VM 测试无 dart-define ⇒ false）。
      expect(InteractionEventService.isConfigured, isFalse);
      InteractionEventService.record(
        eventType: 'diagnosed',
        payload: const {},
        sessionTag: 'sess-1',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls, 0);
    });

    test('C：配置 + 假 sender ⇒ 恰 1 次，uri/头/体形状正确', () async {
      InteractionEventService.debugConfiguredOverride = true;
      InteractionEventService.debugEndpointOverride =
          'https://endpoint.example.host';
      InteractionEventService.debugKeyOverride = 'wbpk_test_key';
      final calls =
          <({Uri uri, Map<String, String> headers, List<int> body})>[];
      InteractionEventService.debugSenderOverride = (uri, headers, body) async {
        calls.add((uri: uri, headers: headers, body: body));
        return 201;
      };
      InteractionEventService.record(
        eventType: 'diagnosed',
        payload: const {
          'syndromes': ['P001'],
        },
        sessionTag: 'sess-9',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(calls.length, 1);
      expect(
        calls.single.uri.toString(),
        'https://endpoint.example.host/.cloud/database/rest/interaction_events',
      );
      expect(calls.single.headers['x-wb-webapp-access-key'], 'wbpk_test_key');
      expect(calls.single.headers['Prefer'], 'return=minimal');

      final decoded =
          jsonDecode(utf8.decode(calls.single.body)) as List<dynamic>;
      expect(decoded.length, 1);
      final row = decoded.single as Map<String, dynamic>;
      expect(row['event_type'], 'diagnosed');
      expect(row['source'], 'app');
      expect(row['session_tag'], 'sess-9');
      expect(row['payload'], const {
        'syndromes': ['P001'],
      });
    });

    test('D：sender 抛异常 ⇒ 不外抛（未处理错误会让本测试失败）', () async {
      InteractionEventService.debugConfiguredOverride = true;
      InteractionEventService.debugSenderOverride =
          (uri, headers, body) async => throw StateError('network down');
      InteractionEventService.record(
        eventType: 'anchor_ack',
        payload: const {},
        sessionTag: 'sess-1',
      );
      // 若异常逃逸出服务内部 catch，测试区会以未处理异步错误判红。
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    test('E：§4-516 anon_id 注入 ⇒ payload 多一键，session_tag 零变化', () async {
      InteractionEventService.debugConfiguredOverride = true;
      InteractionEventService.debugEndpointOverride = 'https://e.example.host';
      InteractionEventService.debugKeyOverride = 'k';
      InteractionEventService.anonId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
      final bodies = <List<int>>[];
      InteractionEventService.debugSenderOverride = (uri, headers, body) async {
        bodies.add(body);
        return 201;
      };
      InteractionEventService.record(
        eventType: 'diagnosed',
        payload: const {
          'syndromes': ['P001'],
          'syndrome_count': 1,
        },
        sessionTag: 'sess-9',
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final row =
          (jsonDecode(utf8.decode(bodies.single)) as List).single
              as Map<String, dynamic>;
      final payload = row['payload'] as Map<String, dynamic>;
      expect(payload['anon_id'], 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
      expect(payload['syndrome_count'], 1);
      expect(payload['syndromes'], ['P001']);
      // 反向判据（报批稿 §六 ④）：业务键不受 anon_id 影响。
      expect(row['session_tag'], 'sess-9');
    });

    test('F：anonId 为 null 或空串 ⇒ 不发键（该行不可归因）', () async {
      InteractionEventService.debugConfiguredOverride = true;
      InteractionEventService.debugEndpointOverride = 'https://e.example.host';
      InteractionEventService.debugKeyOverride = 'k';
      for (final v in <String?>[null, '']) {
        InteractionEventService.anonId = v;
        final bodies = <List<int>>[];
        InteractionEventService.debugSenderOverride =
            (uri, headers, body) async {
              bodies.add(body);
              return 201;
            };
        InteractionEventService.record(
          eventType: 'anchor_ack',
          payload: const {'syndrome_id': 'P001'},
          sessionTag: 's',
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        final row =
            (jsonDecode(utf8.decode(bodies.single)) as List).single
                as Map<String, dynamic>;
        expect(
          (row['payload'] as Map<String, dynamic>).containsKey('anon_id'),
          isFalse,
          reason: 'anonId=$v 时不应发键（报批稿 §七 F2 设计如此）',
        );
      }
    });
  });
}
