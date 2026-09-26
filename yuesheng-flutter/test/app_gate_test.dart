// ─────────────────────────────────────────────────────────────
// App 启动门测试 — 首启功能引导（批次63）
//
// 覆盖路径：
//   1. 未看过引导（onboarding_completed 未写）→ 显示 OnboardingFlow
//   2. 引导完成（走完引导点「开始使用」）→ 落库标记 + 进主壳（书架）
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
import 'package:writingcoach/features/bookshelf/bookshelf_page.dart';
import 'package:writingcoach/features/onboarding/onboarding_flow.dart';

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

    // 走完引导：循环点「下一步」直到末页按钮「开始使用」出现。
    // ★ 不硬编码页数：`OnboardingFlow._pages` 已由 3 页增至 5 页
    //   （a64b50bb 增「怎么开始」、1f4abb61 增「配置 API」）⇒ 硬编码点击数必红。
    // 注：6b04d639 曾把问卷(onboarding_questionnaire)的 6 页误当引导页数改坏本测试，
    // 73acfaed 还原为 3 页；本次改为「走到末页为止」，两错皆不再复现。
    // 引导页末页按钮「开始使用」与任意页标题可能重名，故用按钮精确 finder。
    var advanced = false;
    for (var i = 0; i < 10; i++) {
      if (find.widgetWithText(FilledButton, '开始使用').evaluate().isNotEmpty) {
        advanced = true;
        break;
      }
      expect(
        find.text('下一步'),
        findsOneWidget,
        reason: '非末页应恰有一个「下一步」（当前第 ${i + 1} 页）',
      );
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }
    expect(advanced, isTrue, reason: '循环 10 次仍未走到引导末页');
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
