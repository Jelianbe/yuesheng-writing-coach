// ─────────────────────────────────────────────────────────────
// 批次 H：checkTeacherConsistency 一致性检查判定测试
//
// 此前 4 个引用文件（corpus_teacher_acceptance / pilot_llm_sim /
// teaching_loop_snapshot / live_interface_comparison）全部只有
// passed==true 正路径断言——「error 级才不通过」的通过判定
// （teacher_validator.dart:457-458）整个无判据锚定。
// 本文件按四条规则 + 汇总判定逐分支锚定：
//   NO_TASK_FOR_ENCOURAGE_DEFER（warning）/ TASK_REQUIRED_FOR_GUIDE_TRAIN
//   （error）/ NO_VERDICT_WORDS（error）/ NO_SYNDROME_ID_LEAK（error）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/teacher_validator.dart';

TrainingTask _task() {
  return const TrainingTask(
    targetSyndromeId: 'P003',
    targetDimension: 'pacing_control',
    taskType: 'rewrite',
    taskDescription: '重写这段',
    difficulty: 'medium',
    evaluationCriteria: ['节奏是否加快'],
  );
}

void main() {
  group('批次 H checkTeacherConsistency（通过判定 + 四规则）', () {
    test('#C1 仅 warn 级违规 → passed 仍为 true 且违规被记录', () {
      // encourage + 携带 trainingTask → NO_TASK_FOR_ENCOURAGE_DEFER（warning）
      final r = checkTeacherConsistency(
        TeacherResult(
          teachingDecision: 'encourage',
          teachingReason: 'r',
          naturalLanguage: '这段写得不错',
          trainingTask: _task(),
        ),
      );
      expect(r.passed, isTrue, reason: '仅 warning 不构成不通过');
      expect(r.violations, hasLength(1));
      expect(r.violations.single.rule, 'NO_TASK_FOR_ENCOURAGE_DEFER');
      expect(r.violations.single.severity, 'warning');
    });

    test('#C2 guide + 缺 trainingTask → error → passed false', () {
      final r = checkTeacherConsistency(
        const TeacherResult(
          teachingDecision: 'guide',
          teachingReason: 'r',
          naturalLanguage: '我们看看这段',
        ),
      );
      expect(r.passed, isFalse);
      expect(r.violations.single.rule, 'TASK_REQUIRED_FOR_GUIDE_TRAIN');
      expect(r.violations.single.severity, 'error');
    });

    test('#C3 natural_language 含判决词 → error → passed false', () {
      final r = checkTeacherConsistency(
        TeacherResult(
          teachingDecision: 'train',
          teachingReason: 'r',
          naturalLanguage: '你应该在这里加快节奏',
          trainingTask: _task(),
        ),
      );
      expect(r.passed, isFalse);
      expect(r.violations.single.rule, 'NO_VERDICT_WORDS');
      expect(r.violations.single.message, contains('应该'));
    });

    test('#C4 natural_language 泄漏症候 ID → error → passed false', () {
      final r = checkTeacherConsistency(
        TeacherResult(
          teachingDecision: 'train',
          teachingReason: 'r',
          naturalLanguage: '这里体现了 P003 的典型问题',
          trainingTask: _task(),
        ),
      );
      expect(r.passed, isFalse);
      expect(r.violations.single.rule, 'NO_SYNDROME_ID_LEAK');
    });

    test('#C5 零违规 → passed true + violations 空', () {
      final r = checkTeacherConsistency(
        TeacherResult(
          teachingDecision: 'train',
          teachingReason: 'r',
          naturalLanguage: '这段的处理可以再收紧一些',
          trainingTask: _task(),
        ),
      );
      expect(r.passed, isTrue);
      expect(r.violations, isEmpty);
    });

    test('#C6 warn 与 error 并存 → error 主导 passed false，warning 仍记录', () {
      // encourage + task（warning）+ 判决词（error）混合
      final r = checkTeacherConsistency(
        TeacherResult(
          teachingDecision: 'encourage',
          teachingReason: 'r',
          naturalLanguage: '你应该继续保持',
          trainingTask: _task(),
        ),
      );
      expect(r.passed, isFalse, reason: '任一 error 即不通过，warning 不豁免');
      expect(r.violations, hasLength(2));
      expect(
        r.violations.map((v) => v.rule),
        containsAll(['NO_TASK_FOR_ENCOURAGE_DEFER', 'NO_VERDICT_WORDS']),
      );
    });
  });
}
