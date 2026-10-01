// ADR-C117 理论提案 P0 批（SUGGEST-004/024/030/032/056）落地护栏
// 守卫：5 条提案的 KB 数据层登记（负面边界/训练资产）不被回退。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';

void main() {
  group('theory-proposal-p0-landing', () {
    test('SUGGEST-004 -> P006 相对规范 + 突出≠有效', () {
      final c = getSyndromeContent(['P006']);
      expect(c, contains('相对于该文自身的规范'));
      expect(c, contains('突出多 ≠ 更有效'));
    });

    test('SUGGEST-030 -> P005/P018 标点密度≠节奏', () {
      for (final id in ['P005', 'P018']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('标点/句读密度≠节奏'));
        expect(c, contains('禁止把任何标点一对一映射'));
      }
    });

    test('SUGGEST-032 -> P032 语气词不贴固定标签', () {
      final c = getSyndromeContent(['P032']);
      expect(c, contains('不得贴固定功能标签'));
      expect(c, contains('同形词'));
    });

    test('SUGGEST-024 -> A003 复盘五问', () {
      final c = getTrainingContent(['P004']);
      expect(c, contains('复盘五问'));
      expect(c, contains('自我调节'));
    });

    test('SUGGEST-056 -> A003 不得反推过程', () {
      final c = getTrainingContent(['P004']);
      expect(c, contains('禁止由学员成品文本反推'));
    });
  });
}
