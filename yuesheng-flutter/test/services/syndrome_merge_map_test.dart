// ─────────────────────────────────────────────────────────────
// syndrome_merge_map_test — C126 幽灵键清理锁定测试
//
// kSyndromeMergeMap 曾残留 `'P034': 'P025'` 幽灵键：P034 本是现行症候
// （代词指代不清/零回指过载症），却被错吸进旧 P025。本测试锁定清理结果：
//   1. mergeMap 不再含 'P034' 键
//   2. mergeMap 不再含 'P025' 值（幽灵值彻底消失）
//   3. effectiveSyndromeId('P034') == 'P034'（P034 自聚，不再被改写）
//   4. syndromeNameOf('P034') == '代词指代不清/零回指过载症'（精确匹配优先）
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/syndrome_registry.dart';

void main() {
  group('C126 幽灵键清理（P034→P025 残留）', () {
    test('#1 kSyndromeMergeMap 不再含 P034 键', () {
      expect(
        kSyndromeMergeMap.containsKey('P034'),
        isFalse,
        reason: 'P034 是现行症候，不应作为 legacy 归一键',
      );
    });

    test('#2 kSyndromeMergeMap 不再含 P025 值', () {
      expect(
        kSyndromeMergeMap.containsValue('P025'),
        isFalse,
        reason: '幽灵值 P025 彻底消失（P025 自身仍是现行症候记录，只是不被任何 legacy 指向）',
      );
    });

    test('#3 effectiveSyndromeId(P034) == P034（P034 自聚）', () {
      expect(effectiveSyndromeId('P034'), 'P034');
    });

    test('#4 syndromeNameOf(P034) == 代词指代不清/零回指过载症', () {
      expect(
        syndromeNameOf('P034'),
        '代词指代不清/零回指过载症',
        reason: '精确匹配注册表优先，语义不随幽灵键删除而变',
      );
    });
  });
}
