// ─────────────────────────────────────────────────────────────
// TrainingInputBuilder 单元测试 — FSM 起点真实化（批次 44）
//
// 覆盖路径：
//   1. 诊断历史充足 + 趋势改善 → teachingState 起点 = consolidating
//      （修复：原硬编码 identified，FSM 永远到不了 consolidating）
//   2. 诊断历史少（<2）→ 返回 null（既有行为保持）
//   3. 多次诊断但未稳定改善 → 起点不越级（conservative，不误判 consolidating）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/training_evaluator.dart';
import 'package:writingcoach/services/training_input_builder.dart';
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

  Future<String> seedSession() async {
    return sessionRepo.createBlankSession();
  }

  Future<void> appendDiagnosis(
    String sessionId, {
    required String maxSeverity,
    required int timestamp,
    String syndromeId = 's1',
  }) async {
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'diagnosis',
      'syndromes': [syndromeId],
      'maxSeverity': maxSeverity,
      'timestamp': timestamp,
      'sessionId': sessionId,
    });
  }

  Future<void> appendTraining(
    String sessionId, {
    String result = 'passed',
  }) async {
    await studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'training',
      'syndromeId': 's1',
      'result': result,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  group('buildTrainingInputForActiveSyndrome — FSM 起点', () {
    test(
      '#1 诊断充足 + 趋势改善（L3→L2→L1→L1）→ teachingState 起点 = consolidating',
      () async {
        final sessionId = await seedSession();
        // 时间正序：L3(最旧) → L2 → L1 → L1(最新)
        await appendDiagnosis(sessionId, maxSeverity: 'L3', timestamp: 1000);
        await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 2000);
        await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 3000);
        await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 4000);
        await appendTraining(sessionId);

        final input = await buildTrainingInputForActiveSyndrome(
          studentModelRepo,
          sessionId,
          's1',
          const ActiveProblemMeta(currentSeverity: Severity.l1),
        );

        expect(input, isNotNull);
        // 批次 44 修复核心：起点不再是硬编码 identified，
        // 而是按诊断历史推断出 consolidating（评估报告徽章可达「趋稳中」）
        expect(input!.teachingState, TeachingState.consolidating);
      },
    );

    test('#1b 恰好 2 条诊断（阈值边界）→ 非 null', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 1000);
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 2000);

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        const ActiveProblemMeta(currentSeverity: Severity.l1),
      );

      expect(input, isNotNull);
    });

    test('#2 诊断历史不足（<2 条）→ null（既有行为保持）', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 1000);

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        const ActiveProblemMeta(currentSeverity: Severity.l2),
      );

      expect(input, isNull);
    });

    test('#2b 训练尾部连续 failed → deteriorationInput 连续失败锚定', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 1000);
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 2000);
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 's1',
        'result': 'failed',
        'timestamp': 3000,
        'sessionId': sessionId,
      });
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 's1',
        'result': 'failed',
        'timestamp': 4000,
        'sessionId': sessionId,
      });

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        const ActiveProblemMeta(currentSeverity: Severity.l1),
      );

      expect(input, isNotNull);
      expect(input!.deteriorationInput.consecutiveFailures, 2);
    });

    test('#3 多次诊断但未稳定改善（L1→L2→L1→L2 波动）→ 起点不越级到 consolidating', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 1000);
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 2000);
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: 3000);
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: 4000);

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        const ActiveProblemMeta(currentSeverity: Severity.l2),
      );

      expect(input, isNotNull);
      // 波动无改善趋势 → 起点为 in_progress（保守，不误判 consolidating）
      expect(input!.teachingState, TeachingState.inProgress);
    });
  });

  group('computeTrainingPerformance（批次16 7.2 performance_gate）', () {
    Future<void> appendTrainingAt(
      String sessionId, {
      required String result,
      required int timestamp,
      String syndromeId = 's1',
    }) async {
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': syndromeId,
        'result': result,
        'timestamp': timestamp,
        'sessionId': sessionId,
      });
    }

    test('#P1 无训练记录 → null', () async {
      final sessionId = await seedSession();
      expect(
        await computeTrainingPerformance(studentModelRepo, sessionId, 's1'),
        isNull,
      );
    });

    test('#P2 混合结果 → passRate / 连续段计算正确', () async {
      final sessionId = await seedSession();
      // 时间正序：failed → passed → partial → passed（最新）
      await appendTrainingAt(sessionId, result: 'failed', timestamp: 1000);
      await appendTrainingAt(sessionId, result: 'passed', timestamp: 2000);
      await appendTrainingAt(sessionId, result: 'partial', timestamp: 3000);
      await appendTrainingAt(sessionId, result: 'passed', timestamp: 4000);

      final p = await computeTrainingPerformance(
        studentModelRepo,
        sessionId,
        's1',
      );
      expect(p, isNotNull);
      expect(p!.totalCount, 4);
      expect(p.passRate, 0.5); // 2 passed / 4
      expect(p.consecutivePasses, 1); // 最新为 passed，遇 partial 中断
      expect(p.consecutiveFails, 0); // 最新为 passed，不是 failed
    });

    test('#P3 连续未达标 → consecutiveFails 正确（partial 不计入）', () async {
      final sessionId = await seedSession();
      await appendTrainingAt(sessionId, result: 'partial', timestamp: 1000);
      await appendTrainingAt(sessionId, result: 'failed', timestamp: 2000);
      await appendTrainingAt(sessionId, result: 'failed', timestamp: 3000);

      final p = await computeTrainingPerformance(
        studentModelRepo,
        sessionId,
        's1',
      );
      expect(p, isNotNull);
      expect(p!.passRate, 0.0);
      expect(p.consecutiveFails, 2);
      expect(p.consecutivePasses, 0);
    });

    test('#P4 只统计目标症候，不串其他症候', () async {
      final sessionId = await seedSession();
      await appendTrainingAt(sessionId, result: 'passed', timestamp: 1000);
      await appendTrainingAt(
        sessionId,
        result: 'failed',
        timestamp: 2000,
        syndromeId: 's2',
      );

      final p = await computeTrainingPerformance(
        studentModelRepo,
        sessionId,
        's1',
      );
      expect(p, isNotNull);
      expect(p!.totalCount, 1);
      expect(p.passRate, 1.0);
      expect(p.consecutiveFails, 0);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // ADR-C105 B5：派生字段的**直接**断言（不改实现，经输出 DTO 直锚）
  //
  // 立项依据（v3 更正后的实测）：`buildTrainingInputForActiveSyndrome` 的真实
  // 直接调用 = 5 处 / 1 文件（本文件 :76/:95/:109/:138/:156），但它们断言的
  // 只是 `teachingState` 与 `consecutiveFailures`。以下 helper **此前无任何
  // 直接断言**：`_resolvePreviousSeverity` / `_computeGapDays` /
  // `_computeDaysSinceLastObservation` / `_hasConfirmation` /
  // `_countConsecutiveLowSeverity` / `_isRelapseDetected` / `_loadTrainingFields`。
  // 它们的值全部经 `_assembleSummary` 落到输出 DTO ⇒ 可从 DTO 直锚，无需改实现。
  // ═════════════════════════════════════════════════════════════

  group('ADR-C105 B5 派生字段直接断言', () {
    /// 以「天」为单位构造时间戳（base 取大固定值，避免负数/溢出）
    int ts(int day) => 1000000 + day * 86400;

    Future<EvaluationSummaryInput> buildInput(
      String sessionId,
      Severity currentSeverity,
    ) async {
      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        's1',
        ActiveProblemMeta(currentSeverity: currentSeverity),
      );
      if (input == null) {
        fail('前置不满足：诊断记录 < 2 条时返回 null（检查本用例的种子）');
      }
      return input;
    }

    test('★previousSeverity 取**倒数第二条**诊断（不是第一条/最旧条）', () async {
      final sessionId = await seedSession();
      // 时间正序：L1(day0) → L2(day10) → L1(day20) → L1(day30 最新)
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(10));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(20));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(30));

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.severityInput.previousSeverity,
        Severity.l1,
        reason:
            'previousSeverity = 倒序第 2 条（day20 的 L1）。'
            '若误取「倒序第 0 条」会得到同为 L1 而蒙混过关；'
            '若误取「最旧条」会得到 L1 也相同 ⇒ 本用例再叠一条对照（下一条用例用 L2 区分）',
      );
      expect(input.severityInput.occurrenceCount, 4);
    });

    test('★previousSeverity 与最新一条区分（倒数第二条 L2、最新 L1）', () async {
      final sessionId = await seedSession();
      // 正序：L1(day0) → L2(day10) → L1(day20 最新)
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(10));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(20));

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.severityInput.previousSeverity,
        Severity.l2,
        reason:
            '倒序 = [L1(20), L2(10), L1(0)] ⇒ 第 2 条是 L2；'
            '若有人把它改成取最旧条（L1）或最新条（L1），本断言立即变红',
      );
    });

    test('★gapDays = 最近两次诊断的间隔（天，向下取整）', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(20));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(30));

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.deteriorationInput.gapDays,
        10,
        reason: '(day30 − day20) = 10 天；若误取「最新 − 最旧」会得到 30',
      );
    });

    test('★consecutiveLowSeverity = 自最新往前数连续 L1 个数（遇非 L1 断）', () async {
      final sessionId = await seedSession();
      // 正序：L1(0) → L2(10) → L1(20) → L1(30)
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(10));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(20));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(30));

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.stateTransitionInput.consecutiveLowSeverity,
        2,
        reason: '倒序扫：L1、L1、遇 L2 停止 ⇒ 2；若把整个序列都数进来会得到 3',
      );
    });

    test('★relapseDetected 三态：L1→L2 真 / L1→L3 真 / L1→L1 假', () async {
      // 两条 L1 诊断 ⇒ 倒序第 2 条（=最旧）为 L1，即可作为「上次严重度」
      final sid = await seedSession();
      await appendDiagnosis(sid, maxSeverity: 'L1', timestamp: ts(0));
      await appendDiagnosis(sid, maxSeverity: 'L1', timestamp: ts(10));
      expect(
        (await buildInput(
          sid,
          Severity.l2,
        )).stateTransitionInput.relapseDetected,
        isTrue,
      );
      expect(
        (await buildInput(
          sid,
          Severity.l3,
        )).stateTransitionInput.relapseDetected,
        isTrue,
      );
      expect(
        (await buildInput(
          sid,
          Severity.l1,
        )).stateTransitionInput.relapseDetected,
        isFalse,
        reason: '当前仍 L1 ⇒ 不算复发（本三态是 ADR-C105 B5 要求的用例）',
      );
    });

    test('★wasResolvedToL1 需 confirmation 命中 confirmed+L1（错一个即假）', () async {
      final sessionId = await seedSession();
      await appendDiagnosis(sessionId, maxSeverity: 'L2', timestamp: ts(0));
      await appendDiagnosis(sessionId, maxSeverity: 'L1', timestamp: ts(10));

      Future<void> appendConfirmation({
        required String action,
        required String severity,
      }) => studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'confirmation',
        'syndromes': ['s1'],
        'action': action,
        'severity': severity,
        'timestamp': ts(11),
        'sessionId': sessionId,
      });

      // 未加确认记录 → false
      expect(
        (await buildInput(
          sessionId,
          Severity.l2,
        )).deteriorationInput.wasResolvedToL1,
        isFalse,
      );

      // 加一条 severity=L2 的确认 → 仍 false（严重度不匹配）
      await appendConfirmation(action: 'confirmed', severity: 'L2');
      expect(
        (await buildInput(
          sessionId,
          Severity.l2,
        )).deteriorationInput.wasResolvedToL1,
        isFalse,
        reason: 'confirmed 但 severity≠L1 ⇒ 不得算「已缓解到 L1」',
      );

      // 加一条 confirmed+L1 → true
      await appendConfirmation(action: 'confirmed', severity: 'L1');
      expect(
        (await buildInput(
          sessionId,
          Severity.l2,
        )).deteriorationInput.wasResolvedToL1,
        isTrue,
      );
    });

    test('★daysSinceLastObservation 取「训练/诊断」中更近者（非仅诊断）', () async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final sessionId = await seedSession();
      // 诊断在 10 天前；训练在 1 天前 ⇒ 最近观察应是训练
      await appendDiagnosis(
        sessionId,
        maxSeverity: 'L2',
        timestamp: now - 10 * 86400,
      );
      await appendDiagnosis(
        sessionId,
        maxSeverity: 'L1',
        timestamp: now - 9 * 86400,
      );
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': 's1',
        'result': 'passed',
        'timestamp': now - 1 * 86400,
        'sessionId': sessionId,
      });

      final input = await buildInput(sessionId, Severity.l1);
      expect(
        input.stateTransitionInput.daysSinceLastObservation,
        lessThan(5),
        reason:
            '最近观察 = 1 天前的训练。若实现漏掉训练分支、只看诊断，'
            '会得到 ~9~10 ⇒ 断言失败（本用例守护「训练也算观察」语义）',
      );

      // 对照组：移除训练（新建会话只留诊断）⇒ 应以诊断为准（≈9 天）
      final sid2 = await seedSession();
      await appendDiagnosis(
        sid2,
        maxSeverity: 'L2',
        timestamp: now - 10 * 86400,
      );
      await appendDiagnosis(
        sid2,
        maxSeverity: 'L1',
        timestamp: now - 9 * 86400,
      );
      final input2 = await buildInput(sid2, Severity.l1);
      expect(
        input2.stateTransitionInput.daysSinceLastObservation,
        greaterThanOrEqualTo(8),
        reason: '无训练时以最近诊断为准（≈9 天）',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // B0-1：`_filterTrainingRecords` 不对称归一（活bug 止血）
  //
  // 缺陷：`training_input_builder.dart:407` 写的是
  //     effectiveSyndromeId(stored) == syndromeId      ← 右边没归一
  // 而同文件其余6 处（:73/:123/:388）+ `diagnosis_service:108/123` +
  // `message_injector:553/559` 全都是双边归一。
  //
  // 为什么会出事（2026-10-04 实测）：
  //   `kSyndromeMergeMap` 有 **33 个键同时是现行活跃 ID**（P001–P033）
  //   ⇒ `effectiveSyndromeId('P005') == 'P003'`
  //   ⇒ 拿「现行ID」查「现行ID」时，单边归一把 store侧改掉 → 不等 → 漏读。
  //   实测自匹配：**双边式 34/34 · 不对称式 1/34**。
  //
  // 之前为何没被抓住：本文件所有夹具都用 `'s1'`/`'s2'` 这类**假ID**，
  // 而 merge map 只含`P\d+`/`H\d+` ⇒ 假 ID 恒过 `?? id` 分支，
  // 对称与不对称**行为完全一致** ⇒ 缺陷对它不可见。
  // ⇒ 所以必须用**真ID**（P0xx）造夹具，本组用例才有鉴别力。
  // ═════════════════════════════════════════════════════════════

  group('B0-1 _filterTrainingRecords 归一对称性', () {
    // 真ID 造夹具：诊断与训练都用同一个现行 ID。
    Future<void> seedWithRealId(
      String sessionId, {
      required String syndromeId,
      String result = 'passed',
    }) async {
      await appendDiagnosis(
        sessionId,
        maxSeverity: 'L2',
        timestamp: 1000,
        syndromeId: syndromeId,
      );
      await appendDiagnosis(
        sessionId,
        maxSeverity: 'L1',
        timestamp: 2000,
        syndromeId: syndromeId,
      );
      await studentModelRepo.appendTeachingHistory(sessionId, {
        'type': 'training',
        'syndromeId': syndromeId,
        'result': result,
        'timestamp': 3000,
        'sessionId': sessionId,
      });
    }

    test('#B1 ★★★ 现行ID 查自己 →训练记录必须被数进来', () async {
      // 夹具ID 取 P005（句式节奏单一）。merge: P005 → P003，
      // 所以旧实现会把 store 侧 P005 归一成 P003，
      // 而 query侧仍是 P005 ⇒ 不等 ⇒ trainingCount = 0（本用例红）。
      const realId = 'P005';
      final sessionId = await seedSession();
      await seedWithRealId(sessionId, syndromeId: realId);

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        realId,
        const ActiveProblemMeta(currentSeverity: Severity.l1),
      );

      expect(input, isNotNull);
      expect(
        input!.minDataInput.trainingCount,
        1,
        reason:
            '库里存的是**现行** ID $realId（v46 迁移后存量行已被改写为现行 ID），'
            '查询也是现行 ID ⇒ 必须自匹配。若得到 0，说明单边归一把 store 侧'
            '改到了别的号码上⇒ 该症候的训练历史读不出来。',
      );
    });

    test('#B2 全34 个现行 ID 逐一自匹配（防止只修好一个）', () async {
      // 迭代**现行注册表全量**而不是抽样：实测 33/34 会被改写，
      // 若只断言单个 ID，修成「只对 P005 特判」也会绿。
      final broken = <String>[];
      for (final id in kSyndromeIds) {
        final sessionId = await seedSession();
        await seedWithRealId(sessionId, syndromeId: id);
        final input = await buildTrainingInputForActiveSyndrome(
          studentModelRepo,
          sessionId,
          id,
          const ActiveProblemMeta(currentSeverity: Severity.l1),
        );
        final cnt = input?.minDataInput.trainingCount ?? -1;
        if (cnt != 1) broken.add('$id→count=$cnt');
      }
      expect(
        broken,
        isEmpty,
        reason: '以下现行 ID 自匹配失败（漏读训练历史）：${broken.join(", ")}',
      );
    });

    test('#B3 跨症候串号（漏读之外的第二重后果）', () async {
      // ★ 2026-10-05（层 2 单轨收口批）：本用例的前置断言**已整体改写**。
      //
      //   归一时代的形态：断言 `effectiveSyndromeId(owner) == owner`
      //   （M1 语义「现行 ID 恒等」）。串号窗口 = `merge[stored] == query`
      //   恰好成立的那一对（owner=P005、victim=P003、merge[P005]=P003）
      //   ⇒ 查 P003 时，库里 P005 的记录被当成 P003 的历史。修前实测 count=1。
      //
      //   单轨下的形态：**没有 ID 变换函数了**（`effectiveSyndromeId`
      //   随 `kSyndromeMergeMap` 整张删除）⇒ 「恒等」不再是需要断言的性质：
      //   `a == a` 是恒真断言，零鉴别力。
      //
      //   ⚠️ 旧断言不是「无用」而是**测错了对象**。它守的是
      //      「归一函数不改动现行 ID」；单轨后真正可能出错的形态变成了
      //      **「两个在册 ID 指向同一实体」** —— 那样直比会在注册表层面
      //      就撞车，比归一时代的串号更早、更隐蔽。
      //      下面前置断言查的正是这个。
      const owner = 'P005'; // 句式节奏单一
      const victim = 'P003'; // 视角漂移
      // 单轨前置：两者都在册、且**不是同一个实体**
      expect(
        syndromeRecordOf(owner),
        isNotNull,
        reason: '单轨：$owner 必须在册（否则它不再是可用 ID）',
      );
      expect(
        syndromeRecordOf(victim),
        isNotNull,
        reason: '单轨：$victim 必须在册（否则它不再是可用 ID）',
      );
      expect(
        syndromeRecordOf(owner)!.name != syndromeRecordOf(victim)!.name,
        isTrue,
        reason: '两个不同 ID 必须指向不同实体（否则直比会在注册表层面撞车）',
      );

      final sessionId = await seedSession();
      // 库里只有 owner 的数据：2 条诊断 + 1 条训练。
      await seedWithRealId(sessionId, syndromeId: owner);

      // 查victim：诊断数不够 2 → 返回 null。先补victim 的诊断让它过阈值。
      // ★ 这两条诊断**不含任何训练记录** ⇒ 若最终 trainingCount > 0，
      //   那个数字只可能来自 owner 的记录被误认。
      for (final ts in [4000, 5000]) {
        await appendDiagnosis(
          sessionId,
          maxSeverity: 'L1',
          timestamp: ts,
          syndromeId: victim,
        );
      }

      final input = await buildTrainingInputForActiveSyndrome(
        studentModelRepo,
        sessionId,
        victim,
        const ActiveProblemMeta(currentSeverity: Severity.l1),
      );

      expect(input, isNotNull, reason: '诊断数 2 已过阈值，应返回非 null');
      expect(
        input!.minDataInput.trainingCount,
        0,
        reason:
            '库里只有 $owner（句式节奏单一）的训练记录，'
            '查 $victim（视角漂移）⇒ 必须 0。'
            '若 >0，说明单边归一把 $owner 归一成了 $victim，'
            '把别的症候的训练历史当成本症候的喂给了教练。',
      );
    });
  });
}
