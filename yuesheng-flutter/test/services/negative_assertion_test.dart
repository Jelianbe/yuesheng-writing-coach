// ─────────────────────────────────────────────────────────────
// negative_assertion_test — 设定资料库第二批：拒绝即负断言
//
// 覆盖：
//   1. types：withNegative 往返（fromDbJson 保真）/ 未知字段容错
//   2. committer：buildNegativeAssertionsContext 纯函数（空/正常/多条）
//   3. editor：setNegative 勾选 → listNegativeAssertions 命中；
//      目标断言不存在 → 零写；confirmed 勾选不进入负断言清单
//   4. repo：listNegativeAssertions 过滤（仅 rejected && negative）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/services/character_editor_service.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  group('1. types：withNegative 往返', () {
    test('#1 fromDbJson 还原 negative + 未知字段容错', () {
      final a = CharacterAssertion.fromDbJson(const {
        'attribute': '性格',
        'value': '冷酷',
        'timestamp': 1,
        'status': 'rejected',
        'rejectReason': '抽取错误',
        'negative': true,
        'unknownField': 'x', // 容错：不得抛
      });
      expect(a.negative, isTrue);
      expect(a.status, 'rejected');
    });

    test('#2 toJson → fromDbJson 往返保真', () {
      const a = CharacterAssertion(
        attribute: '身份',
        value: '捕快',
        timestamp: 2,
        status: 'rejected',
        negative: true,
      );
      final round = CharacterAssertion.fromDbJson(a.toJson());
      expect(round.negative, isTrue);
      expect(round.value, '捕快');
    });

    test('#3 未写 negative 字段 → 默认 false（存量库兼容）', () {
      final a = CharacterAssertion.fromDbJson(const {
        'attribute': '身份',
        'value': '捕快',
        'timestamp': 2,
      });
      expect(a.negative, isFalse);
    });

    test('#4 withNegative 只改 negative，其余原样保留', () {
      const a = CharacterAssertion(
        attribute: '性格',
        value: '冷酷',
        chapter: 3,
        timestamp: 1,
        status: 'rejected',
        rejectReason: '重复',
      );
      final b = a.withNegative(true);
      expect(b.negative, isTrue);
      expect(b.value, '冷酷');
      expect(b.chapter, 3);
      expect(b.rejectReason, '重复');
      expect(a.negative, isFalse, reason: '原对象不可变');
    });
  });

  group('2. committer：buildNegativeAssertionsContext 纯函数', () {
    test('#5 空 → 空串（零注入）', () {
      expect(buildNegativeAssertionsContext(const []), '');
    });

    test('#6 正常渲染：实体 · 属性 ≠ 值 + 语义', () {
      final ctx = buildNegativeAssertionsContext(const [
        NegativeFact(entity: '林晚', attribute: '身份', value: '捕快'),
      ]);
      expect(ctx, contains('负断言'));
      expect(ctx, contains('林晚 · 身份 ≠ 捕快'));
      expect(ctx, contains('不成立'));
      expect(ctx, contains('不得默认或暗示其成立'));
    });

    test('#7 多条全部列出', () {
      final ctx = buildNegativeAssertionsContext(const [
        NegativeFact(entity: '林晚', attribute: '身份', value: '捕快'),
        NegativeFact(entity: '沈砚', attribute: '身份', value: '锦衣卫'),
      ]);
      expect(ctx, contains('林晚 · 身份 ≠ 捕快'));
      expect(ctx, contains('沈砚 · 身份 ≠ 锦衣卫'));
    });
  });

  group('3. editor + repo：勾选/过滤/零写', () {
    late AppDatabase db;
    late CharacterEditorService editor;
    late CharacterFactRepository factRepo;
    late String manuscriptId;
    late String characterId;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      editor = CharacterEditorService(db);
      factRepo = CharacterFactRepository(db);
      manuscriptId = await ManuscriptRepository(
        db,
      ).createManuscript(title: '负断言测试');
      await factRepo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '林晚',
        assertions: const [
          CharacterAssertion(
            attribute: '身份',
            value: '捕快',
            chapter: 3,
            timestamp: 1000,
          ),
        ],
      );
      final row = await factRepo.getCharacter(manuscriptId, '林晚');
      characterId = row!.id;
    });

    tearDown(() async => db.close());

    test('#8 先拒绝再勾选 → listNegativeAssertions 命中', () async {
      const target = CharacterAssertion(
        attribute: '身份',
        value: '捕快',
        chapter: 3,
        timestamp: 1000,
      );
      await editor.rejectAssertion(characterId: characterId, target: target);
      expect(
        await factRepo.listNegativeAssertions(manuscriptId),
        isEmpty,
        reason: '拒绝 ≠ 勾选，默认零注入',
      );

      await editor.setNegative(
        characterId: characterId,
        target: target,
        negative: true,
      );
      final negatives = await factRepo.listNegativeAssertions(manuscriptId);
      expect(negatives, hasLength(1));
      expect(negatives.single.$1.name, '林晚');
      expect(negatives.single.$2.attribute, '身份');
      expect(negatives.single.$2.negative, isTrue);
    });

    test('#9 未拒绝（confirmed）勾选 → 不进负断言清单', () async {
      const target = CharacterAssertion(
        attribute: '身份',
        value: '捕快',
        chapter: 3,
        timestamp: 1000,
      );
      await editor.setNegative(
        characterId: characterId,
        target: target,
        negative: true,
      );
      expect(
        await factRepo.listNegativeAssertions(manuscriptId),
        isEmpty,
        reason: 'confirmed 不是负断言来源',
      );
    });

    test('#10 目标断言不存在 → 零写（原断言不动）', () async {
      const ghost = CharacterAssertion(
        attribute: '不存在属性',
        value: '不存在值',
        chapter: 99,
        timestamp: 9999,
      );
      final ok = await editor.setNegative(
        characterId: characterId,
        target: ghost,
        negative: true,
      );
      expect(ok, isFalse, reason: '目标断言不存在不落写');
      final row = await factRepo.getCharacter(manuscriptId, '林晚');
      final a = CharacterFactRepository.parseAssertions(row!.assertions).single;
      expect(a.negative, isFalse);
      expect(a.value, '捕快');
    });

    test('#11 取消勾选 → 从负断言清单消失', () async {
      const target = CharacterAssertion(
        attribute: '身份',
        value: '捕快',
        chapter: 3,
        timestamp: 1000,
      );
      await editor.rejectAssertion(characterId: characterId, target: target);
      await editor.setNegative(
        characterId: characterId,
        target: target,
        negative: true,
      );
      expect(await factRepo.listNegativeAssertions(manuscriptId), hasLength(1));
      await editor.setNegative(
        characterId: characterId,
        target: target,
        negative: false,
      );
      expect(await factRepo.listNegativeAssertions(manuscriptId), isEmpty);
    });

    test('#12 repo 过滤：仅 rejected && negative（别的角色 rejected 未勾选不进）', () async {
      await factRepo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '沈砚',
        assertions: const [
          CharacterAssertion(
            attribute: '身份',
            value: '锦衣卫',
            chapter: 1,
            timestamp: 100,
          ),
        ],
      );
      const target = CharacterAssertion(
        attribute: '身份',
        value: '捕快',
        chapter: 3,
        timestamp: 1000,
      );
      await editor.rejectAssertion(characterId: characterId, target: target);
      await editor.setNegative(
        characterId: characterId,
        target: target,
        negative: true,
      );
      // 沈砚 rejected 未勾选
      final shenRow = await factRepo.getCharacter(manuscriptId, '沈砚');
      await editor.rejectAssertion(
        characterId: shenRow!.id,
        target: const CharacterAssertion(
          attribute: '身份',
          value: '锦衣卫',
          chapter: 1,
          timestamp: 100,
        ),
      );
      final negatives = await factRepo.listNegativeAssertions(manuscriptId);
      expect(negatives, hasLength(1), reason: '只含林晚勾选的那条');
      expect(negatives.single.$1.name, '林晚');
    });
  });
}
