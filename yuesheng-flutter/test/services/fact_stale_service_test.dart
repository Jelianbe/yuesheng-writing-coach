// ─────────────────────────────────────────────────────────────
// fact_stale_service_test — C78 批次2a「幽灵事实」治理单元测试
//
// 病根：character_fact / event_fact 的外键挂在 manuscript_id 而非章节上，
// 删章节对它们零连带影响 → 从被删章节抽出的断言变「幽灵」，继续参与
// F05 时序矛盾 / F07 因果链断裂检测，给用户报不存在的矛盾。
//
// 覆盖：
//   1. markChapterStale 并集判据三分支（只命中 hash / 只命中章号 / 存量不标）
//   2. 事件侧 stale（event_fact.stale 是 **int**，写 1 读 == 1）
//   3. markStaleEvents 不碰存量（chapterHash == null）
//   4. mergeAssertions 三元组规则 (a) 重新确认优先 / (b) 用户裁决优先
//   5. 四条删除路径各自触发 stale
//   6. deleteVolume 的 draft 过滤（决策5）
//   7. restoreChapter 不解除 stale（决策4）
//   8. clearStaleChapter 只删该章 stale，不动别的章
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

// drift 与 matcher 都导出 isNull，本文件要用 matcher 的版本（expect 用）
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';
import 'package:writingcoach/services/fact_stale_service.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late FactStaleService stale;
  late ChapterRepository chapterRepo;
  late VolumeRepository volumeRepo;
  late EventFactRepository eventRepo;
  late String manuscriptId;

  final hashA = chapterFingerprint('正文A');
  final hashB = chapterFingerprint('正文B');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    stale = FactStaleService(db);
    chapterRepo = ChapterRepository(db);
    volumeRepo = VolumeRepository(db);
    eventRepo = EventFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  CharacterAssertion assertion(
    String attribute,
    String value, {
    int? chapter,
    String? chapterHash,
    bool staleFlag = false,
    String status = 'confirmed',
    String source = 'ai',
    String? evidence,
    int timestamp = 1000,
  }) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      timestamp: timestamp,
      status: status,
      source: source,
      evidence: evidence,
      chapterHash: chapterHash,
      stale: staleFlag,
    );
  }

  /// 直接写 character_fact 行——断言 JSON 需要精确控制 chapterHash/stale，
  /// 走 upsertCharacter 会被合并逻辑改写。
  Future<void> seedCharacter(String name, List<CharacterAssertion> list) async {
    await db
        .into(db.characterFacts)
        .insert(
          CharacterFactsCompanion.insert(
            id: generateUuid(),
            manuscriptId: manuscriptId,
            name: name,
            assertions: Value(jsonEncode(list.map((a) => a.toJson()).toList())),
          ),
        );
  }

  Future<List<CharacterAssertion>> readAssertions(String name) async {
    final row =
        await (db.select(db.characterFacts)..where(
              (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
            ))
            .getSingleOrNull();
    return CharacterFactRepository.parseAssertions(row!.assertions);
  }

  Future<void> seedEvent(
    String name, {
    required int chapter,
    String? chapterHash,
    int staleValue = 0,
  }) async {
    await db
        .into(db.eventFacts)
        .insert(
          EventFactsCompanion.insert(
            id: generateUuid(),
            manuscriptId: manuscriptId,
            name: name,
            eventType: '决定',
            chapter: Value(chapter),
            chapterHash: Value(chapterHash),
            stale: Value(staleValue),
          ),
        );
  }

  Future<String> seedChapter({
    required int order,
    required String content,
    String? volumeId,
    String status = 'draft',
  }) async {
    final id = await chapterRepo.createChapter(
      manuscriptId,
      title: '第${order}章',
      content: content,
      sortOrder: order,
      volumeId: volumeId,
    );
    if (status != 'draft') {
      // 绕过 Repository 钩子直接改状态，避免污染「哪条路径触发了 stale」的判定
      await (db.update(db.chapters)..where((t) => t.id.equals(id))).write(
        ChaptersCompanion(status: Value(status)),
      );
    }
    return id;
  }

  group('markChapterStale 并集判据', () {
    test('#1 只命中 hash 支（AI 报错章号）→ 仍标 stale', () async {
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 99, chapterHash: hashA),
      ]);

      await stale.markChapterStale(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      final list = await readAssertions('阿禾');
      expect(list.length, 1);
      expect(list.first.stale, isTrue, reason: '章号 99 与删除章不符，但指纹命中');
    });

    test('#2 只命中章号支（指纹对不上）→ 标 stale', () async {
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3, chapterHash: 'deadbeef'),
      ]);

      await stale.markChapterStale(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      final list = await readAssertions('阿禾');
      expect(list.first.stale, isTrue, reason: '指纹不匹配，但章号命中删除章');
    });

    test('#3 决策2 防回归：跟本章无关的存量断言（无指纹、无章号）不标 stale', () async {
      await seedCharacter('阿禾', [
        assertion('性格', '冷静'), // chapterHash == null 且 chapter == null
      ]);

      await stale.markChapterStale(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      final list = await readAssertions('阿禾');
      expect(list.first.stale, isFalse);
    });

    test('#4 存量断言命中章号支 → 照标 stale（删除是权威事件）', () async {
      // 决策2 的「存量不标」豁免**只作用于重诊路径**（ADR §5.1）：重诊是系统
      // 自动跑的，误标会让用户一夜看到全部断言变灰；删除是用户明确发起的，
      // 该章事实就是幽灵，不按章号标就永远清不掉升级前的存量数据。
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3), // chapterHash == null
      ]);

      await stale.markChapterStale(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      final list = await readAssertions('阿禾');
      expect(list.first.stale, isTrue);
    });

    test('#5 别的作品的断言不受影响', () async {
      final other = await ManuscriptRepository(
        db,
      ).createManuscript(title: '另一篇');
      await db
          .into(db.characterFacts)
          .insert(
            CharacterFactsCompanion.insert(
              id: generateUuid(),
              manuscriptId: other,
              name: '阿禾',
              assertions: Value(
                jsonEncode([assertion('性格', '冷静', chapter: 3).toJson()]),
              ),
            ),
          );

      await stale.markChapterStale(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      final row = await (db.select(
        db.characterFacts,
      )..where((t) => t.manuscriptId.equals(other))).getSingleOrNull();
      final list = CharacterFactRepository.parseAssertions(row!.assertions);
      expect(list.first.stale, isFalse);
    });
  });

  group('事件侧 stale', () {
    test('#6 markChapterStale 把该章事件标 stale（int 1）', () async {
      await seedEvent('阿禾决定去金陵', chapter: 3, chapterHash: hashA);
      await seedEvent('阿青离家', chapter: 5, chapterHash: hashB);

      await stale.markChapterStale(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      final events = await eventRepo.listEvents(manuscriptId);
      final target = events.firstWhere((e) => e.name == '阿禾决定去金陵');
      final other = events.firstWhere((e) => e.name == '阿青离家');
      expect(target.stale, 1, reason: 'event_fact.stale 是 int，不是 bool');
      expect(other.stale, 0);
    });

    test('#7 决策2：markStaleEvents 不碰 chapterHash 为空的存量事件', () async {
      await seedEvent('存量事件', chapter: 3); // chapterHash == null
      await seedEvent('旧版事件', chapter: 3, chapterHash: 'deadbeef');
      await seedEvent('新版事件', chapter: 3, chapterHash: hashA);

      await stale.markStaleEvents(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      final events = await eventRepo.listEvents(manuscriptId);
      int staleOf(String name) =>
          events.firstWhere((e) => e.name == name).stale;
      expect(staleOf('存量事件'), 0, reason: '决策2：无指纹的存量事件不标');
      expect(staleOf('旧版事件'), 1);
      expect(staleOf('新版事件'), 0, reason: '本轮刚确认的事件不得自标');
    });
  });

  group('mergeAssertions 三元组合并', () {
    test('#8 (a) 三元组命中 → 新断言替换旧的，且旧的**不**标 stale', () async {
      final existing = [
        assertion(
          '性格',
          '冷静',
          chapter: 3,
          chapterHash: 'deadbeef',
          timestamp: 100,
        ),
      ];
      final incoming = [assertion('性格', '冷静', chapter: 3, timestamp: 200)];

      final merged = FactStaleService.mergeAssertions(
        existing,
        incoming,
        hashA,
        chapterNo: 3,
      );

      expect(merged.length, 1);
      expect(merged.first.timestamp, 200, reason: '新断言顶替旧的');
      expect(merged.first.stale, isFalse, reason: '规则(a)：重新确认不标 stale');
      expect(merged.first.chapterHash, hashA, reason: '规则(c)：incoming 填指纹');
    });

    test('#9 (b) 既有断言被用户拒绝 → 保留既有、丢弃 AI 新断言', () async {
      final existing = [
        assertion('性格', '冷静', chapter: 3, status: 'rejected', evidence: '旧证据'),
      ];
      final incoming = [assertion('性格', '冷静', chapter: 3, evidence: '新证据')];

      final merged = FactStaleService.mergeAssertions(
        existing,
        incoming,
        hashA,
        chapterNo: 3,
      );

      expect(merged.length, 1);
      expect(merged.first.evidence, '旧证据');
      expect(
        merged.first.status,
        'rejected',
        reason: 'R-009：AI 重复抽取不得复活用户已拒绝的断言',
      );
    });

    test("#10 (b') 既有断言是用户手写 → 保留既有、丢弃 AI 新断言", () async {
      final existing = [
        assertion('职业', '捕快', chapter: 3, source: 'user', evidence: '用户手写'),
      ];
      final incoming = [assertion('职业', '捕快', chapter: 3, evidence: 'AI 抽取')];

      final merged = FactStaleService.mergeAssertions(
        existing,
        incoming,
        hashA,
        chapterNo: 3,
      );

      expect(merged.length, 1);
      expect(merged.first.evidence, '用户手写');
      expect(merged.first.source, 'user', reason: 'AI 不得覆盖用户手写值');
    });

    test('#11 决策2：无指纹的既有断言即使章号命中也不标 stale', () async {
      final existing = [assertion('性格', '冷静', chapter: 3)];

      final merged = FactStaleService.mergeAssertions(
        existing,
        const [],
        hashA,
        chapterNo: 3,
      );

      expect(merged.length, 1);
      expect(merged.first.stale, isFalse, reason: '升级后首次重诊不得把全部存量断言一次性标灰');
    });

    test('#12 指纹过期的同章断言 → 标 stale', () async {
      final existing = [
        assertion('性格', '冷静', chapter: 3, chapterHash: 'deadbeef'),
      ];

      final merged = FactStaleService.mergeAssertions(
        existing,
        const [],
        hashA,
        chapterNo: 3,
      );

      expect(merged.first.stale, isTrue);
    });

    test('#13 防跨章误伤：别的章的断言不因本章重诊而标 stale', () async {
      final existing = [assertion('职业', '捕快', chapter: 5, chapterHash: hashB)];

      final merged = FactStaleService.mergeAssertions(
        existing,
        const [],
        hashA,
        chapterNo: 3,
      );

      expect(
        merged.first.stale,
        isFalse,
        reason: '第 5 章的断言哈希必然 != 第 3 章指纹，不按章号限定会全库误伤',
      );
    });

    test('#14 指纹或章号缺失 → 退化成批次3-D2 的纯三元组去重', () async {
      final existing = [assertion('性格', '冷静', chapter: 3, timestamp: 100)];
      final incoming = [assertion('性格', '冷静', chapter: 3, timestamp: 200)];

      final merged = FactStaleService.mergeAssertions(
        existing,
        incoming,
        null,
        chapterNo: 3,
      );

      expect(merged.length, 1);
      expect(merged.first.timestamp, 100, reason: '退化路径保留先出现者（历史断言）');
      expect(merged.first.chapterHash, isNull, reason: '退化路径不填指纹');
    });
  });

  group('删除路径钩子', () {
    test('#15 softDeleteChapter → 该章断言标 stale', () async {
      final chapterId = await seedChapter(order: 3, content: '正文A');
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3, chapterHash: hashA),
      ]);

      await chapterRepo.softDeleteChapter(chapterId);

      expect((await readAssertions('阿禾')).first.stale, isTrue);
    });

    test('#16 purgeChapter → 该章断言标 stale', () async {
      final chapterId = await seedChapter(order: 3, content: '正文A');
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3, chapterHash: hashA),
      ]);

      await chapterRepo.purgeChapter(chapterId);

      expect((await readAssertions('阿禾')).first.stale, isTrue);
      expect(await chapterRepo.getChapter(chapterId), isNull);
    });

    test('#17 deleteChapter → 该章断言标 stale', () async {
      final chapterId = await seedChapter(order: 3, content: '正文A');
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3, chapterHash: hashA),
      ]);

      await chapterRepo.deleteChapter(chapterId);

      expect((await readAssertions('阿禾')).first.stale, isTrue);
      expect(await chapterRepo.getChapter(chapterId), isNull);
    });

    test('#18 deleteVolume → 卷内 draft 章节的断言标 stale', () async {
      final volumeId = await volumeRepo.createVolume(manuscriptId);
      await seedChapter(order: 3, content: '正文A', volumeId: volumeId);
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3, chapterHash: hashA),
      ]);

      await volumeRepo.deleteVolume(volumeId);

      expect((await readAssertions('阿禾')).first.stale, isTrue);
    });

    test('#19 决策5（关键防错）：deleteVolume 只标 draft 章节，不动 archived', () async {
      final volumeId = await volumeRepo.createVolume(manuscriptId);
      // draft 章节（本次受影响）
      await seedChapter(order: 3, content: '正文A', volumeId: volumeId);
      // archived 章节（已在回收站，不在 deleteVolume 的 where 条件内）
      await seedChapter(
        order: 4,
        content: '正文B',
        volumeId: volumeId,
        status: 'archived',
      );
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3, chapterHash: hashA),
        assertion('职业', '捕快', chapter: 4, chapterHash: hashB),
      ]);

      await volumeRepo.deleteVolume(volumeId);

      final list = await readAssertions('阿禾');
      final byAttr = {for (final a in list) a.attribute: a};
      expect(byAttr['性格']!.stale, isTrue, reason: 'draft 章节被删 → 标 stale');
      expect(
        byAttr['职业']!.stale,
        isFalse,
        reason: 'archived 章节不在 deleteVolume 影响范围内，不得被多标',
      );
    });

    test('#20 决策4：restoreChapter 不自动解除 stale', () async {
      final chapterId = await seedChapter(order: 3, content: '正文A');
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3, chapterHash: hashA),
      ]);
      await chapterRepo.softDeleteChapter(chapterId);
      expect((await readAssertions('阿禾')).first.stale, isTrue);

      await chapterRepo.restoreChapter(chapterId);

      expect(
        (await readAssertions('阿禾')).first.stale,
        isTrue,
        reason: '从回收站恢复不自动解除 stale——UI 要如实标注「章节已改写」',
      );
    });
  });

  group('缺表降级（辅助动作不得阻断主流程）', () {
    test('#22 缺 character_fact/event_fact 表时，删除章节照常生效', () async {
      // 复刻真实风险：character_fact 是 **v16** 才建的表（database.dart:467），
      // 最小 schema 的存量库升级时 `if (from < 16)` 被跳过 → 两张表永远补不上。
      // 守卫缺失时 stale 钩子抛 no such table，softDeleteChapter 的 update
      // 根本执行不到 → 用户点「删除章节」却删不掉，属职责倒置。
      await db.customStatement('DROP TABLE IF EXISTS character_fact');
      await db.customStatement('DROP TABLE IF EXISTS event_fact');
      final chapterId = await seedChapter(order: 3, content: '正文A');

      await chapterRepo.softDeleteChapter(chapterId);

      expect(
        (await chapterRepo.getChapter(chapterId))!.status,
        'archived',
        reason: '缺表只降级「标 stale」这一步，不得阻断删除主流程',
      );
    });

    test('#23 缺表时 clearStaleChapter / markStaleEvents 静默无事可做', () async {
      await db.customStatement('DROP TABLE IF EXISTS character_fact');
      await db.customStatement('DROP TABLE IF EXISTS event_fact');

      await stale.clearStaleChapter(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );
      await stale.markStaleEvents(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      // 不抛异常即通过：缺表 = 无事可标，不是错误。
    });
  });

  group('clearStaleChapter', () {
    test('#21 只删该章 stale 断言与事件，不动别的章、不动未 stale 的', () async {
      await seedCharacter('阿禾', [
        assertion('性格', '冷静', chapter: 3, chapterHash: hashA, staleFlag: true),
        assertion('年龄', '十七', chapter: 3, chapterHash: hashA),
        assertion('职业', '捕快', chapter: 4, chapterHash: hashB, staleFlag: true),
      ]);
      await seedEvent('第3章旧事件', chapter: 3, chapterHash: hashA, staleValue: 1);
      await seedEvent('第3章新事件', chapter: 3, chapterHash: hashA);
      await seedEvent('第4章旧事件', chapter: 4, chapterHash: hashB, staleValue: 1);

      await stale.clearStaleChapter(
        manuscriptId: manuscriptId,
        chapterNo: 3,
        chapterHash: hashA,
      );

      final list = await readAssertions('阿禾');
      expect(
        list.map((a) => a.attribute).toList(),
        ['年龄', '职业'],
        reason: '删掉本章 stale 的「性格」，保留未 stale 的与别章的',
      );
      final events = await eventRepo.listEvents(manuscriptId);
      expect(events.map((e) => e.name).toList(), ['第3章新事件', '第4章旧事件']);
    });
  });
}
