// ─────────────────────────────────────────────────────────────
// edit_diff_test — 位置级 diff 纯函数（ADR-C132 批1 埋点地基）
//
// 覆盖：无变化 / 尾部修改 / 头部修改 / 中间修改 / 纯增 / 纯删 /
// 清空 / 首次写入 / 中段合并（多段分离修改合并为一段）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/edit_diff.dart';

void main() {
  group('locateTextDiff', () {
    test('无变化 → 空列表', () {
      expect(locateTextDiff('abc', 'abc'), isEmpty);
    });

    test('尾部修改：剥离公共前缀', () {
      final segs = locateTextDiff('他走了过去。', '他走了过去，又回头。');
      expect(segs, hasLength(1));
      expect(segs.first.start, 5);
      expect(segs.first.end, 9);
      expect(segs.first.before, '');
      expect(segs.first.after, '，又回头');
    });

    test('头部修改：剥离公共后缀', () {
      final segs = locateTextDiff('他走了过去。', '她走了过去。');
      expect(segs, hasLength(1));
      expect(segs.first.start, 0);
      expect(segs.first.end, 1);
      expect(segs.first.before, '他');
      expect(segs.first.after, '她');
    });

    test('中间修改：前后缀同时剥离', () {
      final segs = locateTextDiff('他慢慢走了过去。', '他飞快走了过去。');
      expect(segs, hasLength(1));
      expect(segs.first.start, 1);
      expect(segs.first.end, 3);
      expect(segs.first.before, '慢慢');
      expect(segs.first.after, '飞快');
    });

    test('纯增：before 为空（首次写入）→ 整段', () {
      final segs = locateTextDiff('', '第一章 出发');
      expect(segs, hasLength(1));
      expect(segs.first.start, 0);
      expect(segs.first.end, '第一章 出发'.length);
      expect(segs.first.before, '');
      expect(segs.first.after, '第一章 出发');
    });

    test('纯删：after 为空（清空）→ 整段 [0,0)', () {
      final segs = locateTextDiff('第一章 出发', '');
      expect(segs, hasLength(1));
      expect(segs.first.start, 0);
      expect(segs.first.end, 0);
      expect(segs.first.before, '第一章 出发');
      expect(segs.first.after, '');
    });

    test('多段分离修改合并为一段（中段近似，锚定命中不受影响）', () {
      final segs = locateTextDiff('他走在路上，天很蓝。', '她走在路上，天很灰。');
      expect(segs, hasLength(1));
      expect(segs.first.start, 0);
      expect(segs.first.end, 9);
      expect(segs.first.before, '他走在路上，天很蓝');
      expect(segs.first.after, '她走在路上，天很灰');
    });
  });
}
