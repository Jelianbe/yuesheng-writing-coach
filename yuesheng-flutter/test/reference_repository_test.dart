// ─────────────────────────────────────────────────────────────
// ReferenceRepository 单元测试 — 附属文件 + 会话引用写入接口
// 使用内存数据库，验证 file-dao / reference-dao 复刻的正确性
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';

void main() {
  late AppDatabase db;
  late ManuscriptRepository msRepo;
  late ChapterRepository chRepo;
  late SessionRepository sessRepo;
  late ReferenceRepository refRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    msRepo = ManuscriptRepository(db);
    chRepo = ChapterRepository(db);
    sessRepo = SessionRepository(db);
    refRepo = ReferenceRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  // 辅助：创建稿件 + 会话
  Future<({String manuscriptId, String sessionId})>
  seedManuscriptAndSession() async {
    final msId = await msRepo.createManuscript(title: '测试稿件', genre: '小说');
    final sessId = await sessRepo.createBlankSession();
    return (manuscriptId: msId, sessionId: sessId);
  }

  // ════════════════════════════════════════════════════════════
  // 1. attached_files 写入
  // ════════════════════════════════════════════════════════════
  group('attached_files 写入', () {
    test('createAttachedFile 创建 + 查询单条', () async {
      final seed = await seedManuscriptAndSession();
      final file = await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '大纲.txt',
        fileRole: 'outline',
        content: '第一卷：开端\n第二卷：发展',
      );

      expect(file.id, isNotEmpty);
      expect(file.bookId, seed.manuscriptId);
      expect(file.fileName, '大纲.txt');
      expect(file.fileRole, 'outline');
      expect(file.mimeType, 'text/plain');
      expect(file.content, '第一卷：开端\n第二卷：发展');
      expect(file.byteSize, '第一卷：开端\n第二卷：发展'.length);

      final fetched = await refRepo.getAttachedFile(file.id);
      expect(fetched, isNotNull);
      expect(fetched!.fileName, '大纲.txt');
    });

    test(
      'createAttachedFile 默认值（fileRole=general, mimeType=text/plain）',
      () async {
        final seed = await seedManuscriptAndSession();
        final file = await refRepo.createAttachedFile(
          bookId: seed.manuscriptId,
          fileName: '笔记.txt',
          content: '一些笔记',
        );

        expect(file.fileRole, 'general');
        expect(file.mimeType, 'text/plain');
        expect(file.byteSize, 4); // "一些笔记".length
      },
    );

    test(
      'listAttachedFiles 列出书籍下所有文件（按 sort_order, created_at DESC）',
      () async {
        final seed = await seedManuscriptAndSession();
        await refRepo.createAttachedFile(
          bookId: seed.manuscriptId,
          fileName: '文件A',
          content: 'A',
        );
        await refRepo.createAttachedFile(
          bookId: seed.manuscriptId,
          fileName: '文件B',
          content: 'B',
          fileRole: 'material',
        );

        final list = await refRepo.listAttachedFiles(seed.manuscriptId);
        expect(list.length, 2);
      },
    );

    test('updateAttachedFile 更新名称/角色/内容（byte_size 同步刷新）', () async {
      final seed = await seedManuscriptAndSession();
      final file = await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '原名',
        content: '短',
      );
      expect(file.byteSize, 1);

      await refRepo.updateAttachedFile(
        file.id,
        fileName: '新名',
        fileRole: 'material',
        content: '这是更长的内容',
      );

      final updated = await refRepo.getAttachedFile(file.id);
      expect(updated!.fileName, '新名');
      expect(updated.fileRole, 'material');
      expect(updated.content, '这是更长的内容');
      expect(updated.byteSize, 7); // "这是更长的内容".length
    });

    test('updateAttachedFile 空参数 no-op', () async {
      final seed = await seedManuscriptAndSession();
      final file = await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '不变',
        content: '内容',
      );

      await refRepo.updateAttachedFile(file.id);

      final unchanged = await refRepo.getAttachedFile(file.id);
      expect(unchanged!.fileName, '不变');
      expect(unchanged.content, '内容');
    });

    test('deleteAttachedFile 删除后查询返回 null', () async {
      final seed = await seedManuscriptAndSession();
      final file = await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '待删',
        content: 'x',
      );

      await refRepo.deleteAttachedFile(file.id);

      final fetched = await refRepo.getAttachedFile(file.id);
      expect(fetched, isNull);
    });

    test('listAttachedFilesByRole 按角色过滤', () async {
      final seed = await seedManuscriptAndSession();
      await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '大纲',
        content: 'x',
        fileRole: 'outline',
      );
      await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '素材1',
        content: 'y',
        fileRole: 'material',
      );
      await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '素材2',
        content: 'z',
        fileRole: 'material',
      );

      final materials = await refRepo.listAttachedFilesByRole(
        seed.manuscriptId,
        'material',
      );
      expect(materials.length, 2);
      expect(materials.every((f) => f.fileRole == 'material'), isTrue);
    });

    test('getFileByOrder 按 sort_order 查询', () async {
      final seed = await seedManuscriptAndSession();
      // sortOrder 默认 0，新建文件都是 0
      final file = await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '第一个',
        content: 'x',
      );

      final found = await refRepo.getFileByOrder(seed.manuscriptId, 0);
      expect(found, isNotNull);
      expect(found!.id, file.id);

      final notFound = await refRepo.getFileByOrder(seed.manuscriptId, 99);
      expect(notFound, isNull);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 2. session_reference 写入
  // ════════════════════════════════════════════════════════════
  group('session_reference 写入', () {
    test('addReference 添加 manuscript 引用（非主引用）', () async {
      final seed = await seedManuscriptAndSession();
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
      );

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs.length, 1);
      expect(refs.first.refType, 'manuscript');
      expect(refs.first.refId, seed.manuscriptId);
      expect(refs.first.isPrimary, 0);
    });

    test('addReference 幂等（重复插入同一引用不报错）', () async {
      final seed = await seedManuscriptAndSession();
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
      );
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
      );

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs.length, 1);
    });

    test('addReference isPrimary=true 自动设为主引用 + 同步 sessions 缓存', () async {
      final seed = await seedManuscriptAndSession();
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
        isPrimary: true,
      );

      final primary = await refRepo.getPrimaryReference(seed.sessionId);
      expect(primary, isNotNull);
      expect(primary!.refType, 'manuscript');
      expect(primary.refId, seed.manuscriptId);

      // sessions.manuscript_id 应被同步
      final sessions = await sessRepo.listSessions();
      expect(sessions.first.manuscriptId, seed.manuscriptId);
    });

    test('addReference chapter 主引用自动回填 manuscript_id', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '第一章');

      await refRepo.addReference(
        seed.sessionId,
        'chapter',
        chId,
        isPrimary: true,
      );

      final sessions = await sessRepo.listSessions();
      expect(sessions.first.manuscriptId, seed.manuscriptId);
      expect(sessions.first.chapterId, chId);
    });

    test('setPrimaryReference 切换主引用（清掉旧的）', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '章A');

      // 先加 manuscript 主引用
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
        isPrimary: true,
      );
      // 再加 chapter 非主引用
      await refRepo.addReference(seed.sessionId, 'chapter', chId);

      // 切换主引用到 chapter
      await refRepo.setPrimaryReference(seed.sessionId, 'chapter', chId);

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      final chapterRef = refs.firstWhere((r) => r.refType == 'chapter');
      final manuscriptRef = refs.firstWhere((r) => r.refType == 'manuscript');
      expect(chapterRef.isPrimary, 1);
      expect(manuscriptRef.isPrimary, 0);

      // sessions 缓存应同步
      final sessions = await sessRepo.listSessions();
      expect(sessions.first.chapterId, chId);
      expect(sessions.first.manuscriptId, seed.manuscriptId);
    });

    test('setPrimaryReference file 类型抛出异常', () async {
      final seed = await seedManuscriptAndSession();

      expect(
        () => refRepo.setPrimaryReference(seed.sessionId, 'file', 'fake_id'),
        throwsArgumentError,
      );
    });

    test('批次7（D2）：addReference file 次引用写入成功（v21 CHECK 已扩）且不设主', () async {
      final seed = await seedManuscriptAndSession();
      final file = await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '人物设定.txt',
        content: '主角设定',
      );

      // v21 前 CHECK 拒绝 'file'，v21 后允许作次引用
      await refRepo.addReference(seed.sessionId, 'file', file.id);

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs.length, 1);
      expect(refs.first.refType, 'file');
      expect(refs.first.refId, file.id);
      expect(refs.first.isPrimary, 0, reason: 'file 仅作次引用，不可设主');
      expect(refs.first.title, contains('人物设定.txt'));
    });

    test('批次7（D2）：file 不占用自动设主名额（file+章节混合时章节设主）', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '第一章');
      final file = await refRepo.createAttachedFile(
        bookId: seed.manuscriptId,
        fileName: '素材.txt',
        content: '素材',
      );

      // 模拟 chat_page 发送顺序：先 @ 素材文件，后 @ 章节
      await refRepo.addReference(seed.sessionId, 'file', file.id);
      await refRepo.addReference(
        seed.sessionId,
        'chapter',
        chId,
        isPrimary: true,
      );

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      final fileRef = refs.firstWhere((r) => r.refType == 'file');
      final chapterRef = refs.firstWhere((r) => r.refType == 'chapter');
      expect(fileRef.isPrimary, 0);
      expect(chapterRef.isPrimary, 1, reason: '自动设主名额不被 file 占用');
    });

    test('removeReference 删除非主引用', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '章A');

      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
        isPrimary: true,
      );
      await refRepo.addReference(seed.sessionId, 'chapter', chId);

      await refRepo.removeReference(seed.sessionId, 'chapter', chId);

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs.length, 1);
      expect(refs.first.refType, 'manuscript');
    });

    test('removeReference 删除主引用时自动另选最早的一条', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '章A');

      // manuscript 为主引用
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
        isPrimary: true,
      );
      // chapter 为非主引用
      await refRepo.addReference(seed.sessionId, 'chapter', chId);

      // 删除主引用 manuscript
      await refRepo.removeReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
      );

      // chapter 应自动升级为主引用
      final primary = await refRepo.getPrimaryReference(seed.sessionId);
      expect(primary, isNotNull);
      expect(primary!.refType, 'chapter');
      expect(primary.refId, chId);

      // sessions 缓存应同步（chapter 主引用回填 manuscript_id）
      final sessions = await sessRepo.listSessions();
      expect(sessions.first.chapterId, chId);
      expect(sessions.first.manuscriptId, seed.manuscriptId);
    });

    test('removeReference 删除最后一条主引用时清空 sessions 缓存', () async {
      final seed = await seedManuscriptAndSession();
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
        isPrimary: true,
      );

      await refRepo.removeReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
      );

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs, isEmpty);

      final primary = await refRepo.getPrimaryReference(seed.sessionId);
      expect(primary, isNull);

      final sessions = await sessRepo.listSessions();
      expect(sessions.first.manuscriptId, isNull);
      expect(sessions.first.chapterId, isNull);
    });

    test('listSessionsReferencing 反向查询', () async {
      final seed = await seedManuscriptAndSession();
      final sess2 = await sessRepo.createBlankSession();

      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
      );
      await refRepo.addReference(sess2, 'manuscript', seed.manuscriptId);

      final referencing = await refRepo.listSessionsReferencing(
        'manuscript',
        seed.manuscriptId,
      );
      expect(referencing.length, 2);
      expect(referencing.every((s) => s.sessionId.isNotEmpty), isTrue);
    });

    test('getPrimaryReference 无主引用时返回 null', () async {
      final seed = await seedManuscriptAndSession();
      final primary = await refRepo.getPrimaryReference(seed.sessionId);
      expect(primary, isNull);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 3. listReferencesOfSession（UNION ALL 三表 JOIN）
  // P0 漏洞 5：核心查询方法完全未测
  // ════════════════════════════════════════════════════════════
  group('listReferencesOfSession', () {
    test('空会话返回空列表', () async {
      final seed = await seedManuscriptAndSession();
      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs, isEmpty);
    });

    test(
      'manuscript 引用：title 来自 manuscripts.title，manuscriptId 为 null',
      () async {
        final seed = await seedManuscriptAndSession();
        await refRepo.addReference(
          seed.sessionId,
          'manuscript',
          seed.manuscriptId,
        );

        final refs = await refRepo.listReferencesOfSession(seed.sessionId);
        expect(refs.length, 1);
        expect(refs.first.refType, 'manuscript');
        expect(refs.first.refId, seed.manuscriptId);
        expect(refs.first.title, '测试稿件'); // 来自 manuscripts.title
        expect(refs.first.manuscriptId, isNull); // manuscript 类型返回 NULL
        expect(refs.first.isPrimary, 0);
      },
    );

    test(
      'chapter 引用：title 来自 chapters.title，manuscriptId 来自 chapters.manuscript_id',
      () async {
        final seed = await seedManuscriptAndSession();
        final chId = await chRepo.createChapter(
          seed.manuscriptId,
          title: '第一章',
        );

        await refRepo.addReference(seed.sessionId, 'chapter', chId);

        final refs = await refRepo.listReferencesOfSession(seed.sessionId);
        expect(refs.length, 1);
        expect(refs.first.refType, 'chapter');
        expect(refs.first.refId, chId);
        expect(refs.first.title, '第一章'); // 来自 chapters.title
        expect(
          refs.first.manuscriptId,
          seed.manuscriptId,
        ); // 来自 chapters.manuscript_id
      },
    );

    test('混合引用 ORDER BY is_primary DESC（主引用排第一）', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '章节');

      // 先加 chapter（非主），再加 manuscript（主）
      await refRepo.addReference(seed.sessionId, 'chapter', chId);
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
        isPrimary: true,
      );

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs.length, 2);
      // 主引用应排第一
      expect(refs.first.isPrimary, 1);
      expect(refs.first.refType, 'manuscript');
      expect(refs.last.isPrimary, 0);
      expect(refs.last.refType, 'chapter');
    });

    test('chapter 主引用排第一（反向场景）', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '章节');

      // 先加 manuscript（非主），再加 chapter（主）
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
      );
      await refRepo.addReference(
        seed.sessionId,
        'chapter',
        chId,
        isPrimary: true,
      );

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs.length, 2);
      expect(refs.first.isPrimary, 1);
      expect(refs.first.refType, 'chapter');
      expect(refs.last.isPrimary, 0);
      expect(refs.last.refType, 'manuscript');
    });

    test('不存在的 sessionId 返回空列表', () async {
      final refs = await refRepo.listReferencesOfSession(
        'nonexistent-session-id',
      );
      expect(refs, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 4. updateExcerptRange（A-3 方案 Y：手动选段写入/清除）
  // ════════════════════════════════════════════════════════════
  group('updateExcerptRange（A-3 方案 Y）', () {
    test('写入段落锚点 → excerpt_range 为锚点 JSON', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '第一章');
      await refRepo.addReference(seed.sessionId, 'chapter', chId);

      final hit = await refRepo.updateExcerptRange(
        seed.sessionId,
        'chapter',
        chId,
        (chapterId: chId, startPara: 2, endPara: 5),
      );
      expect(hit, isTrue);

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(
        refs.first.excerptRange,
        '{"chapterId":"$chId","startPara":2,"endPara":5}',
      );
    });

    test('清除选段（anchor=null）→ excerpt_range 置空', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '第一章');
      await refRepo.addReference(
        seed.sessionId,
        'chapter',
        chId,
        excerptRange: (chapterId: chId, startPara: 1, endPara: 3),
      );

      final hit = await refRepo.updateExcerptRange(
        seed.sessionId,
        'chapter',
        chId,
        null,
      );
      expect(hit, isTrue);

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs.first.excerptRange, isNull);
    });

    test('会话无该引用 → 返回 false 且不写库', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '第一章');
      // 不 addReference，直接 update
      final hit = await refRepo.updateExcerptRange(
        seed.sessionId,
        'chapter',
        chId,
        (chapterId: chId, startPara: 0, endPara: 1),
      );
      expect(hit, isFalse);

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      expect(refs, isEmpty);
    });

    test('不影响 is_primary 与其它引用（仅更新目标行）', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '第一章');
      await refRepo.addReference(
        seed.sessionId,
        'chapter',
        chId,
        isPrimary: true,
      );
      await refRepo.addReference(
        seed.sessionId,
        'manuscript',
        seed.manuscriptId,
      );

      await refRepo.updateExcerptRange(seed.sessionId, 'chapter', chId, (
        chapterId: chId,
        startPara: 0,
        endPara: 0,
      ));

      final refs = await refRepo.listReferencesOfSession(seed.sessionId);
      final chapter = refs.firstWhere((r) => r.refType == 'chapter');
      final manuscript = refs.firstWhere((r) => r.refType == 'manuscript');
      expect(chapter.isPrimary, 1); // 主引用身份不变
      expect(chapter.excerptRange, isNotNull);
      expect(manuscript.excerptRange, isNull); // 其它引用不受影响
    });

    test('addReference 携带 excerptRange 的序列化与 updateExcerptRange 一致', () async {
      final seed = await seedManuscriptAndSession();
      final chId = await chRepo.createChapter(seed.manuscriptId, title: '章A');

      await refRepo.addReference(
        seed.sessionId,
        'chapter',
        chId,
        excerptRange: (chapterId: chId, startPara: 1, endPara: 2),
      );
      final viaAdd = (await refRepo.listReferencesOfSession(
        seed.sessionId,
      )).first.excerptRange;

      // 清除后经 updateExcerptRange 重新写入同一锚点
      await refRepo.updateExcerptRange(seed.sessionId, 'chapter', chId, null);
      await refRepo.updateExcerptRange(seed.sessionId, 'chapter', chId, (
        chapterId: chId,
        startPara: 1,
        endPara: 2,
      ));
      final viaUpdate = (await refRepo.listReferencesOfSession(
        seed.sessionId,
      )).first.excerptRange;

      expect(viaAdd, isNotNull);
      expect(viaAdd, viaUpdate); // 两条写入路径字节级一致
    });
  });
}
