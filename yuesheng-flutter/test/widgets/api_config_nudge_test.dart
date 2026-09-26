// ─────────────────────────────────────────────────────────────
// api_config_nudge 测试 — 首次使用 AI 功能时的「配置 API」一次性引导（C2）
//
// 为什么必须有本文件（批次 1f4abb61 的真实教训）：
//   该批次把 maybeShowApiConfigNudge 接进了三个发送/诊断入口，但**没跑全量测试**
//   （ADR 自述「沙箱跳过全量，CI 兜底」）⇒ 由于本 helper 会读
//   LlmConfigStorage（flutter_secure_storage），而 testWidgets 下**未 mock 的该
//   平台通道会永久挂起**（同一坑见 test/helpers/mock_last_session_storage.dart 批次50），
//   导致 24 例既有测试全部卡死在入口、断言连锁转红。
//   ⇒ 本文件把「引导自身行为」钉住，把「通道隔离」显式化，避免同类事故复发。
//
// 覆盖：
//   #1 未配 + 未看过 → 弹一次，且**弹之前**就落 seen=true（防叠弹）
//   #2 〔稍后〕→ 关闭对话框，不导航
//   #3 〔去设置〕→ 关闭对话框 + 深链 /settings
//   #4 已看过（seen=true）→ 不弹，且**根本不触碰 secure storage**（短路判据）
//   #5 已配（三字段齐全）→ 不弹，且静默落 seen=true
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/features/onboarding/api_config_nudge.dart';
import 'package:writingcoach/router/app_routes.dart';

import '../helpers/mock_secure_storage.dart';

void main() {
  late AppDatabase db;
  late MockSecureStorage storage;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    storage = MockSecureStorage()..install();
  });

  tearDown(() async {
    storage.uninstall();
    await db.close();
  });

  /// 触发按钮（helper 需要真实 BuildContext，故经按钮回调触发）
  Widget triggerButton() => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () async => maybeShowApiConfigNudge(context, db),
        child: const Text('触发'),
      ),
    ),
  );

  Future<void> trigger(WidgetTester tester) async {
    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
  }

  testWidgets('#1 未配 + 未看过 → 弹一次，且弹之前即落 seen=true', (tester) async {
    await tester.pumpWidget(MaterialApp(home: triggerButton()));

    expect(await AppStateRepository(db).getApiConfigHintSeen(), isFalse);

    await trigger(tester);

    expect(find.text('还未配置 AI 服务商 API'), findsOneWidget);
    expect(find.text('稍后'), findsOneWidget);
    expect(find.text('去设置'), findsOneWidget);

    // 「先标记已展示，再弹」——防快速重复发送叠弹（实现注释明示的次序契约）
    expect(await AppStateRepository(db).getApiConfigHintSeen(), isTrue);
  });

  testWidgets('#2 〔稍后〕→ 关闭对话框，不导航', (tester) async {
    await tester.pumpWidget(MaterialApp(home: triggerButton()));
    await trigger(tester);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(find.text('还未配置 AI 服务商 API'), findsNothing);
    // 未导航：触发页仍在
    expect(find.text('触发'), findsOneWidget);
  });

  testWidgets('#3 〔去设置〕→ 关闭对话框 + 深链 /settings', (tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => triggerButton()),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) =>
              const Scaffold(body: Center(child: Text('SETTINGS_STUB'))),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await trigger(tester);

    await tester.tap(find.text('去设置'));
    await tester.pumpAndSettle();

    expect(find.text('还未配置 AI 服务商 API'), findsNothing);
    expect(find.text('SETTINGS_STUB'), findsOneWidget);
    expect(await AppStateRepository(db).getApiConfigHintSeen(), isTrue);
  });

  testWidgets('#4 已看过 → 不弹，且不触碰 secure storage（短路判据）', (tester) async {
    await AppStateRepository(db).setApiConfigHintSeen(true);
    storage.reads.clear();

    await tester.pumpWidget(MaterialApp(home: triggerButton()));
    await trigger(tester);

    expect(find.text('还未配置 AI 服务商 API'), findsNothing);
    // 关键：一次配置读取都没有发生 ⇒ 在真实环境也不会挂起
    expect(storage.reads, isEmpty);
    expect(await AppStateRepository(db).getApiConfigHintSeen(), isTrue);
  });

  testWidgets('#5 已配（三字段齐全）→ 不弹，且静默落 seen=true', (tester) async {
    storage.seedConfigured();

    await tester.pumpWidget(MaterialApp(home: triggerButton()));
    await trigger(tester);

    expect(find.text('还未配置 AI 服务商 API'), findsNothing);
    // 正对照：证明本替身确实拦截到了真实通道（否则 #4 的 reads.isEmpty 可能空转）
    expect(storage.reads, contains(kApiKeyPref));
    expect(await AppStateRepository(db).getApiConfigHintSeen(), isTrue);
  });
}
