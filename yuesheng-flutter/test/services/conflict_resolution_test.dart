// ─────────────────────────────────────────────────────────────
// conflict_resolution_test — 设定资料库第二批·AI 辅助比较
//
// 覆盖：
//   1. 纯函数 detectCharacterConflicts：同章/均无章命中、跨章不算、
//      rejected/superseded 排除、首对防 N²、稳定排序
//   2. buildConflictComparisonPrompt：正常渲染 + 不代决语义
//   3. UI：对照面板三选一 / AI 按钮 / 取消 / 「两者都保留」
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/services/setting_library_service.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/widgets/character/character_dialogs.dart';

const _a = CharacterAssertion(
  attribute: '身份',
  value: '捕快',
  chapter: 3,
  timestamp: 1,
);
const _b = CharacterAssertion(
  attribute: '身份',
  value: '画师',
  chapter: 3,
  timestamp: 2,
);

void main() {
  group('1. detectCharacterConflicts 纯函数', () {
    test('#1 同章同属性异值 → 命中', () {
      final out = detectCharacterConflicts([('林晚', _a), ('林晚', _b)]);
      expect(out, hasLength(1));
      expect(out.single.name, '林晚');
      expect(out.single.a.value, '捕快');
      expect(out.single.b.value, '画师');
    });

    test('#2 均未标章同属性异值 → 命中（章节 null 归一组）', () {
      const a1 = CharacterAssertion(attribute: '身份', value: '捕快', timestamp: 1);
      const a2 = CharacterAssertion(attribute: '身份', value: '画师', timestamp: 2);
      final out = detectCharacterConflicts([('林晚', a1), ('林晚', a2)]);
      expect(out, hasLength(1));
    });

    test('#3 跨章异值 → 不算（时序演进防误杀）', () {
      const a1 = CharacterAssertion(
        attribute: '身份',
        value: '捕快',
        chapter: 3,
        timestamp: 1,
      );
      const a2 = CharacterAssertion(
        attribute: '身份',
        value: '捕头',
        chapter: 10,
        timestamp: 2,
      );
      expect(detectCharacterConflicts([('林晚', a1), ('林晚', a2)]), isEmpty);
    });

    test('#4 同值不冲突', () {
      const same = CharacterAssertion(
        attribute: '身份',
        value: '捕快',
        chapter: 3,
        timestamp: 9,
      );
      expect(detectCharacterConflicts([('林晚', _a), ('林晚', same)]), isEmpty);
    });

    test('#5 rejected / superseded 排除', () {
      final rejected = _b.withStatus('rejected');
      final superseded = _b.withStatus('superseded');
      expect(detectCharacterConflicts([('林晚', _a), ('林晚', rejected)]), isEmpty);
      expect(
        detectCharacterConflicts([('林晚', _a), ('林晚', superseded)]),
        isEmpty,
      );
    });

    test('#6 同属性三值 → 只取首对（防 N²）', () {
      const c = CharacterAssertion(
        attribute: '身份',
        value: '画家',
        chapter: 3,
        timestamp: 3,
      );
      final out = detectCharacterConflicts([('林晚', _a), ('林晚', _b), ('林晚', c)]);
      expect(out, hasLength(1), reason: '每组冲突只报首对');
    });

    test('#7 跨人物/属性互不影响 + 稳定排序', () {
      const d1 = CharacterAssertion(
        attribute: '性格',
        value: '冷酷',
        chapter: 1,
        timestamp: 1,
      );
      const d2 = CharacterAssertion(
        attribute: '性格',
        value: '温和',
        chapter: 1,
        timestamp: 2,
      );
      const e1 = CharacterAssertion(
        attribute: '职业',
        value: '捕快',
        chapter: 5,
        timestamp: 1,
      );
      const e2 = CharacterAssertion(
        attribute: '职业',
        value: '画师',
        chapter: 5,
        timestamp: 2,
      );
      final out = detectCharacterConflicts([
        ('沈砚', d1),
        ('沈砚', d2),
        ('林晚', e1),
        ('林晚', e2),
      ]);
      expect(out, hasLength(2));
      expect(out.first.name, '林晚', reason: '按人物名升序');
      expect(out.first.a.attribute, '职业');
    });
  });

  group('2. buildConflictComparisonPrompt', () {
    test('#8 渲染两条断言 + 不代决语义', () {
      final prompt = buildConflictComparisonPrompt(name: '林晚', a: _a, b: _b);
      expect(prompt, contains('人物：林晚'));
      expect(prompt, contains('第3章'));
      expect(prompt, contains('身份 = 捕快'));
      expect(prompt, contains('身份 = 画师'));
      expect(prompt, contains('最终由你决定'));
    });
  });

  group('3. UI 对照面板', () {
    testWidgets('#9 三选一：保留 A 返回 keepA 并落库回调', (tester) async {
      MergeVerdict? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    picked = await showConflictResolutionDialog(
                      context,
                      pair: const AssertionConflictPair(
                        name: '林晚',
                        a: _a,
                        b: _b,
                      ),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('疑似重复：身份'), findsOneWidget);
      expect(find.text('身份 = 捕快'), findsOneWidget);
      expect(find.text('身份 = 画师'), findsOneWidget);

      await tester.tap(find.text('保留').first);
      await tester.pumpAndSettle();
      expect(picked, MergeVerdict.keepA);
    });

    testWidgets('#10 两者都保留返回 keepBoth', (tester) async {
      MergeVerdict? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    picked = await showConflictResolutionDialog(
                      context,
                      pair: const AssertionConflictPair(
                        name: '林晚',
                        a: _a,
                        b: _b,
                      ),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('两者都保留'));
      await tester.pumpAndSettle();
      expect(picked, MergeVerdict.keepBoth);
    });

    testWidgets('#11 取消返回 null（不落库）', (tester) async {
      MergeVerdict? picked = MergeVerdict.keepA;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () async {
                    picked = await showConflictResolutionDialog(
                      context,
                      pair: const AssertionConflictPair(
                        name: '林晚',
                        a: _a,
                        b: _b,
                      ),
                    );
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });

    testWidgets('#12 AI 帮我比较：点击展示分析（纯文本）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showConflictResolutionDialog(
                    context,
                    pair: const AssertionConflictPair(name: '林晚', a: _a, b: _b),
                    aiCompare: () async => '分析：捕快 vs 画师可能并存（职业侧面）。',
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('AI 帮我比较（纯分析）'), findsOneWidget);
      await tester.tap(find.text('AI 帮我比较（纯分析）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('捕快 vs 画师'), findsOneWidget);
    });
  });
}
