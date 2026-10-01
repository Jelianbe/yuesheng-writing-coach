// ADR-C118 理论提案 P1 批1（SUGGEST-031/033/034/036/037/041/047/049/084）落地护栏
// 守卫：9 条边界纪律条目登记于症候手册数据层（P003/P006/P018/P032）不被回退。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  group('theory-proposal-p1-b1-landing', () {
    test('SUGGEST-031 -> P018 多种合法句法分析', () {
      final c = getSyndromeContent(['P018']);
      expect(c, contains('多种合法句法分析'));
    });

    test('SUGGEST-033 -> P018 不是改写处方', () {
      final c = getSyndromeContent(['P018']);
      expect(c, contains('不是改写处方'));
    });

    test('SUGGEST-034 -> P032 语境可及性', () {
      final c = getSyndromeContent(['P032']);
      expect(c, contains('语境可及性'));
    });

    test('SUGGEST-036 -> P032 同形用法', () {
      final c = getSyndromeContent(['P032']);
      expect(c, contains('同形用法'));
    });

    test('SUGGEST-037 -> P006 语气词密度与口语度无线性关系', () {
      final c = getSyndromeContent(['P006']);
      expect(c, contains('语气词密度与口语度无线性关系'));
    });

    test('SUGGEST-041 -> P003 中心向前看', () {
      final c = getSyndromeContent(['P003']);
      expect(c, contains('中心向前看'));
    });

    test('SUGGEST-047 -> P006/P018 故事层的事件重复', () {
      for (final id in ['P006', 'P018']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('故事层的事件重复'));
      }
    });

    test('SUGGEST-049 -> P032 中文体标记功能不同', () {
      final c = getSyndromeContent(['P032']);
      expect(c, contains('中文体标记功能不同'));
    });

    test('SUGGEST-084 -> P003 角色不在场', () {
      final c = getSyndromeContent(['P003']);
      expect(c, contains('角色不在场'));
    });
  });
}
