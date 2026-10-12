// ─────────────────────────────────────────────────────────────
// D4 · O1 双 Owner 幂等判决性实验（ADR-0005 §6 项 2 / 外部评审 U8）
//
// 命题（待证实或证伪）：
//   DiagnosisService 解锁族（checkAndResolveMastered / autoCheckAndUnlock →
//   resolveSyndromesBatch，写 active_problems.status）与
//   DiagnosisCommitter.applyPhaseMigration（写 teaching_state + 插升级卡）
//   在同一轮 _runDiagnosisCommitSequence 内先后执行，
//   存在「顺序依赖 + 非幂等」。
//
// 实验设计（同轮双路径 A/B + 重入行为 + 一条正对照）：
//   A · 现行顺序（解锁先行，迁移后置）—— 对齐生产 _runDiagnosisCommitSequence
//   B · 逆序（迁移先行，解锁后置）—— 若终态不同 ⇒ 顺序依赖被证实
//   C · 重入（A 序列后同轮再调一次 applyPhaseMigration）—— 若链跳 ⇒ 非幂等被证实
//   D · 正对照（达标率 <0.7 时跑 A）—— 证明 A 的迁移确由 M4-A 触发，
//       不是「无论如何都迁移」（没有这条对照，A 的绿没有鉴别力）
//
// 夹具（每例fresh in-memory DB）：
//   - 会话停在 P2_PRACTICE_LOOP
//   - 一条活跃症候 s1，teaching_state=mastered（本轮会被正向解锁）
//   - 4 条 confirmation 史（3 confirmed + 1 disputed）⇒ 达标率 0.75 ≥ 0.7、
//     样本 4 ≥ minPhaseMigrationSamples(3) ⇒ M4-A 放行
//   - 本轮为「干净诊断」：syndromes 空、无 suggestedPhase
//     （无 suggestedPhase ⇒ 路径1 AI 驱动不触发，只走路径2 M4-A —— 隔离变量）
//
// 边界（R-010）：纯测试层新增，不改任何 lib/ 产品代码。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sessionRepo;
  late TeachingStateRepository stateRepo;
  late DiagnosisRepository diagnosisRepo;
  late StudentModelRepository studentModelRepo;
  late DiagnosisService diagnosisService;
  late DiagnosisCommitter committer;
  late String sessionId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sessionRepo = SessionRepository(db);
    stateRepo = TeachingStateRepository(db);
    diagnosisRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    diagnosisService = DiagnosisService(
      diagnosisRepo: diagnosisRepo,
      studentModelRepo: studentModelRepo,
    );
    committer = DiagnosisCommitter(
      sessionRepo: sessionRepo,
      stateRepo: stateRepo,
      diagnosisRepo: diagnosisRepo,
      studentModelRepo: studentModelRepo,
      referenceRepo: ReferenceRepository(db),
      chapterRepo: ChapterRepository(db),
    );
    sessionId = await sessionRepo.createBlankSession();
    await stateRepo.updatePhase(sessionId, TeachingPhase.p2PracticeLoop.value);
  });

  tearDown(() async => db.close());

  /// 夹具：一条活跃症候 s1（ mastered ⇒ 本轮被正向解锁 ）
  Future<void> seedMasteredActiveProblem() async {
    final msgId = await sessionRepo.addMessage(
      sessionId,
      'assistant',
      '诊断内容',
      messageType: 'diagnosis_result',
    );
    await diagnosisRepo.commitDiagnosis(
      DiagnosisInput(
        sessionId: sessionId,
        messageId: msgId,
        syndromes: [
          {'syndrome_id': 's1', 'name': '叙事含糊', 'severity': 'L2'},
        ],
        suggestedActions: const [],
        confidence: 0.8,
      ),
    );
    await diagnosisRepo.updateTeachingState(sessionId, 's1', 'mastered');
  }

  /// 夹具：达标率史（confirmation 记录）。
  /// [confirmed]/[disputed] 计入 computePassRateForPhaseMigration 的分母，
  /// 且样本量须 ≥ minPhaseMigrationSamples(3)。
  /// 症候号用 'sx'（从不落 active_problem）⇒ 不干扰 s1 的解锁判据。
  Future<void> seedConfirmationHistory({
    required int confirmed,
    required int disputed,
  }) async {
    var ts = 1000;
    for (var i = 0; i < confirmed; i++) {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['sx'],
        'action': 'confirmed',
        'timestamp': ts++,
        'sessionId': sessionId,
      });
    }
    for (var i = 0; i < disputed; i++) {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['sx'],
        'action': 'disputed',
        'timestamp': ts++,
        'sessionId': sessionId,
      });
    }
  }

  /// 本轮「干净诊断」：空症候、无 suggestedPhase。
  /// 空症候 ⇒ commitDiagnosis 不产生新 active_problem（M4-A 的
  /// 「活跃全 resolved」只可能由解锁族达成，隔离出顺序变量）。
  ParsedDiagnosis cleanDiagnosis() => const ParsedDiagnosis(
    syndromes: [],
    suggestedActions: [],
    confidence: 0.8,
  );

  Future<DiagnosisInput> cleanDiagnosisInput() async {
    final msgId = await sessionRepo.addMessage(sessionId, 'user', '（本轮正文）');
    return DiagnosisInput(
      sessionId: sessionId,
      messageId: msgId,
      syndromes: const [],
      suggestedActions: const [],
      confidence: 0.8,
    );
  }

  Future<String?> currentPhase() async =>
      (await stateRepo.getTeachingState(sessionId))?.currentPhase;

  Future<int> upgradeCardCount() async => (await sessionRepo.listMessages(
    sessionId,
  )).where((m) => m.messageType == 'phase_upgrade').length;

  Future<bool> hasActiveProblem() async =>
      (await diagnosisRepo.listActiveProblems(sessionId)).isNotEmpty;

  group('D4-O1 · A 路径（现行顺序：解锁先行 → 迁移后置）', () {
    test('A1：mastered 症候被解锁 + M4-A 同轮升阶 P2→P3，恰 1 张升级卡', () async {
      await seedMasteredActiveProblem();
      await seedConfirmationHistory(confirmed: 3, disputed: 1);
      final input = await cleanDiagnosisInput();

      // 对齐生产 _runDiagnosisCommitSequence（diagnosis_flow_handler.dart:603-640）：
      // step1 commitDiagnosisWithHistory（内含解锁族）→ step2 updateSubphase
      //       → step4 applyPhaseMigration
      // （step3 结果卡只写消息流，不碰教学状态，实验中略去）
      await diagnosisService.commitDiagnosisWithHistory(input);
      await stateRepo.updateSubphase(sessionId, null);
      await committer.applyPhaseMigration(
        sessionId: sessionId,
        diagnosis: cleanDiagnosis(),
      );

      expect(
        await currentPhase(),
        TeachingPhase.p3Training.value,
        reason: 'A 路径下同轮应完成 P2→P3',
      );
      expect(await upgradeCardCount(), 1, reason: '恰 1 张升级卡');
      expect(await hasActiveProblem(), isFalse, reason: 's1 应已被解锁');
    });
  });

  group('D4-O1 · B 路径（逆序：迁移先行 → 解锁后置）', () {
    test('B1：逆序下 M4-A 看不到「已解锁」状态 ⇒ 同轮不升阶、零卡', () async {
      await seedMasteredActiveProblem();
      await seedConfirmationHistory(confirmed: 3, disputed: 1);
      final input = await cleanDiagnosisInput();

      // 逆序：先迁移后解锁
      await committer.applyPhaseMigration(
        sessionId: sessionId,
        diagnosis: cleanDiagnosis(),
      );
      await diagnosisService.commitDiagnosisWithHistory(input);

      expect(
        await currentPhase(),
        TeachingPhase.p2PracticeLoop.value,
        reason: '逆序下 M4-A 见到 s1 仍活跃 ⇒ 不满足「活跃全 resolved」',
      );
      expect(await upgradeCardCount(), 0, reason: '不迁移 ⇒ 零升级卡');
      expect(
        await hasActiveProblem(),
        isFalse,
        reason: '解锁族后置仍生效 —— 排除「B 不迁移是因为解锁没跑」',
      );
    });
  });

  group('D4-O1 · C 路径（同轮重入 applyPhaseMigration）', () {
    test('C1：同轮二次调用链跳 P3→P4 + 第二张卡 ⇒ 非幂等', () async {
      await seedMasteredActiveProblem();
      await seedConfirmationHistory(confirmed: 3, disputed: 1);
      final input = await cleanDiagnosisInput();

      await diagnosisService.commitDiagnosisWithHistory(input);
      await stateRepo.updateSubphase(sessionId, null);
      await committer.applyPhaseMigration(
        sessionId: sessionId,
        diagnosis: cleanDiagnosis(),
      );
      // 同轮重入（生产当前只有一处调用点，故此路径为潜在而非现存）
      await committer.applyPhaseMigration(
        sessionId: sessionId,
        diagnosis: cleanDiagnosis(),
      );

      expect(
        await currentPhase(),
        TeachingPhase.p4Review.value,
        reason: '第二次调用在已升阶状态上再评估 ⇒ 链跳到 P4',
      );
      expect(await upgradeCardCount(), 2, reason: '链跳产生第二张升级卡');
    });
  });

  group('D4-O1 · D 路径（正对照：M4-C 达标率拦截）', () {
    test('D1：达标率 1/3 < 0.7 ⇒ A 顺序也不升阶（证明 A1 确由 M4-A 触发）', () async {
      await seedMasteredActiveProblem();
      // 1 confirmed + 2 disputed ⇒ passRate = 0.333 < phasePassRate(0.7)
      await seedConfirmationHistory(confirmed: 1, disputed: 2);
      final input = await cleanDiagnosisInput();

      await diagnosisService.commitDiagnosisWithHistory(input);
      await stateRepo.updateSubphase(sessionId, null);
      await committer.applyPhaseMigration(
        sessionId: sessionId,
        diagnosis: cleanDiagnosis(),
      );

      expect(
        await currentPhase(),
        TeachingPhase.p2PracticeLoop.value,
        reason: 'M4-C 拦截 ⇒ 顺序正确也不迁移',
      );
      expect(await upgradeCardCount(), 0);
      expect(
        await hasActiveProblem(),
        isFalse,
        reason: 's1 mastered 仍被解锁 —— 与 A1 同前提，唯一差异是达标率',
      );
    });
  });
}
