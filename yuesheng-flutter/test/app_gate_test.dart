// ─────────────────────────────────────────────────────────────
// App 启动门测试 — 首启功能引导（批次63）
//
// 覆盖路径：
//   1. 未看过引导（onboarding_completed 未写）→ 显示 OnboardingFlow
//   2. 引导完成（走完 3 页点「开始使用」）→ 落库标记 + 进主壳（书架）
//   3. 已看过引导（onboarding_completed=true）→ 直接主壳
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/main.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/bookshelf_page.dart';
import 'package:writingcoach/widgets/onboarding_flow.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildApp() {
    return ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: const YueshengApp(),
    );
  }

  testWidgets('#1 首次启动（未看过引导）→ 显示 OnboardingFlow', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.text('我是月笙'), findsOneWidget);
    // 未进主壳
    expect(find.byType(BookshelfPage), findsNothing);
  });

  testWidgets('#2 完成引导 → 写标记 + 进主壳', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    // 走完 3 页（末页按钮与页标题都叫「开始使用」，用按钮精确 finder）
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '开始使用'));
    await tester.pumpAndSettle();

    // 已进主壳（书架）
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(BookshelfPage), findsOneWidget);

    // 落库标记
    final done = await AppStateRepository(db).getOnboardingCompleted();
    expect(done, isTrue);
  });

  testWidgets('#3 已看过引导 → 直接主壳', (tester) async {
    await AppStateRepository(db).setOnboardingCompleted(true);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(BookshelfPage), findsOneWidget);
  });
}
