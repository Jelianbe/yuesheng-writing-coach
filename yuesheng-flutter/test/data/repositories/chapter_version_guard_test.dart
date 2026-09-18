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
//   4. **第二道仓库接线守卫**：60 条同秒小快照 ⇒ 经接线后恰保留 10 条（硬编码）
//      —— 与 `writing_providers_test#82-3-3` 相互独立，让 M3/M5 类**接线**变异
//         两处同时变红，而不是只有单点守卫
//   5. 常量契约：仓库别名与叶子单一真源**未脱钩**
//
// ⚠️ 与既有 `chapter_orphan_cleanup_test` 一样：tearDown 必须再 resetForTesting
//   一次，否则全局单例挂着一个已 close 的 DB 会污染同进程其他用例。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_scoped_keys.dart';
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

  test('#4 第二道仓库接线守卫：60 条同秒小快照 ⇒ 恰保留 10 条（独立于 #82-3-3）', () async {
    // ⚠️ 用例定位（勿删、勿软化为 range 断言）：
    //   独立验证者实测：变异 M3（接线换回旧 `removeRange` 上限截断）与 M5
    //   （接线传 `recentFloor: 0`）时，**各只有 `writing_providers_test` 的
    //   `#82-3-3` 一条用例变红** ⇒ 纯函数测试守护不了仓库接线，接线侧只有单点守卫。
    //   将来有人为了改数字「顺手」调 `#82-3-3`，整条保留策略的接线就再无替代守卫。
    //   本用例是与 `#82-3-3` **相互独立**的第二道接线守卫，唯一目的即让这类
    //   **接线**变异两处同时变红。故此处**硬编码 10**（不引用 `kRecentKeepFloor`）
    //   —— 引用常量会让「改常量」这种漂移同时骗过两处。
    final repo = AppStateRepository(db);

    // 确定性造同秒 60 条：直写原始 JSON。
    // 不用「循环 60 次 addChapterVersion」的宽松手法 —— 那会跨秒 ⇒ flaky。
    // 每条正文 4 汉字 = 12 字节，60 条 ≈ 720 B ≪ 512 KB ⇒ 体积阶段不介入（隔离变量）。
    final int base = nowSec() - 100; // 与随后写入的 now 同落 'h0' 桶
    await repo.setValue(
      chapterVersionsKey(chapterId),
      jsonEncode(<Map<String, dynamic>>[
        for (var i = 0; i < 60; i++)
          <String, dynamic>{
            'savedAt': base,
            'wordCount': 4,
            'content': '旧版本$i',
          },
      ]),
    );

    await repo.addChapterVersion(chapterId, '最新版本');
    final versions = await repo.listChapterVersions(chapterId);

    expect(
      versions,
      hasLength(10),
      reason: '经**接线**后的保底条数（字面量 10）。M5（recentFloor: 0）时同桶只剩 1 条 ⇒ 必红',
    );
    expect(
      versions.map((v) => v.content).toList(),
      <String>[
        '最新版本',
        '旧版本0',
        '旧版本1',
        '旧版本2',
        '旧版本3',
        '旧版本4',
        '旧版本5',
        '旧版本6',
        '旧版本7',
        '旧版本8',
      ],
      reason: '顺序恒为新→旧、同秒按下标升序。M3（换回上限截断）时保留 40 条 ⇒ 必红',
    );
  });

  test('#5 常量契约：仓库别名与叶子单一真源未脱钩', () {
    // 能拦的失败模式：别名被写成**硬编码字面量**且与叶子不一致
    //（如 `static const int maxChapterVersions = 30;` 而叶子仍是 40）
    // ⇒ 「别名与单一真源脱钩」，此前无任何用例会红。
    // ⚠️ 拦不住「只改叶子常量」那一类漂移 —— 别名是 `= kMaxChapterVersions`，
    //    会自动跟随；那一类由 `version_retention_test.dart` 的常量契约组
    //    （`expect(kMaxChapterVersions, 40)`）拦截。两者互补，缺一不可。
    expect(AppStateRepository.maxChapterVersions, kMaxChapterVersions);
  });
}
