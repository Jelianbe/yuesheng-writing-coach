// ─────────────────────────────────────────────────────────────
// world_entry_integration_test — 批次 W1 世界观入口挂接集成测试
//
// 覆盖（对应 W1-T04 验收标准）：
//   ① ⋮ 菜单出现「世界观」项，点击后 sheet 关闭并触发 onOpenWorlds
//   ④ 既有「角色」项与 onOpenCharacters 未被误伤（不得删除 / 改名）
//   ⑤ 路由契约：AppRoutes.worlds == '/worlds' 且 appRouter 已注册该顶层路由
//   ⑥ /worlds 落地页 extra 契约：带 manuscriptId → WorldFactPage；无 → PlaceholderPage
// ─────────────────────────────────────────────────────────────

import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/widgets/placeholder_page.dart';
import 'package:writingcoach/widgets/world/world_fact_page.dart';
import 'package:writingcoach/features/writing/writing_menu_sheet.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/features/writing/writing_page_menu_actions.dart';
import 'package:writingcoach/features/writing/writing_page_host.dart';

import '../../helpers/mock_last_session_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 通用 harness：用按钮触发 WritingMenuSheet.show()（对齐 writing_menu_sheet_test）
  Future<void> pumpSheet(
    WidgetTester tester, {
    required VoidCallback onOpenWorlds,
    VoidCallback? onOpenCharacters,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => WritingMenuSheet.show(
                  context,
                  lastSavedAt: null,
                  onDiagnose: () {},
                  onOpenCharacters: onOpenCharacters,
                  onOpenWorlds: onOpenWorlds,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  group('写作页 ⋮ 菜单「世界观」入口', () {
    testWidgets('新增「世界观」项，且保留既有「角色」项', (tester) async {
      await pumpSheet(tester, onOpenWorlds: () {});
      expect(find.text('世界观'), findsOneWidget);
      expect(find.text('角色'), findsOneWidget, reason: '不得删除 / 改名既有角色项');
    });

    testWidgets('点击「世界观」→ onOpenWorlds 触发 + sheet 关闭', (tester) async {
      var called = false;
      await pumpSheet(tester, onOpenWorlds: () => called = true);

      expect(find.byType(BottomSheet), findsOneWidget);
      // 「世界观」位于「写作工具」组末位，可能落在首屏外 → 滚动到可见再点
      final item = find.text('世界观');
      await tester.scrollUntilVisible(
        item,
        120,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(item);
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('既有「角色」回调仍可触发（未误伤 onOpenCharacters）', (tester) async {
      var characters = false;
      await pumpSheet(
        tester,
        onOpenWorlds: () {},
        onOpenCharacters: () => characters = true,
      );

      await tester.tap(find.text('角色'));
      await tester.pumpAndSettle();

      expect(characters, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });
  });

  group('路由契约 /worlds', () {
    test('AppRoutes.worlds == /worlds', () {
      expect(AppRoutes.worlds, '/worlds');
    });

    test('appRouter 已注册 /worlds 顶层路由', () {
      final paths = appRouter.configuration.routes.whereType<GoRoute>().map(
        (r) => r.path,
      );
      expect(paths, contains(AppRoutes.worlds));
    });
  });

  group('/worlds 落地页（extra 契约）', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
    });

    tearDown(() {
      container.dispose();
      db.close();
    });

    testWidgets('带 manuscriptId → WorldFactPage；无 → PlaceholderPage', (
      tester,
    ) async {
      final manuscriptId = await ManuscriptRepository(
        db,
      ).createManuscript(title: '测试作品');

      // 与 app_router 的 /worlds builder 同构（同路径常量 + 同 extra 契约）
      final router = GoRouter(
        initialLocation: '/home',
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, _) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: AppRoutes.worlds,
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>? ?? {};
              final mid = extra['manuscriptId'] as String? ?? '';
              if (mid.isEmpty) {
                return const PlaceholderPage(
                  title: '世界观',
                  subtitle: '未提供作品 ID',
                );
              }
              return WorldFactPage(manuscriptId: mid);
            },
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // 带 manuscriptId → 落地 WorldFactPage（初始空态）
      unawaited(
        router.push(
          AppRoutes.worlds,
          extra: <String, dynamic>{'manuscriptId': manuscriptId},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorldFactPage), findsOneWidget);
      expect(find.text('还没有世界观设定'), findsOneWidget);

      // 无 manuscriptId → PlaceholderPage（对齐 /characters 守卫口径）
      unawaited(router.push(AppRoutes.worlds));
      await tester.pumpAndSettle();
      expect(find.text('未提供作品 ID'), findsOneWidget);
    });
  });

  // ── W1-T06：真实 appRouter 端到端（走真实注册的 builder，非复刻路由）──
  //
  // 补此前缺口：原集成测试用「本地复刻 GoRouter」验证 extra 契约，未打真实
  // appRouter 的 /worlds builder；且 `openWorlds` 无任何测试。本组用真实
  // appRouter + 真实 openWorlds，端到端验证 openWorlds → /worlds → WorldFactPage。
  group('真实 appRouter：openWorlds → /worlds → WorldFactPage', () {
    late AppDatabase db;
    late ProviderContainer container;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          // flutter_secure_storage 平台通道在 testWidgets 下会挂起 → 必须 mock
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

    Future<void> pumpRealApp(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();
      // appRouter 为全局单例，跨用例可能残留 location → 复位到书架 Tab
      GoRouter.of(
        tester.element(find.byType(Navigator).first),
      ).go(AppRoutes.bookshelf);
      await tester.pumpAndSettle();
    }

    testWidgets('有 manuscriptId → openWorlds 推入真实 /worlds → 渲染 WorldFactPage', (
      tester,
    ) async {
      final mid = await ManuscriptRepository(
        db,
      ).createManuscript(title: '测试作品');
      await pumpRealApp(tester);

      final ctx = tester.element(find.byType(Navigator).first);
      openWorlds(_FakeWritingPageHost(context: ctx, resolvedManuscriptId: mid));
      await tester.pumpAndSettle();

      expect(find.byType(WorldFactPage), findsOneWidget);
      expect(find.text('还没有世界观设定'), findsOneWidget);
    });

    testWidgets('manuscriptId 为空 → 不跳转 + SnackBar「章节加载中，请稍后再试」', (
      tester,
    ) async {
      await pumpRealApp(tester);

      final ctx = tester.element(find.byType(Navigator).first);
      openWorlds(
        _FakeWritingPageHost(context: ctx, resolvedManuscriptId: null),
      );
      await tester.pumpAndSettle();

      expect(find.byType(WorldFactPage), findsNothing);
      expect(find.text('章节加载中，请稍后再试'), findsOneWidget);
    });
  });
}

/// 最小 [WritingPageHost] 假件：`openWorlds` 仅使用 [context] 与
/// [resolvedManuscriptId]（`writing_page_menu_actions.dart:87-99`），
/// 其余成员以 noSuchMethod 兜底（本测试永不触达）。
class _FakeWritingPageHost implements WritingPageHost {
  @override
  final BuildContext context;

  @override
  final String? resolvedManuscriptId;

  _FakeWritingPageHost({required this.context, this.resolvedManuscriptId});

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '未使用的 WritingPageHost 成员被调用：${invocation.memberName}',
  );
}
