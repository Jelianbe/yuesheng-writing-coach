// ─────────────────────────────────────────────────────────────
// chapter_version_guard_test — 版本快照「落库前体积护栏」行为断言
//
// 背景：`AppStateRepository._warnIfOverVersionBytes` 是本批第 3 件交付物的
//   **唯一行为**（单条快照即超 512KB 预算时：体积淘汰留 1 条 + warn 留痕 +
//   不阻断保存）。此前只有编译级验证 ⇒ 属「该交付物零行为证据」的假绿形态。
//
// 覆盖：
//   1. 前提自检：夹具确实越界（防将来调高阈值后本文件静默空过）
//   2. 淘汰语义：两条都超预算 ⇒ 只剩最后写入那条，且保存未被阻断
//   3. 留痕：恰一条 warn，字段齐全，且**不含正文**（R-029）
//
// ⚠️ 与既有 `chapter_orphan_cleanup_test` 一样：tearDown 必须再 resetForTesting
//   一次，否则全局单例挂着一个已 close 的 DB 会污染同进程其他用例。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/data/repositories/version_retention.dart';
import 'package:writingcoach/services/error_handler.dart';

void main() {
  late AppDatabase db;
  late ErrorLogRepository logRepo;

  const String chapterId = 'guard-chapter';
  // UTF-8 = 180000 × 3 = 540000 字节 > kMaxChapterVersionBytes(524288)
  final String big = '字' * 180000;

  setUp(() {
    ErrorHandler.instance.resetForTesting();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    logRepo = ErrorLogRepository(db);
    ErrorHandler.instance.attachRepository(logRepo);
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await db.close();
  });

  test('#1 前提自检：夹具确实越过体积预算', () {
    // 无此断言时，若将来有人调高 kMaxChapterVersionBytes，本文件会**静默全绿空过**。
    expect(chapterVersionBytes(big), 540000);
    expect(chapterVersionBytes(big), greaterThan(kMaxChapterVersionBytes));
  });

  test('#2 单条即超预算：淘汰到 1 条（最新永不淘汰）且不阻断保存', () async {
    final repo = AppStateRepository(db);
    await repo.addChapterVersion(chapterId, '${big}A');
    await repo.addChapterVersion(chapterId, '${big}B');

    // 能正常读回 = 保存未被护栏阻断
    final versions = await repo.listChapterVersions(chapterId);
    expect(versions, hasLength(1), reason: '两条均超预算 ⇒ 先写的被体积淘汰，只留最新 1 条');
    expect(versions.first.content, '${big}B', reason: '保留的是最后写入那条');
  });

  test('#3 护栏留痕：warn + 白名单字段 + 不含正文（R-029）', () async {
    await AppStateRepository(db).addChapterVersion(chapterId, big);

    await pumpEventQueue();
    final logs = await logRepo.queryErrorLogs();
    expect(logs, hasLength(1), reason: '仅一次超预算写入 ⇒ 恰一条留痕');
    final log = logs.single;
    expect(log.level, 'warn');
    expect(log.category, 'database');
    expect(log.message, '单章版本快照超体积预算');

    final ctx = log.context!;
    expect(ctx['repo'], 'app_state');
    expect(ctx['op'], 'addChapterVersion');
    expect(ctx['chapterId'], chapterId);
    expect(ctx['count'], 1);
    expect(ctx['limit'], kMaxChapterVersionBytes);
    expect(ctx['bytes'], greaterThan(kMaxChapterVersionBytes));
    expect(
      ctx['bytes'],
      chapterVersionBytes(big),
      reason: '恰为本次落库正文的 UTF-8 字节数',
    );

    expect(
      log.context.toString().contains(big.substring(0, 20)),
      isFalse,
      reason: 'R-029：留痕不得携带正文',
    );
  });
}
