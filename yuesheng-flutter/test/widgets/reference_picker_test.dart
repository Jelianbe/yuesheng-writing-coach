// ─────────────────────────────────────────────────────────────
// ReferencePicker widget 测试 — 引用选择器
//
// 覆盖路径：
//   1. 无稿件 → 空态
//   2. 「引用整本书」→ onSelect('manuscript', msId, title) + 关闭
//   3. 展开章节 → 点章节 → onSelect('chapter', chId, title)
//   4. 素材 Tab → 点素材 → onSelect('file', fileId, title)
//   5. 取消 → 关闭且不触发 onSelect
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/reference_picker.dart';

void main() {
  late AppDatabase db;
  late ManuscriptRepository msRepo;
  late ChapterRepository chRepo;
  late ReferenceRepository refRepo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    msRepo = ManuscriptRepository(db);
    chRepo = ChapterRepository(db);
    refRepo = ReferenceRepository(db);
  });

  tearDown(() async => db.close());

  Widget buildHost(
    void Function(String refType, String refId, String title)? onSelect,
  ) {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ReferencePicker(onSelect: onSelect),
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openPicker(
    WidgetTester tester,
    void Function(String refType, String refId, String title)? onSelect,
  ) async {
    await tester.pumpWidget(buildHost(onSelect));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('#1 无稿件 → 作品 Tab 空态', (tester) async {
    await openPicker(tester, null);

    expect(find.text('选择引用'), findsOneWidget);
    expect(find.text('还没有作品'), findsOneWidget);
  });

  testWidgets('#2 「引用整本书」→ onSelect(manuscript) + 弹层关闭', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说', genre: '小说');
    String? gotType;
    String? gotId;
    String? gotTitle;

    await openPicker(tester, (t, id, title) {
      gotType = t;
      gotId = id;
      gotTitle = title;
    });

    expect(find.text('测试小说'), findsOneWidget);
    await tester.tap(find.text('引用整本书'));
    await tester.pumpAndSettle();

    expect(gotType, 'manuscript');
    expect(gotId, msId);
    expect(gotTitle, '测试小说');
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('#3 展开章节 → 点章节 → onSelect(chapter)', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final chId = await chRepo.createChapter(
      msId,
      title: '第一章 启程',
      content: '正文',
      sortOrder: 1,
    );
    String? gotType;
    String? gotId;

    await openPicker(tester, (t, id, title) {
      gotType = t;
      gotId = id;
    });

    // 展开稿件行
    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();

    expect(find.text('第一章 启程'), findsOneWidget);
    await tester.tap(find.text('第一章 启程'));
    await tester.pumpAndSettle();

    expect(gotType, 'chapter');
    expect(gotId, chId);
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('#4 素材 Tab → 点素材 → onSelect(file)', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final file = await refRepo.createAttachedFile(
      bookId: msId,
      fileName: '大纲.txt',
      fileRole: 'outline',
      content: '第一卷内容',
    );
    String? gotType;
    String? gotId;

    await openPicker(tester, (t, id, title) {
      gotType = t;
      gotId = id;
    });

    // 切到素材 Tab，展开稿件组后显示文件
    await tester.tap(find.text('素材'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();

    expect(find.text('大纲.txt'), findsOneWidget);
    await tester.tap(find.text('大纲.txt'));
    await tester.pumpAndSettle();

    expect(gotType, 'file');
    expect(gotId, file.id);
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('#4b 批次77 素材 Tab 无素材 → 空态文案指向真实路径', (tester) async {
    // 无任何素材文件：作品 Tab 至少需要一篇作品才能切 Tab，但素材为空
    await msRepo.createManuscript(title: '测试小说');

    await openPicker(tester, null);

    await tester.tap(find.text('素材'));
    await tester.pumpAndSettle();

    expect(find.text('还没有素材文件'), findsOneWidget);
    // 批次77：不再指向不存在的「素材页」，改真实路径
    expect(find.text('在作品详情的「文件」中添加素材文件'), findsOneWidget);
    expect(find.textContaining('素材页'), findsNothing);
  });

  testWidgets('#5 取消 → 关闭且不触发 onSelect', (tester) async {
    await msRepo.createManuscript(title: '测试小说');
    var called = false;

    await openPicker(tester, (t, id, title) => called = true);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(called, isFalse);
    expect(find.text('选择引用'), findsNothing);
  });

  testWidgets('#6 mention 模式：显示路径徽章 + 选择回调 @路径', (tester) async {
    final msId = await msRepo.createManuscript(title: '测试小说');
    final chId = await chRepo.createChapter(
      msId,
      title: '第一章',
      content: '正文',
      sortOrder: 0,
    );
    String? gotPath;
    String? gotTitle;

    // mention 模式宿主
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => ReferencePicker(
                      mode: 'mention',
                      onSelectMention: (path, title) {
                        gotPath = path;
                        gotTitle = title;
                      },
                    ),
                  ),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    // 作品行显示 @测试小说 徽章（批次71：编号 @W001 → 文字标题）
    expect(find.text('@测试小说'), findsOneWidget);

    // 展开 → 章节徽章 @测试小说/第一章
    await tester.tap(find.text('测试小说'));
    await tester.pumpAndSettle();
    expect(find.text('@测试小说/第一章'), findsOneWidget);

    // 选章节 → 回调 @路径
    await tester.tap(find.text('第一章'));
    await tester.pumpAndSettle();

    expect(gotPath, '@[chapter:$chId]');
    expect(gotTitle, '测试小说 · 第一章');
    expect(find.text('选择引用'), findsNothing);
  });
}
