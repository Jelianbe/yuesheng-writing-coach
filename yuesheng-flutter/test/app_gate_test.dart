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
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/main.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/features/bookshelf/bookshelf_page.dart';
import 'package:writingcoach/features/onboarding/api_config_nudge.dart';
import 'package:writingcoach/features/onboarding/onboarding_flow.dart';
import 'package:writingcoach/features/writing/writing_page.dart';

import 'helpers/mock_secure_storage.dart';

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

  // ─────────────────────────────────────────────────────────────
  // P3（T-20261126-06 · R-027 批号「2026-11-26 四项全批 A」· R3 补测）
  //
  // 缺陷：`onboarding_flow_test.dart` 的 P3/P3b 两条**只断回调路由**
  // （skipped==1 / completed==0）。回调被调用 ≠ 标志被写入。实测把
  // `main.dart` 里 `await repo.setApiConfigHintSeen(true);` 注释掉，
  // 那两条仍全绿 —— 整条「跳过写两标志」功能**零覆盖**。
  //
  // 判据（落库结果，不是 mock 断言）：起 App 时两标志均为 false（不预置）
  // → 点「跳过」→ **getApiConfigHintSeen() 必须为 true**。
  // 变红条件：`main.dart` 的 `setApiConfigHintSeen(true)` 被删/被绕开。
  // ─────────────────────────────────────────────────────────────
  testWidgets('P3 端到端：跳过 → 两标志均已落库（回调被调 ≠ 标志被写）', (tester) async {
    final repo = AppStateRepository(db);
    // 前置：不预置任何标志，复现真实首启态
    expect(
      await repo.getOnboardingCompleted(),
      isFalse,
      reason: '前置：本用例要求 onboarding_completed 未被预置',
    );
    expect(
      await repo.getApiConfigHintSeen(),
      isFalse,
      reason: '前置：本用例要求 api_config_hint_seen 未被预置',
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(OnboardingFlow), findsOneWidget);
    expect(find.text('跳过'), findsOneWidget);

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    // ★ 核心判据（本用例存在的唯一理由）：标志落库。
    //   删掉 main.dart 的 setApiConfigHintSeen(true) ⇒ 此断言立刻红。
    expect(
      await repo.getApiConfigHintSeen(),
      isTrue,
      reason:
          '「跳过」必须把 api_config_hint_seen 落库为 true；'
          '只验证回调被调用是假绿（T-20261126-06 R3）',
    );
    expect(
      await repo.getOnboardingCompleted(),
      isTrue,
      reason: '「跳过」必须把 onboarding_completed 落库为 true',
    );

    // 跳过也须进主壳（不能被隐私弹窗或标志写入阻断）
    //
    // ★ R1 统计口径的活文档（`§4-573` 裁定）：到主壳的点击数**恒为 2** ——
    //   [点1 跳过] + [点2 隐私「我知道了」]。隐私告知是合规弹层，
    //   **跳过的用户也要看**（`main.dart:223-235` 末尾 `_maybeShowPrivacyNotice()`），
    //   它不会因为跳过引导就不弹。
    //   ⇒ 所以 P3 的收益**不是**「把 2 次点击降到 1 次」，而是
    //     「首次诊断前不再多一次 API nudge」——总打断 **3 → 2**。
    //   下面用 `if` 而不是硬断言弹层存在：`maybeShowPrivacyNoticeOnce` 内部
    //   有「已确认则静默跳过」的短路，硬断言会在预置了该标志时误红。
    if (find.text('我知道了').evaluate().isNotEmpty) {
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
    }
    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(BookshelfPage), findsOneWidget);
  });

  // ─────────────────────────────────────────────────────────────
  // P3 端到端（后半段）：跳过写下的 flag 必须**真的对下游生效** ——
  // 0 字章节点「诊断本章」时不得弹「还未配置 AI 服务商 API」。
  //
  // ⚠️ 诚实标注：本条**单独看无鉴别力**。P2（T-20261126-05）已把字数校验
  //   上移到 nudge 之前 ⇒ 0 字时 nudge 根本不执行，flag 写没写都不弹。
  //   变异实测：注释掉 main.dart:228 后本条仍绿（见回执 §1.3 第三段）。
  //   ⇒ 保留它是为了钉住**用户可见终态**（回归护栏），真正的鉴别力在
  //     上一条的 `getApiConfigHintSeen() == true`。不要被它的绿误导。
  // ─────────────────────────────────────────────────────────────
  testWidgets('P3 端到端（终态）：跳过之后 0 字诊断不弹 API 引导', (tester) async {
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final msId = await msRepo.createManuscript(title: '回归作品');
    final emptyChapterId = await chRepo.createChapter(
      msId,
      title: '空章节',
      content: '',
    );

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    if (find.text('我知道了').evaluate().isNotEmpty) {
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
    }

    // 进写作页（同一 DB，沿用「跳过」写下的 flag）
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: WritingPage(chapterId: emptyChapterId, manuscriptId: msId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('aiChatFab')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('诊断本章'));
    await tester.pumpAndSettle();

    expect(
      find.text('还未配置 AI 服务商 API'),
      findsNothing,
      reason: '跳过已写 api_config_hint_seen ⇒ 首次诊断不应再弹 API 引导',
    );
    expect(
      find.text('请至少输入 100 字后再提交诊断'),
      findsOneWidget,
      reason: '0 字应先报字数不足（P2 顺序）',
    );
  });

  // ─────────────────────────────────────────────────────────────
  // P3 端到端（下游消费）：跳过写下的 flag 必须被**真实消费者**读到 ——
  // 直接调用生产代码 `maybeShowApiConfigNudge`（诊断/对话三个入口共用的
  // 唯一 helper），断言它被 flag 短路：不弹对话框、也不触碰 secure storage。
  //
  // 与上一条的区别：上一条用 0 字路径，nudge 根本不执行 ⇒ 无鉴别力；
  // 本条直接测 nudge 本身，flag 写没写**直接决定**弹不弹：
  // 注释掉 main.dart 的 setApiConfigHintSeen(true) ⇒ flag=false ⇒ 弹 → 红。
  // 不用 LLM、不依赖真实网络。
  // ─────────────────────────────────────────────────────────────
  testWidgets('P3 端到端（下游消费）：跳过之后 nudge 被 flag 短路', (tester) async {
    final storage = MockSecureStorage()..install();
    addTearDown(storage.uninstall);

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    if (find.text('我知道了').evaluate().isNotEmpty) {
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
    }

    // 前置确认：flag 确由「跳过」写下（此断言由上一条已钉，这里再核一次
    // 以免本条的失败原因被误读成「nudge 逻辑本身坏了」）
    expect(await AppStateRepository(db).getApiConfigHintSeen(), isTrue);

    storage.reads.clear();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async => maybeShowApiConfigNudge(context, db),
                child: const Text('触发 nudge'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('触发 nudge'));
    await tester.pumpAndSettle();

    expect(
      find.text('还未配置 AI 服务商 API'),
      findsNothing,
      reason: '跳过已写 flag ⇒ nudge 必须短路不弹（下游消费失效）',
    );
    expect(
      storage.reads,
      isEmpty,
      reason: 'flag 短路应在读 API 配置之前返回（api_config_nudge.dart:35）',
    );
  });
}
