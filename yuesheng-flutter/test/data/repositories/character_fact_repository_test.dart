// ─────────────────────────────────────────────────────────────
// character_fact_repository_test — 批次66 B62i 人物知识仓储单元测试
//
// 覆盖：
//   1. upsert 新人物 → list/get 往返
//   2. 重复 upsert → 更新断言（UNIQUE(manuscript_id, name)）
//   3. 断言 JSON 往返（parseAssertions）
//   4. parseAssertions 非法 JSON / 脏条目 → 保守跳过
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
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

  test('#1 upsert 新人物 → list/get 往返', () async {
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      firstSeenChapter: 1,
      firstSeenAt: 1000,
      assertions: [
        CharacterAssertion(
          attribute: '独生子女状态',
          value: '独生子',
          chapter: 3,
          timestamp: 1000,
        ),
      ],
    );

    final list = await repo.listCharacters(manuscriptId);
    expect(list.length, 1);
    expect(list.first.name, '阿禾');
    expect(list.first.firstSeenChapter, 1);
    expect(list.first.firstSeenAt, 1000);

    final got = await repo.getCharacter(manuscriptId, '阿禾');
    expect(got, isNotNull);
    final assertions = CharacterFactRepository.parseAssertions(got!.assertions);
    expect(assertions.length, 1);
    expect(assertions.first.attribute, '独生子女状态');
    expect(assertions.first.value, '独生子');
    expect(assertions.first.chapter, 3);
    expect(assertions.first.timestamp, 1000);
  });

  test('#2 重复 upsert → 合并断言不覆盖历史（批次3-D2）', () async {
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [
        CharacterAssertion(
          attribute: '职业',
          value: '郎中',
          chapter: 2,
          timestamp: 1000,
        ),
      ],
    );
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [
        CharacterAssertion(
          attribute: '职业',
          value: '捕快',
          chapter: 9,
          timestamp: 2000,
        ),
      ],
    );

    final list = await repo.listCharacters(manuscriptId);
    expect(list.length, 1, reason: '同作品同名人物唯一');

    final got = await repo.getCharacter(manuscriptId, '阿禾');
    final assertions = CharacterFactRepository.parseAssertions(got!.assertions);
    // D2: 合并去重后保留两条历史断言（不同 value+chapter 视为不同断言）
    expect(assertions.length, 2, reason: '历史断言不覆盖');
    final values = assertions.map((a) => a.value).toSet();
    expect(values, containsAll(['郎中', '捕快']));
  });

  test('#2b 重复 upsert 同断言 → 去重不重复（批次3-D2）', () async {
    final assertion = CharacterAssertion(
      attribute: '职业',
      value: '郎中',
      chapter: 2,
      timestamp: 1000,
    );
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [assertion],
    );
    // 同 (attribute, value, chapter) 三元组 → 去重
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      assertions: [assertion],
    );

    final got = await repo.getCharacter(manuscriptId, '阿禾');
    final assertions = CharacterFactRepository.parseAssertions(got!.assertions);
    expect(assertions.length, 1, reason: '同三元组去重');
  });

  test('#2c 重复 upsert 不覆盖 firstSeenChapter/firstSeenAt（批次3-D2）', () async {
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      firstSeenChapter: 1,
      firstSeenAt: 1000,
      assertions: [
        CharacterAssertion(
          attribute: '职业',
          value: '郎中',
          chapter: 1,
          timestamp: 1000,
        ),
      ],
    );
    // 第二次传入更晚的 firstSeenChapter/firstSeenAt，应不覆盖
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '阿禾',
      firstSeenChapter: 15,
      firstSeenAt: 9999,
      assertions: [
        CharacterAssertion(
          attribute: '职业',
          value: '捕快',
          chapter: 15,
          timestamp: 9999,
        ),
      ],
    );

    final got = await repo.getCharacter(manuscriptId, '阿禾');
    expect(got!.firstSeenChapter, 1, reason: '首次出场章节不覆盖');
    expect(got.firstSeenAt, 1000, reason: '首次出场时间不覆盖');
  });

  test('#3 多人按姓名排序', () async {
    await repo.upsertCharacter(manuscriptId: manuscriptId, name: '阿青');
    await repo.upsertCharacter(manuscriptId: manuscriptId, name: '阿禾');

    final list = await repo.listCharacters(manuscriptId);
    expect(list.map((c) => c.name).toList(), ['阿禾', '阿青']);
  });

  test('#4 parseAssertions 非法 JSON / 脏条目 → 保守跳过', () async {
    expect(CharacterFactRepository.parseAssertions(''), isEmpty);
    expect(CharacterFactRepository.parseAssertions('not-json'), isEmpty);
    expect(CharacterFactRepository.parseAssertions('{}'), isEmpty);

    // 合法列表 + 一条缺属性名的脏条目 → 仅保留合法条目
    final parsed = CharacterFactRepository.parseAssertions(
      '[{"attribute":"职业","value":"郎中","chapter":2,"timestamp":1000},'
      '{"attribute":"","value":"非法"},'
      '{"value":"缺属性名"}]',
    );
    expect(parsed.length, 1);
    expect(parsed.single.value, '郎中');
  });
}
