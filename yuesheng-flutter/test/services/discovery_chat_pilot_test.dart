// ─────────────────────────────────────────────────────────────
// chat 链试点发现调用牙测（R-027 · T-20261109-01 施工批）。
//
// 对应报批稿五条硬约束 + S-9 + S-3 去向：
//   门控   三键门（键不全 ⇒ 零出站）/ 取消门 / 长度门 / 失败不外抛
//   S-9    试点不触发任何验证层调用（B5 同族）
//   S-3    出口三 + 出口一无编号进候选区；出口二 / 出口一有编号不登记
//   装配   出站 system 帧含方向段 + D2 域声明（C1/C2）
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/candidate_zone.dart';
import 'package:writingcoach/services/discovery_chat_pilot.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/verification_gate.dart';

/// 出站替身（与 `discovery_call_test.dart` 同构）。
class _SpyClient extends LlmClient {
  final Future<String> Function(List<ChatMessage> messages) handler;

  int calls = 0;
  List<ChatMessage> lastMessages = const [];

  _SpyClient(this.handler);

  @override
  Future<String> chatCompletion(
    List<ChatMessage> messages, {
    int? maxTokens,
    Map<String, dynamic>? extraBody,
    CancelToken? cancelToken,
  }) {
    calls++;
    lastMessages = messages;
    return handler(messages);
  }
}

const VerificationKeys _completeKeys = VerificationKeys(
  baseUrl: 'https://verify.invalid/v1',
  apiKey: 'k',
  model: 'm',
);

const VerificationKeys _incompleteKeys = VerificationKeys(
  baseUrl: 'https://verify.invalid/v1',
  apiKey: '',
  model: 'm',
);

VerificationGate _gate(VerificationKeys keys, _SpyClient client) =>
    VerificationGate(
      keysLoader: () async => keys,
      clientFactory: (_) => client,
      sink: (_) {},
    );

const String _content = '弗利西安看向火车的窗外。桦树林染上秋日的黄色。';

String _observations(String items) => '{"observations":[$items]}';

void main() {
  group('门控（与分块链发现调用同款）', () {
    test('三键不全 ⇒ 零出站（键判据分母：完整键会出站）', () async {
      final client = _SpyClient((_) async => _observations(''));
      final zone = CandidateZone();
      final result = await runChatChainDiscovery(
        gate: _gate(_incompleteKeys, client),
        llmClient: client,
        content: _content,
        zone: zone,
        sourceTextId: 'chapter-1',
      );
      expect(result.rawCount, 0);
      expect(client.calls, 0, reason: '三键门：零出站');
      expect(zone.entries(), isEmpty);
    });

    test('取消 ⇒ 不发起', () async {
      final client = _SpyClient((_) async => _observations(''));
      final result = await runChatChainDiscovery(
        gate: _gate(_completeKeys, client),
        llmClient: client,
        content: _content,
        zone: CandidateZone(),
        sourceTextId: 'chapter-1',
        cancelled: true,
      );
      expect(result.rawCount, 0);
      expect(client.calls, 0);
    });

    test('出站失败 ⇒ 不外抛、按零条处理（失败不外抛 + 不重试）', () async {
      var calls = 0;
      final client = _SpyClient((_) async {
        calls++;
        throw Exception('网络故障');
      });
      final result = await runChatChainDiscovery(
        gate: _gate(_completeKeys, client),
        llmClient: client,
        content: _content,
        zone: CandidateZone(),
        sourceTextId: 'chapter-1',
      );
      expect(result.rawCount, 0);
      expect(calls, 1, reason: '不重试');
    });
  });

  group('装配与解析（C1/C2）', () {
    test('出站 system 帧 = 新装配面：方向段 + 恰一份 D2 域声明', () async {
      late List<ChatMessage> captured;
      final client = _SpyClient((messages) async {
        captured = messages;
        return _observations('');
      });
      await runChatChainDiscovery(
        gate: _gate(_completeKeys, client),
        llmClient: client,
        content: _content,
        zone: CandidateZone(),
        sourceTextId: 'chapter-1',
        ordinal: 2,
      );
      final system = captured.firstWhere((m) => m.role == 'system').content;
      expect(system.contains('## 分析方向（系统指定）'), isTrue);
      expect(system.contains('### 证据域声明（D'), isTrue);
      expect('### 证据域声明（'.allMatches(system).length, 1);
      expect(system.contains('- 主方向：信息组织与叙事节奏'), isTrue);
    });
  });

  group('S-3 去向登记', () {
    test('出口三 + 出口一无编号进候选区；出口二 / 出口一有编号不登记', () async {
      final raw = _observations(
        '{"exit":"unclassified","anchorQuotes":["桦树林染上秋日的黄色。"],'
        '"reason":"清单未覆盖的季节意象问题","syndromeId":""},'
        '{"exit":"promoted","anchorQuotes":["弗利西安看向火车的窗外。"],'
        '"inference":"视角锚定假设","syndromeId":""},'
        '{"exit":"observation","anchorQuotes":["弗利西安看向火车的窗外。"],'
        '"reason":"证据暂缓","syndromeId":""},'
        '{"exit":"promoted","anchorQuotes":["桦树林染上秋日的黄色。"],'
        '"inference":"有编号假设","syndromeId":"P018"}',
      );
      final client = _SpyClient((_) async => raw);
      final zone = CandidateZone();
      final result = await runChatChainDiscovery(
        gate: _gate(_completeKeys, client),
        llmClient: client,
        content: _content,
        zone: zone,
        sourceTextId: 'chapter-1',
      );
      expect(result.rawCount, 4, reason: '分母与集合断言成对');
      expect(zone.entries().length, 2, reason: '出口三 + 出口一无编号');
      final unclassified = zone.entryByAnchor('桦树林染上秋日的黄色。')!;
      expect(unclassified.hypothesis, '清单未覆盖的季节意象问题');
      final hypothesis = zone.entryByAnchor('弗利西安看向火车的窗外。')!;
      expect(hypothesis.hypothesis, '视角锚定假设');
      expect(
        zone.entries().where((e) => e.hypothesis == '证据暂缓'),
        isEmpty,
        reason: '出口二不登记',
      );
      expect(
        zone.entries().where((e) => e.hypothesis == '有编号假设'),
        isEmpty,
        reason: '出口一有编号归验证层管辖区，不入候选区',
      );
    });

    test('跨文本计数：同锚点不同 sourceTextId 累加', () async {
      final zone = CandidateZone();
      Future<void> fire(String sourceId) async {
        final client = _SpyClient(
          (_) async => _observations(
            '{"exit":"unclassified","anchorQuotes":["桦树林染上秋日的黄色。"],'
            '"reason":"同一现象","syndromeId":""}',
          ),
        );
        await runChatChainDiscovery(
          gate: _gate(_completeKeys, client),
          llmClient: client,
          content: _content,
          zone: zone,
          sourceTextId: sourceId,
        );
      }

      await fire('chapter-1');
      await fire('chapter-2');
      await fire('chapter-2');
      expect(
        zone.entryByAnchor('桦树林染上秋日的黄色。')!.occurrences,
        2,
        reason: '同来源重复不计数，跨来源独立计数',
      );
    });
  });
}
