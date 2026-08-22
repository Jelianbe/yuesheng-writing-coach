// ─────────────────────────────────────────────────────────────
// EvaluationReportsStore 单元测试 — 评估报告状态管理
//
// 覆盖路径：
//   1. buildEvaluationReport：训练后 → reports[messageId] 非空 + round 递增
//   2. 无诊断历史 → 不保存 + round 不变
//   3. dismissEvaluationReport：关闭指定消息的报告
//   4. resetReports：清空全部
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/providers/evaluation_providers.dart';
import 'package:writingcoach/services/evaluation_service.dart';
import 'package:writingcoach/types/display_types.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late AppStateRepository appStateRepo;
  late EvaluationReportsStore store;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    appStateRepo = AppStateRepository(db);
    store = EvaluationReportsStore(
      EvaluationService(diagnosisRepo, studentModelRepo),
      appStateRepo,
    );
  });

  tearDown(() async => db.close());

  Future<(String sessionId, String messageId)>
  seedSessionWithDiagnosis() async {
    final sessionId = await sessionRepo.createBlankSession();
    final messageId = await sessionRepo.addMessage(
      sessionId,
      'assistant',
      '诊断内容',
      messageType: 'diagnosis_result',
    );
    await diagnosisRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sessionId,
        messageId: messageId,
        syndromes: [
          {'syndrome_id': 's1', 'name': '叙事含糊', 'severity': 'L2'},
        ],
        suggestedActions: const [],
        confidence: 0.8,
      ),
    );
    return (sessionId, messageId);
  }

  group('EvaluationReportsStore', () {
    test('#1 buildEvaluationReport → reports 挂到消息 + round 递增', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();

      await store.buildEvaluationReport(sessionId, messageId);

      expect(store.state.reports.containsKey(messageId), isTrue);
      final report = store.state.reports[messageId]!;
      expect(report.round, 0);
      expect(report.trend, isNotNull);
      expect(store.state.currentRound, 1);
    });

    test('#2 无诊断历史 → 不保存 + round 不变', () async {
      final sessionId = await sessionRepo.createBlankSession();

      await store.buildEvaluationReport(sessionId, 'msg-none');

      expect(store.state.reports, isEmpty);
      expect(store.state.currentRound, 0);
    });

    test('#3 dismissEvaluationReport → 删除指定消息报告', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(sessionId, messageId);
      expect(store.state.reports.containsKey(messageId), isTrue);

      await store.dismissEvaluationReport(messageId);

      expect(store.state.reports.containsKey(messageId), isFalse);
      expect(store.state.currentRound, 1, reason: '关闭不影响轮次');
    });

    test('#4 resetReports → 清空全部', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(sessionId, messageId);

      await store.resetReports();

      expect(store.state.reports, isEmpty);
      expect(store.state.currentRound, 0);
    });

    // ── 批次4-M3：持久化回归测试 ──

    test('#5 buildEvaluationReport 后报告落库 app_state（批次4-M3）', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(sessionId, messageId);

      // DB 层直接验证
      final round = await appStateRepo.getEvaluationRound(sessionId);
      expect(round, 1, reason: '轮次已落库');

      final report = await appStateRepo.getEvaluationReport(
        sessionId,
        messageId,
      );
      expect(report, isNotNull, reason: '报告已落库');
      expect(report!.round, 0);
      expect(report.trainingCount, greaterThan(0));
    });

    test('#6 restoreForSession 从 DB 恢复报告 + 轮次（批次4-M3）', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(sessionId, messageId);
      // 再构建一轮，让 currentRound=2
      final messageId2 = await sessionRepo.addMessage(
        sessionId,
        'assistant',
        '诊断2',
        messageType: 'diagnosis_result',
      );
      await store.buildEvaluationReport(sessionId, messageId2);
      expect(store.state.currentRound, 2);
      expect(store.state.reports.length, 2);

      // 模拟应用重启：新建 store 实例，从 DB 恢复
      final newStore = EvaluationReportsStore(
        EvaluationService(diagnosisRepo, studentModelRepo),
        appStateRepo,
      );
      await newStore.restoreForSession(sessionId);

      expect(newStore.state.currentRound, 2, reason: '轮次从 DB 恢复');
      expect(newStore.state.reports.length, 2, reason: '报告从 DB 恢复');
      expect(newStore.state.reports.containsKey(messageId), isTrue);
      expect(newStore.state.reports.containsKey(messageId2), isTrue);
    });

    test('#7 dismissEvaluationReport 同步删除 DB 记录（批次4-M3）', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(sessionId, messageId);

      // DB 有记录
      var report = await appStateRepo.getEvaluationReport(sessionId, messageId);
      expect(report, isNotNull);

      await store.dismissEvaluationReport(messageId);

      // DB 记录已删除
      report = await appStateRepo.getEvaluationReport(sessionId, messageId);
      expect(report, isNull);
    });

    test('#8 resetReports 同步清空 DB 记录（批次4-M3）', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(sessionId, messageId);

      await store.resetReports();

      // DB 报告和轮次都清空
      final reports = await appStateRepo.listEvaluationReports(sessionId);
      expect(reports, isEmpty);
      final round = await appStateRepo.getEvaluationRound(sessionId);
      expect(round, 0);
    });

    test('#9 EvaluationData toJson/fromJson 往返一致性（批次4-M3）', () {
      final original = EvaluationData(
        round: 3,
        trend: EvaluationTrend.improving,
        trainingCount: 5,
        passRate: 0.8,
        severityDelta: -1,
        summaryText: '整体改善',
        syndromeDetails: [
          SyndromeEvaluationDetail(
            syndromeId: 's1',
            syndromeName: '叙事含糊',
            currentSeverity: Severity.l1,
            teachingState: TeachingState.consolidating,
            passCount: 3,
            totalCount: 4,
            trend: EvaluationTrend.improving,
          ),
        ],
        generatedAt: 1700000000,
      );
      final json = original.toJsonString();
      final restored = EvaluationData.fromJsonString(json);
      expect(restored, isNotNull);
      expect(restored!.round, 3);
      expect(restored.trend, EvaluationTrend.improving);
      expect(restored.trainingCount, 5);
      expect(restored.passRate, 0.8);
      expect(restored.severityDelta, -1);
      expect(restored.summaryText, '整体改善');
      expect(restored.syndromeDetails.length, 1);
      expect(restored.syndromeDetails.first.syndromeId, 's1');
      expect(
        restored.syndromeDetails.first.teachingState,
        TeachingState.consolidating,
      );
      expect(restored.generatedAt, 1700000000);
    });
  });
}
