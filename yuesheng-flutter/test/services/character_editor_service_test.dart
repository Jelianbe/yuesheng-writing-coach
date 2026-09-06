// ─────────────────────────────────────────────────────────────
// character_editor_service_test — C78 批次3 断言级人工裁决单测
//
// 覆盖（ADR-C78 §6 / FR-5）：
//   1. rejectAssertion：状态改 rejected + 理由落库（D-7 chips 载体）
//      + 直接拒绝（无理由）→ rejectReason 保持 null
//   2. reject 不存在的行 / 不存在的断言 / 重复拒绝 → false（零写）
//   3. correctAssertion：原条 rejected 留痕 + 新增 source=user 断言
//   4. addUserAssertion：chapterHash 按该章正文指纹（§5.1(c)）；
//      章号空 / 章节不存在 → hash null（不猜）
//   5. 属性/值为空 → false（R-028 边界校验）
//   6. updateAliases：trim + 去空 + 去重保序
//   7. 改写不碰其他断言（逐字段保留）
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
      // 另一条不受影响
      expect(list.firstWhere((a) => a.value == '捕快').status, 'confirmed');
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
  });

  group('addUserAssertion', () {
    test('写入 user 断言 + 该章正文指纹（§5.1(c)）', () async {
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
        chapter: 7,
      );
      expect(ok, isTrue);
      final added = (await assertionsOf(characterId)).last;
      expect(added.source, 'user');
      expect(added.status, 'confirmed');
      expect(added.attribute, '身世');
      expect(added.value, '孤儿');
      expect(added.chapter, 7);
      expect(added.chapterHash, isNotNull, reason: '手写断言同参 stale 规则');
    });

    test('章号空 / 章节不存在 → chapterHash null（不猜）', () async {
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
      expect(list.lastWhere((a) => a.value == '夜巡').chapterHash, isNull);
      expect(list.lastWhere((a) => a.value == '有意思').chapterHash, isNull);
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
