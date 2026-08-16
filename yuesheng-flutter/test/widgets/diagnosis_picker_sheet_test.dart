// ─────────────────────────────────────────────────────────────
// DiagnosisPickerSheet 测试 — 诊断章节选择弹层（缺口清单第 7 项）
//
// 覆盖：作品列表渲染 / 展开章节 / 选章回调 / 短章节提示 /
// 空态引导 / 加载更多。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/diagnosis_picker_sheet.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Widget buildSheet({required DiagnosisChapterCallback onSelect}) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => DiagnosisPickerSheet(onSelect: onSelect),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 打开弹层
  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  const longContent =
      '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，'
      '远处的山峦在暮色中显得格外孤寂。一位旅人独自走在雪地里，'
      '身后留下一串深深浅浅的脚印，很快又被新雪覆盖。'
      '他裹紧了身上的斗篷，目光投向远方那点若隐若现的灯火。';

  testWidgets('作品列表 + 展开章节 + 选章回调', (tester) async {
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final msId = await msRepo.createManuscript(title: '测试作品');
    await chRepo.createChapter(msId, title: '第一章：启程', content: longContent);

    String? selectedMsId;
    String? selectedChapterId;
    await tester.pumpWidget(
      buildSheet(
        onSelect: (msId, chapter) {
          selectedMsId = msId;
          selectedChapterId = chapter.id;
        },
      ),
    );
    await openSheet(tester);

    // 作品行
    expect(find.text('测试作品'), findsOneWidget);
    expect(find.text('选择要诊断的章节'), findsOneWidget);

    // 展开章节
    await tester.tap(find.text('测试作品'));
    await tester.pumpAndSettle();
    expect(find.text('第一章：启程'), findsOneWidget);
    expect(find.textContaining('字'), findsOneWidget);

    // 选章 → 回调
    await tester.tap(find.text('第一章：启程'));
    await tester.pumpAndSettle();

    expect(selectedMsId, msId);
    expect(selectedChapterId, isNotNull);
    expect(selectedChapterId, isNotEmpty);
  });

  testWidgets('短章节（<100 字）→ 提示且不回调', (tester) async {
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final msId = await msRepo.createManuscript(title: '短作品');
    final shortChapterId = await chRepo.createChapter(
      msId,
      title: '短章',
      content: '太短了。',
    );

    var called = false;
    await tester.pumpWidget(
      buildSheet(onSelect: (msId, chapter) => called = true),
    );
    await openSheet(tester);

    await tester.tap(find.text('短作品'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('短章'));
    await tester.pumpAndSettle();

    expect(find.text('章节内容少于 100 字，请先编辑章节'), findsOneWidget);
    expect(called, isFalse);
    expect(shortChapterId, isNotEmpty);
  });

  testWidgets('空库 → 显示「还没有作品」引导', (tester) async {
    await tester.pumpWidget(buildSheet(onSelect: (msId, chapter) {}));
    await openSheet(tester);

    expect(find.text('还没有作品'), findsOneWidget);
    expect(find.text('去书架创建 →'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('章节数超过初始 50 → 显示「加载更多」', (tester) async {
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final msId = await msRepo.createManuscript(title: '多章作品');
    for (var i = 0; i < 55; i++) {
      await chRepo.createChapter(msId, title: '第 $i 章', content: longContent);
    }

    await tester.pumpWidget(buildSheet(onSelect: (msId, chapter) {}));
    await openSheet(tester);

    await tester.tap(find.text('多章作品'));
    await tester.pumpAndSettle();

    // 初始仅显示前 50 章（第 0 章可见，第 50 章不存在）
    expect(find.text('第 0 章'), findsOneWidget);
    expect(find.text('第 50 章'), findsNothing);

    // 滚动到列表末尾的「加载更多」（ensureVisible 后需 pump 使布局真正更新）
    await tester.scrollUntilVisible(
      find.text('加载更多（5 章未显示）'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('加载更多（5 章未显示）'), findsOneWidget);

    // 加载更多 → 全部章节可渲染（章节列为非懒加载 Column，直接断言树内存在）
    await tester.tap(find.text('加载更多（5 章未显示）'));
    await tester.pumpAndSettle();

    expect(find.text('第 54 章'), findsOneWidget);
    expect(find.textContaining('加载更多'), findsNothing);
  });
}
