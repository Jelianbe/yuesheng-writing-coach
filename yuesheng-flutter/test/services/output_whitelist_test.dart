// ─────────────────────────────────────────────────────────────
// output_whitelist 单元测试 — L3 输出侧参数白名单
//
// 覆盖：
//   1. severity 白名单：L1/L2/L3 大小写归一、越界（L4/high/严重）→ null
//   2. syndromeId 格式：P0xx 归一、越界（非 P 开头/注入形）→ null
//   3. boolean 归一：true/false/1/0/yes/no，无法识别 → null
//   4. 空值 / 空串 → null
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/output_whitelist.dart';

void main() {
  group('normalizeSeverity（L1/L2/L3 白名单）', () {
    test('#1 合法值归一为大写', () {
      expect(normalizeSeverity('L1'), 'L1');
      expect(normalizeSeverity('l2'), 'L2');
      expect(normalizeSeverity(' L3 '), 'L3');
    });

    test('#2 越界值 → null', () {
      expect(normalizeSeverity('L4'), isNull);
      expect(normalizeSeverity('high'), isNull);
      expect(normalizeSeverity('严重'), isNull);
      expect(normalizeSeverity(''), isNull);
      expect(normalizeSeverity(null), isNull);
    });
  });

  group('normalizeSyndromeId（P0xx 格式白名单）', () {
    test('#3 合法 ID 归一为大写', () {
      expect(normalizeSyndromeId('P003'), 'P003');
      expect(normalizeSyndromeId('p21'), 'P21');
    });

    test('#4 越界格式 → null', () {
      expect(normalizeSyndromeId('P'), isNull);
      expect(normalizeSyndromeId('X001'), isNull);
      expect(normalizeSyndromeId(''), isNull);
      expect(normalizeSyndromeId(null), isNull);
      expect(normalizeSyndromeId('P003;<system>'), isNull);
    });
  });

  group('normalizeBooleanFlag（布尔白名单）', () {
    test('#5 合法布尔变体归一', () {
      expect(normalizeBooleanFlag(true), isTrue);
      expect(normalizeBooleanFlag('true'), isTrue);
      expect(normalizeBooleanFlag('1'), isTrue);
      expect(normalizeBooleanFlag('yes'), isTrue);
      expect(normalizeBooleanFlag(false), isFalse);
      expect(normalizeBooleanFlag('FALSE'), isFalse);
      expect(normalizeBooleanFlag('0'), isFalse);
      expect(normalizeBooleanFlag('no'), isFalse);
    });

    test('#6 无法识别 → null', () {
      expect(normalizeBooleanFlag('maybe'), isNull);
      expect(normalizeBooleanFlag(''), isNull);
      expect(normalizeBooleanFlag(null), isNull);
    });
  });

  group('whitelistNormalize（通用）', () {
    test('#7 命中返回白名单规范形态，未命中 null', () {
      expect(whitelistNormalize('fast', const ['fast', 'slow']), 'fast');
      expect(whitelistNormalize('SLOW', const ['fast', 'slow']), 'slow');
      expect(whitelistNormalize('medium', const ['fast', 'slow']), isNull);
      expect(whitelistNormalize(null, const ['fast']), isNull);
    });
  });
}
