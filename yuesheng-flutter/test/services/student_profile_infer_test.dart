// ─────────────────────────────────────────────────────────────
// student_profile 家族推断函数的直接单元测试（R-019 重构护栏）
//
// 背景：inferCognitiveStyle / buildStrategyEffectiveness / inferProficiency
// 在 test/ 里**零直接引用**，此前只有经 buildStudentContext 的间接覆盖
// ——6 个变异全部漏网（见 tool/_verify_profile_r019_batch.py），
// 即「测试全绿」并不代表这些分支被验证过。本文件补的正是这块真空。
//
// 每个用例都锚定一处判据边界，变异验证要求：改动该判据 → 本文件必须变红。
// ─────────────────────────────────────────────────────────────
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/student_profile.dart';
import 'package:writingcoach/services/student_profile_compute.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late StudentModelRepository studentModelRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    studentModelRepo = StudentModelRepository(db);
  });

  tearDown(() async => db.close());

  group('inferProficiency（纯函数，阈值边界逐档）', () {
    test('空历史 → beginner，置信度 0（无可推断样本）', () {
      final r = inferProficiency(<Severity>[]);
      expect(r.level, ProficiencyLevel.beginner);
      expect(r.confidence, 0);
    });

    test('l3 恰好达阈值 3 → beginner（>= 边界，改 > 即漏）', () {
      final r = inferProficiency([
        Severity.l3,
        Severity.l3,
        Severity.l3,
      ]);
      expect(r.level, ProficiencyLevel.beginner);
      // min(0.9, 0.4 + 3/3) = 0.9
      expect(r.confidence, closeTo(0.9, 1e-9));
    });

    test('l2 恰好达阈值 5 → beginner（>= 边界，改 > 即漏）', () {
      final r = inferProficiency([
        Severity.l2,
        Severity.l2,
        Severity.l2,
        Severity.l2,
        Severity.l2,
      ]);
      expect(r.level, ProficiencyLevel.beginner);
      // min(0.8, 0.3 + 5/5) = 0.8
      expect(r.confidence, closeTo(0.8, 1e-9));
    });

    test('近期窗口内全 l1 且样本达标 → advanced，置信度 0.8', () {
      final r = inferProficiency([
        Severity.l1,
        Severity.l1,
        Severity.l1,
      ]);
      expect(r.level, ProficiencyLevel.advanced);
      expect(r.confidence, ProficiencyThresholds.advancedConfidence);
    });

    test('样本 < 3 → intermediate 低样本置信度 0.4', () {
      final r = inferProficiency([Severity.l1, Severity.l2]);
      expect(r.level, ProficiencyLevel.intermediate);
      expect(r.confidence, ProficiencyThresholds.lowSampleConfidence);
    });

    test('样本 ≥ 10 → intermediate 高样本置信度 0.9', () {
      // 10 条全 l1 会命中 advanced（窗口取末 5 条且全 l1），故把非 l1 放进
      // 窗口内破坏该判据——放开头无效，窗口只看最后 5 条
      final history = List<Severity>.filled(10, Severity.l1);
      history[9] = Severity.l2;
      final r = inferProficiency(history);
      expect(r.level, ProficiencyLevel.intermediate);
      expect(r.confidence, ProficiencyThresholds.highSampleConfidence);
    });
  });

  group('inferCognitiveStyle（关键词计数 + 比值判据）', () {
    test('user 消息不足 2 条 → null（门槛 <2，改 <1 即漏）', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await sessionRepo.addMessage(sessionId, 'user', '逻辑 结构 因果 框架');

      // 单条消息即便关键词密布也不做推断（样本不足）
      final r = await inferCognitiveStyle(sessionRepo, sessionId);
      expect(r, isNull);
    });

    test('两条消息但无关键词命中 → null', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await sessionRepo.addMessage(sessionId, 'assistant', '你好');
      await sessionRepo.addMessage(sessionId, 'user', '今天天气不错');
      await sessionRepo.addMessage(sessionId, 'user', '嗯，是的');

      final r = await inferCognitiveStyle(sessionRepo, sessionId);
      expect(r, isNull);
    });

    test('analytical/intuitive = 2 → analytical（>= 边界，改 > 即漏）', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await sessionRepo.addMessage(sessionId, 'user', '逻辑 结构');
      await sessionRepo.addMessage(sessionId, 'user', '感觉');

      final r = await inferCognitiveStyle(sessionRepo, sessionId);
      expect(r, isNotNull);
      expect(r!.style, CognitiveStyle.analytical);
    });

    test('analytical/intuitive = 0.5 → intuitive（<= 边界）', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await sessionRepo.addMessage(sessionId, 'user', '逻辑');
      await sessionRepo.addMessage(sessionId, 'user', '感觉 体会');

      final r = await inferCognitiveStyle(sessionRepo, sessionId);
      expect(r, isNotNull);
      expect(r!.style, CognitiveStyle.intuitive);
    });

    test('两者持平 → mixed，置信度走 mixed 常量对', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await sessionRepo.addMessage(sessionId, 'user', '逻辑');
      await sessionRepo.addMessage(sessionId, 'user', '感觉');

      final r = await inferCognitiveStyle(sessionRepo, sessionId);
      expect(r, isNotNull);
      expect(r!.style, CognitiveStyle.mixed);
      // min(0.6, 0.3 + 2 × 0.03) = 0.36
      expect(r.confidence, closeTo(0.36, 1e-9));
    });
  });

  group('buildStrategyEffectiveness（分组聚合 + 渲染）', () {
    Map<String, dynamic> record({
      required String mode,
      required String eff,
      required List<String> syndromes,
    }) => {
      'type': 'diagnosis',
      'teaching_mode': mode,
      'effectiveness': eff,
      'syndromes': syndromes,
    };

    test('有效记录不足 2 条 → 空串（门槛 <2，改 <1 即漏）', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await studentModelRepo.appendTeachingHistory(
        sessionId,
        record(mode: 'socratic', eff: 'improved', syndromes: ['P001']),
      );

      final text = await buildStrategyEffectiveness(
        studentModelRepo,
        sessionId,
      );
      expect(text, isEmpty);
    });

    test('同症候同 mode 两次 → 合并计次渲染', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await studentModelRepo.appendTeachingHistory(
        sessionId,
        record(mode: 'socratic', eff: 'improved', syndromes: ['P001']),
      );
      await studentModelRepo.appendTeachingHistory(
        sessionId,
        record(mode: 'socratic', eff: 'improved', syndromes: ['P001']),
      );

      final text = await buildStrategyEffectiveness(
        studentModelRepo,
        sessionId,
      );
      expect(text, contains('P001'));
      expect(text, contains('苏格拉底追问 × 2 次（有效）'));
    });

    test('no_change 不覆盖既有有效值（保留更严重/明确的判定）', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await studentModelRepo.appendTeachingHistory(
        sessionId,
        record(mode: 'socratic', eff: 'worsened', syndromes: ['P001']),
      );
      await studentModelRepo.appendTeachingHistory(
        sessionId,
        record(mode: 'socratic', eff: 'no_change', syndromes: ['P001']),
      );

      final text = await buildStrategyEffectiveness(
        studentModelRepo,
        sessionId,
      );
      // 第二次的 no_change 不应把「恶化」冲掉
      expect(text, contains('恶化'));
      expect(text, isNot(contains('无变化')));
    });

    test('同 mode 连续 2 次无变化 → 追加切换建议', () async {
      final sessionId = await sessionRepo.createBlankSession();
      await studentModelRepo.appendTeachingHistory(
        sessionId,
        record(mode: 'mirror', eff: 'no_change', syndromes: ['P002']),
      );
      await studentModelRepo.appendTeachingHistory(
        sessionId,
        record(mode: 'mirror', eff: 'no_change', syndromes: ['P002']),
      );

      final text = await buildStrategyEffectiveness(
        studentModelRepo,
        sessionId,
      );
      expect(text, contains('镜像反馈 × 2 次（无变化）'));
      expect(text, contains('连续无效，建议切换'));
    });
  });
}
