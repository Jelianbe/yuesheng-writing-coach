// ─────────────────────────────────────────────────────────────
// 隐私与费用告知对话框：widget 测试（v0.1 发布准备批任务 2）
//
// 覆盖路径：
//   #1 未确认 → maybeShowPrivacyNoticeOnce 弹出 → 三段文案可见
//   #2 点「我知道了」→ 关闭 + flag 落库（'1'）
//   #3 已确认（flag='1'）→ 不再弹出
//   #4 直接 showPrivacyNoticeDialog（设置页语义）→ 关闭但不写 flag
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/widgets/privacy_notice_dialog.dart';

void main() {
  late AppDatabase db;
  late AppStateRepository appState;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    appState = AppStateRepository(db);
  });

  tearDown(() async => db.close());

  Widget buildHost(Future<void> Function(BuildContext) onTap) {
    return MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: ElevatedButton(
            onPressed: () => onTap(ctx),
            child: const Text('trigger'),
          ),
        ),
      ),
    );
  }

  testWidgets('#1 未确认 → 弹出 + 三段文案可见', (tester) async {
    await tester.pumpWidget(
      buildHost((ctx) => maybeShowPrivacyNoticeOnce(ctx, appState)),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsOneWidget);
    expect(find.textContaining('发送至 DeepSeek API'), findsOneWidget);
    expect(find.textContaining('无任何遥测与数据上报'), findsOneWidget);
    expect(find.textContaining('DeepSeek 账户按用量承担'), findsOneWidget);
  });

  testWidgets('#2 点「我知道了」→ 关闭 + flag 落库', (tester) async {
    await tester.pumpWidget(
      buildHost((ctx) => maybeShowPrivacyNoticeOnce(ctx, appState)),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsNothing);
    expect(await appState.getValue(kPrivacyNoticeAckKey), '1');
  });

  testWidgets('#3 已确认 → 不再弹出', (tester) async {
    await appState.setValue(kPrivacyNoticeAckKey, '1');

    await tester.pumpWidget(
      buildHost((ctx) => maybeShowPrivacyNoticeOnce(ctx, appState)),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsNothing);
  });

  testWidgets('#4 设置页直开语义 → 关闭后不写 flag', (tester) async {
    await tester.pumpWidget(buildHost(showPrivacyNoticeDialog));
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsNothing);
    // flag 的写入只属于首启一次性路径（maybeShowPrivacyNoticeOnce）
    expect(await appState.getValue(kPrivacyNoticeAckKey), isNull);
  });
}
