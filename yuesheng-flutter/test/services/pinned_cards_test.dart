// ─────────────────────────────────────────────────────────────
// pinned_cards_test — 设定资料库第二批·分级供给 L2（用户钉选）
//
// 覆盖：
//   1. repo：setPinned 往返 / 取消 / active 过滤（merged 排除）/ 名字升序
//   2. buildPinnedCardsContext：名片构造 / rejected 排除 / 3 条截断 /
//      空列表零注入
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late CharacterFactRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CharacterFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
  });

  tearDown(() async => db.close());

  const confirmed = CharacterAssertion(
    attribute: '身份',
    value: '捕快',
    chapter: 3,
    timestamp: 1,
    status: 'confirmed',
  );
  const rejected = CharacterAssertion(
    attribute: '职业',
    value: '画师',
    chapter: 3,
    timestamp: 2,
    status: 'rejected',
  );

  Future<String> create(
    String name, {
    List<CharacterAssertion> assertions = const [],
  }) async {
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: name,
      firstSeenChapter: 1,
      firstSeenAt: 1000,
      assertions: assertions,
    );
    final row = await repo.getCharacter(manuscriptId, name);
    return row!.id;
  }

  group('1. repo setPinned / listPinned', () {
    test('#1 钉住 → listPinned 含该角色', () async {
      final id = await create('林晚');
      await repo.setPinned(id, pinned: true);

      final pinned = await repo.listPinned(manuscriptId);
      expect(pinned.map((c) => c.name), ['林晚']);
      expect(pinned.single.pinned, 1);
    });

    test('#2 取消钉住 → 移除', () async {
      final id = await create('林晚');
      await repo.setPinned(id, pinned: true);
      await repo.setPinned(id, pinned: false);

      expect(await repo.listPinned(manuscriptId), isEmpty);
    });

    test('#3 merged 源行不驻留（即使被钉）', () async {
      final targetId = await create('林晚');
      final sourceId = await create('沈砚');
      await repo.mergeCharacter(targetId: targetId, sourceId: sourceId);
      await repo.setPinned(sourceId, pinned: true);

      final pinned = await repo.listPinned(manuscriptId);
      expect(pinned.map((c) => c.name), isNot(contains('沈砚')));
    });

    test('#4 多角色按名字升序', () async {
      final b = await create('乙');
      final a = await create('甲');
      await repo.setPinned(b, pinned: true);
      await repo.setPinned(a, pinned: true);

      final pinned = await repo.listPinned(manuscriptId);
      expect(pinned.map((c) => c.name), ['乙', '甲']);
    });

    test('#5 不存在的 id 静默跳过', () async {
      await repo.setPinned('no_such_id', pinned: true);
      expect(await repo.listPinned(manuscriptId), isEmpty);
    });
  });

  group('2. buildPinnedCardsContext', () {
    test('#6 名片构造 + rejected 排除', () {
      final ctx = buildPinnedCardsContext([
        CharacterFact(
          id: 'c1',
          manuscriptId: 'm1',
          name: '林晚',
          firstSeenChapter: 1,
          firstSeenAt: 1,
          assertions: jsonEncode([confirmed.toJson(), rejected.toJson()]),
          description: '',
          aliases: '[]',
          status: 'active',
          pinned: 1,
          createdAt: 1,
          updatedAt: 1,
        ),
      ]);
      expect(ctx, isNotNull);
      expect(ctx, contains('学员主动钉住'));
      expect(ctx, contains('身份=捕快'));
      expect(ctx, isNot(contains('画师')), reason: 'rejected 不进名片');
    });

    test('#7 每实体至多 3 条（kPinnedCardMaxAssertions）', () {
      final many = [
        for (var i = 0; i < 5; i++)
          CharacterAssertion(
            attribute: '属性$i',
            value: '值$i',
            timestamp: i,
            status: 'confirmed',
          ),
      ];
      final ctx = buildPinnedCardsContext([
        CharacterFact(
          id: 'c1',
          manuscriptId: 'm1',
          name: '林晚',
          firstSeenChapter: 1,
          firstSeenAt: 1,
          assertions: jsonEncode([for (final a in many) a.toJson()]),
          description: '',
          aliases: '[]',
          status: 'active',
          pinned: 1,
          createdAt: 1,
          updatedAt: 1,
        ),
      ]);
      expect(ctx, contains('属性0=值0'));
      expect(ctx, contains('属性2=值2'));
      expect(ctx, isNot(contains('属性4=值4')), reason: '超 3 条截断');
    });

    test('#8 空列表 → null（零注入）', () {
      expect(buildPinnedCardsContext(const []), isNull);
    });

    test('#9 全部断言被排除 → null', () {
      final ctx = buildPinnedCardsContext([
        CharacterFact(
          id: 'c1',
          manuscriptId: 'm1',
          name: '林晚',
          firstSeenChapter: 1,
          firstSeenAt: 1,
          assertions: jsonEncode([rejected.toJson()]),
          description: '',
          aliases: '[]',
          status: 'active',
          pinned: 1,
          createdAt: 1,
          updatedAt: 1,
        ),
      ]);
      expect(ctx, isNull);
    });
  });
}
