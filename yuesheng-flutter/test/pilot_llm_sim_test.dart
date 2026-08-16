// ignore_for_file: avoid_print
// 试点：子代理模拟 LLM（读真实提示词）→ 产出协议回复 → 过真实解析/校验
// 验证「子代理模拟」方法可行：输出能被 app 真实 parser/validator 吃进，
// 且命中 ground truth（P006 L2 → train + rewrite），无任何硬约束违规。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/teacher_parser.dart';
import 'package:writingcoach/services/teacher_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

String _fix(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  test('pilot P006: 子代理模拟诊断/教学 LLM → 真实解析+一致性校验通过', () {
    final diagRaw = _fix('pilot_p006_diagnosis.txt');
    final teacherRaw = _fix('pilot_p006_teacher.txt');

    // ── 诊断层 ──
    final diag = parseDiagnosis(diagRaw);
    expect(diag.diagnosis, isNotNull, reason: '诊断块应被解析');
    final d = diag.diagnosis!;
    final hit = d.syndromes
        .where((s) => s.syndromeId == 'P006' && s.severity == Severity.l2)
        .toList();
    print('[诊断] 命中症候: '
        '${d.syndromes.map((s) => "${s.syndromeId}/${s.severity}").join(", ")}');
    print('[诊断] confidence=${d.confidence}  '
        'suggested_actions=${d.suggestedActions.length}');
    expect(hit, isNotEmpty, reason: '应命中 P006 L2（ground truth）');

    // ── 教学层 ──
    final tParse = parseTeacherDecision(teacherRaw);
    expect(tParse.teacher, isNotNull, reason: '教学块应被解析(schema 合法)');
    final t = tParse.teacher!;
    print('[教学] decision=${t.teachingDecision}');
    print('[教学] reason=${t.teachingReason}');
    print('[教学] natural_language=${t.naturalLanguage}');
    print('[教学] location_marks=${t.locationMarks}');
    final cons = checkTeacherConsistency(t);
    print('[教学] consistency.passed=${cons.passed}  '
        'violations=${cons.violations.map((v) => "${v.severity}:${v.rule}").join(", ")}');

    // 硬约束断言（教练不是评判器）
    expect(cons.passed, isTrue,
        reason: '一致性应通过：无判决词/无P0xx泄漏/guide-train必带task');
    expect(t.teachingDecision, equals('train'), reason: 'L2 症候 → train');
    expect(t.trainingTask, isNotNull, reason: 'train 必带 training_task');
    expect(t.trainingTask!.taskType, equals('rewrite'));
    expect(RegExp(r'P0\d{2}').hasMatch(t.naturalLanguage), isFalse,
        reason: 'natural_language 不得泄漏症候ID');
  });
}
