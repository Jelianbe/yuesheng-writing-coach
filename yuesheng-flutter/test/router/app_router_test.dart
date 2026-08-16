// ─────────────────────────────────────────────────────────────
// app_router_test — go_router 路由配置测试
//
// 覆盖路径：
//   1. 初始路径为 / (写作 Tab)
//   2. /bookshelf 路由可达
//   3. /growth 路由可达
//   4. /chat 路由可达
//   5. 未知路径 → errorBuilder 显示"页面未找到"
//   6. Tab 切换：3 个 NavigationDestination 存在
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/router/app_router.dart';

import '../helpers/mock_last_session_storage.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // 批次 50：隔离 flutter_secure_storage 平台通道（testWidgets 下未 mock 的通道调用会挂起）
        lastSessionStorageProvider.overrideWithValue(
          MemoryLastSessionStorage(),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  group('app_router', () {
    testWidgets('#1 初始路径为 /bookshelf (书架 Tab，C2 改造)', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      // C2 改造后默认 Tab 改为书架（selectedIndex == 0）
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
    });

    testWidgets('#2 /bookshelf 路由可达', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到书架 Tab
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      navBar.onDestinationSelected!(0);
      await tester.pumpAndSettle();

      expect(find.text('书架'), findsWidgets);
    });

    testWidgets('#3 /growth 路由可达', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      navBar.onDestinationSelected!(2);
      await tester.pumpAndSettle();

      expect(find.text('成长'), findsWidgets);
    });

    testWidgets('#4 /chat 路由可达', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 通过 context.go 跳转到 /chat
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/chat');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // ChatPage 头部标题「会话」（批次 10：AppBar → ChatHeader）
      expect(find.text('会话'), findsOneWidget);
    });

    testWidgets('#5 未知路径 → errorBuilder 显示"页面未找到"', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go('/nonexistent-path');
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('页面未找到'), findsOneWidget);
      expect(find.textContaining('/nonexistent-path'), findsOneWidget);
    });

    testWidgets('#6 Tab 切换：3 个 NavigationDestination 存在', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      // appRouter 是全局单例，#4/#5 已修改其 location（go('/chat')、go('/nonexistent-path')）
      // 需先重置回 / 才能验证 Tab 布局的 NavigationBar
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(AppRoutes.writing);
      await tester.pumpAndSettle();

      // NavigationBar 存在 + 3 个 NavigationDestination（数据对象）
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.destinations.length, 3);

      // 验证 3 个 Tab 的 label（C2 改造后 Tab2 从"写作"改为"对话"）
      final labels = navBar.destinations
          .map((d) => (d as NavigationDestination).label)
          .toList();
      expect(labels, ['书架', '对话', '成长']);
    });

    testWidgets('#7 /append-chapters 路由可达（批次 20）', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(
        AppRoutes.appendChapters,
        extra: {'manuscriptId': 'x', 'title': '作品'},
      );
      await tester.pumpAndSettle();

      expect(find.text('追加章节'), findsOneWidget);
      expect(find.text('选择导入方式'), findsOneWidget);
    });

    testWidgets('#8 /project-settings 路由可达（批次 20）', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(
        AppRoutes.projectSettings,
        extra: {'manuscriptId': 'x', 'title': '作品'},
      );
      await tester.pumpAndSettle();

      expect(find.text('项目设置'), findsOneWidget);
      expect(find.text('危险区'), findsOneWidget);
    });

    testWidgets('#9 /progress-detail 路由可达（批次 21）', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(AppRoutes.progressDetail, extra: {'sessionId': 'x'});
      await tester.pumpAndSettle();

      expect(find.text('学习进度'), findsOneWidget);
      expect(find.text('生成学习报告'), findsOneWidget);
    });

    testWidgets('#10 批次68 Tab 切换轻淡入（body 装配 TweenAnimationBuilder）', (
      tester,
    ) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      // appRouter 是全局单例，#4/#5 已改过 location——先重置回书架 Tab，
      // 保证 shell currentIndex=0 干净状态（对齐 #6 的处理）
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(AppRoutes.bookshelf);
      await tester.pumpAndSettle();

      // body 淡入动画已装配（初始 Tab），语义 key tab-fade-N
      Finder tabFade() => find.byWidgetPredicate(
        (w) =>
            w is TweenAnimationBuilder<double> &&
            '${w.key}'.contains('tab-fade'),
      );
      expect(tabFade(), findsOneWidget);

      // 切到对话 Tab：淡入组件仍在（key 随 index 变化重建 tween）
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      navBar.onDestinationSelected!(1);
      await tester.pumpAndSettle();
      expect(tabFade(), findsOneWidget);

      // 再切成长 Tab
      navBar.onDestinationSelected!(2);
      await tester.pumpAndSettle();
      expect(tabFade(), findsOneWidget);
    });
  });
}
