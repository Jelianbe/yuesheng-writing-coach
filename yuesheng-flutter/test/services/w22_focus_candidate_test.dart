// ───────────────────────────────────────────────
// W-22 G1 · 候选焦点 payload 序列化护栏
//
// 设计批 §6.1 修正一：候选集经 DiagnosisResultCardPayload（既有消息持久化
// 通道）落库——不建新表。本测试守序列化往返稳定与「空候选不落 key」。
// ───────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/message_card_service.dart';

FocusCandidateCard _cand(
  String id, {
  String name = '情绪标签化',
  int total = 7,
  String rationale = 'P001：严重度 L2(2) · 干预价值 high(3) · 跨 2 章独立出现(2) ⇒ 7',
}) => FocusCandidateCard(
  syndromeId: id,
  name: name,
  total: total,
  rationale: rationale,
);

void main() {
  group('W-22 G1 payload 序列化', () {
    test('候选在场 ⇒ toJson→fromJson 往返逐字段稳定', () {
      final payload = DiagnosisResultCardPayload(
        syndromeCount: 1,
        syndromes: const [
          DiagnosisSyndromeCard(
            syndromeId: 'P001',
            name: '情绪标签化',
            severity: 'L2',
            evidenceCount: 1,
          ),
        ],
        suggestedActions: const [],
        confidence: 0.9,
        diagnosisId: 'msg-1',
        focusCandidates: [
          _cand('P001'),
          _cand('P003', name: '视角漂移', total: 5),
        ],
      );

      final json = payload.toJson();
      expect(json.containsKey('focusCandidates'), isTrue);
      expect((json['focusCandidates'] as List).length, 2);

      final restored = DiagnosisResultCardPayload.fromJson(json);
      expect(restored.focusCandidates, isNotNull);
      expect(restored.focusCandidates!.length, 2);
      expect(restored.focusCandidates![0].syndromeId, 'P001');
      expect(restored.focusCandidates![0].name, '情绪标签化');
      expect(restored.focusCandidates![0].total, 7);
      expect(
        restored.focusCandidates![0].rationale,
        payload.focusCandidates![0].rationale,
      );
      expect(restored.focusCandidates![1].syndromeId, 'P003');
    });

    test('空候选 ⇒ 不落 key，fromJson 归一为 null（候选区不渲染）', () {
      final payload = DiagnosisResultCardPayload(
        syndromeCount: 1,
        syndromes: const [
          DiagnosisSyndromeCard(
            syndromeId: 'P001',
            name: '情绪标签化',
            severity: 'L2',
            evidenceCount: 1,
          ),
        ],
        suggestedActions: const [],
        confidence: 0.9,
        diagnosisId: 'msg-1',
        focusCandidates: const [],
      );
      final json = payload.toJson();
      expect(json.containsKey('focusCandidates'), isFalse);
      expect(DiagnosisResultCardPayload.fromJson(json).focusCandidates, isNull);
    });

    test('null 候选（旧消息/未接线批次）⇒ 同样不渲染', () {
      final payload = DiagnosisResultCardPayload(
        syndromeCount: 1,
        syndromes: const [
          DiagnosisSyndromeCard(
            syndromeId: 'P001',
            name: '情绪标签化',
            severity: 'L2',
            evidenceCount: 1,
          ),
        ],
        suggestedActions: const [],
        confidence: 0.9,
        diagnosisId: 'msg-1',
      );
      expect(payload.toJson().containsKey('focusCandidates'), isFalse);
      expect(
        DiagnosisResultCardPayload.fromJson(payload.toJson()).focusCandidates,
        isNull,
      );
    });

    test('缺字段候选项容错（syndrome_id 缺失 ⇒ 空串，不抛）', () {
      final restored = FocusCandidateCard.fromJson({
        'name': '视角漂移',
        'total': 5,
      });
      expect(restored.syndromeId, '');
      expect(restored.name, '视角漂移');
      expect(restored.total, 5);
      expect(restored.rationale, '');
    });
  });
}
