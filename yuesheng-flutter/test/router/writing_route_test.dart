// ─────────────────────────────────────────────────────────────
// writing_route_test — /writing/:chapterId 路由集成测试
//
// 覆盖路径：
//   #1 导航到 /writing/:chapterId → WritingPage 渲染章节标题
//   #2 P0-1 返回键带 manuscriptId 跳回作品详情（不进入占位页）
//
// 注意：使用 buildTestRouter() 独立构建 GoRouter，而非全局单例 appRouter，
//      避免与其他测试文件共享 GoRouter 内部状态造成竞态污染。
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
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/widgets/bookshelf_page.dart';
import 'package:writingcoach/widgets/chat_page.dart';
import 'package:writingcoach/widgets/growth_detail_page.dart';
import 'package:writingcoach/widgets/growth_page.dart';
import 'package:writingcoach/widgets/manuscript_detail_page.dart';
import 'package:writingcoach/widgets/placeholder_page.dart';
import 'package:writingcoach/widgets/writing_page.dart';

// ── 测试专用：独立构建一份 GoRouter，避免全局 appRouter 跨测试污染 ──
GoRouter buildTestRouter() {
  return GoRouter(
    initialLocation: AppRoutes.bookshelf,
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('页面未找到')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('找不到对应页面'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => context.go(AppRoutes.bookshelf),
              child: const Text('返回书架'),
            ),
          ],
        ),
      ),
    ),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          body: shell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: shell.goBranch,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.menu_book), label: '书架'),
              NavigationDestination(icon: Icon(Icons.chat), label: '对话'),
              NavigationDestination(icon: Icon(Icons.auto_graph), label: '成长'),
            ],
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.bookshelf,
                builder: (context, state) => const BookshelfPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: '/', builder: (c, s) => const ChatPage())],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.growth,
                builder: (context, state) => GrowthPage(
                  onOpenDetail: () => context.go(AppRoutes.growthDetail),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.manuscriptDetail,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return ManuscriptDetailPage(
            args: ManuscriptDetailArgs(
              manuscriptId: extra?['manuscriptId'] as String? ?? '',
              title: extra?['title'] as String?,
            ),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.writingChapter,
        builder: (context, state) {
          final chapterId = state.pathParameters['chapterId'] ?? '';
          final extra = state.extra as Map<String, dynamic>?;
          final manuscriptId = extra?['manuscriptId'] as String? ?? '';
          final chapterTitle = extra?['chapterTitle'] as String?;
          return WritingPage(
            chapterId: chapterId,
            chapterTitle: chapterTitle,
            manuscriptId: manuscriptId,
            onBack: () {
              context.go(
                AppRoutes.manuscriptDetail,
                extra: <String, dynamic>{
                  'manuscriptId': manuscriptId,
                  'title': chapterTitle,
                },
              );
            },
          );
        },
      ),
      GoRoute(
        path: AppRoutes.growthDetail,
        builder: (context, state) => const GrowthDetailPage(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (c, s) => const PlaceholderPage(title: '设置'),
      ),
      GoRoute(path: '/chat', redirect: (_, _) => '/'),
    ],
  );
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String msId;
  late String chapterId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    // 预置：创建稿件 + 章节（标题 "测试章节"）
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    msId = await msRepo.createManuscript(title: '测试作品');
    chapterId = await chRepo.createChapter(
      msId,
      title: '测试章节',
      content: '这是一段测试内容。',
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  group('writing route', () {
    testWidgets('#1 导航到 /writing/:chapterId → WritingPage 渲染章节标题', (
      tester,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: buildTestRouter()),
        ),
      );
      await tester.pumpAndSettle();

      // 通过 GoRouter 跳转到 /writing/:chapterId
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(
        '/writing/$chapterId',
        extra: <String, dynamic>{'chapterTitle': '测试章节', 'manuscriptId': msId},
      );
      await tester.pumpAndSettle();

      // WritingPage 渲染 + AppBar 显示章节标题
      expect(find.byType(WritingPage), findsOneWidget);
      expect(find.text('测试章节'), findsWidgets);
    });

    testWidgets('#2 P0-1 WritingPage 返回键带 manuscriptId 跳回作品详情（不进入占位页）', (
      tester,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: buildTestRouter()),
        ),
      );
      await tester.pumpAndSettle();

      // Step A: 从作品详情页进入写作页（带 manuscriptId extra）
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(
        '/manuscript-detail',
        extra: <String, dynamic>{'manuscriptId': msId, 'title': '测试作品'},
      );
      await tester.pumpAndSettle();

      // 确认在作品详情页（AppBar 标题正确，非占位页文案）
      expect(find.text('未提供作品 ID'), findsNothing);
      expect(find.text('测试作品'), findsWidgets);

      // Step B: 模拟作品详情 -> 写作页 push（带 manuscriptId）
      GoRouter.of(ctx).push(
        '/writing/$chapterId',
        extra: <String, dynamic>{'chapterTitle': '测试章节', 'manuscriptId': msId},
      );
      await tester.pumpAndSettle();
      expect(find.byType(WritingPage), findsOneWidget);

      // Step C: 点写作页 AppBar 返回按钮
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Step D: 断言回到作品详情页，且 NOT "未提供作品 ID" 占位页
      expect(find.byType(WritingPage), findsNothing);
      expect(
        find.text('未提供作品 ID'),
        findsNothing,
        reason: 'P0-1 断链：返回时未传 manuscriptId，进入占位页',
      );
      expect(find.text('测试作品'), findsWidgets);
    });
  });
}
