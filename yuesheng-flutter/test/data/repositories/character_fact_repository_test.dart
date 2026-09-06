// ─────────────────────────────────────────────────────────────
// character_fact_repository_test — 批次66 B62i 人物知识仓储单元测试
//
// 覆盖：
//   1. upsert 新人物 → list/get 往返
//   2. 重复 upsert → 更新断言（UNIQUE(manuscript_id, name)）
//   3. 断言 JSON 往返（parseAssertions）
//   4. parseAssertions 非法 JSON / 脏条目 → 保守跳过
//
// C78 批次2c 追加（§5.4 匹配归一化与合并）：
//   5. listCharacters 默认排除 merged 源行，includeMerged:true 可回溯
//   6. mergeCharacter 三步：断言迁入 + 源名进 aliases + 源行标 merged
//   7. 【核心】断言迁移保 source——源行的用户手改值压过目标行的 AI 值
//      （现成的 FactStaleService.mergeAssertions 做不到，本批为此新写判据）
//   8. 源行是**标记**（软删）不是物理删，且源行自身别名一并收编
//   9. 事务回滚：外层抛异常 → 三步整体不落库，目标行不被写坏
//  10. 边界：自并 / 跨作品 / 无效 id → false 且不落任何写
//  11. 端到端：别名收编后，用别名参与的事件仍能被关联到
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

// 只取 Value：drift 整体导入会带进 isNull / isNotNull，与 matcher 撞名
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/services/character_identity.dart';
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

  // ── C78 批次2c（§5.4 匹配归一化与合并）────────────────────────────
  CharacterAssertion assertion(
    String attribute,
    String value, {
    int? chapter,
    int timestamp = 1000,
    String source = 'ai',
    String status = 'confirmed',
  }) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      timestamp: timestamp,
      source: source,
      status: status,
    );
  }

  /// 直接写行：合并用例要精确控制 status / aliases / 断言全字段，
  /// 走 upsertCharacter 会被三元组合并改写，验不出「保 source」。
  Future<String> seedCharacter(
    String name, {
    String? inManuscript,
    List<CharacterAssertion> assertions = const [],
    List<String> aliases = const [],
    String status = 'active',
  }) async {
    final id = generateUuid();
    await db
        .into(db.characterFacts)
        .insert(
          CharacterFactsCompanion.insert(
            id: id,
            manuscriptId: inManuscript ?? manuscriptId,
            name: name,
            assertions: Value(
              jsonEncode(assertions.map((a) => a.toJson()).toList()),
            ),
            aliases: Value(jsonEncode(aliases)),
            status: Value(status),
          ),
        );
    return id;
  }

  Future<CharacterFact> rowNamed(String name) async {
    final all = await repo.listCharacters(manuscriptId, includeMerged: true);
    return all.firstWhere((c) => c.name == name);
  }

  group('§5.4 匹配归一化与合并', () {
    test('#5 listCharacters 默认排除 merged 源行，includeMerged 可回溯', () async {
      await seedCharacter('林晚晴');
      await seedCharacter('阿晴', status: 'merged');

      // 默认：源行不出现（否则 F05 会把它的断言与目标的副本双重计入）
      final visible = await repo.listCharacters(manuscriptId);
      expect(visible.map((c) => c.name).toList(), ['林晚晴']);

      // 显式回溯：合并源行仍在库里，用户要能查到
      final all = await repo.listCharacters(manuscriptId, includeMerged: true);
      expect(all.map((c) => c.name).toSet(), {'林晚晴', '阿晴'});
    });

    test('#6 mergeCharacter 三步：断言迁入 + 源名进 aliases + 源行标 merged', () async {
      final targetId = await seedCharacter(
        '林晚晴',
        assertions: [assertion('性格', '冷静', chapter: 1)],
      );
      final sourceId = await seedCharacter(
        '阿晴',
        assertions: [assertion('职业', '捕快', chapter: 5)],
      );

      final ok = await repo.mergeCharacter(
        targetId: targetId,
        sourceId: sourceId,
      );
      expect(ok, true);

      final target = await rowNamed('林晚晴');
      final merged = CharacterFactRepository.parseAssertions(target.assertions);
      expect(merged.map((a) => a.value).toSet(), {'冷静', '捕快'});
      expect(parseJsonStringList(target.aliases), ['阿晴']);
      expect((await rowNamed('阿晴')).status, 'merged');
    });

    test('#7 断言迁移保 source：源行的用户手改值压过目标行的 AI 值', () async {
      // 这条是本批**不能**复用 FactStaleService.mergeAssertions 的原因：
      // 它传 null 走简并分支（existing 优先），目标行是 existing → 源行里
      // 用户手改的 user 断言会被目标行的 ai 断言吃掉，用户手动修正蒸发（R-009）。
      final targetId = await seedCharacter(
        '林晚晴',
        assertions: [assertion('独生子女状态', '独生子', chapter: 3, source: 'ai')],
      );
      final sourceId = await seedCharacter(
        '阿晴',
        assertions: [assertion('独生子女状态', '独生子', chapter: 3, source: 'user')],
      );

      await repo.mergeCharacter(targetId: targetId, sourceId: sourceId);

      final target = await rowNamed('林晚晴');
      final merged = CharacterFactRepository.parseAssertions(target.assertions);
      expect(merged.length, 1, reason: '同三元组去重');
      expect(merged.single.source, 'user', reason: 'R-009：用户手改值压过 AI 值');
    });

    test('#8 源行是标记（软删）不是物理删，且源行自身别名一并收编', () async {
      // 载体实测：character_fact 无 deleted_at 类软删列（tables.dart:506-534），
      // 项目软删惯例本就是用 status 列标记。物理删会丢首次出场信息、
      // 且 UNIQUE(manuscript_id, name) 下源名可被 AI 再次抽出重建 → 合并被拆开。
      final targetId = await seedCharacter('林晚晴');
      final sourceId = await seedCharacter(
        '阿晴',
        aliases: ['晴儿'],
        assertions: [assertion('职业', '捕快', chapter: 5)],
      );

      await repo.mergeCharacter(targetId: targetId, sourceId: sourceId);

      // 物理删的话这两行都会取不到
      final source = await rowNamed('阿晴');
      expect(source.status, 'merged');
      expect(
        CharacterFactRepository.parseAssertions(source.assertions),
        isNotEmpty,
        reason: '源行断言不清空——留后悔药，且默认不进检测不会双重计入',
      );

      final target = await rowNamed('林晚晴');
      expect(parseJsonStringList(target.aliases), ['阿晴', '晴儿']);
    });

    test('#9 事务回滚：外层事务抛异常 → 合并三步整体不落库', () async {
      final targetId = await seedCharacter(
        '林晚晴',
        assertions: [assertion('性格', '冷静', chapter: 1)],
      );
      final sourceId = await seedCharacter(
        '阿晴',
        assertions: [assertion('职业', '捕快', chapter: 5)],
      );

      // drift 嵌套事务走 savepoint：外层抛异常 → 内层的三步一并回滚。
      await expectLater(
        db.transaction(() async {
          await repo.mergeCharacter(targetId: targetId, sourceId: sourceId);
          throw StateError('boom');
        }),
        throwsA(isA<StateError>()),
      );

      final target = await rowNamed('林晚晴');
      final kept = CharacterFactRepository.parseAssertions(target.assertions);
      expect(kept.map((a) => a.value).toList(), ['冷静'], reason: '源行断言不得残留在目标行');
      expect(parseJsonStringList(target.aliases), isEmpty, reason: '别名不得被污染');
      expect((await rowNamed('阿晴')).status, 'active', reason: '源行不得被标记');
    });

    test('#10 边界：自并 / 跨作品 / 无效 id → false 且不落任何写', () async {
      final targetId = await seedCharacter('林晚晴');
      final sourceId = await seedCharacter('阿晴');
      final otherMs = await ManuscriptRepository(
        db,
      ).createManuscript(title: '另一部稿');
      final outsiderId = await seedCharacter('外人', inManuscript: otherMs);

      expect(
        await repo.mergeCharacter(targetId: targetId, sourceId: targetId),
        false,
        reason: '自己并自己',
      );
      expect(
        await repo.mergeCharacter(targetId: targetId, sourceId: '不存在的id'),
        false,
      );
      expect(
        await repo.mergeCharacter(targetId: targetId, sourceId: outsiderId),
        false,
        reason: '跨作品合并必须挡住（R-028）',
      );

      // 三次都该是 no-op：源行仍是 active、目标行 aliases 仍空
      expect((await rowNamed('阿晴')).status, 'active');
      expect(parseJsonStringList((await rowNamed('林晚晴')).aliases), isEmpty);
      expect(sourceId, isNotEmpty);
    });

    test('#11 端到端：别名收编后，用别名参与的事件仍能被关联到', () async {
      final targetId = await seedCharacter('林晚晴');
      final sourceId = await seedCharacter('阿晴');
      final eventRepo = EventFactRepository(db);
      // 事件里记录的是**别名**——合并前它关联不到「林晚晴」
      await eventRepo.upsertEvent(
        manuscriptId: manuscriptId,
        name: '巷口冲突',
        eventType: '冲突',
        chapter: 2,
        participants: ['阿晴', '沈砚'],
      );
      final events = await eventRepo.listEvents(manuscriptId);

      // 合并前：两行无别名交集 → 各成一身份，林晚晴只认主名 → 关联不到
      final before = await repo.listCharacters(manuscriptId);
      final beforeNames = identityAliases(before)['林晚晴'] ?? {'林晚晴'};
      expect(filterEventsByIdentity(events, beforeNames), isEmpty);

      // 合并后：源名进目标 aliases → 同一条事件命中
      await repo.mergeCharacter(targetId: targetId, sourceId: sourceId);
      final after = await repo.listCharacters(manuscriptId);
      final afterNames = identityAliases(after)['林晚晴']!;
      expect(afterNames, contains('阿晴'));
      expect(
        filterEventsByIdentity(events, afterNames).map((e) => e.name).toList(),
        ['巷口冲突'],
      );
    });
  });
}
