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
import 'package:writingcoach/services/growth_service.dart';
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
      GrowthService(db),
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
        GrowthService(db),
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

    test('#10 E-1：复诊字段往返 + 旧 JSON 向后兼容', () {
      // 新字段往返：occurrences / recurrences / previousSeverity 完整保留
      const detail = SyndromeEvaluationDetail(
        syndromeId: 's1',
        syndromeName: '叙事含糊',
        currentSeverity: Severity.l2,
        teachingState: TeachingState.inProgress,
        passCount: 2,
        totalCount: 3,
        trend: EvaluationTrend.improving,
        occurrences: 3,
        recurrences: 1,
        previousSeverity: Severity.l3,
      );
      final roundTrip = SyndromeEvaluationDetail.fromJson(detail.toJson());
      expect(roundTrip, isNotNull);
      expect(roundTrip!.occurrences, 3);
      expect(roundTrip.recurrences, 1);
      expect(roundTrip.previousSeverity, Severity.l3);
      expect(roundTrip.isRecurrence, isTrue);

      // 旧 JSON（E-1 字段缺失）→ 回退为「非复诊」默认值，不抛错
      final legacy = SyndromeEvaluationDetail.fromJson(const {
        'syndromeId': 's0',
        'syndromeName': '旧条目',
        'currentSeverity': 'L2',
        'teachingState': 'identified',
        'passCount': 1,
        'totalCount': 2,
        'trend': 'stable',
      });
      expect(legacy, isNotNull);
      expect(legacy!.occurrences, 1);
      expect(legacy.recurrences, 0);
      expect(legacy.previousSeverity, isNull);
      expect(legacy.isRecurrence, isFalse);
    });
  });

  group('P1-5 能力分快照', () {
    test('#E5 buildEvaluationReport 附加评估时点全局能力分（同口径，非新公式）', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();

      await store.buildEvaluationReport(sessionId, messageId);

      final report = store.state.reports[messageId];
      expect(report, isNotNull);
      // 附加了六维能力分快照（与 GrowthService.getAbilityScores 同函数产物）
      expect(report!.abilityScores, isNotEmpty);
      expect(
        report.abilityScores.length,
        GrowthService.abilityDimensions.length,
      );
      expect(report.abilityScores.first.score, inInclusiveRange(0, 100));
    });

    test('#E6 能力快照随报告落库，重启后仍可读回', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(sessionId, messageId);

      final newStore = EvaluationReportsStore(
        EvaluationService(diagnosisRepo, studentModelRepo),
        appStateRepo,
        GrowthService(db),
      );
      await newStore.restoreForSession(sessionId);

      final restored = newStore.state.reports[messageId];
      expect(restored, isNotNull);
      expect(restored!.abilityScores, isNotEmpty);
    });

    test('#E7 旧 JSON（无 abilityScores 键）反序列化 → 空数组，不抛错', () async {
      final legacy = EvaluationData.fromJsonString(
        '{"round":1,"trend":"stable","trainingCount":0,"passRate":0.5,"summaryText":"旧报告","syndromeDetails":[],"generatedAt":1000}',
      );
      expect(legacy, isNotNull);
      expect(legacy!.abilityScores, isEmpty);
    });

    test('#E8 能力快照序列化往返保真（toJsonString → fromJsonString）', () async {
      final (sessionId, messageId) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(sessionId, messageId);

      final report = store.state.reports[messageId]!;
      final roundTrip = EvaluationData.fromJsonString(report.toJsonString());

      expect(roundTrip, isNotNull);
      expect(roundTrip!.abilityScores.length, report.abilityScores.length);
      expect(
        roundTrip.abilityScores.first.score,
        report.abilityScores.first.score,
      );
      expect(
        roundTrip.abilityScores.first.dimension,
        report.abilityScores.first.dimension,
      );
    });
  });

  group('P1-5 跨会话能力历史', () {
    test('#E9 listAllEvaluationReports 跨会话聚合 + 按 generatedAt 升序', () async {
      final (s1, m1) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(s1, m1);
      final (s2, m2) = await seedSessionWithDiagnosis();
      await store.buildEvaluationReport(s2, m2);

      final all = await appStateRepo.listAllEvaluationReports();

      expect(all.length, 2);
      expect(all[0].generatedAt, lessThanOrEqualTo(all[1].generatedAt));
    });
  });
}
