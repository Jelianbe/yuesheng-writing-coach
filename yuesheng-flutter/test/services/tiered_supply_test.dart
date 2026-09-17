// ─────────────────────────────────────────────────────────────
// tiered_supply_test — 设定资料库第二批·分级供给 L1（命中展开 + 元信息）
//
// 覆盖：
//   1. matchHitEntities：name 命中 / alias 命中 / 单字名跳过 /
//      跨正文与用户消息 / 未命中
//   2. buildHitSettingsContext：命中展开 / rejected 排除 / 截断上限 /
//      冷实体元信息 / 空输入零注入
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
    assertions: _encode(assertions),
    description: '',
    aliases: aliases,
    status: 'active',
    pinned: 0,
    createdAt: 1,
    updatedAt: 1,
  );
}

String _encode(List<CharacterAssertion> assertions) {
  return jsonEncode([for (final a in assertions) a.toJson()]);
}

const _confirmed = CharacterAssertion(
  attribute: '身份',
  value: '捕快',
  chapter: 3,
  timestamp: 1,
  status: 'confirmed',
);
const _pending = CharacterAssertion(
  attribute: '性格',
  value: '冷酷',
  chapter: 3,
  timestamp: 2,
  status: 'pending',
);
const _rejected = CharacterAssertion(
  attribute: '职业',
  value: '画师',
  chapter: 3,
  timestamp: 3,
  status: 'rejected',
);

void main() {
  group('1. matchHitEntities', () {
    final characters = [
      makeCharacter('林晚', aliases: '["阿禾"]'),
      makeCharacter('沈砚'),
      makeCharacter('王'), // 单字名不参与
    ];

    test('#1 正文命中 name', () {
      final hits = matchHitEntities(
        chapterContent: '林晚走进客栈。',
        userText: '',
        characters: characters,
      );
      expect(hits, ['林晚']);
    });

    test('#2 用户消息命中 alias', () {
      final hits = matchHitEntities(
        chapterContent: '',
        userText: '阿禾后来怎么了？',
        characters: characters,
      );
      expect(hits, ['林晚']);
    });

    test('#3 单字名不参与（防误伤）', () {
      final hits = matchHitEntities(
        chapterContent: '王大人驾到。',
        userText: '',
        characters: characters,
      );
      expect(hits, isEmpty);
    });

    test('#4 跨正文与消息合并命中多个', () {
      final hits = matchHitEntities(
        chapterContent: '林晚拔出刀。',
        userText: '沈砚在哪？',
        characters: characters,
      );
      expect(hits, ['林晚', '沈砚'], reason: '按名字升序去重');
    });

    test('#5 未命中返回空', () {
      final hits = matchHitEntities(
        chapterContent: '街市熙攘。',
        userText: '',
        characters: characters,
      );
      expect(hits, isEmpty);
    });
  });

  group('2. buildHitSettingsContext', () {
    test('#6 命中展开 + rejected 排除', () {
      final characters = [
        makeCharacter(
          '林晚',
          assertions: const [_confirmed, _pending, _rejected],
        ),
      ];
      final ctx = buildHitSettingsContext(
        hitNames: const ['林晚'],
        characters: characters,
      );
      expect(ctx, isNotNull);
      expect(ctx, contains('人物「林晚」'));
      expect(ctx, contains('身份=捕快'));
      expect(ctx, contains('性格=冷酷'));
      expect(ctx, isNot(contains('画师')), reason: 'rejected 不展开');
    });

    test('#7 冷实体元信息（未提及计数）', () {
      final characters = [
        makeCharacter('林晚', assertions: const [_confirmed]),
        makeCharacter('沈砚', assertions: const [_confirmed]),
      ];
      final ctx = buildHitSettingsContext(
        hitNames: const ['林晚'],
        characters: characters,
      );
      expect(ctx, contains('未提及的设定共 1 条'));
      expect(ctx, contains('主动向学员询问'));
    });

    test('#8 全部命中 → 无冷实体元信息', () {
      final characters = [
        makeCharacter('林晚', assertions: const [_confirmed]),
      ];
      final ctx = buildHitSettingsContext(
        hitNames: const ['林晚'],
        characters: characters,
      );
      expect(ctx, isNot(contains('未提及的设定')));
    });

    test('#9 空命中 → null（零注入）', () {
      final ctx = buildHitSettingsContext(
        hitNames: const [],
        characters: const [],
      );
      expect(ctx, isNull);
    });

    test('#10 命中但全部断言被排除 → null', () {
      final characters = [
        makeCharacter('林晚', assertions: const [_rejected]),
      ];
      final ctx = buildHitSettingsContext(
        hitNames: const ['林晚'],
        characters: characters,
      );
      expect(ctx, isNull);
    });

    test('#11 每人物截断上限 kHitSettingMaxPerEntity', () {
      final many = [
        for (var i = 0; i < 12; i++)
          CharacterAssertion(
            attribute: '属性$i',
            value: '值$i',
            timestamp: i,
            status: 'confirmed',
          ),
      ];
      final characters = [makeCharacter('林晚', assertions: many)];
      final ctx = buildHitSettingsContext(
        hitNames: const ['林晚'],
        characters: characters,
      );
      expect(ctx, contains('属性0=值0'));
      expect(ctx, isNot(contains('属性11=值11')), reason: '超过 8 条截断');
    });
  });
}
