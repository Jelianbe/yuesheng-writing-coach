// ADR-C120 理论提案 P2 批B（SUGGEST-063/064/065/067）落地护栏
// 守卫：4 条豁免 A 档批判边界登记知识库数据层（syndrome 手册「边界纪律」列表 /
//       technique 技法「技法描述」段末 `- 边界：…`）。纯数据层，零注册表改动。
// 6 处断言 = 063×1(P010 新建/P013 追加 同文)；064×1(P007/P028/P015 同文) + T009 技法；
//           065×1(P028/P029 新建/P007 同文)；067×1(P013/P022/P011/P012 同文) + T027 技法。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';

void main() {
  group('theory-proposal-p2-b-landing', () {
    test('SUGGEST-063 -> P010/P013 未声明定义不得直接贴"转折"标签', () {
      for (final id in ['P010', 'P013']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('直接贴"转折"标签'));
      }
    });

    test('SUGGEST-064 -> P007/P028/P015 不得把"主角没做成"合并判为"目标没达成"', () {
      for (final id in ['P007', 'P028', 'P015']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('合并判为一句"目标没达成"'));
      }
    });

    test('SUGGEST-064 -> T009 三值不得合并（长篇人物弧未验证）', () {
      final c = getTechniqueContent(['T009']);
      expect(c, contains('三值不得合并'));
    });

    test('SUGGEST-065 -> P028/P029/P007 人物相信的因果≠故事世界因果', () {
      for (final id in ['P028', 'P029', 'P007']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('把人物相信的因果（would_cause）写成故事世界成立的因果'));
      }
    });

    test('SUGGEST-067 -> P013/P022/P011/P012 不得引用 Hauge 百分位/五角色模板做诊断', () {
      for (final id in ['P013', 'P022', 'P011', 'P012']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('等 Hauge 百分位/五角色模板做结构诊断'));
      }
    });

    test('SUGGEST-067 -> T027 数字绑定 99 部英语电影、对网文不适用', () {
      final c = getTechniqueContent(['T027']);
      expect(c, contains('绑定 99 部英语电影'));
    });
  });
}
