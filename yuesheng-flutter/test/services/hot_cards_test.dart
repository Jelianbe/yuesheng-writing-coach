// ─────────────────────────────────────────────────────────────
// hot_cards_test — 设定资料库第二批·分级供给 L2（热度驻留）
//
// 覆盖：
//   1. computeHotEntities：近轮提及计数 / 次数降序 / 单字名跳过 /
//      alias 计入 / 窗口截断 / 空输入
//   2. buildHotCardsContext：名片构造 / rejected 排除 / ≤3 条截断 /
//      空列表零注入
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/types/character_types.dart';

CharacterFact makeCharacter(
  String name, {
  String aliases = '[]',
  List<CharacterAssertion> assertions = const [],
}) {
  return CharacterFact(
    id: name,
    manuscriptId: 'm1',
    name: name,
    firstSeenChapter: 1,
    firstSeenAt: 1,
    assertions: jsonEncode([for (final a in assertions) a.toJson()]),
    description: '',
    aliases: aliases,
    status: 'active',
    pinned: 0,
    createdAt: 1,
    updatedAt: 1,
  );
}

const _confirmed = CharacterAssertion(
  attribute: '身份',
  value: '捕快',
  chapter: 3,
  timestamp: 1,
  status: 'confirmed',
);
const _rejected = CharacterAssertion(
  attribute: '职业',
  value: '画师',
  chapter: 3,
  timestamp: 2,
  status: 'rejected',
);

void main() {
  final characters = [
    makeCharacter('林晚', aliases: '["阿禾"]'),
    makeCharacter('沈砚'),
    makeCharacter('王'),
  ];

  group('1. computeHotEntities', () {
    test('#1 近轮提及计数 → 次数降序 Top N', () {
      final hot = computeHotEntities(
        recentUserTexts: const ['林晚走进客栈。', '林晚和沈砚对峙。', '林晚又出现了。'],
        characters: characters,
      );
      expect(hot, ['林晚', '沈砚']);
    });

    test('#2 alias 计入同一实体', () {
      final hot = computeHotEntities(
        recentUserTexts: const ['阿禾在江边。', '林晚拔刀。'],
        characters: characters,
      );
      expect(hot, ['林晚']);
    });

    test('#3 单字名不参与', () {
      final hot = computeHotEntities(
        recentUserTexts: const ['王大人驾到。'],
        characters: characters,
      );
      expect(hot, isEmpty);
    });

    test('#4 空输入 → 空', () {
      expect(
        computeHotEntities(recentUserTexts: const [], characters: characters),
        isEmpty,
      );
    });

    test('#5 max 截断', () {
      final hot = computeHotEntities(
        recentUserTexts: const ['林晚、沈砚、阿禾都在。', '林晚与沈砚同行。', '林晚。'],
        characters: characters,
        max: 1,
      );
      expect(hot, ['林晚']);
    });
  });

  group('2. buildHotCardsContext', () {
    test('#6 名片构造 + rejected 排除', () {
      final ctx = buildHotCardsContext([
        makeCharacter('林晚', assertions: const [_confirmed, _rejected]),
      ]);
      expect(ctx, isNotNull);
      expect(ctx, contains('近几轮常被提及'));
      expect(ctx, contains('身份=捕快'));
      expect(ctx, isNot(contains('画师')), reason: 'rejected 不进名片');
    });

    test('#7 每实体至多 3 条（kHotCardMaxAssertions）', () {
      final many = [
        for (var i = 0; i < 5; i++)
          CharacterAssertion(
            attribute: '属性$i',
            value: '值$i',
            timestamp: i,
            status: 'confirmed',
          ),
      ];
      final ctx = buildHotCardsContext([makeCharacter('林晚', assertions: many)]);
      expect(ctx, contains('属性0=值0'));
      expect(ctx, contains('属性2=值2'));
      expect(ctx, isNot(contains('属性4=值4')), reason: '超 3 条截断');
    });

    test('#8 空列表 → null（零注入）', () {
      expect(buildHotCardsContext(const []), isNull);
    });
  });
}
