import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/widgets/growth_detail_page.dart';
import 'package:writingcoach/widgets/growth_page.dart';
import 'package:writingcoach/widgets/placeholder_page.dart';
import 'package:writingcoach/widgets/settings_page.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() {
    db.close();
  });

  /// 构建一个带 ProviderScope override 的 MaterialApp.router
  Widget buildTestApp() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp.router(routerConfig: appRouter),
    );
  }

  group('C4 路由集成 — 配置', () {
    test('#C1 AppRoutes.growthDetail 常量存在', () {
      expect(AppRoutes.growthDetail, '/growth-detail');
    });

    test('#C2 Tab3 路径仍为 /growth', () {
      expect(AppRoutes.growth, '/growth');
    });
  });

  group('C4 路由集成 — 渲染', () {
    testWidgets('#R1 Tab3 → 渲染 GrowthPage（非 PlaceholderPage）', (tester) async {
      await tester.pumpWidget(buildTestApp());
      // 初始在书架 Tab，切到 Tab3（index=2）
      final goRouter = appRouter;
      goRouter.go(AppRoutes.growth);
      await tester.pumpAndSettle();

      expect(find.byType(GrowthPage), findsOneWidget);
      expect(find.byType(PlaceholderPage), findsNothing);
    });

    testWidgets('#R2 /growth-detail → 渲染 GrowthDetailPage', (tester) async {
      await tester.pumpWidget(buildTestApp());
      appRouter.go(AppRoutes.growthDetail);
      await tester.pumpAndSettle();

      expect(find.byType(GrowthDetailPage), findsOneWidget);
    });

    testWidgets('#R3 Tab3 AppBar 右侧详情入口 → 点击跳转到 /growth-detail', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestApp());
      appRouter.go(AppRoutes.growth);
      await tester.pumpAndSettle();

      // 点击 AppBar 右侧 info_outline 图标
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();

      // 应该跳转到详情页
      expect(find.byType(GrowthDetailPage), findsOneWidget);
    });

    testWidgets('#R4 快捷入口「设置」→ 跳转 /settings 渲染 SettingsPage', (tester) async {
      await tester.pumpWidget(buildTestApp());
      appRouter.go(AppRoutes.growth);
      await tester.pumpAndSettle();

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
      // 设置页标题
      expect(find.text('API 配置'), findsOneWidget);
    });
  });
}
