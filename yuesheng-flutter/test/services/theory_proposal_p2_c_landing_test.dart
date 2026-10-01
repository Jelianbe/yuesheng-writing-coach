// ADR-C120 理论提案 P2 批C（SUGGEST-050/051/055/066/070/076）落地护栏
// 守卫：6 条豁免 A 档批判边界登记知识库数据层（syndrome 手册「边界纪律」列表 /
//       technique 技法「技法描述」段末 `- 边界：…`）。纯数据层，零注册表改动。
// 8 处断言 = 050×1(P005/P018 同文)；051×1(P003/P007/P023 同文)；
//           055×1(P013/P020)；066×2(P016 手册 + T029 技法)；
//           070×2(P016/P019 手册 + T029 技法)；076×1(P013/P015/P020)。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/technique_knowledge_base.dart';

void main() {
  group('theory-proposal-p2-c-landing', () {
    test('SUGGEST-050 -> P005/P018 前后文风距离大不得反推结构完整度', () {
      for (final id in ['P005', 'P018']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('前后文风距离大'));
      }
    });

    test('SUGGEST-051 -> P003/P007/P023 愿望/信念不入事实时间线', () {
      for (final id in ['P003', 'P007', 'P023']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('并入故事事实时间线'));
      }
    });

    test('SUGGEST-055 -> P013/P020 五维事件索引批判边界', () {
      for (final id in ['P013', 'P020']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('五维事件索引当成等权'));
      }
    });

    test('SUGGEST-066 -> P016 相邻章表面不连贯不自动判生硬', () {
      final c = getSyndromeContent(['P016']);
      expect(c, contains('主题重合低直接判为过渡生硬'));
    });

    test('SUGGEST-066 -> T029 四种合法替代排除流程边界', () {
      final c = getTechniqueContent(['T029']);
      expect(c, contains('（有意换线/跃迁/倒叙/支线回归）'));
    });

    test('SUGGEST-070 -> P016/P019 四轴类型不当断章/转场处方', () {
      for (final id in ['P016', 'P019']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('四轴类型当'));
      }
    });

    test('SUGGEST-070 -> T029 四轴只做事后审查已存在章界', () {
      final c = getTechniqueContent(['T029']);
      expect(c, contains('四轴（换事件/换焦点'));
    });

    test('SUGGEST-076 -> P013/P015/P020 每章单读合理≠跨章弧正确', () {
      for (final id in ['P013', 'P015', 'P020']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('每章单独读都合理'));
      }
    });
  });
}
