// ─────────────────────────────────────────────────────────────
// volume_group_test — 批次89-2 章节按卷分组纯函数单测
//
// 覆盖：
//   1. 无卷 → 空分组（UI 走扁平列表）
//   2. 按卷分组 + 组内按 sort_order
//   3. 未分卷章节归入末尾「未分卷」组
//   4. 空卷展示（无章节的卷也有分组）
//   5. volumeId 指向已删卷的章节 → 按未分卷处理
//   6. 卷按 sort_order 排序展示
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/utils/volume_group.dart';

Volume _v(String id, {String title = '', int sortOrder = 0}) {
  return Volume(
    id: id,
    manuscriptId: 'm1',
    title: title,
    sortOrder: sortOrder,
    createdAt: 0,
    updatedAt: 0,
  );
}

Chapter _c(String id, {String? volumeId, int sortOrder = 0}) {
  return Chapter(
    id: id,
    manuscriptId: 'm1',
    volumeId: volumeId,
    title: '章节$id',
    content: '',
    previousContent: null,
    wordCount: 0,
    sortOrder: sortOrder,
    status: 'draft',
    lastDiagnosedAt: null,
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  test('#1 无卷 → 空分组（UI 走扁平列表）', () {
    final groups = groupChaptersByVolume(const [], [
      _c('c1', sortOrder: 0),
      _c('c2', sortOrder: 1),
    ]);
    expect(groups, isEmpty);
  });

  test('#2 按卷分组 + 组内按 sort_order', () {
    final groups = groupChaptersByVolume(
      [_v('v1', title: '第一卷')],
      [
        _c('c2', volumeId: 'v1', sortOrder: 2),
        _c('c1', volumeId: 'v1', sortOrder: 1),
      ],
    );
    expect(groups.length, 1);
    expect(groups[0].volume!.id, 'v1');
    expect(groups[0].chapters.map((c) => c.id).toList(), ['c1', 'c2']);
  });

  test('#3 未分卷章节归入末尾「未分卷」组', () {
    final groups = groupChaptersByVolume(
      [_v('v1', title: '第一卷'), _v('v2', title: '第二卷')],
      [
        _c('c1', volumeId: 'v1', sortOrder: 0),
        _c('c2', sortOrder: 1), // 未分卷
        _c('c3', volumeId: 'v2', sortOrder: 0),
      ],
    );
    expect(groups.length, 3);
    expect(groups[0].volume!.id, 'v1');
    expect(groups[1].volume!.id, 'v2');
    expect(groups[2].volume, isNull);
    expect(groups[2].chapters.map((c) => c.id).toList(), ['c2']);
  });

  test('#4 空卷展示（无章节的卷也有分组）', () {
    final groups = groupChaptersByVolume(
      [_v('v1', title: '空卷'), _v('v2', title: '有章卷')],
      [_c('c1', volumeId: 'v2')],
    );
    expect(groups.length, 2);
    expect(groups[0].chapters, isEmpty, reason: '空卷分组保留（UI 显示暂无章节）');
    expect(groups[1].chapters.length, 1);
  });

  test('#5 volumeId 指向已删卷的章节 → 按未分卷处理', () {
    final groups = groupChaptersByVolume(
      [_v('v1', title: '第一卷')],
      [
        _c('c1', volumeId: 'v1'),
        _c('c2', volumeId: 'ghost-v2'), // 脏数据：指向不存在的卷
      ],
    );
    expect(groups.length, 2);
    expect(groups[0].volume!.id, 'v1');
    expect(groups[1].volume, isNull);
    expect(groups[1].chapters.map((c) => c.id).toList(), ['c2']);
  });

  test('#6 卷按 sort_order 排序展示', () {
    final groups = groupChaptersByVolume([
      _v('v3', title: '第三卷', sortOrder: 3),
      _v('v1', title: '第一卷', sortOrder: 1),
    ], []);
    expect(groups.map((g) => g.volume!.id).toList(), ['v1', 'v3']);
  });

  // ── 批次96-4：buildChapterSections 平铺渲染段 ──
  group('buildChapterSections（批次96-4 平铺）', () {
    test('#S1 散落章节平铺 + 卷组按全局序自然穿插（用户示例）', () {
      final sections = buildChapterSections(
        [_v('v1', title: '第一卷'), _v('v2', title: '第二卷')],
        [
          _c('loose1', sortOrder: 0), // 第一章（散落）
          _c('loose2', sortOrder: 1), // 第二章（散落）
          _c('in1', volumeId: 'v1', sortOrder: 2), // 第一卷第一章
          _c('in2', volumeId: 'v2', sortOrder: 3), // 第二卷第一章
          _c('loose3', sortOrder: 4), // 第三章（散落）
        ],
      );
      expect(sections.length, 5);
      // 顺序：第一章 → 第二章 → 第一卷[第一章] → 第二卷[第一章] → 第三章
      expect(sections[0].looseChapter!.id, 'loose1');
      expect(sections[1].looseChapter!.id, 'loose2');
      expect(sections[2].volume!.id, 'v1');
      expect(sections[2].chapters.map((c) => c.id).toList(), ['in1']);
      expect(sections[3].volume!.id, 'v2');
      expect(sections[3].chapters.map((c) => c.id).toList(), ['in2']);
      expect(sections[4].looseChapter!.id, 'loose3');
    });

    test('#S2 卷内多章聚在卷头下，按 sort_order 排序', () {
      final sections = buildChapterSections(
        [_v('v1', title: '第一卷')],
        [
          _c('in2', volumeId: 'v1', sortOrder: 2),
          _c('loose', sortOrder: 0),
          _c('in1', volumeId: 'v1', sortOrder: 1),
        ],
      );
      // 全局序：loose(0) → in1(1) → in2(2)
      expect(sections.length, 2);
      expect(sections[0].looseChapter!.id, 'loose');
      expect(sections[1].volume!.id, 'v1');
      expect(sections[1].chapters.map((c) => c.id).toList(), ['in1', 'in2']);
    });

    test('#S3 空卷追尾（无章节的卷按卷序追加末尾）', () {
      final sections = buildChapterSections(
        [
          _v('v1', title: '空卷', sortOrder: 2),
          _v('v2', title: '有章卷', sortOrder: 1),
        ],
        [_c('in1', volumeId: 'v2', sortOrder: 0)],
      );
      expect(sections.length, 2);
      expect(sections[0].volume!.id, 'v2');
      expect(sections[1].volume!.id, 'v1');
      expect(sections[1].chapters, isEmpty);
    });

    test('#S4 指向已删卷的脏数据章节 → 按散落平铺', () {
      final sections = buildChapterSections(
        [_v('v1', title: '第一卷')],
        [_c('c1', volumeId: 'v1'), _c('c2', volumeId: 'ghost')],
      );
      expect(sections.length, 2);
      expect(sections[0].volume!.id, 'v1');
      expect(sections[1].looseChapter!.id, 'c2');
    });
  });
}
