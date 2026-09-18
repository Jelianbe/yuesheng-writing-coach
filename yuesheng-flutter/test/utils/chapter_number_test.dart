// ─────────────────────────────────────────────────────────────
// chapter_number_test — 章号口径纯函数（ADR-C95 · 批次 N12-F1 / N12-F3a）
//
// 本文件是 ADR-C95 §7 验收判据 1–3 的**直接**实现：
//   1. 正例：`sortOrder = 0` ⇒ 「第1章」（原缺陷：渲染成「第0章」）
//   2. 反例：**杀死 `sortOrder + 1` 兜底** —— 删过首章的稿里两者不相等
//   3. 反例：**杀死「非 null 即渲染」** —— 引用已删章 ⇒ 返回 null（调用方隐藏）
//
// `N12-F3a` 追加：`sortOrderAtPosition`（**写侧**归一 —— 用户能填的只有序位，库里存的是身份）。
//   反例 1：杀死「序位 == sortOrder」的朴素假设（删过首章的稿）；越界 ⇒ null，**禁**兜底成 0/+1。
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

  group('sortOrderAtPosition：序位(1 基) → sortOrder（写侧归一，N12-F3a）', () {
    test('#C95-9 正例：序位 → 该位置的 sortOrder，且与正向**互逆**', () {
      final map = buildChapterNoMap([chapter(0), chapter(5), chapter(9)]);

      expect(sortOrderAtPosition(map, 1), 0);
      expect(sortOrderAtPosition(map, 2), 5, reason: '序位 2 的章 sortOrder 是 5');
      expect(sortOrderAtPosition(map, 3), 9);
      // 互逆：正向(反向(p)) == p —— 正反两条路不可能分叉
      for (var p = 1; p <= 3; p++) {
        expect(displayChapterNo(map, sortOrderAtPosition(map, p)), p);
      }
    });

    test('#C95-10 负例：序位 <1 / 越界 / 空映射 ⇒ null（**禁**兜底成 0 或 `+1`）', () {
      final map = buildChapterNoMap([chapter(0), chapter(1)]);

      expect(sortOrderAtPosition(map, 0), isNull, reason: '序位从 1 起');
      expect(sortOrderAtPosition(map, -1), isNull);
      expect(sortOrderAtPosition(map, 3), isNull, reason: '只有 2 章');
      expect(sortOrderAtPosition(const {}, 1), isNull);
    });

    test('#C95-11 反例：删过首章的稿 —— 序位 1 是 sortOrder=1，**不是** 0', () {
      // 杀死「序位即 sortOrder」的朴素假设（ADR-C95 §3 反例 1：删除不重编号）。
      final map = buildChapterNoMap([chapter(1), chapter(2)]);

      expect(sortOrderAtPosition(map, 1), 1);
      expect(sortOrderAtPosition(map, 2), 2);
    });

    test('#C95-12 同序重复：与正向去重规则一致 —— 不可达序位返回 null', () {
      // 正向 putIfAbsent 取首次出现的序位 ⇒ 0→1、重复的 0 跳过、1→3
      final map = buildChapterNoMap([chapter(0), chapter(0), chapter(1)]);

      expect(map[0], 1);
      expect(map[1], 3);
      expect(
        sortOrderAtPosition(map, 2),
        isNull,
        reason: '序位 2 在去重后的映射里不存在 ⇒ 不得反查出某个章',
      );
      expect(sortOrderAtPosition(map, 1), 0);
      expect(sortOrderAtPosition(map, 3), 1);
    });
  });
}
