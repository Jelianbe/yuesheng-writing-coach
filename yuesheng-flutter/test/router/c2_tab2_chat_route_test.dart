// ─────────────────────────────────────────────────────────────
// c2_tab2_chat_route_test — C2 路由重构验证（Tab2 改为对话）
//
// C2 改造点（实施前应失败，实施后应通过）：
//   1. 初始路径从 / (写作 Tab) 改为 /bookshelf（默认 Tab 改书架）
//   2. Tab2 从"写作"占位页改为"对话"（ChatPage）
//   3. Tab2 导航项 label 从"写作"改为"对话"，图标从 edit 改为 chat
//   4. /chat 顶层路由重定向到 Tab2（保留深链入口，避免死路由）
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

  group('C2 Tab2 改为对话', () {
    testWidgets('#1 初始路径为 /bookshelf（默认 Tab 改书架）', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 默认应落到书架 Tab（Branch A，index 0）
      // 精确断言：NavigationBar.selectedIndex == 0
      // 当前默认是 Tab2（index 1，写作占位页），C2 改造后应改为 index 0
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 0);
    });

    testWidgets('#2 Tab2 导航项 label 为"对话"', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 重置到默认路径，避免其他测试污染全局单例
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(AppRoutes.bookshelf);
      await tester.pumpAndSettle();

      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      final labels = navBar.destinations
          .map((d) => (d as NavigationDestination).label)
          .toList();

      // Tab2 label 应从"写作"改为"对话"
      expect(labels, ['书架', '对话', '成长']);
    });

    testWidgets('#3 切换到 Tab2 → 渲染 ChatPage（头部标题"会话"）', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 切换到 Tab2（index 1）
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      navBar.onDestinationSelected!(1);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Tab2 应渲染 ChatPage（头部标题「会话」）
      expect(find.text('会话'), findsOneWidget);
    });

    testWidgets('#4 /chat 重定向到 Tab2（保留深链入口）', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 通过 /chat 深链跳转
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(AppRoutes.chat);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // 应重定向到 Tab2，渲染 ChatPage
      expect(find.text('会话'), findsOneWidget);

      // Tab2 应高亮（NavigationBar.selectedIndex == 1）
      final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(navBar.selectedIndex, 1);
    });
  });
}
