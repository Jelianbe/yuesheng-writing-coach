// ─────────────────────────────────────────────────────────────
// AdoptSuggestionSheet widget 测试 — 采纳建议弹窗
//
// 覆盖路径：
//   #1 渲染：标题 + 建议预览 + 局部合并 + 替换全部（无备份时不显示撤销）
//   #2 局部合并 → DB 内容 = 原文 + 建议，原文保留
//   #3 局部合并后 → previous_content 备份了原文
//   #4 有 previous_content → 显示撤销上次采纳 → 点击恢复原文
//   #5 替换全部 → 二次确认（取消不变 / 确认替换）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/adopt_suggestion_sheet.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String chapterId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final msId = await msRepo.createManuscript(title: '测试作品');
    chapterId = await chRepo.createChapter(
      msId,
      title: '第一章',
      content: '原文段落一。\n\n原文段落二。',
    );
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildSheetHost({required String suggestion}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => AdoptSuggestionSheet.show(
                context,
                chapterId: chapterId,
                suggestion: suggestion,
                onAdopted: () {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  group('AdoptSuggestionSheet', () {
    testWidgets('#1 渲染：标题 + 建议预览 + 局部合并 + 替换全部（无撤销按钮）', (tester) async {
      await tester.pumpWidget(buildSheetHost(suggestion: 'AI改写的建议内容'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('采纳建议'), findsOneWidget);
      expect(find.text('AI改写的建议内容'), findsOneWidget);
      expect(find.text('局部合并'), findsOneWidget);
      expect(find.text('替换全部'), findsOneWidget);
      // 无 previous_content 时，撤销按钮不应显示
      expect(find.text('撤销上次采纳'), findsNothing);
    });

    testWidgets('#2 局部合并 → DB 内容 = 原文 + 建议，原文保留', (tester) async {
      await tester.pumpWidget(buildSheetHost(suggestion: 'AI建议段落'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('局部合并'));
      await tester.pumpAndSettle();

      final chRepo = ChapterRepository(db);
      final ch = await chRepo.getChapter(chapterId);
      expect(ch!.content, contains('原文段落一'));
      expect(ch.content, contains('原文段落二'));
      expect(ch.content, contains('AI建议段落'));
      // 建议被追加到末尾
      expect(ch.content, endsWith('AI建议段落'));
    });

    testWidgets('#3 局部合并后 → previous_content 备份了原文（不含建议）', (tester) async {
      await tester.pumpWidget(buildSheetHost(suggestion: 'AI建议'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('局部合并'));
      await tester.pumpAndSettle();

      final chRepo = ChapterRepository(db);
      final ch = await chRepo.getChapter(chapterId);
      expect(ch!.previousContent, isNotNull);
      expect(ch.previousContent, contains('原文段落一'));
      expect(ch.previousContent, contains('原文段落二'));
      expect(ch.previousContent, isNot(contains('AI建议')));
    });

    testWidgets('#4 有 previous_content → 显示撤销上次采纳 → 点击恢复原文', (tester) async {
      // 预置：先做一次采纳，产生 previous_content
      final chRepo = ChapterRepository(db);
      await chRepo.adoptContentToChapter(chapterId, '第一次采纳的内容');
      // 此时 content='第一次采纳的内容', previous_content='原文段落一...\n\n原文段落二...'

      await tester.pumpWidget(buildSheetHost(suggestion: '第二次建议'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 撤销按钮应显示（previous_content 存在）
      expect(find.text('撤销上次采纳'), findsOneWidget);

      await tester.tap(find.text('撤销上次采纳'));
      await tester.pumpAndSettle();

      // 内容应恢复为原文
      final ch = await chRepo.getChapter(chapterId);
      expect(ch!.content, contains('原文段落一'));
      expect(ch.content, contains('原文段落二'));
      expect(ch.content, isNot(contains('第一次采纳的内容')));
      // previous_content 应被清空
      expect(ch.previousContent, isNull);
    });

    testWidgets('#5 替换全部 → 二次确认（取消不变 / 确认则完全替换 + 备份）', (tester) async {
      await tester.pumpWidget(buildSheetHost(suggestion: 'AI完全改写的内容'));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 点击替换全部 → 弹出二次确认
      await tester.tap(find.text('替换全部'));
      await tester.pumpAndSettle();

      expect(find.text('此操作将用AI改写完全替换章节原有内容，原文可通过撤销上次采纳恢复'), findsOneWidget);

      // 取消 → 内容不变
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      final chRepo = ChapterRepository(db);
      var ch = await chRepo.getChapter(chapterId);
      expect(ch!.content, contains('原文段落一'));
      expect(ch.content, isNot(contains('AI完全改写的内容')));

      // 再次点击替换全部并确认
      await tester.tap(find.text('替换全部'));
      await tester.pumpAndSettle();

      expect(find.text('此操作将用AI改写完全替换章节原有内容，原文可通过撤销上次采纳恢复'), findsOneWidget);
      await tester.tap(find.text('确认替换'));
      await tester.pumpAndSettle();

      ch = await chRepo.getChapter(chapterId);
      expect(ch!.content, 'AI完全改写的内容');
      // 原文已备份到 previous_content
      expect(ch.previousContent, isNotNull);
      expect(ch.previousContent, contains('原文段落一'));
    });
  });
}
