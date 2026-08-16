// ─────────────────────────────────────────────────────────────
// MentionParser 单元测试 — @ 引用语法解析
// 批次71：从编号格式（@W001/C003）改为文字标题格式（@作品标题/章节标题）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/services/mention_parser.dart';

void main() {
  late AppDatabase db;
  late MentionParser parser;
  late ManuscriptRepository msRepo;
  late ChapterRepository chRepo;
  late ReferenceRepository refRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    msRepo = ManuscriptRepository(db);
    chRepo = ChapterRepository(db);
    refRepo = ReferenceRepository(db);
    parser = MentionParser(msRepo, chRepo, refRepo);
  });

  tearDown(() async => db.close());

  // ════════════════════════════════════════════════════════════
  // 1. buildMentionPath
  // ════════════════════════════════════════════════════════════
  group('buildMentionPath', () {
    test('作品/章节/素材路径生成', () {
      expect(buildMentionPath('我的小说'), '@我的小说');
      expect(buildMentionPath('我的小说', subTitle: '第三章'), '@我的小说/第三章');
      expect(buildMentionPath('我的小说', subTitle: '大纲.txt'), '@我的小说/大纲.txt');
    });
  });

  // ════════════════════════════════════════════════════════════
  // 2. parseMentions
  // ════════════════════════════════════════════════════════════
  group('parseMentions', () {
    Future<void> seed() async {
      await msRepo.createManuscript(
        title: '书一',
        genre: '小说',
        sortOrder: 0,
      );
      await msRepo.createManuscript(
        title: '书二',
        genre: '小说',
        sortOrder: 1,
      );
    }

    test('@书一 → 解析为标题匹配的作品', () async {
      await seed();
      final first = (await msRepo.listManuscripts()).first;
      final result = await parser.parseMentions('请分析一下 @书一 的开头');

      expect(result.mentions, hasLength(1));
      expect(result.mentions.single.refType, 'manuscript');
      expect(result.mentions.single.refId, first.id);
      expect(result.mentions.single.title, '书一');
      expect(result.cleanedText, '请分析一下  的开头');
    });

    test('@书二/第一章 → 标题匹配作品+章节', () async {
      await seed();
      final second = (await msRepo.listManuscripts())[1];
      final ch = await chRepo.createChapter(
        second.id,
        title: '第一章',
        content: '内容',
        sortOrder: 0,
      );

      final result = await parser.parseMentions('看下 @书二/第一章 这段');

      expect(result.mentions, hasLength(1));
      expect(result.mentions.single.refType, 'chapter');
      expect(result.mentions.single.refId, ch);
      expect(result.mentions.single.title, '书二 · 第一章');
      expect(result.cleanedText, '看下  这段');
    });

    test('@书一/大纲.txt → 标题匹配作品+素材文件', () async {
      await seed();
      final first = (await msRepo.listManuscripts()).first;
      final file = await refRepo.createAttachedFile(
        bookId: first.id,
        fileName: '大纲.txt',
        fileRole: 'outline',
        content: '大纲内容',
      );

      final result = await parser.parseMentions('引用 @书一/大纲.txt 的大纲');

      expect(result.mentions, hasLength(1));
      expect(result.mentions.single.refType, 'file');
      expect(result.mentions.single.refId, file.id);
      expect(result.mentions.single.title, '【素材】大纲.txt');
      expect(result.cleanedText, '引用  的大纲');
    });

    test('无效引用（标题不匹配）→ 不解析且文本保留', () async {
      await seed();
      final result = await parser.parseMentions('没有 @不存在的书 这个作品');

      expect(result.mentions, isEmpty);
      expect(result.cleanedText, '没有 @不存在的书 这个作品');
    });

    test('多个引用同时解析', () async {
      await seed();
      final result = await parser.parseMentions('对比 @书一 与 @书二');

      expect(result.mentions, hasLength(2));
      expect(result.mentions[0].title, '书一');
      expect(result.mentions[1].title, '书二');
      expect(result.cleanedText, '对比  与');
    });

    test('标题前缀冲突：书一 vs 书一二 → 长度降序匹配', () async {
      await msRepo.createManuscript(
        title: '书一',
        genre: '小说',
        sortOrder: 0,
      );
      await msRepo.createManuscript(
        title: '书一二',
        genre: '小说',
        sortOrder: 1,
      );

      // @书一二 应匹配到 "书一二" 而非 "书一"
      final result = await parser.parseMentions('看 @书一二 的内容');
      expect(result.mentions, hasLength(1));
      expect(result.mentions.single.title, '书一二');
    });

    test('边界检查：@书一开始 不应匹配到 "书一"', () async {
      await seed();
      final result = await parser.parseMentions('关于@书一开始的剧情');

      expect(result.mentions, isEmpty);
      expect(result.cleanedText, '关于@书一开始的剧情');
    });
  });
}
