// ─────────────────────────────────────────────────────────────
// VerificationConfigSection 状态判据 widget 测试（S1 阶段三 (d) · 甄可验）
//
// 判据真源（现场 Read，非记忆）：
//   .ai/team/runs/2026-11-07-发现层展示批/03-简知微-S1设计稿.md
//     §状态设计 3 :107-117（A–E 逐字规格）
//   04c-主理人-路①裁定落地与会话交接.md §2 / §3(d)
//   04b-主理人-阶段二验收结论与待裁点.md §三（routing checker 口径修正）
//
// 三例成套（正 / 负向自测 / 防误删）：
//   A 负例 · B 正例 · E+接线真 router；C 三次单侧变异实测见
//   10-甄可验-S1状态判据widget测试.md（不写在用例里，避免污染例集）。
//
// ★ 与派单口径的一处现场纠偏（E1，file:line 现场重取）：
//   派单写「目标页独有文案 = find.text('独立核对（验证层）配置')」。
//   实测该串在**来源页** verification_config_section.dart:73
//   （SectionCard title）与**目标页** verification_config_page.dart:198
//   （_buildFormCard 的 SectionCard title）各有一份 ⇒ 不独有，
//   用它作「判达」会双命中 / 不跳转也命中 ⇒ 零鉴别力。
//   改以目标页 AppBar title '独立核对配置'（:153，不受 _isLoading 门控）
//   作主判据，另加 :177 的独立 Text 作第二独有判据。详见产物文档。
//
// 隔离：零真实网络 / 零真实 LLM / 零真实 flutter_secure_storage。
//   A/B 用注入 fake storage；生产 router 用例 stub 平台通道
//   （范式照抄 api_config_page_test.dart:98-122，本项目已验证 E1）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/features/app_settings/verification_config_page.dart';
import 'package:writingcoach/features/app_settings/verification_config_section.dart';
import 'package:writingcoach/features/app_settings/widgets/settings_cards.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/services/verification_gate.dart';

/// 三空串：判据 A 的真空，**必须经 fake storage 注入**，不得靠「不传 storage」
/// 制造空（主链有 resolveLlmConfig fallback，省略参数不构成真空，见 03 :113）。
const VerificationKeys _kEmptyKeys = VerificationKeys(
  baseUrl: '',
  apiKey: '',
  model: '',
);

/// 三键齐全：与三空串在 VerificationKeys.isComplete 上必然取反 ⇒ 夹具有鉴别力。
const VerificationKeys _kCompleteKeys = VerificationKeys(
  baseUrl: 'https://verify.example.com/v1',
  apiKey: 'sk-verify-fixture-key',
  model: 'verify-fixture-model',
);

// ★ 期望侧一律钉**字面量**，不引用生产常量 / helper。
//   引用生产真源会让期望与被测物同源 ⇒ 改生产时两边同步平移 ⇒ 断言永真
//   （flutter-widget-test-false-green ⑦，本项目 2026-10-04 实测 27 条变异全绿）。
const String _kPath = '/settings/verification-config';
const String _kTargetTitle = '独立核对配置';
const String _kSectionTitle = '独立核对（验证层）配置';
const String _kEntryLabel = '配置独立核对';
const String _kOfflineCopy = '配置保存在本机，离线也可修改。';
const String _kNotFound = '页面未找到';
const String _kEmptyPlaceholderKey = 'verification_empty_placeholder';

/// 注入式 fake：覆盖 load() 返回构造好的三键。
/// 父类构造仅创建 `const FlutterSecureStorage()` 对象（不发起平台通道），
/// 且 load() 被覆盖后 _storage 永不被读 ⇒ 零真实 flutter_secure_storage 依赖。
class _FakeKeysStorage extends VerificationKeysStorage {
  final VerificationKeys _keys;

  _FakeKeysStorage(this._keys);

  @override
  Future<VerificationKeys> load() async => _keys;
}

void main() {
  late AppDatabase db;
  late Map<String, String> secure;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    secure = <String, String>{};
    // 生产 router 用例里 SettingsPage 挂的是 const VerificationConfigSection()
    // （无注入），会走真实 VerificationKeysStorage().load()；不 stub 通道会在
    // testWidgets 下挂起 / 抛 MissingPluginException ⇒ 页面停在 loading（假红）。
    // 范式照抄 api_config_page_test.dart:98-122（本项目已验证 E1）。
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (call) async {
            final key = (call.arguments as Map?)?['key'] as String?;
            switch (call.method) {
              case 'read':
                return secure[key];
              case 'write':
                secure[key!] = (call.arguments as Map)['value'] as String;
                return null;
              case 'delete':
                secure.remove(key);
                return null;
            }
            return null;
          },
        );
  });

  tearDown(() async => db.close());

  /// A/B 用：**真 GoRouter**（不是 mock 掉 context.push 的替身）。
  /// 首页直接挂注入 fake 的 Section；verificationConfig 路由的 builder 命中时
  /// 记一笔 —— 这是「真实导航到达该路由」的证据，而非「断言 push 被调用」。
  /// 裸 MaterialApp 会让 context.push 抛 No GoRouter found（假红）；
  /// 而替身 router 只验 push 调用时，路由目标写错也照样绿（#X6 :725-749）。
  GoRouter buildSectionRouter({
    required VerificationKeys keys,
    required List<String> pushSpy,
  }) {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: SingleChildScrollView(
              child: VerificationConfigSection(storage: _FakeKeysStorage(keys)),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.verificationConfig,
          builder: (context, state) {
            pushSpy.add(state.uri.path);
            return VerificationConfigPage(storage: _FakeKeysStorage(keys));
          },
        ),
      ],
    );
  }

  Future<void> pumpSection(WidgetTester tester, GoRouter router) async {
    // ① 放大视口：容器懒构建会让「找不到」空过；每个 findsNothing 前配阳性对照。
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  /// 生产 appRouter（真 router）范式：照抄 settings_page_test.dart:834-844
  /// 的 pumpRouter / api_config_page_test.dart:730-738 的 #X6。
  Future<void> pumpProductionRouter(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 双向滚动进视口（照抄 api_config_page_test.dart:756-776）。
  Future<void> scrollUntilVisibleText(WidgetTester tester, String label) async {
    final finder = find.text(label);
    if (finder.evaluate().isNotEmpty) return;
    final listView = find.byType(Scrollable).first;
    try {
      await tester.dragUntilVisible(finder, listView, const Offset(0, -200));
      await tester.pumpAndSettle();
    } catch (_) {
      // 已到顶部仍找不到 ⇒ 交给后续 expect 判失败，不静默当通过。
    }
    if (finder.evaluate().isNotEmpty) return;
    try {
      await tester.dragUntilVisible(finder, listView, const Offset(0, 200));
      await tester.pumpAndSettle();
    } catch (_) {
      // 已滚到边界仍找不到 ⇒ 交给后续 expect 判失败，不静默当通过。
    }
  }

  /// 滚到**可点**位置：ListView 惰性构建会让控件 find 得到却点在视口外，
  /// #X6 首跑实测 tap 静默不生效（api_config_page_test.dart:778-786）。
  Future<void> ensureOnScreen(WidgetTester tester, String label) async {
    await scrollUntilVisibleText(tester, label);
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  // ── A 负例（03 :113）────────────────────────────────────────
  // 变异②（状态行恒隐藏「未启用」文本）⇒ 本例必须红，见产物文档 C。
  testWidgets('A 未配置三空串 - 未启用可见、无空态占位、无暂无', (tester) async {
    final pushSpy = <String>[];
    await pumpSection(
      tester,
      buildSectionRouter(keys: _kEmptyKeys, pushSpy: pushSpy),
    );

    // ①⑧ 阳性对照：先证明页面真的渲染了；用「至少 1 个」而非精确计数，
    // 避免注入违例时对照行先炸、语义断言被遮蔽。
    expect(
      find.text(_kSectionTitle),
      findsAtLeastNWidgets(1),
      reason: '页面真的渲染了 SectionCard，缺席断言才有意义',
    );
    expect(find.byType(ActionRow), findsWidgets);

    // 规格 A：整句唯一短语（D），不用 textContaining('启用')——
    // 「已启用」含「启用」会假红；也不用 textContaining('未配置')——
    // 主链警告条常驻「尚未配置 API」。
    expect(find.text('未启用'), findsOneWidget);
    expect(find.byKey(const Key(_kEmptyPlaceholderKey)), findsNothing);
    expect(find.textContaining('暂无'), findsNothing);

    // 防误删：空态不得退化成「已启用」，入口 ActionRow 不得被收掉。
    expect(find.text('已启用'), findsNothing);
    expect(find.text(_kEntryLabel), findsOneWidget);
  });

  // ── B 正例（03 :114）────────────────────────────────────────
  // 变异①（状态行恒显示「未启用」）⇒ 本例必须红，见产物文档 C。
  testWidgets('B 配置齐 - 已启用、否定未启用、tap 触发真实 push', (tester) async {
    final pushSpy = <String>[];
    await pumpSection(
      tester,
      buildSectionRouter(keys: _kCompleteKeys, pushSpy: pushSpy),
    );

    expect(find.byType(ActionRow), findsWidgets); // 规格 B
    expect(find.text(_kEntryLabel), findsOneWidget); // 阳性对照
    expect(find.text('已启用'), findsOneWidget);
    expect(find.text('未启用'), findsNothing); // D：整句唯一短语

    // D 陷阱自证：短词「启用」在「已启用」态必然命中 ⇒
    // 若否定写成 find.textContaining('启用'), findsNothing 就会假红。
    expect(find.textContaining('启用'), findsWidgets);

    // E/B：tap 后必须捕获到**真实**路由 push（真 GoRouter builder 被真实调用）。
    expect(pushSpy, isEmpty);
    await tester.tap(find.text(_kEntryLabel));
    await tester.pumpAndSettle();
    expect(pushSpy, [_kPath], reason: '字面量钉路径，常量漂移会红');
    expect(
      find.text(_kTargetTitle),
      findsOneWidget,
      reason: '目标页 AppBar :153 独有文案，证明真的导航到达',
    );
  });

  // ── E 零死按钮 + 目标页/来源页独有内容（03 :117 / 04c §2）────
  testWidgets('E 生产 router 点入口 - 目标页独有内容出现且来源页消失', (tester) async {
    expect(AppRoutes.verificationConfig, _kPath, reason: '常量字面量（期望侧钉死，非生产同源）');

    await pumpProductionRouter(tester);
    appRouter.go(AppRoutes.settings);
    await tester.pumpAndSettle();

    await ensureOnScreen(tester, _kEntryLabel);
    await tester.tap(find.text(_kEntryLabel));
    await tester.pumpAndSettle();

    // 判据 = 目标页独有内容。★ 不是派单写的「独立核对（验证层）配置」：
    //   那串来源页 :73 与目标页 :198 各一份，不独有、零鉴别力（见文件头注释）。
    expect(find.byType(VerificationConfigPage), findsOneWidget);
    expect(
      find.text(_kTargetTitle),
      findsOneWidget,
      reason: '目标页 AppBar :153，不受 _isLoading 门控',
    );
    expect(
      find.text(_kOfflineCopy),
      findsOneWidget,
      reason: '目标页 :177 独立 Text；来源页 description 是更长的整句，精确不匹配',
    );
    expect(
      find.text(_kNotFound),
      findsNothing,
      reason: '不得落到 errorBuilder（删/改 GoRoute 会命中 ⇒ 此断言红）',
    );
    // ★ 负例：来源页独有内容已消失（#X6 :748 范式，push 后来源页 offstage）。
    expect(find.text(_kEntryLabel), findsNothing);
  });

  // ── Flutter 路由接线断言（04b §三：routing checker 不覆盖 AppRoutes/GoRoute）──
  // 变异③（删 app_router.dart:346-349 顶层 GoRoute）⇒ 本例必须红。
  testWidgets('接线 appRouter 直达 verificationConfig - GoRoute 渲染目标页', (
    tester,
  ) async {
    expect(AppRoutes.verificationConfig, _kPath);

    await pumpProductionRouter(tester);
    appRouter.go(AppRoutes.verificationConfig);
    await tester.pumpAndSettle();

    expect(
      find.byType(VerificationConfigPage),
      findsOneWidget,
      reason:
          'app_router.dart:346-349 顶层 GoRoute 的 builder 指向 VerificationConfigPage',
    );
    expect(find.text(_kTargetTitle), findsOneWidget);
    expect(
      find.text(_kNotFound),
      findsNothing,
      reason: '删掉 GoRoute ⇒ 落 errorBuilder ⇒ 此断言必红（变异③ 自证）',
    );
  });
}
