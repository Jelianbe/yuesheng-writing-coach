// ─────────────────────────────────────────────────────────────
// teacher_validator_location_test — 批次63 B62d location_marks 校验
//
// 覆盖：
//   1. 合法字符串数组 → 解析进 TeacherResult.locationMarks
//   2. 缺失 → 默认空列表（向后兼容）
//   3. 非法类型（对象/数字/含非字符串元素）→ 静默忽略，不阻断整条建议
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/teacher_validator.dart';

Map<String, dynamic> _baseJson({Object? locationMarks = const ['第2段：他低声说道']}) {
  return {
    'teaching_decision': 'guide',
    'teaching_reason': '给出具体修改指引',
    'natural_language': '这里可以先肯定你的处理方式。',
    'location_marks': ?locationMarks,
    'training_task': {
      'target_syndrome_id': 'P003',
      'target_dimension': null,
      'task_type': 'rewrite',
      'task_description': '找出章节中 3 处情绪标签化表达，改写成动作与感官细节。',
      'difficulty': 'medium',
      'evaluation_criteria': ['避免直接使用情绪词'],
    },
  };
}

void main() {
  test('#1 合法字符串数组 → 解析进 TeacherResult.locationMarks', () {
    final result = validateTeacherOutput(_baseJson());
    expect(result.passed, true);
    expect(result.data, isNotNull);
    expect(result.data!.locationMarks, ['第2段：他低声说道']);
  });

  test('#2 多条位置 → 全部保留', () {
    final json = _baseJson(locationMarks: const ['第2段：他低声说道……', '第5段：她看着窗外……']);
    final result = validateTeacherOutput(json);
    expect(result.passed, true);
    expect(result.data!.locationMarks.length, 2);
  });

  test('#3 缺失 location_marks → 默认空列表（向后兼容）', () {
    final result = validateTeacherOutput(_baseJson(locationMarks: null));
    expect(result.passed, true);
    expect(result.data!.locationMarks, isEmpty);
  });

  test('#4 非法类型（对象）→ 静默忽略，不阻断整条建议', () {
    final result = validateTeacherOutput(
      _baseJson(locationMarks: {'第2段': '他低声说道'}),
    );
    expect(result.passed, true);
    expect(result.data!.locationMarks, isEmpty);
  });

  test('#5 含非字符串元素 → 静默忽略整字段', () {
    final result = validateTeacherOutput(
      _baseJson(locationMarks: const ['第2段：他低声说道', 123]),
    );
    expect(result.passed, true);
    expect(result.data!.locationMarks, isEmpty);
  });

  test('#6 空数组 → 空列表，不阻断', () {
    final result = validateTeacherOutput(_baseJson(locationMarks: const []));
    expect(result.passed, true);
    expect(result.data!.locationMarks, isEmpty);
  });
}
