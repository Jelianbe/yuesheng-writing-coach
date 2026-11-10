// ─────────────────────────────────────────────────────────────
// S3 数据面测试（T-20261108-02 · R-027 已批 2026-11-08）
// 覆盖：discoverySectionOf 映射（S0 / 态① / 出口三过滤 / 往返稳定）
//       + DiagnosisResultCardPayload.discovery 落库往返与旧消息兼容。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/discovery_card_payload.dart';
import 'package:writingcoach/services/discovery_note.dart';
import 'package:writingcoach/services/message_card_service.dart';

void main() {
  group('discoverySectionOf（轮次产物 → 折叠条 payload 唯一映射行）', () {
    test('result == null ⇒ null（S0：短文单次链路 / 旧轮，不落 key）', () {
      expect(discoverySectionOf(true, null), isNull);
      expect(discoverySectionOf(false, null), isNull);
    });

    test('configured=false 也落 key（gate=null 亦广播 empty ⇒ 态①数据）', () {
      final s = discoverySectionOf(false, DiscoveryParseResult.empty);
      expect(s, isNotNull);
      expect(s!.configured, isFalse);
      expect(s.unclassified, isEmpty);
    });

    test('只保留出口三；promoted / observation 不进用户面 payload', () {
      const r = DiscoveryParseResult(
        rawCount: 3,
        promoted: 1,
        dropped: 0,
        notes: [
          DiscoveryNote(
            exit: DiscoveryExit.promoted,
            anchorQuotes: ['a'],
            syndromeId: 'P001',
          ),
          DiscoveryNote(
            exit: DiscoveryExit.observation,
            reason: '观察记录',
            anchorQuotes: ['b'],
          ),
          DiscoveryNote(
            exit: DiscoveryExit.unclassified,
            reason: '清单未覆盖的节奏问题',
            anchorQuotes: ['c', 'd'],
          ),
        ],
      );
      final s = discoverySectionOf(true, r)!;
      expect(s.configured, isTrue);
      expect(s.unclassified, hasLength(1));
      expect(s.unclassified.single.reason, '清单未覆盖的节奏问题');
      expect(s.unclassified.single.anchorQuotes, ['c', 'd']);
    });

    test('DiscoverySectionCard toJson/fromJson 往返稳定；空条目不落 key', () {
      const s = DiscoverySectionCard(
        configured: true,
        unclassified: [
          DiscoveryNoteCard(reason: 'r', anchorQuotes: ['q']),
        ],
      );
      final back = DiscoverySectionCard.fromJson(s.toJson());
      expect(back.configured, isTrue);
      expect(back.unclassified.single.reason, 'r');
      expect(back.unclassified.single.anchorQuotes, ['q']);

      final emptyJson = const DiscoverySectionCard(configured: false).toJson();
      expect(emptyJson.containsKey('unclassified'), isFalse);
    });
  });

  group('DiagnosisResultCardPayload.discovery（卡片 payload 通道）', () {
    Map<String, dynamic> baseJson() => {
      'syndromeCount': 0,
      'syndromes': <dynamic>[],
      'suggestedActions': <dynamic>[],
      'confidence': 0.0,
      'diagnosisId': 'm1',
    };

    test('旧消息 / 短文轮：payload 无 discovery key ⇒ null（S0 兼容）', () {
      final p = DiagnosisResultCardPayload.fromJson(baseJson());
      expect(p.discovery, isNull);
    });

    test('discovery 落库往返（toJson → fromJson 保形）', () {
      const payload = DiagnosisResultCardPayload(
        syndromeCount: 0,
        syndromes: [],
        suggestedActions: [],
        confidence: 0,
        diagnosisId: 'm1',
        discovery: DiscoverySectionCard(
          configured: true,
          unclassified: [
            DiscoveryNoteCard(reason: 'r1', anchorQuotes: ['q1']),
          ],
        ),
      );
      final back = DiagnosisResultCardPayload.fromJson(payload.toJson());
      expect(back.discovery, isNotNull);
      expect(back.discovery!.configured, isTrue);
      expect(back.discovery!.unclassified.single.reason, 'r1');
      expect(back.discovery!.unclassified.single.anchorQuotes, ['q1']);
    });
  });
}
