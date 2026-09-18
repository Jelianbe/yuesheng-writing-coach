// ─────────────────────────────────────────────────────────────
// character_editor_service_test — C78 批次3 断言级人工裁决单测
//
// 覆盖（ADR-C78 §6 / FR-5）：
//   1. rejectAssertion：状态改 rejected + 理由落库（D-7 chips 载体）
//      + 直接拒绝（无理由）→ rejectReason 保持 null
//   2. reject 不存在的行 / 不存在的断言 / 重复拒绝 → false（零写）
//   3. correctAssertion：原条 rejected 留痕 + 新增 source=user 断言
//   4. addUserAssertion：章号按**序位**归一到身份后取该章正文指纹（§5.1(c)）；
//      章号空 / 序位不存在 → 身份与 hash 均 null（不猜）
//   5. 属性/值为空 → false（R-028 边界校验）
//   6. updateAliases：trim + 去空 + 去重保序
//   7. 改写不碰其他断言（逐字段保留）
//
// `N12-F3b` 追加（`ADR-C96 §1.3` 第 1 行 + §6 潜伏缺口）：
//   8. 用户手填章号 = **序位** ⇒ 写库前归一到身份（否则指纹与展示指向不同章）
//   9. `_withStatus` 逐字段重建的**保真**：身份与 `negative` 都不得被静默清掉
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/services/character_editor_service.dart';
import 'package:writingcoach/types/character_types.dart';

void main() {
  late AppDatabase db;
  late CharacterEditorService editor;
  late CharacterFactRepository factRepo;
  late ChapterRepository chapterRepo;
  late String manuscriptId;
  late String characterId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    editor = CharacterEditorService(db);
    factRepo = CharacterFactRepository(db);
    chapterRepo = ChapterRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试稿');
    await factRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚晴',
      firstSeenChapter: 3,
      assertions: [
        const CharacterAssertion(
          attribute: '性格',
          value: '冷静',
          chapter: 3,
          // N12-F3b：AI 写入路径现在会填身份 ⇒ 夹具按**新行**形态构造，
          // 下面的「保真」用例才有东西可保管。
          chapterSortOrder: 2,
          timestamp: 1000,
        ),
        const CharacterAssertion(
          attribute: '职业',
          value: '捕快',
          chapter: 4,
          timestamp: 2000,
        ),
      ],
    );
    final row = await factRepo.getCharacter(manuscriptId, '林晚晴');
    characterId = row!.id;
  });

  tearDown(() async => db.close());

  Future<List<CharacterAssertion>> assertionsOf(String id) async {
    final row = await factRepo.getCharacterById(id);
    return CharacterFactRepository.parseAssertions(row!.assertions);
  }

  group('rejectAssertion', () {
    test('状态改 rejected 且理由落库（D-7）', () async {
      final ok = await editor.rejectAssertion(
        characterId: characterId,
        target: await assertionsOf(
          characterId,
        ).then((l) => l.firstWhere((a) => a.value == '冷静')),
        reason: '抽取错误',
      );
      expect(ok, isTrue);
      final list = await assertionsOf(characterId);
      final rejected = list.firstWhere((a) => a.value == '冷静');
      expect(rejected.status, 'rejected');
      expect(rejected.rejectReason, '抽取错误');
      // 其他字段逐项保留（改写不留痕即失真）
      expect(rejected.attribute, '性格');
      expect(rejected.chapter, 3);
      expect(rejected.timestamp, 1000);
      expect(rejected.source, 'ai');
      expect(
        rejected.chapterSortOrder,
        2,
        reason: 'N12-F3b 保真 #7：改写逐字段重建，漏一个字段就静默丢一次',
      );
      // 另一条不受影响
      expect(list.firstWhere((a) => a.value == '捕快').status, 'confirmed');
    });

    test('身份与负断言在改写链上保真（N12-F3b 修复的潜伏缺口）', () async {
      Future<CharacterAssertion> cur() async =>
          (await assertionsOf(characterId)).firstWhere((a) => a.value == '冷静');

      await editor.rejectAssertion(
        characterId: characterId,
        target: await cur(),
        reason: '抽取错误',
      );
      await editor.setNegative(
        characterId: characterId,
        target: await cur(),
        negative: true,
      );
      expect((await cur()).negative, isTrue);

      // 再走一次 _withStatus（改拒绝理由）—— 「先勾负断言、再改理由」的真实顺序
      await editor.rejectAssertion(
        characterId: characterId,
        target: await cur(),
        reason: '重复',
      );
      final after = await cur();
      expect(after.rejectReason, '重复');
      expect(
        after.negative,
        isTrue,
        reason: '修复前 _withStatus 漏传 negative ⇒ 这一步把它静默清成 false',
      );
      expect(after.chapterSortOrder, 2, reason: '身份必须一并保真');
    });

    test('直接拒绝（无理由）→ rejectReason 为 null', () async {
      final target = await assertionsOf(
        characterId,
      ).then((l) => l.firstWhere((a) => a.value == '冷静'));
      await editor.rejectAssertion(characterId: characterId, target: target);
      final rejected = (await assertionsOf(
        characterId,
      )).firstWhere((a) => a.value == '冷静');
      expect(rejected.status, 'rejected');
      expect(rejected.rejectReason, isNull);
    });

    test('行不存在 / 断言不存在 / 重复拒绝 → false', () async {
      final target = await assertionsOf(
        characterId,
      ).then((l) => l.firstWhere((a) => a.value == '冷静'));
      expect(
        await editor.rejectAssertion(
          characterId: 'no-such-row',
          target: target,
        ),
        isFalse,
      );
      expect(
        await editor.rejectAssertion(
          characterId: characterId,
          target: const CharacterAssertion(
            attribute: '性格',
            value: '不存在值',
            chapter: 3,
            timestamp: 9999,
          ),
        ),
        isFalse,
      );
      await editor.rejectAssertion(characterId: characterId, target: target);
      // 重复拒绝：内容无变化 → false（不做无意义空写）
      expect(
        await editor.rejectAssertion(characterId: characterId, target: target),
        isFalse,
      );
    });
  });

  group('correctAssertion', () {
    test('原条 rejected 留痕 + 新增 user 断言', () async {
      final target = await assertionsOf(
        characterId,
      ).then((l) => l.firstWhere((a) => a.value == '冷静'));
      final ok = await editor.correctAssertion(
        characterId: characterId,
        target: target,
        newValue: '外冷内热',
      );
      expect(ok, isTrue);
      final list = await assertionsOf(characterId);
      expect(
        list.firstWhere((a) => a.value == '冷静').status,
        'rejected',
        reason: '原条自动拒绝留痕，否则同章同属性双 confirmed 成为 F05 幽灵',
      );
      final corrected = list.firstWhere((a) => a.value == '外冷内热');
      expect(corrected.status, 'confirmed');
      expect(corrected.source, 'user');
      expect(corrected.attribute, '性格');
      expect(corrected.chapter, 3);
    });

    test('空值 → false（R-009 纯手动输入，不猜）', () async {
      final target = await assertionsOf(
        characterId,
      ).then((l) => l.firstWhere((a) => a.value == '冷静'));
      expect(
        await editor.correctAssertion(
          characterId: characterId,
          target: target,
          newValue: '  ',
        ),
        isFalse,
      );
    });

    test('未填章号 ⇒ 继承被修正断言的身份（修正 = 同章改值，不借机换章）', () async {
      final target = await assertionsOf(
        characterId,
      ).then((l) => l.firstWhere((a) => a.value == '冷静'));
      expect(
        await editor.correctAssertion(
          characterId: characterId,
          target: target,
          newValue: '外冷内热',
        ),
        isTrue,
      );

      final corrected = (await assertionsOf(
        characterId,
      )).firstWhere((a) => a.value == '外冷内热');
      expect(corrected.chapter, 3, reason: '沿用原断言的章号');
      expect(corrected.chapterSortOrder, 2, reason: 'N12-F3b：身份随之继承');
      expect(corrected.chapterIdentity, 2);
    });

    test('填了章号 ⇒ 按**序位**归一到身份，指纹随身份取（§1.3 第 1 行错绑的修复）', () async {
      // 刻意让序位与 sortOrder 分叉：唯一一章的身份是 7，而它是**第 1 章**。
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第一章',
        content: '雪落无声。',
        sortOrder: 7,
      );
      final target = await assertionsOf(
        characterId,
      ).then((l) => l.firstWhere((a) => a.value == '冷静'));

      expect(
        await editor.correctAssertion(
          characterId: characterId,
          target: target,
          newValue: '外冷内热',
          chapter: 1, // 用户填的是他看得见的序位
        ),
        isTrue,
      );

      final corrected = (await assertionsOf(
        characterId,
      )).firstWhere((a) => a.value == '外冷内热');
      expect(corrected.chapter, 1, reason: 'R1′：用户原写的数原样保留');
      expect(corrected.chapterSortOrder, 7, reason: '序位 1 ⇒ 身份 7');
      expect(
        corrected.chapterHash,
        isNotNull,
        reason:
            '指纹按**身份**取 ⇒ 命中该章正文；'
            '修复前它把用户填的 1 直接当 sortOrder 查（无此章）⇒ 指纹为 null',
      );
    });
  });

  group('addUserAssertion', () {
    test('写入 user 断言：序位 → 身份归一 + 该章正文指纹（§5.1(c)）', () async {
      // 唯一一章身份是 7、序位是 1（模拟「首章被删过、删除不重编号」的稿）。
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第三章',
        content: '林晚晴握紧刀柄。',
        sortOrder: 7,
      );
      final ok = await editor.addUserAssertion(
        characterId: characterId,
        attribute: '身世',
        value: '孤儿',
        chapter: 1, // 用户填的是**序位**（弹层标签「章节（可选，如：7）」）
      );
      expect(ok, isTrue);
      final added = (await assertionsOf(characterId)).last;
      expect(added.source, 'user');
      expect(added.status, 'confirmed');
      expect(added.attribute, '身世');
      expect(added.value, '孤儿');
      expect(added.chapter, 1, reason: 'R1′：用户原写的数原样保留');
      expect(added.chapterSortOrder, 7, reason: 'N12-F3b：写库前归一成身份');
      expect(added.chapterHash, isNotNull, reason: '手写断言同参 stale 规则');
    });

    test('章号空 / 序位不存在 → 身份与 chapterHash 均 null（不猜）', () async {
      await editor.addUserAssertion(
        characterId: characterId,
        attribute: '习惯',
        value: '夜巡',
      );
      await editor.addUserAssertion(
        characterId: characterId,
        attribute: '口头禅',
        value: '有意思',
        chapter: 99,
      );
      final list = await assertionsOf(characterId);
      final noChapter = list.lastWhere((a) => a.value == '夜巡');
      expect(noChapter.chapterHash, isNull);
      expect(noChapter.chapterSortOrder, isNull);

      final outOfRange = list.lastWhere((a) => a.value == '有意思');
      expect(outOfRange.chapter, 99, reason: 'R1′：越界也保留用户原值');
      expect(
        outOfRange.chapterSortOrder,
        isNull,
        reason: '序位 99 不存在 ⇒ 不猜（ADR-C95 裁定 2）',
      );
      expect(outOfRange.chapterHash, isNull);
    });

    test('属性或值为空 → false', () async {
      expect(
        await editor.addUserAssertion(
          characterId: characterId,
          attribute: '',
          value: 'x',
        ),
        isFalse,
      );
      expect(
        await editor.addUserAssertion(
          characterId: characterId,
          attribute: 'x',
          value: '',
        ),
        isFalse,
      );
    });
  });

  group('updateAliases', () {
    test('trim + 去空 + 去重保序（V-05 #11 引用式副本语义）', () async {
      final ok = await editor.updateAliases(
        characterId: characterId,
        aliases: [' 阿晴 ', '晚晴', '', '阿晴', '阿晴 '],
      );
      expect(ok, isTrue);
      final row = await factRepo.getCharacterById(characterId);
      expect(row!.aliases, '["阿晴","晚晴"]');
    });
  });
}
