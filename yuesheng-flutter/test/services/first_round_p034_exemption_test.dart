// A 包（T-20261028-06 · R-027 舰长批）：
// P034 五条「不判」进入短链首轮判据注入面。
//
// 牙口三处：
//   1) 清单确实在首轮块里（五条标号齐）；
//   2) 与手册逐字一致（复制漂移牙 —— 手册改了本块不跟 ⇒ 红）；
//   3) 用户关闭 P034 ⇒ 清单不注入（R-009），其余症候不受影响。

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/syndrome_knowledge_base.dart';

void main() {
  group('A 包 · P034 不判清单进短链首轮面', () {
    test('① 首轮块含标题与五条标号', () {
      final block = buildFirstRoundCriteriaBlock();
      expect(block, contains('P034（代词指代不清/零回指过载）不判清单：'));
      for (final mark in ['①', '②', '③', '④', '⑤']) {
        expect(block, contains(mark), reason: '缺第 $mark 条');
      }
    });

    test('② 不判清单与手册逐字一致（复制漂移牙）', () {
      final manual = getSyndromeCriteriaSections(const ['P034']);
      final line = manual.split('\n').firstWhere((l) => l.contains('以下不判指称过载'));
      expect(
        buildFirstRoundCriteriaBlock(),
        contains(line),
        reason: '首轮块里的清单行与手册原文不一致（复制已漂移）',
      );
    });

    test('③ 用户关闭 P034 ⇒ 不判清单不注入（R-009）', () {
      final block = buildFirstRoundCriteriaBlock(
        disabledSyndromeIds: const {'P034'},
      );
      expect(block, isNot(contains('以下不判指称过载')));
      expect(block, isNot(contains('P034（代词指代不清/零回指过载）不判清单')));
      expect(block, contains('P001'), reason: '其余三巨头应照常注入');
    });

    test('④ 四个首轮 ID 全禁 ⇒ 空串（ids.isEmpty 早退语义不变）', () {
      final block = buildFirstRoundCriteriaBlock(
        disabledSyndromeIds: const {'P001', 'P002', 'P003', 'P018'},
      );
      expect(block, isEmpty);
    });

    test('⑤ 关闭其他症候不影响 P034 不判清单', () {
      final block = buildFirstRoundCriteriaBlock(
        disabledSyndromeIds: const {'P001'},
      );
      expect(block, contains('以下不判指称过载'));
    });
  });
}
