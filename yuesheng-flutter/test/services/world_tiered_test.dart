// ─────────────────────────────────────────────────────────────
// world_tiered_test — 设定资料库·世界观接入分级供给 L1（命中展开 + 矛盾 + 冷元信息）
//
// 覆盖：
//   1. matchHitWorlds：name 命中 / 单字名跳过 / 未命中
//   2. buildWorldHitContext：命中展开 / rejected 排除 / 命中矛盾过滤 /
//      冷元信息 / 空世界观零注入
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/types/character_types.dart';

WorldFact makeWorld(
  String name, {
  List<CharacterAssertion> assertions = const [],
}) {
  return WorldFact(
    id: name,
    manuscriptId: 'm1',
    name: name,
    firstSeenChapter: 1,
    firstSeenAt: 1,
    assertions: jsonEncode([for (final a in assertions) a.toJson()]),
    description: '',
    status: 'active',
    createdAt: 1,
    updatedAt: 1,
  );
}

const _confirmed = CharacterAssertion(
  attribute: '灵气',
  value: '稀薄',
  chapter: 1,
  timestamp: 1,
  status: 'confirmed',
);
const _rejected = CharacterAssertion(
  attribute: '时代',
  value: '大唐',
  chapter: 1,
  timestamp: 2,
  status: 'rejected',
);

void main() {
  final worlds = [
    makeWorld('灵气体系', assertions: const [_confirmed, _rejected]),
    makeWorld('朝廷格局'),
    makeWorld('朝'),
  ];

  group('1. matchHitWorlds', () {
    test('#1 正文命中 name', () {
      final hits = matchHitWorlds(
        chapterContent: '灵气体系在百年内衰退。',
        userText: '',
        worlds: worlds,
      );
      expect(hits, ['灵气体系']);
    });

    test('#2 用户消息命中', () {
      final hits = matchHitWorlds(
        chapterContent: '',
        userText: '朝廷格局怎么样了？',
        worlds: worlds,
      );
      expect(hits, ['朝廷格局']);
    });

    test('#3 单字名不参与', () {
      final hits = matchHitWorlds(
        chapterContent: '朝堂之上。',
        userText: '',
        worlds: worlds,
      );
      expect(hits, isEmpty);
    });

    test('#4 未命中返回空', () {
      final hits = matchHitWorlds(
        chapterContent: '街市熙攘。',
        userText: '',
        worlds: worlds,
      );
      expect(hits, isEmpty);
    });
  });

  group('2. buildWorldHitContext', () {
    test('#5 命中展开 + rejected 排除 + 冷元信息', () {
      final ctx = buildWorldHitContext(
        hitNames: const ['灵气体系'],
        worlds: worlds,
        conflicts: const [],
      );
      expect(ctx, isNotNull);
      expect(ctx, contains('灵气=稀薄'));
      expect(ctx, isNot(contains('大唐')), reason: 'rejected 不展开');
      expect(ctx, contains('未提及的设定主题共 2 条'));
    });

    test('#6 命中主题矛盾过滤（只报命中主题）', () {
      final conflicts = [
        WorldConflictObservation(
          themeName: '灵气体系',
          attribute: '灵气',
          orderedValues: const [_confirmed],
          description: '「稀薄」与「浓郁」并存',
          excerpt: '…',
        ),
        WorldConflictObservation(
          themeName: '朝廷格局',
          attribute: '皇权',
          orderedValues: const [_confirmed],
          description: '未命中主题的矛盾不应出现',
          excerpt: '…',
        ),
      ];
      final ctx = buildWorldHitContext(
        hitNames: const ['灵气体系'],
        worlds: worlds,
        conflicts: conflicts,
      );
      expect(ctx, contains('灵气体系'));
      expect(ctx, contains('稀薄」与「浓郁'));
      expect(ctx, isNot(contains('皇权')), reason: '未命中主题的矛盾不报');
    });

    test('#7 全部命中 → 无冷元信息', () {
      final allHitWorlds = [
        makeWorld('灵气体系', assertions: const [_confirmed]),
        makeWorld('朝廷格局'),
      ];
      final ctx = buildWorldHitContext(
        hitNames: const ['灵气体系', '朝廷格局'],
        worlds: allHitWorlds,
        conflicts: const [],
      );
      expect(ctx, isNot(contains('未提及')));
    });

    test('#8 空世界观 → null（零注入）', () {
      expect(
        buildWorldHitContext(
          hitNames: const [],
          worlds: const [],
          conflicts: const [],
        ),
        isNull,
      );
    });

    test('#9 未命中但世界观非空 → 仅冷元信息', () {
      final ctx = buildWorldHitContext(
        hitNames: const [],
        worlds: worlds,
        conflicts: const [],
      );
      expect(ctx, isNotNull);
      expect(ctx, contains('未提及的设定主题共 3 条'));
    });
  });
}
