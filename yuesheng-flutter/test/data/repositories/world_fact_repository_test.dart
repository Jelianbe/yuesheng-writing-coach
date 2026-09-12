// ─────────────────────────────────────────────────────────────
// world_fact_repository_test — 批次 E1 世界观设定仓储单元测试
//
// 覆盖：
//   1. upsert 新条目 → list/get 往返
//   2. 重复 upsert → 断言增量合并（UNIQUE(manuscript_id, name) + 三元组去重）
//   3. 断言 JSON 往返保真（status / source / chapterHash / stale 一个不丢）
//   4. parseAssertions 非法 JSON / 脏条目 → 保守跳过
//   5. listWorlds 默认排除 archived；includeArchived:true 可回溯
//   6. 跨作品隔离（同主题名在另一本书是另一行）
//   7. ★ 白拿验证：带 chapterHash/chapterNo 重诊 → 旧指纹同章断言标 stale
//   8. ★ 白拿验证：用户手写断言（source='user'）不被 AI 同三元组断言覆写
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
// 只取 Value：drift 整体导入会带进 isNull / isNotNull，与 matcher 撞名
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late WorldFactRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = WorldFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  test('#1 upsert 新条目 → list/get 往返', () async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      firstSeenChapter: 1,
      firstSeenAt: 1000,
      assertions: [
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '稀薄',
          chapter: 1,
          timestamp: 1000,
        ),
      ],
    );

    final list = await repo.listWorlds(manuscriptId);
    expect(list.length, 1);
    expect(list.first.name, '灵气体系');
    expect(list.first.firstSeenChapter, 1);
    expect(list.first.firstSeenAt, 1000);
    expect(list.first.status, 'active');

    final got = await repo.getWorld(manuscriptId, '灵气体系');
    expect(got, isNotNull);
    final a = WorldFactRepository.parseAssertions(got!.assertions);
    expect(a.length, 1);
    expect(a.first.attribute, '灵气浓度');
    expect(a.first.value, '稀薄');
    expect(a.first.chapter, 1);
  });

  test('#2 重复 upsert → 断言增量合并，firstSeen 不被覆盖', () async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      firstSeenChapter: 1,
      firstSeenAt: 1000,
      assertions: [
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '稀薄',
          chapter: 1,
          timestamp: 1000,
        ),
      ],
    );
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      firstSeenChapter: 9,
      firstSeenAt: 9000,
      assertions: [
        CharacterAssertion(
          attribute: '地理',
          value: '荒原为主',
          chapter: 4,
          timestamp: 4000,
        ),
      ],
    );

    final list = await repo.listWorlds(manuscriptId);
    expect(list.length, 1, reason: 'UNIQUE(manuscript_id, name) 应合并为一行');
    expect(
      list.first.firstSeenChapter,
      1,
      reason: 'update 不得覆盖 firstSeenChapter',
    );

    final a = WorldFactRepository.parseAssertions(list.first.assertions);
    expect(a.length, 2, reason: '两次断言应增量合并而非覆盖');
    expect(a.map((x) => x.attribute), containsAll(['灵气浓度', '地理']));
  });

  test('#3 断言往返保真：status / source / chapterHash / stale 不丢', () async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '禁剑令',
      assertions: [
        CharacterAssertion(
          attribute: '门派禁令',
          value: '禁止用剑',
          chapter: 2,
          timestamp: 2000,
          status: 'rejected',
          source: 'user',
          evidence: '原文第 2 章',
          chapterHash: 'H2',
          stale: true,
        ),
      ],
    );

    final got = await repo.getWorld(manuscriptId, '禁剑令');
    final a = WorldFactRepository.parseAssertions(got!.assertions).single;
    // 走 fromDbJson 而非 tryFromJson——后者刻意不读这四项，往返会丢
    expect(a.status, 'rejected');
    expect(a.source, 'user');
    expect(a.evidence, '原文第 2 章');
    expect(a.chapterHash, 'H2');
    expect(a.stale, isTrue);
  });

  test('#4 parseAssertions：非法 JSON / 脏条目 → 保守跳过不抛出', () async {
    expect(WorldFactRepository.parseAssertions('not json'), isEmpty);
    expect(WorldFactRepository.parseAssertions('[]'), isEmpty);
    expect(
      WorldFactRepository.parseAssertions(
        '[{"attribute":"","value":"有值"},{"attribute":"有属性","value":""}]',
      ),
      isEmpty,
      reason: '空属性名 / 空值条目应被过滤',
    );
  });

  test('#5 listWorlds 默认排除 archived；includeArchived:true 可回溯', () async {
    await repo.upsertWorld(manuscriptId: manuscriptId, name: '在用设定');
    await repo.upsertWorld(manuscriptId: manuscriptId, name: '废弃设定');
    final archived = await repo.getWorld(manuscriptId, '废弃设定');
    await (db.update(db.worldFacts)..where((t) => t.id.equals(archived!.id)))
        .write(const WorldFactsCompanion(status: Value('archived')));

    final defaultView = await repo.listWorlds(manuscriptId);
    expect(defaultView.length, 1);
    expect(defaultView.single.name, '在用设定');

    final fullView = await repo.listWorlds(manuscriptId, includeArchived: true);
    expect(fullView.length, 2);
  });

  test('#6 跨作品隔离：同主题名在另一本书是另一行', () async {
    final other = await ManuscriptRepository(db).createManuscript(title: '另一本');
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      assertions: [
        CharacterAssertion(
          attribute: '浓度',
          value: '稀薄',
          chapter: 1,
          timestamp: 1,
        ),
      ],
    );
    await repo.upsertWorld(
      manuscriptId: other,
      name: '灵气体系',
      assertions: [
        CharacterAssertion(
          attribute: '浓度',
          value: '浓郁',
          chapter: 1,
          timestamp: 1,
        ),
      ],
    );

    expect((await repo.listWorlds(manuscriptId)).length, 1);
    expect((await repo.listWorlds(other)).length, 1);
    final here = await repo.getWorld(manuscriptId, '灵气体系');
    expect(
      WorldFactRepository.parseAssertions(here!.assertions).single.value,
      '稀薄',
    );
  });

  test('#7 【白拿验证】带指纹重诊 → 旧指纹同章断言标 stale', () async {
    // 第一次抽取：第 1 章，指纹 H1
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      assertions: [
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '稀薄',
          chapter: 1,
          timestamp: 1000,
        ),
      ],
      chapterHash: 'H1',
      chapterNo: 1,
    );
    // 第二次抽取（第 1 章已改写，指纹变 H2）：新断言 + 旧断言应标 stale
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      assertions: [
        CharacterAssertion(
          attribute: '地理',
          value: '荒原为主',
          chapter: 1,
          timestamp: 5000,
        ),
      ],
      chapterHash: 'H2',
      chapterNo: 1,
    );

    final got = await repo.getWorld(manuscriptId, '灵气体系');
    final a = WorldFactRepository.parseAssertions(got!.assertions);
    final old = a.firstWhere((x) => x.attribute == '灵气浓度');
    final fresh = a.firstWhere((x) => x.attribute == '地理');
    expect(old.stale, isTrue, reason: '旧指纹的同章断言应被标 stale（复用角色侧机制）');
    expect(fresh.stale, isFalse, reason: '新断言不应被标 stale');
    expect(fresh.chapterHash, 'H2', reason: '新断言应填当前指纹');
  });

  test('#8 【白拿验证】用户手写断言不被 AI 同三元组覆写（R-009）', () async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '禁剑令',
      assertions: [
        CharacterAssertion(
          attribute: '门派禁令',
          value: '禁止用剑',
          chapter: 2,
          timestamp: 2000,
          source: 'user',
          evidence: '用户手改',
        ),
      ],
      chapterHash: 'H2',
      chapterNo: 2,
    );
    // AI 重新抽取**同一三元组**（attribute + value + chapter 全同）
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '禁剑令',
      assertions: [
        CharacterAssertion(
          attribute: '门派禁令',
          value: '禁止用剑',
          chapter: 2,
          timestamp: 3000,
        ),
      ],
      chapterHash: 'H2',
      chapterNo: 2,
    );

    final got = await repo.getWorld(manuscriptId, '禁剑令');
    final a = WorldFactRepository.parseAssertions(got!.assertions);
    expect(a.length, 1, reason: '同三元组应合并为一条，不重复落库');
    expect(
      a.single.source,
      'user',
      reason: 'mergeAssertions 规则 (b)：用户裁决优先于 AI（R-009）',
    );
    expect(a.single.evidence, '用户手改', reason: '用户手写版本不得被 AI 版本替换');
  });
}
