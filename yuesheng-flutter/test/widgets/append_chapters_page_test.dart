// ─────────────────────────────────────────────────────────────
// append_chapters_page_test — 追加章节导入页 Widget 测试
//
// 覆盖路径：
//   #1 空态渲染（标题/选择导入方式/选择文件按钮）
//   #2 选择文件取消 → 无章节列表
//   #3 解析渲染 → 章节列表（标题/字数/已选计数）
//   #4 已存在章节 → 徽标 + 默认不选中
//   #5 已存在章节禁选（点击不增加选中）
//   #6 全选 / 取消
//   #7 取消全选后确认按钮禁用
//   #8 确认导入 → createChaptersBatch 落库 + ImportSuccessSheet
//   #9 成功弹层「稍后再说」→ 回稿件详情
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/append_chapters_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost({
    required Future<List<AppendChapterItem>?> Function() loader,
  }) {
    final router = GoRouter(
      initialLocation: '/append',
      routes: [
        GoRoute(
          path: '/append',
          builder: (context, state) => AppendChaptersPage(
            manuscriptId: manuscriptId,
            manuscriptTitle: '测试作品',
            pickAndParseOverride: loader,
          ),
        ),
        GoRoute(
          path: '/manuscript-detail',
          builder: (context, state) => const Scaffold(body: Text('稿件详情测试页')),
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// 注入解析结果：选择文件后返回给定章节
  Future<List<AppendChapterItem>?> Function() loaderOf(
    List<AppendChapterItem> chapters,
  ) {
    return () async => chapters;
  }

  Future<void> pickFile(WidgetTester tester) async {
    await tester.tap(find.text('选择文件'));
    await tester.pumpAndSettle();
  }

  group('AppendChaptersPage', () {
    testWidgets('#1 空态渲染', (tester) async {
      await tester.pumpWidget(buildHost(loader: loaderOf([])));
      await tester.pumpAndSettle();

      expect(find.text('追加章节'), findsOneWidget);
      expect(find.text('选择导入方式'), findsOneWidget);
      expect(find.text('将新章节追加到「测试作品」'), findsOneWidget);
      expect(find.text('选择文件'), findsOneWidget);
      // 未解析前无章节列表与确认栏
      expect(find.text('章节列表'), findsNothing);
      expect(find.text('确认导入'), findsNothing);
    });

    testWidgets('#2 选择文件取消 → 无章节列表', (tester) async {
      await tester.pumpWidget(buildHost(loader: () async => null));
      await tester.pumpAndSettle();

      await pickFile(tester);

      expect(find.text('章节列表'), findsNothing);
      expect(find.text('确认导入'), findsNothing);
      // 空态仍保留
      expect(find.text('选择文件'), findsOneWidget);
    });

    testWidgets('#3 解析渲染 → 章节列表', (tester) async {
      await tester.pumpWidget(
        buildHost(
          loader: loaderOf([
            const AppendChapterItem(title: '第一章：启程', content: '第一章内容'),
            const AppendChapterItem(title: '第二章：相遇', content: '第二章内容'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await pickFile(tester);

      expect(find.text('章节列表'), findsOneWidget);
      expect(find.text('第一章：启程'), findsOneWidget);
      expect(find.text('第二章：相遇'), findsOneWidget);
      // 字数
      expect(find.text('5 字'), findsNWidgets(2));
      // 全部新章节默认选中
      expect(find.text('已选 2 章'), findsOneWidget);
      // 底部确认栏
      expect(find.text('确认导入'), findsOneWidget);
    });

    testWidgets('#4 已存在章节 → 徽标 + 默认不选中', (tester) async {
      // 预置同名章节
      await ChapterRepository(db).createChapter(manuscriptId, title: '第一章：启程');
      await tester.pumpWidget(
        buildHost(
          loader: loaderOf([
            const AppendChapterItem(title: '第一章：启程', content: '正文'),
            const AppendChapterItem(title: '第二章：相遇', content: '正文二'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await pickFile(tester);

      expect(find.text('已存在'), findsOneWidget);
      // 说明：共 2 章，1 章新增
      expect(find.text('已存在的章节会被标记，默认不选中（共 2 章，1 章新增）'), findsOneWidget);
      // 只有新增章节被选中
      expect(find.text('已选 1 章'), findsOneWidget);
    });

    testWidgets('#5 已存在章节禁选', (tester) async {
      await ChapterRepository(db).createChapter(manuscriptId, title: '第一章：启程');
      await tester.pumpWidget(
        buildHost(
          loader: loaderOf([
            const AppendChapterItem(title: '第一章：启程', content: '正文'),
            const AppendChapterItem(title: '第二章：相遇', content: '正文二'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await pickFile(tester);

      // 点击已存在章节行不增加选中
      await tester.tap(find.text('第一章：启程'));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 章'), findsOneWidget);
    });

    testWidgets('#6 全选 / 取消', (tester) async {
      // 全部为新章节：初始全选 2 章；取消 → 0；全选 → 2
      // （对齐 RN handleSelectAll 语义：全选仅作用于非已存在章节）
      await tester.pumpWidget(
        buildHost(
          loader: loaderOf([
            const AppendChapterItem(title: '第一章：启程', content: '正文'),
            const AppendChapterItem(title: '第二章：相遇', content: '正文二'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await pickFile(tester);
      expect(find.text('已选 2 章'), findsOneWidget);

      // 取消 → 0 章
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 章'), findsOneWidget);

      // 全选 → 2 章
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('已选 2 章'), findsOneWidget);
    });

    testWidgets('#7 取消全选后确认按钮禁用', (tester) async {
      await tester.pumpWidget(
        buildHost(
          loader: loaderOf([
            const AppendChapterItem(title: '第一章', content: '正文'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await pickFile(tester);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('#8 确认导入 → 落库 + 成功弹层', (tester) async {
      await tester.pumpWidget(
        buildHost(
          loader: loaderOf([
            const AppendChapterItem(title: '第一章：启程', content: '第一章内容'),
            const AppendChapterItem(title: '第二章：相遇', content: '第二章内容'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await pickFile(tester);
      await tester.tap(find.text('确认导入'));
      await tester.pumpAndSettle();

      // 落库：新增 2 章
      final repo = ChapterRepository(db);
      final chapters = await repo.listChapters(manuscriptId);
      expect(chapters.length, 2);
      expect(chapters[0].title, '第一章：启程');
      expect(chapters[1].title, '第二章：相遇');

      // 成功弹层（批次78：追加章节不触发诊断 → 单按钮「返回作品」，无诊断引导）
      expect(find.text('导入成功！'), findsOneWidget);
      expect(find.textContaining('已成功导入 2 个章节'), findsOneWidget);
      expect(find.text('返回作品'), findsOneWidget);
      expect(find.text('立即诊断'), findsNothing);
      expect(find.text('稍后再说'), findsNothing);
    });

    testWidgets('#9 成功弹层「返回作品」→ 回稿件详情', (tester) async {
      await tester.pumpWidget(
        buildHost(
          loader: loaderOf([
            const AppendChapterItem(title: '第一章', content: '正文'),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await pickFile(tester);
      await tester.tap(find.text('确认导入'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('返回作品'));
      await tester.pumpAndSettle();

      expect(find.text('稿件详情测试页'), findsOneWidget);
    });
  });
}
