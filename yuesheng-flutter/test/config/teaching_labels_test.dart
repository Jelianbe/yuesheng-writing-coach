// ─────────────────────────────────────────────────────────────
// R-027 L-UI 话术单一真源单元测试
//
// 锁定 config/teaching_labels.dart 三组标签 + §4-194 边界不变量：
//   · kSeverityLabels      L1/L2/L3 = 轻微/中等/严重
//   · kTeachingStateLabels 刚识别/训练中/趋稳中/已掌握
//   · kConfirmationBarText  五态齐全；★ disputed 不得含「不适用」，
//                          「不适用/不再提示」语义只归 dismissed
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/teaching_labels.dart';
import 'package:writingcoach/types/teaching_types.dart';

void main() {
  group('R-027 L-UI 话术单一真源', () {
    test('kSeverityLabels = 轻微/中等/严重，未知档兜底轻微', () {
      expect(kSeverityLabels['L1'], '轻微');
      expect(kSeverityLabels['L2'], '中等');
      expect(kSeverityLabels['L3'], '严重');

      expect(severityLabel('L1'), '轻微');
      expect(severityLabel('L2'), '中等');
      expect(severityLabel('L3'), '严重');
      expect(severityLabel(null), '轻微', reason: '未知档统一兜底轻微');
      expect(severityLabel('L9'), '轻微');
    });

    test('kTeachingStateLabels = 刚识别/训练中/趋稳中/已掌握', () {
      expect(kTeachingStateLabels[TeachingState.identified], '刚识别');
      expect(kTeachingStateLabels[TeachingState.inProgress], '训练中');
      expect(kTeachingStateLabels[TeachingState.consolidating], '趋稳中');
      expect(kTeachingStateLabels[TeachingState.mastered], '已掌握');
    });

    test('kConfirmationBarText 五态齐全', () {
      expect(kConfirmationBarText.keys.toSet(), {
        'pending',
        'confirmed',
        'partial',
        'disputed',
        'dismissed',
      });
    });

    test('§4-194 边界：disputed 不含「不适用」，dismissed 承接不再提示语义', () {
      final disputed = kConfirmationBarText['disputed']!;
      final dismissed = kConfirmationBarText['dismissed']!;

      // disputed = 仅「已记录异议」，绝不出现「不适用」。
      expect(disputed.first, '已记录异议');
      expect(
        disputed.every((s) => !s.contains('不适用')),
        isTrue,
        reason: 'disputed（异议）状态行+副提示都不得含「不适用」（§4-194）',
      );

      // dismissed = 永久静音/不适用 的唯一合法归属：关闭 + 不再提示 + 可恢复。
      expect(dismissed.first, '已关闭');
      expect(dismissed.last, contains('不再提示'));
      expect(dismissed.last, contains('成长页可恢复'));
    });
  });
}
