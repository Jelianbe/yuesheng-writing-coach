// ─────────────────────────────────────────────────────────────
// practice_launcher_test — P1-6 自主练习选择器
//
// 覆盖路径：
//   1. 显示全部三区（症候 / 类型 / 难度）+ 默认预填
//   2. 选择后「开始练习」回调携带自选值
//   3. 无候选症候 → 引导文案 + 开始按钮禁用
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/chat/practice_launcher.dart';

void main() {
  const syndromes = [
    PracticeSyndromeOption(id: 'P003', name: '情绪标签化'),
    PracticeSyndromeOption(id: 'P008', name: '语言堆砌'),
  ];

  Future<void> openLauncher(
    WidgetTester tester, {
    required void Function(PracticeChoice) onStart,
  }) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => PracticeLauncherSheet.show(
                  context,
                  syndromes: syndromes,
                  onStart: onStart,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('#L1 三区渲染 + 默认选中第一个症候', (tester) async {
    await openLauncher(tester, onStart: (_) {});

    expect(find.text('自主练习'), findsOneWidget);
    // 症候区
    expect(find.text('情绪标签化'), findsOneWidget);
    expect(find.text('语言堆砌'), findsOneWidget);
    // 类型区
    expect(find.text('改写'), findsOneWidget);
    expect(find.text('分析'), findsOneWidget);
    expect(find.text('对比'), findsOneWidget);
    expect(find.text('生成'), findsOneWidget);
    // 难度区
    expect(find.text('入门'), findsOneWidget);
    expect(find.text('进阶'), findsOneWidget);
    expect(find.text('挑战'), findsOneWidget);
    // 开始按钮可用（默认已选症候/类型/难度）
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('#L2 自选类型与难度 → 回调携带选择', (tester) async {
    PracticeChoice? captured;
    await openLauncher(tester, onStart: (c) => captured = c);

    await tester.tap(find.text('生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('挑战'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始练习'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.syndromeId, 'P003');
    expect(captured!.syndromeName, '情绪标签化');
    expect(captured!.taskType, 'generate');
    expect(captured!.difficulty, 'hard');
  });

  testWidgets('#L3 无候选症候 → 引导文案 + 开始按钮禁用', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => PracticeLauncherSheet.show(
                  context,
                  syndromes: const [],
                  onStart: (_) {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂时没有活跃的写作问题'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
