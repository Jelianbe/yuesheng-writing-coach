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
import 'package:writingcoach/router/app_router.dart';
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
      buildHost(
        (ctx) => maybeShowPrivacyNoticeOnce(ctx, appState, isWeb: false),
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsOneWidget);
    expect(find.textContaining('发送至你所选的 AI 服务商 API'), findsOneWidget);
    expect(find.textContaining('无任何遥测与数据上报'), findsOneWidget);
    expect(find.textContaining('服务商账户按用量承担'), findsOneWidget);
  });

  testWidgets('#2 点「我知道了」→ 关闭 + flag 落库', (tester) async {
    await tester.pumpWidget(
      buildHost(
        (ctx) => maybeShowPrivacyNoticeOnce(ctx, appState, isWeb: false),
      ),
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
      buildHost(
        (ctx) => maybeShowPrivacyNoticeOnce(ctx, appState, isWeb: false),
      ),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsNothing);
  });

  testWidgets('#4 设置页直开语义 → 关闭后不写 flag', (tester) async {
    await tester.pumpWidget(
      buildHost((ctx) => showPrivacyNoticeDialog(ctx, isWeb: false)),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsNothing);
    // flag 的写入只属于首启一次性路径（maybeShowPrivacyNoticeOnce）
    expect(await appState.getValue(kPrivacyNoticeAckKey), isNull);
  });

  test('#5 rootNavigatorKey 已挂到 appRouter（main 层轮播结束的告知借它取 context）', () {
    // 防接线回归：若 router 丢失 navigatorKey 配置，main._maybeShowPrivacyNotice
    // 永远取不到 context，轮播路径的告知会静默失效（无编译错误、无日志）。
    expect(
      identical(appRouter.configuration.navigatorKey, rootNavigatorKey),
      isTrue,
    );
  });

  // ── 2026-11-11 按平台分支（`§4-500`）──────────────────────────────
  // 判据设计：web 与非 web **互为负对照**。
  //   只断言 web 三句 → 分不清「分支写对了」与「整串被换掉了」；
  //   只断言非 web 三句 → 同上。
  //   故两侧各一条，且 web 侧额外断言「**不得**出现服务商措辞」
  //   （若哪天有人把两分支合并回一套话，这条会红）。

  test('#6 web 分支：示例模式三句 + 不得出现「你所选的 AI 服务商」', () {
    final lines = privacyNoticeLines(isWeb: true);
    expect(lines.length, 3);
    expect(lines[0], contains('示例模式'));
    expect(lines[0], contains('不会被发送出去'));
    expect(lines[1], contains('浏览器本地'));
    expect(lines[1], contains('无任何遥测与数据上报'));
    expect(lines[2], contains('无需填写 API Key'));
    expect(lines[2], contains('不产生任何 API 费用'));
    // 负向：web 用户没有服务商 ⇒ 出现这句就是虚假告知
    final joined = lines.join('\n');
    expect(joined, isNot(contains('你所选的 AI 服务商')));
    expect(joined, isNot(contains('服务商账户')));
  });

  test('#7 非 web 正对照：原三句逐字不变（Android 已分发文案零变化）', () {
    expect(privacyNoticeLines(isWeb: false), const [
      '· 你的作品文本会发送至你所选的 AI 服务商 API，用于生成诊断与教学反馈。',
      '· 全部数据仅存储在你的设备本地，本应用无任何遥测与数据上报。',
      '· API 费用由你对应的服务商账户按用量承担，本应用不代收任何费用。',
    ]);
  });

  testWidgets('#8 web 弹窗实际渲染：出现示例模式、不出现服务商账户', (tester) async {
    await tester.pumpWidget(
      buildHost((ctx) => showPrivacyNoticeDialog(ctx, isWeb: true)),
    );
    await tester.tap(find.text('trigger'));
    await tester.pumpAndSettle();

    expect(find.text('开始之前，请了解'), findsOneWidget);
    expect(find.textContaining('示例模式'), findsOneWidget);
    expect(find.textContaining('浏览器本地'), findsOneWidget);
    expect(find.textContaining('服务商账户'), findsNothing);
    expect(find.textContaining('发送至你所选的'), findsNothing);
  });
}
