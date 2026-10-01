// ADR-C118 理论提案 P1 批3（SUGGEST-006/007/012/015/038/040/058/059/060/061）落地护栏
// 守卫：判断原则补判（006→P009+P026、007→P010+P019、012→P017+P020+P027、015→P025+P007）
//       + 新建边界纪律块（038→P009、040+059→P008、058→P028、060→P007、061→P027）
//       + 061-P020 侧并入批2b P020 边界纪律块尾，登记于症候手册数据层不被回退。
// 16 处断言 = 038/040/058/059/060 单段各 1；006/007/015/061 双段各 2；012 三段各 3。
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  group('theory-proposal-p1-b3-landing', () {
    test('SUGGEST-006 -> P009/P026 感叹四功能标注每轮', () {
      for (final id in ['P009', 'P026']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('感叹四功能标注每轮'));
      }
    });

    test('SUGGEST-038 -> P009 一律当引语标记', () {
      final c = getSyndromeContent(['P009']);
      expect(c, contains('一律当引语标记'));
    });

    test('SUGGEST-007 -> P010/P019 靠哪种勾人', () {
      for (final id in ['P010', 'P019']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('靠哪种勾人'));
      }
    });

    test('SUGGEST-012 -> P017/P020/P027 场景-概述交替失律', () {
      for (final id in ['P017', 'P020', 'P027']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('场景-概述交替失律'));
      }
    });

    test('SUGGEST-015 -> P025/P007 猜主角会怎么想', () {
      for (final id in ['P025', 'P007']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('猜主角会怎么想'));
      }
    });

    test('SUGGEST-040 -> P008 凭引号形态反推', () {
      final c = getSyndromeContent(['P008']);
      expect(c, contains('凭引号形态反推'));
    });

    test('SUGGEST-058 -> P028 目标没达成=失败=主角被动', () {
      final c = getSyndromeContent(['P028']);
      expect(c, contains('目标没达成=失败=主角被动'));
    });

    test('SUGGEST-059 -> P008 共享某心智', () {
      final c = getSyndromeContent(['P008']);
      expect(c, contains('共享某心智'));
    });

    test('SUGGEST-060 -> P007 挚友/死敌', () {
      final c = getSyndromeContent(['P007']);
      expect(c, contains('挚友/死敌'));
    });

    test('SUGGEST-061 -> P027/P020 直接判为作品更高级', () {
      for (final id in ['P027', 'P020']) {
        final c = getSyndromeContent([id]);
        expect(c, contains('直接判为作品更高级'));
      }
    });
  });
}
