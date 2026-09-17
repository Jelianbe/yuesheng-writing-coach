// ─────────────────────────────────────────────────────────────
// template_learning_test — 设定资料库第二批·模板可学习
//
// 覆盖：
//   1. 常量：静态基础模板非空 + 阈值/上限常量
//   2. repo：listLearnedAttributes 计数/阈值（≥2 回填）/排序/
//      AI 断言不计入/无重复/截断
//   3. UI：断言表单 chips 渲染 + 点击回填属性框（widget）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/widgets/character/character_dialogs.dart';

void main() {
  group('1. 常量', () {
    test('#1 静态基础模板非空且含常用属性', () {
      expect(AttributeTemplate.suggestions, isNotEmpty);
      expect(AttributeTemplate.suggestions, contains('性格'));
      expect(AttributeTemplate.suggestions, contains('职业'));
      expect(AttributeTemplate.learnedMinUses, 2);
      expect(AttributeTemplate.learnedLimit, greaterThan(0));
    });
  });

  group('2. repo：listLearnedAttributes', () {
    late AppDatabase db;
    late CharacterFactRepository factRepo;
    late String manuscriptId;

    Future<void> seedUserAssertion(
      String name,
      String attribute,
      int count,
    ) async {
      await factRepo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: name,
        assertions: [
          for (var i = 0; i < count; i++)
            CharacterAssertion(
              attribute: attribute,
              value: '值$i',
              chapter: 1,
              timestamp: 1000 + i,
              source: 'user',
            ),
        ],
      );
    }

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      factRepo = CharacterFactRepository(db);
      manuscriptId = await ManuscriptRepository(
        db,
      ).createManuscript(title: '模板学习测试');
    });

    tearDown(() async => db.close());

    test('#2 属性名出现 1 次不学习（阈值 2）', () async {
      await seedUserAssertion('林晚', '口头禅', 1);
      expect(await factRepo.listLearnedAttributes(manuscriptId), isEmpty);
    });

    test('#3 属性名 ≥2 次回填', () async {
      await seedUserAssertion('林晚', '口头禅', 2);
      final learned = await factRepo.listLearnedAttributes(manuscriptId);
      expect(learned, contains('口头禅'));
    });

    test('#4 按次数降序排列', () async {
      await seedUserAssertion('林晚', '习惯', 3);
      await seedUserAssertion('沈砚', '经历', 2);
      final learned = await factRepo.listLearnedAttributes(manuscriptId);
      expect(learned.first, '习惯', reason: '3 次应排在 2 次前');
      expect(learned, ['习惯', '经历']);
    });

    test('#5 AI 断言（source=ai）不计入', () async {
      await factRepo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '林晚',
        assertions: const [
          CharacterAssertion(
            attribute: '性格',
            value: '冷酷',
            chapter: 1,
            timestamp: 1,
            source: 'ai',
          ),
          CharacterAssertion(
            attribute: '性格',
            value: '外冷内热',
            chapter: 2,
            timestamp: 2,
            source: 'ai',
          ),
        ],
      );
      expect(
        await factRepo.listLearnedAttributes(manuscriptId),
        isEmpty,
        reason: 'AI 抽取的属性名不参与模板学习（模板学的是用户词汇）',
      );
    });

    test('#6 跨角色计数 + 无重复输出', () async {
      await seedUserAssertion('林晚', '习惯', 1);
      await seedUserAssertion('沈砚', '习惯', 1);
      final learned = await factRepo.listLearnedAttributes(manuscriptId);
      expect(learned, ['习惯'], reason: '跨角色合计 2 次，输出无重复');
    });

    test('#7 截断上限 learnedLimit', () async {
      // 造 10 个属性各 2 次
      for (var i = 0; i < 10; i++) {
        await seedUserAssertion('角色$i', '属性$i', 2);
      }
      final learned = await factRepo.listLearnedAttributes(manuscriptId);
      expect(learned.length, lessThanOrEqualTo(AttributeTemplate.learnedLimit));
    });
  });

  group('3. UI：断言表单 chips', () {
    testWidgets('#8 chips 渲染 + 点击回填属性框', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => showAssertionFormDialog(
                    context,
                    title: '补充断言',
                    suggestions: const ['口头禅', '习惯'],
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

      expect(find.text('常用属性'), findsOneWidget);
      expect(find.text('口头禅'), findsOneWidget);
      expect(find.text('习惯'), findsOneWidget);

      await tester.tap(find.text('口头禅'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.widgetWithText(TextField, '口头禅')),
        isNotNull,
      );
    });

    testWidgets('#9 无建议时不渲染 chips 区', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () =>
                      showAssertionFormDialog(context, title: '补充断言'),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(find.text('常用属性'), findsNothing);
    });
  });
}
