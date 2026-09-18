// ─────────────────────────────────────────────────────────────
// chapter_orphan_cleanup_test — 删章清理章节级 KV（存量缺陷 B25 回归）
//
// 背景：`chapter_draft` / `chapter_versions` / `chapter_goal` 三键以
//   `<前缀>:<chapterId>` 落在 `app_state` 表。此前物理删章**不清**这三键
//   ⇒ 孤儿行永久残留（B25，出处
//   `docs/verify-B-series-prompt-audit-2026-08-18.md:16`）。
//
// 覆盖：
//   1. 硬删（purgeChapter）清三键
//   2. 只清被删章节：相邻章节三键不受影响
//   3. 软删（回收站）**不**清；恢复后版本仍可读回（回归守卫）
//   4. 键名契约（漂移绊线）
//   5. 源码级绊线：lib/ 内不得残留未登记的章节级键字面量
//      —— #4 只拦「键名漂移」，拦不住「新增第 4 个键却忘记登记」，
//         而后者才是 B25 的根因
// ─────────────────────────────────────────────────────────────

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/chapter_scoped_keys.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/services/error_handler.dart';

/// 章节级键字面量：`'<prefix>:$chapterId'` 或 `'<prefix>:${chapterId}'`。
final RegExp _chapterKeyLiteral = RegExp(r"'([a-z_]+):\$\{?chapterId\}?'");

/// 提取源码里命中 [_chapterKeyLiteral] 的全部 prefix。
Set<String> _prefixesIn(String source, RegExp pattern) => <String>{
  for (final m in pattern.allMatches(source)) m.group(1)!,
};

/// lib/ 下全部 `.dart` 文件。找不到 lib/ 时 `fail`（宁可红，也不静默跳过）。
List<File> _libDartFiles() {
  for (final root in <String>[p.join('lib'), p.join('..', 'lib')]) {
    final dir = Directory(root);
    if (dir.existsSync()) {
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
    }
  }
  fail('找不到 lib/ 目录（CWD=${Directory.current.path}）');
}

void main() {
  late AppDatabase db;
  late ChapterRepository chapterRepo;
  late AppStateRepository appStateRepo;
  late String manuscriptId;

  setUp(() async {
    ErrorHandler.instance.resetForTesting();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    chapterRepo = ChapterRepository(db);
    appStateRepo = AppStateRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await db.close();
  });

  /// 写入一章的全部章节级 KV（三键各一）。
  /// `chapter_goal` 无独立仓库方法（写入方是 WritingStore），直写键。
  Future<void> seedChapterKeys(String chapterId) async {
    await appStateRepo.saveChapterDraft(chapterId, '标题', '草稿正文');
    await appStateRepo.addChapterVersion(chapterId, '版本正文');
    await appStateRepo.setValue(chapterGoalKey(chapterId), '1200');
  }

  test('#1 硬删（purgeChapter）清除章节级全部 KV', () async {
    final c = await chapterRepo.createChapter(manuscriptId, title: '第一章');
    await seedChapterKeys(c);
    expect(await appStateRepo.getValue(chapterDraftKey(c)), isNotNull);
    expect(await appStateRepo.getValue(chapterVersionsKey(c)), isNotNull);
    expect(await appStateRepo.getValue(chapterGoalKey(c)), isNotNull);

    await chapterRepo.purgeChapter(c);

    expect(await appStateRepo.getValue(chapterDraftKey(c)), isNull);
    expect(await appStateRepo.getValue(chapterVersionsKey(c)), isNull);
    expect(await appStateRepo.getValue(chapterGoalKey(c)), isNull);
  });

  test('#2 只清被删章节：相邻章节的 KV 原样保留', () async {
    final a = await chapterRepo.createChapter(manuscriptId, title: '第一章');
    final b = await chapterRepo.createChapter(manuscriptId, title: '第二章');
    await seedChapterKeys(a);
    await seedChapterKeys(b);

    await chapterRepo.purgeChapter(a);

    expect(await appStateRepo.getValue(chapterDraftKey(a)), isNull);
    expect(await appStateRepo.getValue(chapterVersionsKey(a)), isNull);
    expect(await appStateRepo.getValue(chapterGoalKey(a)), isNull);
    expect(
      await appStateRepo.getValue(chapterDraftKey(b)),
      isNotNull,
      reason: '不得因前缀/集合误伤相邻章节',
    );
    expect(await appStateRepo.getValue(chapterVersionsKey(b)), isNotNull);
    expect(await appStateRepo.getValue(chapterGoalKey(b)), isNotNull);
  });

  test('#3 软删（回收站）不清 KV；恢复后版本仍可读回', () async {
    final c = await chapterRepo.createChapter(manuscriptId, title: '第一章');
    await seedChapterKeys(c);

    await chapterRepo.softDeleteChapter(c);

    expect(
      await appStateRepo.getValue(chapterDraftKey(c)),
      isNotNull,
      reason: '软删进回收站不得清草稿，否则恢复章节会丢草稿',
    );
    expect(
      await appStateRepo.getValue(chapterVersionsKey(c)),
      isNotNull,
      reason: '软删不得清版本快照，否则恢复后时光机为空',
    );
    expect(await appStateRepo.getValue(chapterGoalKey(c)), isNotNull);

    await chapterRepo.restoreChapter(c);

    final versions = await appStateRepo.listChapterVersions(c);
    expect(versions, hasLength(1));
    expect(versions.first.content, '版本正文');
  });

  test('#4 键名契约（漂移绊线）', () {
    // 写成字面量数组：将来改键名必须显式改这里，逼改动者考虑存量数据迁移。
    expect(chapterScopedKeys('c1'), <String>[
      'chapter_draft:c1',
      'chapter_versions:c1',
      'chapter_goal:c1',
    ]);
    expect(chapterDraftKey('c1'), 'chapter_draft:c1');
    expect(chapterVersionsKey('c1'), 'chapter_versions:c1');
    expect(chapterGoalKey('c1'), 'chapter_goal:c1');
  });

  test('#5 源码级绊线：lib/ 内不得有未登记的章节级键字面量', () {
    // ── 正则正例自检（缺这一步，正则写错就退化成「永远 0 命中 ⇒ 永远绿」）──
    // 本项目先例：`\blog\w*\s*\(` 的 `\b` 在 `_logSafeRun` 的 `_` 与 `l` 之间不成立，
    // 导致 20 个 `_logXxx` 私有函数被整体漏检、得出错误的「留痕率」结论。
    const String sample = r"final k = 'chapter_notes:$chapterId';";
    const String sampleBraced = r"final k = 'chapter_notes:${chapterId}';";
    expect(
      _prefixesIn(sample, _chapterKeyLiteral),
      contains('chapter_notes'),
      reason: r"正例自检 1：必须能匹配 '<prefix>:$chapterId'",
    );
    expect(
      _prefixesIn(sampleBraced, _chapterKeyLiteral),
      contains('chapter_notes'),
      reason: r"正例自检 2：必须能匹配 '<prefix>:${chapterId}'",
    );

    // ── 全集完整性：lib/ 内实际出现的 prefix ⊆ 已登记 prefix ──
    // ⚠️ 边界（如实写明）：当前 lib 内**字面量 0 命中**（写侧已全走构造器）
    //    ⇒ 这是**面向将来的绊线**，不是当下的证据；doc / 行内注释里的字面量
    //    同样会被计入（保守方向，宁可误报也不漏报）。
    final files = _libDartFiles();
    expect(
      files.length,
      greaterThan(100),
      reason: '扫描面自检：lib/ 下 .dart 文件数过少 ⇒ 路径算错，本用例会假绿',
    );

    // ★ 端到端正例：扫描器必须能从**真实源码文件**里读出 3 个已登记前缀。
    //   只测内存样例不够 —— 路径枚举 / 读文件任一环坏掉，都会退化成「0 命中 ⇒ 绿」。
    final selfSource = files
        .firstWhere(
          (f) => p.basename(f.path) == 'chapter_scoped_keys.dart',
          orElse: () => fail('lib/ 下找不到 chapter_scoped_keys.dart'),
        )
        .readAsStringSync();
    expect(
      _prefixesIn(selfSource, _chapterKeyLiteral),
      <String>{'chapter_draft', 'chapter_versions', 'chapter_goal'},
      reason: '端到端正例：真实源码扫描必须命中单点来源里的 3 个键',
    );

    final registered = chapterScopedKeys(
      'X',
    ).map((k) => k.substring(0, k.indexOf(':'))).toSet();
    final found = <String>{};
    for (final f in files) {
      if (p.basename(f.path) == 'chapter_scoped_keys.dart') continue; // 单点来源本身
      found.addAll(_prefixesIn(f.readAsStringSync(), _chapterKeyLiteral));
    }
    expect(
      found.difference(registered),
      isEmpty,
      reason:
          '发现未登记的章节级键 prefix ⇒ 删章时会漏清（B25 复发），'
          '请把它加进 chapterScopedKeys',
    );
  });
}
