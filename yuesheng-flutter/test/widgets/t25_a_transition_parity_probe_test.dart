// ─────────────────────────────────────────────────────────────
// t25_a_transition_parity_probe_test — T-20261125-01「A 面待验项」的可复跑形态
//
// 背景（六面报告 §一 末句，挂了两天没人验）：
//   「转场是否真不同须验收卡走查确认（MaterialPageRoute 也读主题
//     PageTransitionsTheme，理论同转场；本卡不预判）」
//
// 本用例把那次「一次性临时探针」固化成只读诊断 + 回归守卫，断四件事：
//
//   P1 机制：两条路径的 route **实际类型**都 `is MaterialRouteTransitionMixin`
//            （Navigator.push → MaterialPageRoute；
//             context.push → _PageBasedMaterialPageRoute，由 MaterialPage 产出）
//   P2 时长：两条路径 route.transitionDuration 都 == AppMotion.durationTransition
//            （220ms），且主题 builder 是 YueFadeSlidePageTransitionsBuilder
//   P3 曲线：两条路径的 slide dy 在同一组 5 个时间点逐点相同（差 < 1e-6）
//            ⇒ 视觉转场形态一致。这是**收窄**结论，不是「一致就没事」。
//   P4 真分叉：不在视觉，在**叠加层与 go_router 栈可见性**（见组内注释 + 实测）
//
// ★ 这是本批**唯一被授权**的 test 改动（卡面 §四 声明改动面只含 reports 与台账；
//   主理人以「L4 手段优先：没有可复跑读数的问题不可验收」为由例外授权）。
//   用例纯只读：不写盘、不改 lib、不依赖 db / provider / 平台通道。
//
// ★ 口径警示（本仓已栽过一次，故写死在这里）：本文件**只断言转场形态**，
//   不涉及 E 面容量百分比。E 面 `47.4% = 容器÷内容 351.6/741`，视口 800×600；
//   卡面 `69.3%` 是另一组尺（330/476，不含把手与取消行）——
//   两者不可并列归因。容量口径见
//   reports/2026-11-28-T25-01-E面重写-已落地形态与剩余缺口.md §一。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/config/app_motion.dart';
import 'package:writingcoach/theme/app_theme.dart';

// ── 探针用最小路由表：1 个 shell（2 branch）+ 1 个顶层路由 ──
// 结构与 lib/router/app_router.dart 同构（StatefulShellRoute.indexedStack），
// 但只用无状态占位页 ⇒ 不牵 db / provider / 平台通道。
const String _kBranchHome = '/probe-home';
const String _kBranchOther = '/probe-other';
const String _kTopLevel = '/probe-top';

GoRouter _buildProbeRouter({String initialLocation = _kBranchHome}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => Scaffold(
          body: shell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: shell.currentIndex,
            onDestinationSelected: shell.goBranch,
            destinations: const [
              NavigationDestination(icon: Icon(Icons.menu_book), label: '甲'),
              NavigationDestination(icon: Icon(Icons.chat), label: '乙'),
            ],
          ),
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: _kBranchHome,
                builder: (context, state) => const _ProbeHome(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: _kBranchOther,
                builder: (context, state) =>
                    const Scaffold(body: Center(child: Text('乙页'))),
              ),
            ],
          ),
        ],
      ),
      // 顶层路由（非 shell 内）—— context.push 的目标
      GoRoute(
        path: _kTopLevel,
        builder: (context, state) =>
            const Scaffold(body: Center(child: Text('顶层目标页'))),
      ),
    ],
  );
}

/// shell 内的首页：两个按钮各触发一条推送路径。
class _ProbeHome extends StatelessWidget {
  const _ProbeHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('探针首页'),
            // 路径 A：Navigator.push 推一个匿名 MaterialPageRoute
            ElevatedButton(
              key: const Key('probe-navigator-push'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: Center(child: Text('物料路由页'))),
                ),
              ),
              child: const Text('Navigator.push'),
            ),
            // 路径 B：go_router 的 context.push
            ElevatedButton(
              key: const Key('probe-context-push'),
              onPressed: () => context.push<void>(_kTopLevel),
              child: const Text('context.push'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _pumpProbe(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    MaterialApp.router(theme: buildAppTheme(), routerConfig: router),
  );
  await tester.pump();
}

/// 取「包住指定文字的那个 SlideTransition」当前位移 dy（取最近的祖先）。
double _dyOf(WidgetTester tester, String marker) {
  final finder = find.ancestor(
    of: find.text(marker),
    matching: find.byType(SlideTransition),
  );
  expect(
    finder,
    findsWidgets,
    reason: '目标页「$marker」外层应存在 SlideTransition（转场未被绕过）',
  );
  return tester.widget<SlideTransition>(finder.first).position.value.dy;
}

/// 走一条推送路径，按 5 个时间点（50/100/150/200/250ms）采样 slide dy。
Future<List<double>> _sampleDy(
  WidgetTester tester,
  String buttonLabel,
  String marker,
) async {
  await tester.tap(find.text(buttonLabel));
  await tester.pump(); // 起帧：animation 从 0 开始
  final samples = <double>[];
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    samples.add(_dyOf(tester, marker));
  }
  return samples;
}

void main() {
  // ═══════════════════════════════════════════════════════════
  // P1/P2 机制层：两条路径命中同一个 PageTransitionsBuilder
  // ═══════════════════════════════════════════════════════════
  group('T25-A P1/P2 机制层', () {
    testWidgets('P1 两条路径的 route 实际类型都混入 MaterialRouteTransitionMixin', (
      tester,
    ) async {
      // —— 路径 A ——
      final routerA = _buildProbeRouter();
      await _pumpProbe(tester, routerA);
      Route<dynamic>? routeA;
      await tester.tap(find.text('Navigator.push'));
      await tester.pumpAndSettle();
      routeA = ModalRoute.of(tester.element(find.text('物料路由页')));
      expect(routeA, isNotNull);
      expect(
        routeA,
        isA<MaterialRouteTransitionMixin<dynamic>>(),
        reason:
            'Navigator.push(MaterialPageRoute) 应混入 MaterialRouteTransitionMixin',
      );
      // 落地记录：实测类型串
      expect(routeA.runtimeType.toString(), 'MaterialPageRoute<void>');

      // —— 路径 B ——
      final routerB = _buildProbeRouter();
      await _pumpProbe(tester, routerB);
      await tester.tap(find.text('context.push'));
      await tester.pumpAndSettle();
      final routeB = ModalRoute.of(tester.element(find.text('顶层目标页')));
      expect(routeB, isNotNull);
      expect(
        routeB,
        isA<MaterialRouteTransitionMixin<dynamic>>(),
        reason: 'context.push(GoRoute) 应经 MaterialPage 产出同样混入该 mixin 的 route',
      );
      // 落地记录：实测类型串（go_router 14.8.1 → MaterialPage →
      // _PageBasedMaterialPageRoute）
      expect(
        routeB.runtimeType.toString(),
        '_PageBasedMaterialPageRoute<void>',
      );
      // 两者都是 MaterialRouteTransitionMixin ⇒ 转场 builder 同源
      expect(
        routeA.runtimeType == routeB.runtimeType,
        isFalse,
        reason: '类型不同、但 mixin 相同 —— 这正是「机制同、实现类不同」的实证',
      );
    });

    testWidgets('P2 主题 builder 是 YueFadeSlide，两条路径 route 时长都是 220ms', (
      tester,
    ) async {
      // 主题侧
      final theme = buildAppTheme();
      final builder =
          theme.pageTransitionsTheme.builders[TargetPlatform.android];
      expect(builder, isA<YueFadeSlidePageTransitionsBuilder>());
      expect(builder!.transitionDuration, AppMotion.durationTransition);
      expect(builder.transitionDuration, const Duration(milliseconds: 220));

      // ★ 口径：MaterialRouteTransitionMixin.transitionDuration 的实现是
      //   `_getPageTransitionBuilder(navigator!.context)?.transitionDuration`
      //   ⇒ **必须有 navigator 才能读**；裸在 test() 里读会 null-check 崩。
      //   故 route 侧时长只能在 widget 环境里验。

      // 路径 A 侧
      await _pumpProbe(tester, _buildProbeRouter());
      await tester.tap(find.text('Navigator.push'));
      await tester.pumpAndSettle();
      final durA = ModalRoute.of(
        tester.element(find.text('物料路由页')),
      )!.transitionDuration;
      expect(durA, const Duration(milliseconds: 220));

      // 路径 B 侧（换新 router，避免上一路残留）
      await _pumpProbe(tester, _buildProbeRouter());
      await tester.tap(find.text('context.push'));
      await tester.pumpAndSettle();
      final durB = ModalRoute.of(
        tester.element(find.text('顶层目标页')),
      )!.transitionDuration;
      expect(durB, const Duration(milliseconds: 220));
      expect(durB, durA, reason: '两条路径转场时长应相等');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // P3 曲线层：slide dy 逐点相同 + 绝对锚点
  // ═══════════════════════════════════════════════════════════
  group('T25-A P3 曲线层', () {
    testWidgets('P3 两条路径 5 个采样点 dy 逐点相等，且曲线落在 easeOutCubic 锚点上', (
      tester,
    ) async {
      // —— 路径 A ——
      await _pumpProbe(tester, _buildProbeRouter());
      expect(find.text('探针首页'), findsOneWidget);
      final dyManual = await _sampleDy(tester, 'Navigator.push', '物料路由页');
      await tester.pump(const Duration(milliseconds: 400)); // 收尾

      // —— 路径 B ——
      await _pumpProbe(tester, _buildProbeRouter());
      expect(find.text('探针首页'), findsOneWidget);
      final dyRouter = await _sampleDy(tester, 'context.push', '顶层目标页');
      await tester.pump(const Duration(milliseconds: 400));

      // ① 相对断言：两路逐点相同（「形态一致」的直接证据）
      expect(dyRouter.length, dyManual.length);
      for (var i = 0; i < dyManual.length; i++) {
        expect(
          dyRouter[i],
          closeTo(dyManual[i], 1e-6),
          reason: '第 ${(i + 1) * 50}ms 采样点两条路径 dy 应相同',
        );
      }

      // ② 绝对锚点（**不可省**）：只做相对断言时，「两条路径同时被换曲线」
      //    也会全绿 —— 实测确认过：把 AppMotion.curveStandard 换成 Curves.linear，
      //    两路同变、相对断言仍通过。故必须再钉住曲线的绝对值。
      //
      //    理论推导（slideBegin.dy = 0.03，220ms，easeOutCubic）：
      //      dy(t) = 0.03 × (1 − easeOutCubic(t/220))
      //      50ms  ⇒ t=0.2273，曲线 0.5385，dy ≈ 0.01384
      //    实测（HEAD e9c2ef4e）：0.013216 / 0.004714 / 0.001250 /
      //                            0.000083 / 0.000000
      //    ⇒ 容差取 [0.010, 0.018]（linear 会给 0.0232 ⇒ 必红）
      expect(
        dyManual[0],
        inInclusiveRange(0.010, 0.018),
        reason: '50ms 处 dy 应落在 easeOutCubic 区间；超出说明曲线被换',
      );
      // 单调递减，且 200ms 后基本归零
      for (var i = 1; i < dyManual.length; i++) {
        expect(dyManual[i], lessThanOrEqualTo(dyManual[i - 1]));
      }
      expect(dyManual[3], lessThan(0.001));
      expect(dyManual[4], lessThan(1e-9));
      // 起点 > 0 且不超过 slideBegin（0.03）
      expect(dyManual.first, greaterThan(0));
      expect(dyManual.first, lessThan(0.03));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // P4 行为层：真分叉在「叠加层 + go_router 栈可见性」，不在视觉转场
  // ═══════════════════════════════════════════════════════════
  group('T25-A P4 真分叉（叠加层 + 栈可见性）', () {
    testWidgets('P4a Navigator.push 落 branch navigator：底栏仍在、go_router 栈不可见', (
      tester,
    ) async {
      final router = _buildProbeRouter();
      await _pumpProbe(tester, router);
      // 前置：shell 内有 2 个 Navigator（root + branch）
      expect(find.byType(Navigator), findsNWidgets(2));
      final matchesBefore =
          router.routerDelegate.currentConfiguration.matches.length;

      await tester.tap(find.text('Navigator.push'));
      await tester.pumpAndSettle();

      expect(find.text('物料路由页'), findsOneWidget);
      // ① 叠加层：底栏仍在 ⇒ 推的是 branch navigator 的栈，不是 root
      expect(find.byType(NavigationBar), findsOneWidget);
      // ② go_router 栈：match 数**完全不变** ⇒ go_router 对这次推送零感知
      expect(
        router.routerDelegate.currentConfiguration.matches.length,
        matchesBefore,
        reason: 'Navigator.push 不产 RouteMatch ⇒ go_router 的栈里看不到它',
      );
      // ③ 三口径 URL 全不变（详见 P4g）
      expect(router.routeInformationProvider.value.uri.path, _kBranchHome);
      expect(router.state.uri.path, _kBranchHome);
    });

    testWidgets('P4b context.push 落 root navigator：全屏覆盖、go_router 栈可见', (
      tester,
    ) async {
      final router = _buildProbeRouter();
      await _pumpProbe(tester, router);
      final matchesBefore =
          router.routerDelegate.currentConfiguration.matches.length;

      await tester.tap(find.text('context.push'));
      await tester.pumpAndSettle();

      expect(find.text('顶层目标页'), findsOneWidget);
      // ① 叠加层：底栏消失 ⇒ 顶层路由覆盖在 shell 之上（root navigator）
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(Navigator), findsOneWidget);
      // ② go_router 栈：match 数 +1，且末项是 ImperativeRouteMatch
      final cfg = router.routerDelegate.currentConfiguration;
      expect(cfg.matches.length, matchesBefore + 1);
      expect(cfg.matches.last.runtimeType.toString(), 'ImperativeRouteMatch');
      // ③ GoRouter.state.uri 反映目标（≠ 对外 URL，见 P4g）
      expect(router.state.uri.path, _kTopLevel);
    });

    testWidgets('P4c 分叉后果 1：go() 会清掉 context.push 的页，但清不掉 Navigator.push 的页', (
      tester,
    ) async {
      // —— 路径 A：go 走一圈回来，branch 栈被 shell 保留 ⇒ 页面还在 ——
      final routerA = _buildProbeRouter();
      await _pumpProbe(tester, routerA);
      await tester.tap(find.text('Navigator.push'));
      await tester.pumpAndSettle();
      expect(find.text('物料路由页'), findsOneWidget);

      routerA.go(_kBranchOther);
      await tester.pumpAndSettle();
      expect(find.text('乙页'), findsOneWidget);
      expect(find.text('物料路由页'), findsNothing);

      routerA.go(_kBranchHome);
      await tester.pumpAndSettle();
      expect(
        find.text('物料路由页'),
        findsOneWidget,
        reason: 'branch navigator 的栈由 IndexedStack 保留 ⇒ go 回来后页面仍在',
      );

      // —— 路径 B：go 直接把 ImperativeRouteMatch 清掉，且不可恢复 ——
      final routerB = _buildProbeRouter();
      await _pumpProbe(tester, routerB);
      await tester.tap(find.text('context.push'));
      await tester.pumpAndSettle();
      expect(find.text('顶层目标页'), findsOneWidget);

      routerB.go(_kBranchOther);
      await tester.pumpAndSettle();
      expect(find.text('乙页'), findsOneWidget);
      expect(find.text('顶层目标页'), findsNothing);

      routerB.go(_kBranchHome);
      await tester.pumpAndSettle();
      expect(
        find.text('顶层目标页'),
        findsNothing,
        reason: 'go 深链语义：ImperativeRouteMatch 不在目标 location 里 ⇒ 被丢弃',
      );
      expect(routerB.routerDelegate.currentConfiguration.matches.length, 1);
    });

    testWidgets(
      'P4d 分叉后果 2：深链命中差异（context.push 目标可 cold start，匿名 route 无 URI）',
      (tester) async {
        // context.push 的目标在路由表里 ⇒ 冷启动该 location 可直达
        await _pumpProbe(
          tester,
          _buildProbeRouter(initialLocation: _kTopLevel),
        );
        expect(find.text('顶层目标页'), findsOneWidget);

        // Navigator.push 的匿名 MaterialPageRoute 不在路由表 ⇒ 没有任何 location
        // 能让它通过冷启动出现（P4a 已证 routeInformationProvider 也不变）。
        // ⇒ 「不可深链」不是配置问题，是**结构上不可能**。
        await _pumpProbe(tester, _buildProbeRouter());
        expect(find.text('物料路由页'), findsNothing);
      },
    );

    // ★ 口径补钉 2：**三个「URL」字段三个值，混用必错**（本轮实测踩到两次）
    //   同一时刻（context.push 后）：
    //     routeInformationProvider.value.uri  = /probe-home   ← 对外 URL（默认不反映 push）
    //     routerDelegate.currentConfiguration.uri = /probe-home ← 排除 ImperativeRouteMatch
    //     router.state.uri                    = /probe-top    ← **唯一反映 push 目标**
    //   ⇒ 「`context.push` 会改变 URL」是**错的**。准确说法：
    //     · 在 Android/移动端，push 不改变系统级 URL（本来也没有）；
    //     · `optionURLReflectsImperativeAPIs = true` 且 web 时，**对外 URL 才**反映；
    //     · 唯一无条件反映 push 的是 `GoRouter.state.uri`（App 内状态）。
    //   ⇒ 判「两条路径分叉」**不能**用 URL 字段，必须用 match 数与 Navigator 数（P4a/P4b 已钉）。
    testWidgets('P4g 口径对照：三个 URL 字段三个值，只有 state.uri 反映 push', (tester) async {
      for (final label in ['Navigator.push', 'context.push']) {
        final router = _buildProbeRouter();
        await _pumpProbe(tester, router);

        final ripBefore = router.routeInformationProvider.value.uri.toString();
        final cfgBefore = router.routerDelegate.currentConfiguration.uri
            .toString();
        final stateBefore = router.state.uri.toString();

        await tester.tap(find.text(label));
        await tester.pumpAndSettle();

        final isCtxPush = label == 'context.push';
        // ① currentConfiguration.uri：两条路径都不变（排除 ImperativeRouteMatch）
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          cfgBefore,
          reason: '$label：currentConfiguration.uri 应不变',
        );
        // ② routeInformationProvider（对外 URL）：两条路径都不变
        //    （默认 optionURLReflectsImperativeAPIs == false）
        expect(
          router.routeInformationProvider.value.uri.toString(),
          ripBefore,
          reason: '$label：对外 URL 应不变（默认不反映 imperative API）',
        );
        // ③ GoRouter.state.uri：**只有** context.push 会变
        if (isCtxPush) {
          expect(router.state.uri.path, _kTopLevel);
          expect(router.state.uri.toString(), isNot(stateBefore));
        } else {
          expect(router.state.uri.toString(), stateBefore);
        }
      }
    });

    // ★ 口径补钉 3：`optionURLReflectsImperativeAPIs` 默认 false。
    //   置 true 后对外 URL 才会反映 context.push 的目标 location。
    //   ⇒ 「context.push 一定改 URL」是错的；准确说法是「**在 web 且该开关
    //   为 true 时**才反映到对外 URL」，Android 上对外 URL 本来就不存在。
    testWidgets('P4h go_router 默认 optionURLReflectsImperativeAPIs == false', (
      tester,
    ) async {
      expect(GoRouter.optionURLReflectsImperativeAPIs, isFalse);
    });
  });
}
