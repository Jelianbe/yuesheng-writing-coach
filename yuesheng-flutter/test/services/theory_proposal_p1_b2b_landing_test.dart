// ADR-C118 理论提案 P1 批2b（SUGGEST-039/042/081/082/013/014/043/083）落地护栏
// 守卫：P020 新建边界纪律块（039/042/081/082-P020 侧）+ P019 块尾追加（082-P019 侧）
//       + P023 判断原则补判（013/014）+ P023 边界纪律块尾追加（043/083-P023 侧）
//       + P003 边界纪律块尾追加（083-P003 侧）登记于症候手册数据层不被回退。
// 10 处断言 = 6 单段（039/042/081/013/014/043）+ 2 双段×2（082/083）。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  group('theory-proposal-p1-b2b-landing', () {
    test('SUGGEST-039 -> P020 Given-New 分布', () {
      final c = getSyndromeContent(['P020']);
      expect(c, contains('Given-New 分布'));
    });

    test('SUGGEST-042 -> P020 拉近时态更有代入感', () {
      final c = getSyndromeContent(['P020']);
      expect(c, contains('拉近时态更有代入感'));
    });

    test('SUGGEST-081 -> P020 文学质量好/留存高/商业成功', () {
      final c = getSyndromeContent(['P020']);
      expect(c, contains('文学质量好/留存高/商业成功'));
    });

    test('SUGGEST-082 -> P020/P019 停留时长/翻页率/滑动轨迹/滚动深度', () {
      for (final id in ['P020', 'P019']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('停留时长/翻页率/滑动轨迹/滚动深度'));
      }
    });

    test('SUGGEST-013 -> P023 局部接缝矛盾', () {
      final c = getSyndromeContent(['P023']);
      expect(c, contains('局部接缝矛盾'));
    });

    test('SUGGEST-014 -> P023 闭包矛盾', () {
      final c = getSyndromeContent(['P023']);
      expect(c, contains('闭包矛盾'));
    });

    test('SUGGEST-043 -> P023 补全"一个唯一时间点', () {
      final c = getSyndromeContent(['P023']);
      expect(c, contains('补全"一个唯一时间点'));
    });

    test('SUGGEST-083 -> P003/P023 能在原文找到所指', () {
      for (final id in ['P003', 'P023']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('能在原文找到所指'));
      }
    });
  });
}
