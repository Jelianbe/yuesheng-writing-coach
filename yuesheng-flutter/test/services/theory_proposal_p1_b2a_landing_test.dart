// ADR-C118 理论提案 P1 批2a（SUGGEST-009/010/011/045/046/053/057/044/048/054）落地护栏
// 守卫：P016 三条诊断判据 + 六处新建「边界纪律」块登记于症候手册数据层不被回退。
// 14 处断言 = 6 单段（009/010/011/045/044/048）+ 4 双段×2（046/053/057/054）。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  group('theory-proposal-p1-b2a-landing', () {
    test('SUGGEST-009 -> P016 干净换线', () {
      final c = getSyndromeContent(['P016']);
      expect(c, contains('干净换线'));
    });

    test('SUGGEST-010 -> P016 合法大转场', () {
      final c = getSyndromeContent(['P016']);
      expect(c, contains('合法大转场'));
    });

    test('SUGGEST-011 -> P016 不笼统练“加过渡句”', () {
      final c = getSyndromeContent(['P016']);
      expect(c, contains('不笼统练“加过渡句”'));
    });

    test('SUGGEST-045 -> P016 前置或后置二选一', () {
      final c = getSyndromeContent(['P016']);
      expect(c, contains('前置或后置二选一'));
    });

    test('SUGGEST-046 -> P016/P023 默认设为 BEFORE', () {
      for (final id in ['P016', 'P023']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('默认设为 BEFORE'));
      }
    });

    test('SUGGEST-053 -> P016/P017 事件标注过细', () {
      for (final id in ['P016', 'P017']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('事件标注过细'));
      }
    });

    test('SUGGEST-057 -> P016/P017 一棵完整 RST 树覆盖', () {
      for (final id in ['P016', 'P017']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('一棵完整 RST 树覆盖'));
      }
    });

    test('SUGGEST-044 -> P022 就判节奏过快/过慢', () {
      final c = getSyndromeContent(['P022']);
      expect(c, contains('就判节奏过快/过慢'));
    });

    test('SUGGEST-048 -> P022 覆盖词数占比', () {
      final c = getSyndromeContent(['P022']);
      expect(c, contains('覆盖词数占比'));
    });

    test('SUGGEST-054 -> P011/P019 翻页速度/滚动长度/留白', () {
      for (final id in ['P011', 'P019']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('翻页速度/滚动长度/留白'));
      }
    });
  });
}
