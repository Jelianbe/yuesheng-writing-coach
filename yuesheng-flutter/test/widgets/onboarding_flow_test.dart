// ─────────────────────────────────────────────────────────────
// OnboardingFlow widget 测试 — 首启功能引导（批次63）
//
// 覆盖路径：
//   1. 第 1 页渲染（我是月笙）+「下一步」滑到第 2 页
//   2. 连点「下一步」走到末页 → 点「开始使用」→ onComplete 触发
//   3. 右上「跳过」→ onComplete 触发
//   4. 进度点数量 == 页数，且当前页点高亮（更宽）
//
// ★ 页数不是常量：`_pages` 已由 3 页增至 5 页
//   （a64b50bb 增「怎么开始」页、1f4abb61 增「配置 API」页）。
//   ⇒ 测试**不再硬编码点击数**，改为「循环点「下一步」直到出现末页按钮」，
//     这样将来再加页不会再次把本文件改红；页数本身由 #4 的进度点计数钉住。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/onboarding/onboarding_flow.dart';

void main() {
  Widget buildFlow({required VoidCallback onComplete}) {
    return MaterialApp(home: OnboardingFlow(onComplete: onComplete));
  }

  /// 各页标题 + 副标题（顺序须与 `onboarding_flow.dart` 的 `_pages` 一致）。
  ///
  /// 用途：逐页断言，避免「只测首末页、中间页内容静默失守」。
  const pageMarkers = <({String title, String subtitle})>[
    (title: '我是月笙', subtitle: '你的专属写作教练'),
    (title: '我能帮你做什么', subtitle: '三大核心能力'),
    (title: '开始使用', subtitle: '开启写作之旅'),
    (title: '怎么开始', subtitle: '三步用起来'),
    (title: '配置 API', subtitle: '解锁完整功能'),
  ];

  /// 循环点「下一步」直到末页按钮「开始使用」出现（不硬编码页数），
  /// 并**逐页断言该页标题与副标题已渲染**。
  Future<void> advanceToLastPage(WidgetTester tester) async {
    for (var i = 0; i < pageMarkers.length; i++) {
      expect(
        find.text(pageMarkers[i].title),
        findsOneWidget,
        reason: '第 ${i + 1} 页应渲染标题「${pageMarkers[i].title}」',
      );
      expect(
        find.text(pageMarkers[i].subtitle),
        findsOneWidget,
        reason: '第 ${i + 1} 页应渲染副标题「${pageMarkers[i].subtitle}」',
      );
      if (find.widgetWithText(FilledButton, '开始使用').evaluate().isNotEmpty) {
        return;
      }
      expect(
        find.text('下一步'),
        findsOneWidget,
        reason: '非末页应恰有一个「下一步」（当前在第 ${i + 1} 页）',
      );
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
    }
    fail('循环 ${pageMarkers.length} 次仍未走到末页，疑似「下一步」按钮失效');
  }

  testWidgets('#1 第1页渲染 + 下一步 → 第2页', (tester) async {
    await tester.pumpWidget(buildFlow(onComplete: () {}));

    // 第 1 页
    expect(find.text('我是月笙'), findsOneWidget);
    expect(find.text('你的专属写作教练'), findsOneWidget);
    expect(find.text('下一步'), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);

    // 下一步 → 第 2 页
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(find.text('我能帮你做什么'), findsOneWidget);
    expect(find.text('智能诊断'), findsOneWidget);
    expect(find.text('拆解练习'), findsOneWidget);
    expect(find.text('追踪成长'), findsOneWidget);
  });

  testWidgets('#2 走到末页「开始使用」→ onComplete', (tester) async {
    var completed = 0;
    await tester.pumpWidget(buildFlow(onComplete: () => completed++));

    await advanceToLastPage(tester);

    // 末页：标题「配置 API」+ 按钮「开始使用」（两者不同名，断言各自恰好一个）
    expect(find.text('配置 API'), findsOneWidget);
    expect(find.text('开始使用'), findsOneWidget);
    expect(find.text('下一步'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, '开始使用'));
    await tester.pump();
    expect(completed, 1);
  });

  testWidgets('#3 右上「跳过」→ onComplete 触发', (tester) async {
    var completed = 0;
    await tester.pumpWidget(buildFlow(onComplete: () => completed++));

    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(completed, 1);
  });

  testWidgets('#4 进度点数量 == 5 页，且首点高亮（更宽）', (tester) async {
    await tester.pumpWidget(buildFlow(onComplete: () {}));

    // 进度点由 AnimatedContainer 组成，数量 = _pages.length（当前 5）
    final dots = find.byType(AnimatedContainer);
    expect(dots, findsNWidgets(5));
    // 宽度含 margin（horizontal: 3 ⇒ 左右各 3）：
    // 选中 24 + 6 = 30；未选中 8 + 6 = 14。断言「选中比未选中宽」这一语义。
    expect(tester.getSize(dots.at(0)).width, 30);
    expect(tester.getSize(dots.at(1)).width, 14);

    // 翻到第 2 页 → 高亮跟着移动
    await tester.tap(find.text('下一步'));
    await tester.pumpAndSettle();
    expect(tester.getSize(dots.at(0)).width, 14);
    expect(tester.getSize(dots.at(1)).width, 30);
  });
}
