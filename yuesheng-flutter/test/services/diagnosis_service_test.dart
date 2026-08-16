// ─────────────────────────────────────────────────────────────
// diagnosis_service_test — DiagnosisService 单元测试
//
// 覆盖路径：
//   1. calculateEffectiveness：improved（L2→L1）/ worsened（L1→L3）
//   2. calculateEffectiveness：无变化 → null
//   3. calculateEffectiveness：同症候历史 <2 次 → null / 空症候 → null
//   4. commitDiagnosisWithHistory：effectiveness 写入 teaching_history
//   5. commitDiagnosisWithHistory：无变化不写 effectiveness 字段
//   6. commitDiagnosisWithHistory：teaching_mode 默认 socratic
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/diagnosis_service.dart';

void main() {
  late AppDatabase db;
  late SessionRepository sesRepo;
  late DiagnosisRepository diagRepo;
  late StudentModelRepository studentModelRepo;
  late DiagnosisService service;
  late String sessionId;
  var msgCounter = 0;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sesRepo = SessionRepository(db);
    diagRepo = DiagnosisRepository(db);
    studentModelRepo = StudentModelRepository(db);
    service = DiagnosisService(
      diagnosisRepo: diagRepo,
      studentModelRepo: studentModelRepo,
    );
    sessionId = await sesRepo.createBlankSession();
    msgCounter = 0;
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, dynamic> syndrome(String id, String severity) {
    return {
      'syndrome_id': id,
      'name': '症候$id',
      'severity': severity,
      'evidence': <String>['测试证据'],
      'explanation': '',
    };
  }

  DiagnosisInput input(List<Map<String, dynamic>> syndromes) {
    msgCounter++;
    return DiagnosisInput(
      sessionId: sessionId,
      messageId: 'msg-$msgCounter',
      syndromes: syndromes,
      suggestedActions: const [],
      confidence: 0.7,
    );
  }

  /// 拉大首条诊断的 timestamp（-100s），避免两轮诊断同 unix 秒
  /// 导致 getAllDiagnoses 排序不稳定（当前/上一次判定颠倒）
  Future<void> backdateFirstDiagnosis() async {
    await db.customStatement(
      'UPDATE diagnosis_results SET timestamp = timestamp - 100 WHERE session_id = ?',
      [sessionId],
    );
  }

  group('DiagnosisService.calculateEffectiveness', () {
    // calculateEffectiveness 在 commitDiagnosisWithHistory 内于当前诊断落库后调用，
    // 单测时需先 commit 当前输入（对齐 RN 调用链），getAllDiagnoses 才含本次记录。
    test('#1 同症候 L2→L1 → improved', () async {
      await diagRepo.commitDiagnosis(input([syndrome('P003', 'L2')]));
      await backdateFirstDiagnosis();

      final second = input([syndrome('P003', 'L1')]);
      await diagRepo.commitDiagnosis(second);
      final eff = await service.calculateEffectiveness(second);
      expect(eff, 'improved');
    });

    test('#2 同症候 L1→L3 → worsened', () async {
      await diagRepo.commitDiagnosis(input([syndrome('P003', 'L1')]));
      await backdateFirstDiagnosis();

      final second = input([syndrome('P003', 'L3')]);
      await diagRepo.commitDiagnosis(second);
      final eff = await service.calculateEffectiveness(second);
      expect(eff, 'worsened');
    });

    test('#3 同症候同严重度（L2→L2）→ null（不写 no_change）', () async {
      await diagRepo.commitDiagnosis(input([syndrome('P003', 'L2')]));

      final second = input([syndrome('P003', 'L2')]);
      await diagRepo.commitDiagnosis(second);
      final eff = await service.calculateEffectiveness(second);
      expect(eff, isNull);
    });

    test('#4 同症候历史仅 1 次（不足阈值 2）→ null', () async {
      // 无历史诊断，直接计算
      final eff = await service.calculateEffectiveness(
        input([syndrome('P003', 'L2')]),
      );
      expect(eff, isNull);
    });

    test('#5 空症候列表 → null', () async {
      final eff = await service.calculateEffectiveness(input([]));
      expect(eff, isNull);
    });

    test('#6 多症候：其中一症候改善 → improved', () async {
      await diagRepo.commitDiagnosis(
        input([syndrome('P003', 'L2'), syndrome('P007', 'L1')]),
      );
      await backdateFirstDiagnosis();

      // P003 L2→L1（改善），P007 L1→L2（加重但 P003 先命中）
      final second = input([syndrome('P003', 'L1'), syndrome('P007', 'L2')]);
      await diagRepo.commitDiagnosis(second);
      final eff = await service.calculateEffectiveness(second);
      expect(eff, 'improved');
    });
  });

  group('DiagnosisService.commitDiagnosisWithHistory', () {
    test('#7 effectiveness=improved 写入 teaching_history', () async {
      // 第一轮 L2（直接落库）
      await diagRepo.commitDiagnosis(input([syndrome('P003', 'L2')]));
      await backdateFirstDiagnosis();

      // 第二轮 L1 → improved
      await service.commitDiagnosisWithHistory(input([syndrome('P003', 'L1')]));

      final history = await studentModelRepo.getTeachingHistory(sessionId);
      final last = history.last;
      expect(last['type'], 'diagnosis');
      expect(last['effectiveness'], 'improved');
      expect(last['maxSeverity'], 'L1');
    });

    test('#8 无变化 → 不写 effectiveness 字段', () async {
      await diagRepo.commitDiagnosis(input([syndrome('P003', 'L2')]));

      await service.commitDiagnosisWithHistory(input([syndrome('P003', 'L2')]));

      final history = await studentModelRepo.getTeachingHistory(sessionId);
      final last = history.last;
      expect(last['type'], 'diagnosis');
      expect(last.containsKey('effectiveness'), isFalse);
    });

    test('#9 teaching_mode 默认 socratic', () async {
      await service.commitDiagnosisWithHistory(input([syndrome('P003', 'L2')]));

      final history = await studentModelRepo.getTeachingHistory(sessionId);
      final last = history.last;
      expect(last['teaching_mode'], 'socratic');
    });
  });
}
