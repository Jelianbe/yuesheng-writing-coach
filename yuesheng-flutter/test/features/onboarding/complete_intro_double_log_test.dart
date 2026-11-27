// ─────────────────────────────────────────────────────────────
// T-20261126-09 · U1 复现证据：一次 DB 写入失败是否被记了 **2 条** error_logs
//
// 缺陷（严丝合实测，卡面 §〇）：
//   同一次 `setOnboardingCompleted` 失败被两处各采集一次 ——
//     A. `repository_write_guard.dart` `guardRepoWrite` 的 catch：
//        `captureError(level: 'error', category: 'database', message: '$repo.$op 写操作失败')`
//        然后 `rethrow`；
//     B. `main.dart` `_completeIntro` 的 catch：
//        `captureError(level: 'warn', category: 'database', message: '引导完成标记写入失败…')`。
//   ⇒ `error_logs` 双写，诊断噪声翻倍。
//
// 本文件的三段成套（写测试的人不宣布绿灯，改前红 / 改后绿由独立角色复核）：
//   ① 核心：一次失败 ⇒ `error_logs` **恰 1 条**。
//      `main.dart:_completeIntro` 那处手工 captureError 未删时**实测读 2 条** ⇒ 红在断言行；
//      删除后自动转绿。红→绿两段实测读数均已落盘（见下「入库形态」）。
//   ② 防误删对照组（与①同一条用例内）：`debugPrint` 仍在、op 级可归因记录仍在、
//      写入失败**仍进主壳**（`BookshelfPage`）—— 证明修复不能靠牺牲降级/可追溯性换取。
//   ③ 正向路径（第二条用例）：不注入失败 ⇒ `error_logs` 恰 0 条、标记落库 true、
//      仍进主壳 —— 证明夹具本身不污染日志（否则①的读数无意义）。
//
// ── 入库形态（主理人 2026-11-27 裁定 (c)）
//   本文件与 `main.dart` 的修复**同批绿态入库**，红态不入版本历史；
//   **不使用 `SKIP_GIT_GATE=1`、不使用 `skip: true`**。
//   U1 判据要的是「实测证据落盘」，证据 = `.ai/team/runs/2026-11-27-T09-重复采集/
//   01-改前红读数.md`（红读数原文 + `main.dart` sha256 + 可复算命令），
//   不是「仓库必须经过红态」。证据链两段：§一 红（`Expected: <1> / Actual: <2>`）
//   + §三 变体 A 转绿（`rc=0` + `All tests passed!`），与提交顺序无关。
//   否决 `skip: true` 的理由（实测）：`+1 ~1` / `rc=0` 绿而**零证明力**，
//   且修复后无人被提醒删 skip ⇒ 退化为「预置拿走覆盖」型假绿。
//
// ── 为什么必须「真的让 DB 写入抛错」（卡面 V2 的硬要求）
//   Q3 可验证性：若只 mock 返回值，测的是 mock 不是采集。这里用
//   `_FailAppStateWritesExecutor extends QueryExecutor`（形态取自
//   `test/widgets/diagnosis_card_test.dart:123` 的 `_OnlySessionsExecutor`）
//   装饰 `NativeDatabase.memory()`，在 **executor 层**让 app_state 的 INSERT 抛
//   `StateError` —— 异常真的从 drift 执行器里冒出，走 guardRepoWrite 的真实 catch。
//
//   ⚠️ 两个已踩过的陷阱（写进注释防后人重走）：
//   1. **必须放行 error_logs 的 insert**：把 insert 全拦掉 ⇒ 连日志都写不进去 ⇒
//      读数是「0 条」。**0 既不是 1 也不是 2，说明探针坏了**，不是新发现。
//      故拦截条件精确到 `app_state` 表名，并另加 `blockedInserts` 探针自检断言。
//   2. **必须只在测试主体阶段才拦**：`AppDatabase.forTesting()` 首次 `ensureOpen`
//      会跑 schema 创建（大量 runCustom / 建表），建库期就拦会当场炸在建表上。
//      故用可变开关 `armed`，走完引导页之后、点「开始使用」之前才武装。
//
// ── 表名口径（卡面写作 `app_states`，代码里是单数）
//   真源 `lib/data/database/tables.dart`：`class AppStates ... tableName => 'app_state'`。
//   拦截按 `app_state` 匹配（单数），不是 `app_states`。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/error_log_repository.dart';
import 'package:writingcoach/features/bookshelf/bookshelf_page.dart';
import 'package:writingcoach/features/onboarding/onboarding_flow.dart';
import 'package:writingcoach/main.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/services/error_handler.dart';
import 'package:writingcoach/widgets/privacy_notice_dialog.dart';

/// 测试专用：**在 executor 层让 `app_state` 的 INSERT 真实抛错**的装饰器。
///
/// 只拦 `runInsert` 且 SQL 指向 `app_state`；`error_logs` / `pilot_metric_events`
/// 等写入一律放行 —— 否则日志写不进去，读数会退化成「0 条」，那是探针坏了的
/// 读数，不是被测行为。**仅测试侧使用**，不进 lib/，产品代码零改动。
class _FailAppStateWritesExecutor extends QueryExecutor {
  _FailAppStateWritesExecutor(this._inner);

  final QueryExecutor _inner;

  /// 武装开关。**建库与首启读阶段必须为 false**（`ensureOpen` 会跑 schema 创建）。
  bool armed = false;

  /// 被拦下的写入次数。**探针自检用**：为 0 说明这条用例什么都没测到。
  int blockedInserts = 0;

  /// 放行到内层的 `error_logs` INSERT 次数。
  ///
  /// **排空自检用**：`ErrorHandler.captureError` 的落库是 `unawaited(_persist(...))`，
  /// 断言若跑在这条异步链排空前，读数会**偏小**（缺陷还在也可能只读到 1 条 ⇒ 假绿）。
  /// 与查询结果条数交叉比对，可发现「写进去了但查不到」与「还没写」两类偏差。
  int errorLogInserts = 0;

  static bool _isAppStateInsert(String statement) =>
      statement.toLowerCase().contains('app_state');

  static bool _isErrorLogInsert(String statement) =>
      statement.toLowerCase().contains('error_logs');

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _inner.ensureOpen(user);

  @override
  Future<int> runInsert(String statement, List<Object?> args) {
    if (armed && _isAppStateInsert(statement)) {
      blockedInserts++;
      // 抛错（而非返回假 rowId）：要让 guardRepoWrite 的真实 catch 执行。
      throw StateError(
        'T-20261126-09 探针：注入 app_state 写入失败（blockedInserts='
        '$blockedInserts）',
      );
    }
    if (_isErrorLogInsert(statement)) errorLogInserts++;
    return _inner.runInsert(statement, args);
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _inner.runSelect(statement, args);

  // 非 INSERT 的写路径全部放行：本用例只在「建标记」这一步造失败。
  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _inner.runUpdate(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _inner.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _inner.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() => _inner.beginTransaction();

  @override
  QueryExecutor beginExclusive() => _inner.beginExclusive();

  @override
  Future<void> close() => _inner.close();
}

void main() {
  late _FailAppStateWritesExecutor executor;
  late AppDatabase db;

  setUp(() {
    // 单例跨用例残留会让读数不可解释（上一个用例的 repo 还挂着）。
    ErrorHandler.instance.resetForTesting();
    executor = _FailAppStateWritesExecutor(NativeDatabase.memory());
    db = AppDatabase.forTesting(executor);
    // ★ 必须自己挂：`appDatabaseProvider.overrideWithValue(db)` 绕过了 provider
    //   工厂，而 `attachRepository` 就在工厂里（`lib/providers/app_providers.dart`）。
    //   不挂 ⇒ captureError 只入内存队列 ⇒ 库里永远 0 条 ⇒ 假读数。
    ErrorHandler.instance.attachRepository(ErrorLogRepository(db));
  });

  tearDown(() async {
    ErrorHandler.instance.resetForTesting();
    await db.close();
  });

  Widget buildApp() => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const YueshengApp(),
  );

  /// 走到引导末页（「开始使用」出现）。
  ///
  /// 不硬编码页数：`OnboardingFlow._pages` 曾 3 → 5（`app_gate_test.dart:60-64`
  /// 记着这条教训），硬编码点击数会在增页时必红，且红因与被测行为无关。
  Future<void> advanceToLastPage(WidgetTester tester) async {
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
  }

  /// 排空 `ErrorHandler._persist` 的 unawaited 落库链。
  ///
  /// 不用 `sleep` / `pumpEventQueue`：内存库执行是同步的，其 Future 走微任务，
  /// `tester.pump()` 会把微任务队列排空 —— 显式同步点，不靠时间。
  Future<void> flushPersistQueue(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
  }

  // ───────────────────────────────────────────────────────────
  // ① 核心 + ② 防误删对照组（改前改后都应绿；改前因双写而红）
  //
  // ★ 入库形态 = 裁定 (c)：**与 `main.dart` 修复同批绿态入库**，不用 SKIP_GIT_GATE，
  //   不用 skip。本用例的价值不在「仓库里躺着一个红」，而在两条可重放的读数：
  //   1. 改前（`main.dart` sha256 `1e869ee3…b3b`，手工 captureError 仍在）：
  //      `rc=1`、`Expected: <1> / Actual: <2>`、红在下面这条 `expect(logs.length, 1)`。
  //   2. 改后（摘掉手工 captureError）→ `rc=0` + `All tests passed!` + `+2`。
  //   两段原文与复算命令：`.ai/team/runs/2026-11-27-T09-重复采集/01-改前红读数.md`。
  // 3. 为何不用 `skip: true`：实测 `+1 ~1` / `rc=0`（绿）但**零证明力**，
  //    且修复后无人被提醒删 skip ⇒ 退化成 §⑥「预置拿走覆盖」型假绿。
  // ⇒ 谁在守：改后本条若再次读到 2 条（例如有人把手工 captureError 加回来），
  //    会当场红 —— 这条才是「不许双写回潮」的机器判据。
  // ───────────────────────────────────────────────────────────
  testWidgets('核心：一次 app_state 写入失败 ⇒ error_logs 恰 1 条（实测条数见 reason）', (
    tester,
  ) async {
    // 隐私告知预置为「已确认」：本用例的被测对象是 `_completeIntro` 的重复采集，
    // 不是隐私弹层（弹层由 `app_gate_test.dart` 覆盖）。不预置会有两个副作用：
    //   ① 弹层挡在断言之前；② 确认弹层时又写一次 app_state ⇒ 污染日志计数。
    await AppStateRepository(db).setValue(kPrivacyNoticeAckKey, '1');

    // 捕获 debugPrint：V3 要求「引导完成标记写入失败」这行**保留**。
    //
    // ★ 复原必须用 body 内 `try/finally`，**不能**用 `addTearDown`：
    //   `TestWidgetsFlutterBinding._verifyInvariants` 在 **body 结束时**就校验
    //   「foundation 调试变量已被测试改动」⇒ tearDown 才复原已经太晚，
    //   该用例会因**环境类**报错而红（实测：变异后仍红，但红因是
    //   `The value of a foundation debug variable was changed by the test`，
    //   不是断言判红 —— 按纪律这种红一律视为无效，已重做）。
    final printed = <String>[];
    final previousDebugPrint = debugPrint;
    try {
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
        previousDebugPrint(message, wrapWidth: wrapWidth);
      };

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();
      expect(
        find.byType(OnboardingFlow),
        findsOneWidget,
        reason: '前置：首启应停在引导页（onboarding_completed 未被预置）',
      );

      await advanceToLastPage(tester);
      expect(
        executor.blockedInserts,
        0,
        reason: '武装前不得拦下任何写入 —— 建库/首启读阶段拦会炸在 schema 创建上',
      );

      // ★ 此刻才武装：引导页已就绪，之后凡是 app_state 的 INSERT 一律抛错。
      executor.armed = true;

      await tester.tap(find.widgetWithText(FilledButton, '开始使用'));
      await tester.pumpAndSettle();
      await flushPersistQueue(tester);

      // ── 探针自检（先证明这次测量真的发生了）────────────────────
      // 没有这一条，读数「0 条」与「探针坏了」外观完全相同。
      expect(
        executor.blockedInserts,
        greaterThanOrEqualTo(1),
        reason:
            '注入的 DB 写入失败必须真的发生过（blockedInserts=${executor.blockedInserts}）；'
            '为 0 说明 probe 没拦住写入，下面的条数读数不作数',
      );

      // ── ① 核心判据（**必须排在最前**：本用例存在的唯一理由）
      //
      // ★ 顺序不是随手排的（`flutter-widget-test-false-green` §⑧「对照遮蔽」）：
      //   实测把 ② 对照组放在前面时，任何让对照组先炸的缺陷（如削掉 debugPrint）
      //   都会让核心判据**一次都不执行**，而报告上只写「用例红了，红在对的地方」。
      //   实测证据：变异 C（只删 `debugPrint` 一行、保留手工 captureError）下，
      //   核心判据一条都没跑 ⇒ 那条读数**不能**用来证明「条数判据有牙齿」。
      //   ⇒ 核心判据前置后，变异 C 应在条数断言上红（2 条），与变异 A 同因。
      //
      // 改前：guard 的 error 一条 + `_completeIntro` 的 warn 一条 = **2 条** ⇒ 此断言红。
      // 改后：只剩 guard 那一条 ⇒ 绿。
      final logs = await ErrorLogRepository(db).queryErrorLogs();

      // 排空自检前置（否则 `logs.length` 可能读到偏小的值 ⇒ 缺陷存在也绿）。
      // ★ 只断言「查到条数 == 发起次数」，**不断言发起次数 >= 2**：后者修复后恒假
      //   （只剩 guard 一次采集）⇒ 会让「先红后绿」里的绿永远到不了。实测踩过。
      expect(
        logs.length,
        executor.errorLogInserts,
        reason:
            '查询结果 ${logs.length} 条应等于已发起的 error_logs 写入 '
            '${executor.errorLogInserts} 次；不等说明落库链未排空或写入被静默丢弃 '
            '—— 两种偏差都会让核心条数读数偏小（偏小 = 缺陷存在也绿）',
      );
      expect(
        executor.errorLogInserts,
        greaterThanOrEqualTo(1),
        reason:
            '本次测量必须至少发起过 1 次 error_logs 写入（实测 '
            '${executor.errorLogInserts} 次）；为 0 说明采集根本没发生，'
            '条数读数不作数',
      );

      expect(
        logs.length,
        1,
        reason:
            '一次 DB 写入失败只应留下 1 条 error_logs：`guardRepoWrite` 已在 catch 内'
            '采集同一次失败并 rethrow；`main.dart:_completeIntro` 的手工 '
            'captureError 是第二份 ⇒ 双写（T-20261126-09）。'
            '实测 ${logs.length} 条：'
            '${logs.map((l) => '${l.level}|${l.category}|${l.message}').toList()}',
      );

      // ── ② 防误删对照组（修复不得牺牲这三样）──────────────────
      expect(
        printed.any((m) => m.contains('[Intro] 引导完成标记写入失败')),
        isTrue,
        reason:
            'V3：`debugPrint` 降级痕迹必须保留。实测 debugPrint 输出：'
            '${printed.where((m) => m.contains('[Intro]')).toList()}',
      );

      final opLogs = logs
          .where((l) => l.message.contains('app_state.setOnboardingCompleted'))
          .toList();
      expect(
        opLogs,
        hasLength(1),
        reason:
            'V3：可追溯性不得降级 —— 必须仍有**恰一条**能定位到具体写操作'
            '（`app_state.setOnboardingCompleted`）的日志；'
            '实测 ${opLogs.length} 条：${opLogs.map((l) => '${l.level}/${l.message}').toList()}',
      );

      // 降级行为不得改变（边界 3）：写入失败也继续进主壳，用户不卡在引导页。
      expect(find.byType(OnboardingFlow), findsNothing, reason: '写入失败仍须离开引导页');
      expect(
        find.byType(BookshelfPage),
        findsOneWidget,
        reason: '写入失败也必须进主壳（用户不应卡在引导页）',
      );
    } finally {
      debugPrint = previousDebugPrint;
    }
  });

  // ───────────────────────────────────────────────────────────
  // ③ 正向路径（防误删）：夹具与成功路径本身不得产生日志
  //
  // 若这条也绿不了，说明「日志条数」这个观测点被别的东西污染，
  // ① 的读数就不可解释 —— 所以它是 ① 的前提，不是附赠。
  // ───────────────────────────────────────────────────────────
  testWidgets('正向：不注入失败 ⇒ 0 条 error_logs、标记落库 true、进主壳', (tester) async {
    await AppStateRepository(db).setValue(kPrivacyNoticeAckKey, '1');

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingFlow), findsOneWidget, reason: '前置：首启应停在引导页');

    await advanceToLastPage(tester);
    // 不武装：让真实写入成功走完。
    await tester.tap(find.widgetWithText(FilledButton, '开始使用'));
    await tester.pumpAndSettle();
    await flushPersistQueue(tester);

    expect(
      executor.blockedInserts,
      0,
      reason: '未武装时不得拦下任何写入（否则本条的「0 条日志」读数是人为造的）',
    );

    // 标记真的落库（不是只看「回调被调过」—— 见 app_gate_test 的同类教训）
    expect(
      await AppStateRepository(db).getOnboardingCompleted(),
      isTrue,
      reason: '成功路径必须把 onboarding_completed 落库为 true',
    );

    final logs = await ErrorLogRepository(db).queryErrorLogs();
    expect(
      logs,
      isEmpty,
      reason:
          '成功路径不得产生任何 error_logs，否则 ① 的条数读数被污染。'
          '实测 ${logs.length} 条：${logs.map((l) => '${l.level}/${l.message}').toList()}',
    );

    expect(find.byType(OnboardingFlow), findsNothing);
    expect(find.byType(BookshelfPage), findsOneWidget);
  });
}
