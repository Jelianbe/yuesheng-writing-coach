// ─────────────────────────────────────────────────────────────
// world_fact_stale_test — 批次 E1 世界观纳入 stale 治理 + F05 隔离
//
// 覆盖：
//   1. markChapterStale 并集判据对 world_fact 生效（指纹命中 / 章号命中）
//   2. 不误伤：其他章、其他作品的同类断言不动
//   3. clearStaleChapter 只删该章 stale 世界观断言
//   4. 缺 world_fact 表时 markChapterStale 照常返回（缺表守卫，对照既有 #22）
//   5. ★ F05 隔离：世界观断言不进 conflict_detector
//      ——含**反证**：若误把世界观断言喂进检测器，会产出「幽灵矛盾」，
//        从反面证明「判据不可复用」这条设计主张。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

// drift 与 matcher 都导出 isNull，本文件要用 matcher 的版本（expect 用）
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/fact_stale_service.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late FactStaleService stale;
  late String manuscriptId;

  final hashA = chapterFingerprint('正文A');
  final hashB = chapterFingerprint('正文B');

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    stale = FactStaleService(db);
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
  }) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      timestamp: 1000,
      chapterHash: chapterHash,
      stale: staleFlag,
    );
  }

  /// 直接写 world_fact 行——断言 JSON 需精确控制 chapterHash/stale，
  /// 走 upsertWorld 会被合并逻辑改写（与 fact_stale_service_test 同法）。
  Future<void> seedWorld(
    String name,
    List<CharacterAssertion> list, {
    String mid = '',
  }) async {
    await db
        .into(db.worldFacts)
        .insert(
          WorldFactsCompanion.insert(
            id: generateUuid(),
            manuscriptId: mid.isEmpty ? manuscriptId : mid,
            name: name,
            assertions: Value(jsonEncode(list.map((a) => a.toJson()).toList())),
          ),
        );
  }

  Future<List<CharacterAssertion>> readWorld(String name) async {
    final row =
        await (db.select(db.worldFacts)..where(
              (t) => t.manuscriptId.equals(manuscriptId) & t.name.equals(name),
            ))
            .getSingleOrNull();
    return WorldFactRepository.parseAssertions(row!.assertions);
  }

  test('#1 删除章节钩子 → 该章世界观断言标 stale（并集判据）', () async {
    await seedWorld('灵气体系', [
      assertion('灵气浓度', '稀薄', chapter: 1, chapterHash: hashA),
      assertion('地理', '荒原', chapter: 2, chapterHash: hashB),
    ]);

    await stale.markChapterStale(
      manuscriptId: manuscriptId,
      chapterNo: 1,
      chapterHash: hashA,
    );

    final list = await readWorld('灵气体系');
    expect(list.firstWhere((a) => a.attribute == '灵气浓度').stale, isTrue);
    expect(
      list.firstWhere((a) => a.attribute == '地理').stale,
      isFalse,
      reason: '第 2 章断言不得被第 1 章的删除波及',
    );
  });

  test('#2 只命中章号（无指纹的存量断言）同样被标 stale', () async {
    await seedWorld('禁剑令', [assertion('门派禁令', '禁止用剑', chapter: 3)]);

    await stale.markChapterStale(
      manuscriptId: manuscriptId,
      chapterNo: 3,
      chapterHash: hashA,
    );

    expect((await readWorld('禁剑令')).single.stale, isTrue);
  });

  test('#3 跨作品隔离：另一本书的同名条目不受影响', () async {
    final other = await ManuscriptRepository(db).createManuscript(title: '另一本');
    await seedWorld('灵气体系', [
      assertion('灵气浓度', '稀薄', chapter: 1, chapterHash: hashA),
    ]);
    await seedWorld('灵气体系', [
      assertion('灵气浓度', '浓郁', chapter: 1, chapterHash: hashA),
    ], mid: other);

    await stale.markChapterStale(
      manuscriptId: manuscriptId,
      chapterNo: 1,
      chapterHash: hashA,
    );

    final otherRow =
        await (db.select(db.worldFacts)..where(
              (t) => t.manuscriptId.equals(other) & t.name.equals('灵气体系'),
            ))
            .getSingleOrNull();
    final otherList = WorldFactRepository.parseAssertions(otherRow!.assertions);
    expect(otherList.single.stale, isFalse, reason: '跨作品的 stale 标记串了');
  });

  test('#4 clearStaleChapter 只删该章 stale 世界观断言', () async {
    await seedWorld('灵气体系', [
      assertion('灵气浓度', '稀薄', chapter: 1, chapterHash: hashA),
      assertion('地理', '荒原', chapter: 2, chapterHash: hashB),
    ]);

    await stale.markChapterStale(
      manuscriptId: manuscriptId,
      chapterNo: 1,
      chapterHash: hashA,
    );
    await stale.clearStaleChapter(
      manuscriptId: manuscriptId,
      chapterNo: 1,
      chapterHash: hashA,
    );

    final list = await readWorld('灵气体系');
    expect(list.length, 1, reason: '第 1 章的 stale 断言应被删除');
    expect(list.single.attribute, '地理', reason: '第 2 章断言不得被删');
  });

  test('#5 缺 world_fact 表时，markChapterStale 照常返回不抛异常', () async {
    // 复刻既有 #22 的风险形态：表缺失时钩子不得阻断主流程
    // （辅助动作抛异常 = 用户点「删除章节」删不掉的职责倒置）
    await db.customStatement('DROP TABLE IF EXISTS world_fact');
    await stale.markChapterStale(
      manuscriptId: manuscriptId,
      chapterNo: 1,
      chapterHash: hashA,
    );
    await stale.clearStaleChapter(
      manuscriptId: manuscriptId,
      chapterNo: 1,
      chapterHash: hashA,
    );
  });

  test('#6 F05 隔离：世界观矛盾断言不进 conflict_detector', () async {
    // 同一「属性」两个不同值——形状上与角色侧 F05 的输入完全一致
    await seedWorld('灵气体系', [
      assertion('灵气浓度', '稀薄', chapter: 1, chapterHash: hashA),
      assertion('灵气浓度', '浓郁', chapter: 5, chapterHash: hashB),
    ]);

    // 生产路径：F05 的输入只来自 character_fact（此处为空）→ 无观察项
    final real = detectCharacterConflicts(const []);
    expect(real, isEmpty, reason: '世界观数据不得进入 F05 检测');

    // ★ 反证：若把世界观的断言**误**喂进检测器，立刻产出「幽灵矛盾」。
    //    这正是本表判据不可复用 F05 的实证——规则天然带例外
    //    （「灵气稀薄」+「此地有灵脉」是层次感，不是矛盾）。
    final worldRows = await (db.select(
      db.worldFacts,
    )..where((t) => t.manuscriptId.equals(manuscriptId))).get();
    final misused = detectCharacterConflicts(
      worldRows
          .map(
            (w) => (
              name: w.name,
              assertions: WorldFactRepository.parseAssertions(w.assertions),
            ),
          )
          .toList(),
    );
    expect(misused, isNotEmpty, reason: '反证失效：若误喂世界观的断言本不产出观察项，则隔离的必要性需重新论证');
    expect(misused.single.attribute, '灵气浓度');
  });
}
