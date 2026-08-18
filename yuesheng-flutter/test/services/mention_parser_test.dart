import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/services/mention_parser.dart';

AppDatabase _openMemory() => AppDatabase.forTesting(NativeDatabase.memory());

void main() {
  group('A-2 MentionParser 稳定 ID 标记', () {
    late AppDatabase db;
    late MentionParser parser;
    late String msId;
    late String chId;
    late String fileId;

    setUp(() async {
      db = _openMemory();
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final refRepo = ReferenceRepository(db);
      parser = MentionParser(msRepo, chRepo, refRepo);

      msId = await msRepo.createManuscript(title: '我的小说');
      chId = await chRepo.createChapter(msId, title: '第三章');
      final f = await refRepo.createAttachedFile(
        bookId: msId,
        fileName: '大纲.txt',
        content: '大纲内容',
      );
      fileId = f.id;
    });

    tearDown(() async {
      await db.close();
    });

    test('标记 @[chapter:ID] 解析为 ID 优先 + 实时标题', () async {
      final r = await parser.parseMentions('看看 @[chapter:$chId] 这段');
      expect(r.mentions.length, 1);
      final m = r.mentions.first;
      expect(m.refType, 'chapter');
      expect(m.refId, chId);
      expect(m.title, '我的小说 · 第三章'); // 改名免疫：标题由 ID 反查
      expect(m.manuscriptId, msId);
      expect(r.cleanedText.contains('@['), isFalse);
      expect(r.cleanedText.contains('看看'), isTrue);
      expect(r.cleanedText.contains('这段'), isTrue);
    });

    test('标记 @[manuscript:ID] 解析', () async {
      final r = await parser.parseMentions('参考 @[manuscript:$msId] 全书');
      expect(r.mentions.length, 1);
      final m = r.mentions.first;
      expect(m.refType, 'manuscript');
      expect(m.refId, msId);
      expect(m.title, '我的小说');
    });

    test('标记 @[file:ID] 解析', () async {
      final r = await parser.parseMentions('见 @[file:$fileId]');
      expect(r.mentions.length, 1);
      final m = r.mentions.first;
      expect(m.refType, 'file');
      expect(m.refId, fileId);
      expect(m.title, '【素材】大纲.txt');
    });

    test('legacy @标题 仍走前缀匹配兜底（向后兼容）', () async {
      final r = await parser.parseMentions('聊聊 @我的小说 的主题');
      expect(r.mentions.length, 1);
      final m = r.mentions.first;
      expect(m.refType, 'manuscript');
      expect(m.refId, msId); // 仍反查到正确 ID
    });

    test('目标被删的标记降级为字面文本（不丢消息、不崩）', () async {
      const dead = 'deadbeef-not-exist';
      final r = await parser.parseMentions('引用 @[chapter:$dead] 没了');
      expect(r.mentions.isEmpty, isTrue);
      // 标记原样保留在文本中，当作普通文本
      expect(r.cleanedText.contains('@[chapter:$dead]'), isTrue);
    });

    test('混合：legacy 标题 + 标记 共存解析', () async {
      final r = await parser.parseMentions('@我的小说 和 @[chapter:$chId]');
      expect(r.mentions.length, 2);
      expect(r.mentions.any((m) => m.refType == 'manuscript'), isTrue);
      expect(r.mentions.any((m) => m.refType == 'chapter' && m.refId == chId),
          isTrue);
    });

    test('非法 refType 标记降级为字面文本', () async {
      final r = await parser.parseMentions('@[bogus:$chId] 测试');
      expect(r.mentions.isEmpty, isTrue);
      expect(r.cleanedText.contains('@[bogus:'), isTrue);
    });
  });
}
