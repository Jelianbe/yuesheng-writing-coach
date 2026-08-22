import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/widgets/growth_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  /// 字数 ≥100 的章节内容（诊断选章校验通过）
  const longContent =
      '这是一个大雪纷飞的夜晚，北风呼啸着穿过空旷的原野，'
      '远处的山峦在暮色中显得格外孤寂。一位旅人独自走在雪地里，'
      '身后留下一串深深浅浅的脚印，很快又被新雪覆盖。'
      '他裹紧了身上的斗篷，目光投向远方那点若隐若现的灯火。';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildGrowthPage() {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GrowthPage()),
    );
  }

  group('GrowthPage 视觉规范（月色竹青）', () {
    testWidgets('#V1 AppBar 浅色 #F7F8F6 + 48dp + 深字 #2D3142', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFFF7F8F6));
      expect(appBar.toolbarHeight, 48);
      expect(appBar.foregroundColor, const Color(0xFF2D3142));
    });

    testWidgets('#V2 Scaffold 背景 #F7F8F6', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFFF7F8F6));
    });

    testWidgets('#V3 空状态：显示引导 CTA（无数据卡片）', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      // P2-1：空 DB → 显示空状态引导，无数据卡片
      expect(find.text('还没有写作记录'), findsOneWidget);
      expect(find.text('去写第一篇'), findsOneWidget);
    });

    testWidgets('#V4 AppBar 右上有详情入口图标', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.info_outline), findsOneWidget);
    });

    testWidgets('#V5 快捷入口渲染（设置/写作诊断/学习进度）', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      // 批次 11：对齐 RN GROWTH_ENTRIES，总显示于数据区上方
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('写作诊断'), findsOneWidget);
      // 批次 38：原「敬请期待」占位替换为「学习进度」真实入口
      expect(find.text('学习进度'), findsOneWidget);
      expect(find.text('敬请期待'), findsNothing);
    });

    testWidgets('#V5b 批次38 点击「学习进度」→ 跳转学习进度详情页', (tester) async {
      // 预置一个会话（progress-detail 需要 sessionId）
      await SessionRepository(db).createBlankSession();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      // 进入成长 Tab
      appRouter.go(AppRoutes.growth);
      await tester.pumpAndSettle();

      await tester.tap(find.text('学习进度'));
      await tester.pumpAndSettle();

      // 进入学习进度详情页
      expect(find.text('学习进度'), findsOneWidget);
      expect(find.text('当前阶段'), findsOneWidget);
      expect(find.text('诊断次数'), findsOneWidget);
    });

    testWidgets('#V5c 批次78 无会话 → 点击「学习进度」→ SnackBar 轻提示，不跳转', (tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // 最小路由：宿主 = GrowthPage；progress-detail 用 Marker 校验是否跳转
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const GrowthPage()),
          GoRoute(
            path: AppRoutes.progressDetail,
            builder: (context, state) {
              final extra = state.extra as Map<String, dynamic>? ?? {};
              final sid = extra['sessionId'] as String? ?? '';
              return sid.isEmpty
                  ? const Scaffold(body: Text('PLACEHOLDER_DEAD'))
                  : const Scaffold(body: Text('PROGRESS_REAL'));
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

      // 无会话（setUp 未创建会话）→ 轻提示 + 不跳转
      await tester.tap(find.text('学习进度'));
      await tester.pumpAndSettle();

      expect(find.text('还没有写作会话，先写一章吧'), findsOneWidget);
      expect(find.text('PROGRESS_REAL'), findsNothing);
      expect(find.text('PLACEHOLDER_DEAD'), findsNothing);
    });

    testWidgets('#V6 点击「写作诊断」→ 打开章节选择弹层', (tester) async {
      // 预置一个作品 + 章节（批次 13：选章弹层数据源）
      final msRepo = ManuscriptRepository(db);
      final chRepo = ChapterRepository(db);
      final msId = await msRepo.createManuscript(title: '测试作品');
      await chRepo.createChapter(msId, title: '第一章：启程', content: longContent);

      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('写作诊断'));
      await tester.pumpAndSettle();

      // 弹层打开（复刻 RN DiagnosisPickerModal）
      expect(find.text('选择要诊断的章节'), findsOneWidget);
      expect(find.text('测试作品'), findsOneWidget);
    });
  });

  group('GrowthPage 功能', () {
    testWidgets('#F1 空状态：显示"还没有写作记录"引导', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      // P2-1：空 DB → 显示空状态引导 CTA
      expect(find.text('还没有写作记录'), findsOneWidget);
    });

    testWidgets('#F2 空状态：显示"去写第一篇" CTA 按钮', (tester) async {
      await tester.pumpWidget(buildGrowthPage());
      await tester.pumpAndSettle();

      expect(find.text('去写第一篇'), findsOneWidget);
    });

    testWidgets('#F3 点击详情图标 → 跳转详情页', (tester) async {
      String? pushedRoute;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: GrowthPage(
              onOpenDetail: () => pushedRoute = '/growth-detail',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      expect(pushedRoute, '/growth-detail');
    });
  });
}
