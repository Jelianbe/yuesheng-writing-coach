// ─────────────────────────────────────────────────────────────
// chapter_number_test — 章号口径纯函数（ADR-C95 · 批次 N12-F1）
//
// 本文件是 ADR-C95 §7 验收判据 1–3 的**直接**实现：
//   1. 正例：`sortOrder = 0` ⇒ 「第1章」（原缺陷：渲染成「第0章」）
//   2. 反例：**杀死 `sortOrder + 1` 兜底** —— 删过首章的稿里两者不相等
//   3. 反例：**杀死「非 null 即渲染」** —— 引用已删章 ⇒ 返回 null（调用方隐藏）
//
// 口径与理由见 `docs/ADR-C95-chapter-number-convention.md`；实现 `lib/utils/chapter_number.dart`。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/utils/chapter_number.dart';

/// 构造一个只关心 `sortOrder` 的章节（其余字段与解析无关）。
Chapter chapter(int sortOrder) => Chapter(
  id: 'ch-$sortOrder',
  manuscriptId: 'ms-c95',
  title: '第${sortOrder + 1}章',
  content: '',
  wordCount: 0,
  sortOrder: sortOrder,
  status: 'draft',
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  group('buildChapterNoMap：sortOrder → 展示章号(1 基)', () {
    test('#C95-1 从 0 起的连续章 ⇒ 1,2,3（正例：首章是「第1章」不是「第0章」', () {
      final map = buildChapterNoMap([chapter(0), chapter(1), chapter(2)]);

      expect(map[0], 1, reason: '0 基首章的展示号必须是 1');
      expect(map[1], 2);
      expect(map[2], 3);
    });

    test('#C95-2 删过首章的稿（sortOrder 从 1 起）⇒ 1,2 —— 而非 2,3', () {
      // 这是 ADR-C95 §3 反例 1 的复现：删除不重编号。
      final map = buildChapterNoMap([chapter(1), chapter(2)]);

      expect(
        map[1],
        1,
        reason:
            '0 号章已删 ⇒ sortOrder=1 的章现在就是第 1 章；'
            '`sortOrder + 1` 会给出 2，是错的',
      );
      expect(map[2], 2, reason: '`sortOrder + 1` 会给出 3，是错的');
    });

    test('#C95-3 不连续的 sortOrder ⇒ 序位连续（身份值不参与展示号）', () {
      final map = buildChapterNoMap([chapter(0), chapter(5), chapter(9)]);

      expect(map[0], 1);
      expect(map[5], 2, reason: '展示号是序位，不是 sortOrder 的值');
      expect(map[9], 3);
    });

    test('#C95-4 空列表 ⇒ 空映射（不抛）', () {
      expect(buildChapterNoMap(const []), isEmpty);
    });
  });

  group('displayChapterNo / chapterLabel：解析失败必须返回 null', () {
    final map = buildChapterNoMap([chapter(0), chapter(1)]);

    test('#C95-5 命中 ⇒ 返回展示号与文案（正例）', () {
      expect(displayChapterNo(map, 1), 2);
      expect(chapterLabel(map, 1), '第2章');
    });

    test('#C95-6 引用已删章（sortOrder 不在列表中）⇒ null（负例：不编造数字）', () {
      // 这是 ADR-C95 §7 判据 3 的复现：原实现只判 `!= null` 就渲染。
      expect(displayChapterNo(map, 7), isNull);
      expect(chapterLabel(map, 7), isNull);
    });

    test('#C95-7 sortOrder 为 null ⇒ null（负例）', () {
      expect(displayChapterNo(map, null), isNull);
      expect(chapterLabel(map, null), isNull);
    });

    test('#C95-8 空映射 ⇒ 一律 null（负例）', () {
      expect(chapterLabel(const {}, 0), isNull);
    });
  });
}
