// ─────────────────────────────────────────────────────────────
// chat_context_builder_volume_test — 方案2b 卷引用注入
//
// 覆盖：
//   1. volume 引用 → 注入卷结构信息（卷名 + 章节清单），不注入正文
//   2. volumeResolver 未装配（null）→ 卷引用跳过，不注入
// ─────────────────────────────────────────────────────────────

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/chat_context_builder.dart';

ChapterBrief _chapter(String id, String title, int wordCount, int sortOrder) {
  return ChapterBrief(
    id: id,
    title: title,
    wordCount: wordCount,
    sortOrder: sortOrder,
    content: '正文内容，' * 20,
  );
}

void main() {
  group('buildReferencesContext 卷引用注入（方案2b）', () {
    VolumeDetail _volume() {
      return VolumeDetail(
        title: '第一卷',
        manuscriptTitle: '长篇',
        chapters: [
          _chapter('ch-1', '开篇', 1200, 1),
          _chapter('ch-2', '展开', 900, 2),
        ],
      );
    }

    ReferenceResolvers resolvers({VolumeDetail? Function(String)? vol}) {
      return ReferenceResolvers(
        fileResolver: (_) => null,
        chapterResolver: (_) => null,
        manuscriptResolver: (_) => null,
        volumeResolver: vol,
      );
    }

    ReferenceItem _volRef() {
      return ReferenceItem(
        refType: 'volume',
        refId: 'vol-1',
        title: '长篇 · 第一卷',
        isPrimary: 0,
        manuscriptId: 'ms-1',
        excerptRange: null,
      );
    }

    test('volume 引用 → 注入卷结构信息（卷名+章节清单，不含正文）', () {
      final ctx = buildReferencesContext([
        _volRef(),
      ], resolvers: resolvers(vol: (_) => _volume()));
      expect(ctx, contains('### 【次要引用】 卷：长篇 · 第一卷'));
      expect(ctx, contains('- 所属作品：长篇'));
      expect(ctx, contains('- 卷内章节数：2'));
      expect(ctx, contains('- 总字数：2100'));
      expect(ctx, contains('- 卷内章节：'));
      expect(ctx, contains('1. 开篇（1200字）'));
      expect(ctx, contains('2. 展开（900字）'));
      expect(ctx, contains('如需具体内容请引用对应章节'));
      // 2b 语义：不注入章节正文
      expect(ctx, isNot(contains('正文内容，')));
    });

    test('主引用 volume → 标记【主引用】', () {
      final ref = _volRef();
      final primary = ReferenceItem(
        refType: 'volume',
        refId: 'vol-1',
        title: '长篇 · 第一卷',
        isPrimary: 1,
        manuscriptId: 'ms-1',
        excerptRange: null,
      );
      final ctx = buildReferencesContext([
        primary,
      ], resolvers: resolvers(vol: (_) => _volume()));
      expect(ctx, contains('### 【主引用】 卷：长篇 · 第一卷'));
      expect(ref, isNotNull);
    });

    test('volumeResolver 未装配 → 卷引用跳过（不注入、不报错）', () {
      final ctx = buildReferencesContext([
        _volRef(),
      ], resolvers: resolvers(vol: null));
      expect(ctx, isNot(contains('卷：')));
      expect(ctx, isNot(contains('长篇')));
    });
  });
}
