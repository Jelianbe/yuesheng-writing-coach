// ─────────────────────────────────────────────────────────────
// message_card_service 单测 — 批次17 三卡 insert 函数
//
// 真源：yuesheng-android/src/services/__tests__/message-card-service.test.ts
// 覆盖：
//   #1 insertPartialAgreementCard → assistant 角色 + partial_agreement 类型 + JSON content
//   #2 insertPhaseSummaryCard → assistant 角色 + phase_summary 类型 + 完整 payload（含 syndromeChanges）
//   #3 insertDiagnosisFailedCard → assistant 角色 + diagnosis_failed 类型 + failureCount
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/message_card_service.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessRepo = SessionRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    '#1 insertPartialAgreementCard → assistant + partial_agreement + 平铺参数',
    () async {
      final sessionId = await sessRepo.createBlankSession();

      final messageId = await insertPartialAgreementCard(
        sessRepo,
        sessionId,
        'P002',
        '视角跳跃症',
        'L2',
      );

      final messages = await sessRepo.listMessages(sessionId);
      expect(messages.length, 1);
      final msg = messages.first;
      expect(msg.id, messageId);
      expect(msg.role, 'assistant');
      expect(msg.messageType, 'partial_agreement');

      final payload = PartialAgreementCardPayload.fromJson(
        jsonDecode(msg.content) as Map<String, dynamic>,
      );
      expect(payload.syndromeId, 'P002');
      expect(payload.syndromeName, '视角跳跃症');
      expect(payload.severity, 'L2');
    },
  );

  test(
    '#2 insertPhaseSummaryCard → assistant + phase_summary + 完整 payload',
    () async {
      final sessionId = await sessRepo.createBlankSession();

      final messageId = await insertPhaseSummaryCard(
        sessRepo,
        sessionId,
        PhaseSummaryCardPayload(
          result: 'passed',
          resolvedSyndromeCount: 2,
          trainingCount: 5,
          trend: 'improving',
          syndromeChanges: const [
            SyndromeChangeItem(
              syndromeId: 'P002',
              syndromeName: '视角跳跃症',
              trend: 'improving',
            ),
            SyndromeChangeItem(
              syndromeId: 'P007',
              syndromeName: '对话生硬',
              trend: 'stable',
            ),
          ],
        ),
      );

      final messages = await sessRepo.listMessages(sessionId);
      expect(messages.length, 1);
      final msg = messages.first;
      expect(msg.id, messageId);
      expect(msg.role, 'assistant');
      expect(msg.messageType, 'phase_summary');

      final payload = PhaseSummaryCardPayload.fromJson(
        jsonDecode(msg.content) as Map<String, dynamic>,
      );
      expect(payload.result, 'passed');
      expect(payload.resolvedSyndromeCount, 2);
      expect(payload.trainingCount, 5);
      expect(payload.trend, 'improving');
      expect(payload.syndromeChanges.length, 2);
      expect(payload.syndromeChanges[0].syndromeName, '视角跳跃症');
      expect(payload.syndromeChanges[1].trend, 'stable');
    },
  );

  test(
    '#3 insertDiagnosisFailedCard → assistant + diagnosis_failed + failureCount',
    () async {
      final sessionId = await sessRepo.createBlankSession();

      final messageId = await insertDiagnosisFailedCard(sessRepo, sessionId, 3);

      final messages = await sessRepo.listMessages(sessionId);
      expect(messages.length, 1);
      final msg = messages.first;
      expect(msg.id, messageId);
      expect(msg.role, 'assistant');
      expect(msg.messageType, 'diagnosis_failed');

      final payload = DiagnosisFailedCardPayload.fromJson(
        jsonDecode(msg.content) as Map<String, dynamic>,
      );
      expect(payload.failureCount, 3);
    },
  );

  test(
    '#4 insertTeacherSuggestionCard → JSON 往返含 locationMarks（批次63 B62d）',
    () async {
      final sessionId = await sessRepo.createBlankSession();

      final messageId = await insertTeacherSuggestionCard(
        sessRepo,
        sessionId,
        TeacherSuggestionCardPayload(
          suggestionId: 'sug-loc-1',
          teachingDecision: 'guide',
          naturalLanguage: '这段可以先用动作替代情绪词。',
          taskType: 'rewrite',
          taskDescription: '改写 3 处情绪标签。',
          difficulty: 'medium',
          evaluationCriteria: const ['避免情绪词'],
          targetSyndromeId: 'P001',
          targetSyndromeName: '情绪标签化',
          source: 'diagnosis',
          locationMarks: const ['第2段：他低声说道……', '第5段：她看着窗外……'],
        ),
      );

      final messages = await sessRepo.listMessages(sessionId);
      expect(messages.length, 1);
      final msg = messages.first;
      expect(msg.id, messageId);
      expect(msg.messageType, 'teacher_suggestion');

      final payload = TeacherSuggestionCardPayload.fromJson(
        jsonDecode(msg.content) as Map<String, dynamic>,
      );
      expect(payload.suggestionId, 'sug-loc-1');
      expect(payload.locationMarks, ['第2段：他低声说道……', '第5段：她看着窗外……']);
      expect(payload.targetSyndromeName, '情绪标签化');
    },
  );

  test(
    '#5 TeacherSuggestionCardPayload 无 locationMarks → 默认空列表（向后兼容）',
    () async {
      const json = {
        'suggestionId': 'sug-x',
        'teachingDecision': 'train',
        'naturalLanguage': '继续训练',
        'taskType': 'analyze',
        'taskDescription': '分析节奏',
        'difficulty': 'easy',
        'evaluationCriteria': ['标准1'],
        'targetSyndromeId': 'P003',
        'targetSyndromeName': '视角漂移',
        'source': 'diagnosis',
      };
      final payload = TeacherSuggestionCardPayload.fromJson(json);
      expect(payload.locationMarks, isEmpty);
      // 往返不丢失
      final roundTrip = TeacherSuggestionCardPayload.fromJson(payload.toJson());
      expect(roundTrip.locationMarks, isEmpty);
      expect(roundTrip.targetSyndromeName, '视角漂移');
    },
  );

  // ───────────────────────────────────────────────────────────
  // W-49：诊断话语三字段（rootCauseAnalysis / feedbackSummary / readerImpact）
  // 验收 A1–A3：字段加齐、camel/snake 双写容错、空值不落 key、往返稳定。
  // ───────────────────────────────────────────────────────────
  group('W-49 诊断话语字段', () {
    test('A1/A2 三字段往返稳定（非空值逐字段相等）', () {
      const payload = DiagnosisResultCardPayload(
        syndromeCount: 1,
        syndromes: [
          DiagnosisSyndromeCard(
            syndromeId: 'P002',
            name: '信息倾泻',
            severity: 'L2',
            evidenceCount: 1,
            readerImpact: '读者读到这里会失去画面，只剩概念在堆叠',
          ),
        ],
        suggestedActions: ['删掉两句设定说明'],
        confidence: 0.8,
        diagnosisId: 'msg-1',
        rootCauseAnalysis: '开篇把世界观一次性交代，缺少人物动作承载',
        feedbackSummary: '本轮主要是信息密度问题，先处理开场两段',
      );

      final round = DiagnosisResultCardPayload.fromJson(payload.toJson());

      expect(round.rootCauseAnalysis, payload.rootCauseAnalysis);
      expect(round.feedbackSummary, payload.feedbackSummary);
      expect(
        round.syndromes.single.readerImpact,
        payload.syndromes.single.readerImpact,
      );
      // 往返后 toJson 再次相等（幂等）
      expect(round.toJson(), payload.toJson());
    });

    test('A1/A2 空值与 null 均不落 key（不得写成空串）', () {
      const payload = DiagnosisResultCardPayload(
        syndromeCount: 0,
        syndromes: [],
        suggestedActions: [],
        confidence: 0.0,
        diagnosisId: 'msg-2',
        rootCauseAnalysis: '',
        feedbackSummary: '',
      );
      final json = payload.toJson();
      expect(json.containsKey('root_cause_analysis'), isFalse);
      expect(json.containsKey('feedbackSummary'), isFalse);

      const syndrome = DiagnosisSyndromeCard(
        syndromeId: 'P001',
        name: '情绪标签化',
        severity: 'L1',
        evidenceCount: 0,
        readerImpact: '',
      );
      final sJson = syndrome.toJson();
      expect(sJson.containsKey('reader_impact'), isFalse);

      // 空串读入后归一为 null（不是 ''）⇒ 往返仍不落 key
      final back = DiagnosisSyndromeCard.fromJson(sJson);
      expect(back.readerImpact, isNull);
    });

    test('A1/A2 camel 与 snake 双写均接受（历史消息/手工 JSON 容错）', () {
      final camel = DiagnosisResultCardPayload.fromJson({
        'syndromeCount': 1,
        'syndromes': [
          {
            'syndrome_id': 'P001',
            'name': 'x',
            'severity': 'L1',
            'evidenceCount': 0,
            'readerImpact': '读者会跳戏',
          },
        ],
        'suggestedActions': <String>[],
        'confidence': 0.5,
        'diagnosisId': 'm',
        'rootCauseAnalysis': '根因A',
        'feedbackSummary': '小结A',
      });
      expect(camel.rootCauseAnalysis, '根因A');
      expect(camel.feedbackSummary, '小结A');
      expect(camel.syndromes.single.readerImpact, '读者会跳戏');

      final snake = DiagnosisResultCardPayload.fromJson({
        'syndromeCount': 1,
        'syndromes': [
          {
            'syndrome_id': 'P001',
            'name': 'x',
            'severity': 'L1',
            'evidence_count': 0,
            'reader_impact': '读者会跳戏',
          },
        ],
        'suggestedActions': <String>[],
        'confidence': 0.5,
        'diagnosisId': 'm',
        'root_cause_analysis': '根因B',
        'feedback_summary': '小结B',
      });
      expect(snake.rootCauseAnalysis, '根因B');
      expect(snake.feedbackSummary, '小结B');
      expect(snake.syndromes.single.readerImpact, '读者会跳戏');
    });
  });
}
