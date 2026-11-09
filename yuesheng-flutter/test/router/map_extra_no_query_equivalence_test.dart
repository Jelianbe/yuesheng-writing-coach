// U6 前置断言（T-20261023-04）：**先补断言再改代码**。
// 12 个 Map extra 消费点：不传 query 时 builder 产物构造参数逐字取自 extra。
// 施工加 queryParameters fallback 后必须继续全绿；若 query 分支抢占 extra
// （无 query 时取到空值）⇒ 本文件必红。零 lib 改动。
//
// 口径：直接调真源 appRouter.configuration.routes 里的 GoRoute.builder，
// 只验「state → Widget 构造参数」，不渲染页面 —— 3 个详情页在空库下会
// 自己 Navigator.pop，页面生命周期不属于路由参数的等价性问题。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/features/manuscript/manuscript_detail_page.dart';
import 'package:writingcoach/features/writing/writing_page.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/widgets/placeholder_page.dart';

import 'map_extra_no_query_cases.dart';

/// /writing/:chapterId 是唯一带 path 参数的 Map 路由，其余 location 即 pattern。
String patternOf(String location) =>
    location.startsWith('/writing/') ? AppRoutes.writingChapter : location;

GoRoute routeFor(String pattern) => appRouter.configuration.routes
    .whereType<GoRoute>()
    .firstWhere((r) => r.path == pattern);

GoRouterState stateFor(
  String location,
  Object? extra, [
  Map<String, String> pathParams = const <String, String>{},
]) {
  return GoRouterState(
    appRouter.configuration,
    uri: Uri.parse(location),
    matchedLocation: location,
    fullPath: patternOf(location),
    pathParameters: pathParams,
    extra: extra,
    pageKey: ValueKey<String>(location),
  );
}

void main() {
  // builder 需要 BuildContext（writing 的 onBack 闭包捕获它，但本测试不触发），
  // 泵一个最小壳取一个真实 context，不渲染任何目标页面。
  Future<BuildContext> contextOf(WidgetTester t) async {
    await t.pumpWidget(
      const MaterialApp(home: SizedBox(key: Key('u6-context'))),
    );
    return t.element(find.byKey(const Key('u6-context')));
  }

  for (var i = 0; i < mapExtraCases.length; i++) {
    final c = mapExtraCases[i];
    testWidgets('U6 #${i + 1} ${c.name} 无 query ⇒ 参数逐字取自 extra', (t) async {
      expect(c.location.contains('?'), isFalse, reason: '本例必须走无 query 路径');
      final ctx = await contextOf(t);
      final route = routeFor(patternOf(c.location));
      final widget = route.builder!(
        ctx,
        stateFor(c.location, c.extra, c.pathParams),
      );
      expect(
        widget.runtimeType,
        c.pageType,
        reason: '${c.name} builder 产物类型漂移（extra 可能被 query 分支抢占）',
      );
      expect(
        c.read(widget),
        c.expected,
        reason: '${c.name} 页面构造字段与 extra 不逐字相等',
      );
      if (c.emptyTitle != null) {
        final empty = route.builder!(
          ctx,
          stateFor(c.location, null, c.pathParams),
        );
        expect(empty, isA<PlaceholderPage>());
        expect(
          (empty as PlaceholderPage).title,
          c.emptyTitle,
          reason: '缺参守卫标题不得漂移',
        );
      }
    });
  }

  testWidgets('U6 #13 writing/:chapterId 无 extra ⇒ manuscriptId 空但 path 仍在', (
    t,
  ) async {
    final ctx = await contextOf(t);
    final widget =
        routeFor(AppRoutes.writingChapter).builder!(
              ctx,
              stateFor('/writing/ch-eq-13', null, {'chapterId': 'ch-eq-13'}),
            )
            as WritingPage;
    expect(widget.chapterId, 'ch-eq-13');
    expect(widget.manuscriptId, '');
    expect(widget.initialCursorOffset, isNull);
  });

  testWidgets('U6 #14 已有 ?id= 兜底：无 extra 时 query 仍能直达', (t) async {
    final ctx = await contextOf(t);
    final widget =
        routeFor(AppRoutes.manuscriptDetail).builder!(
              ctx,
              stateFor('/manuscript-detail?id=q-eq-14', null),
            )
            as ManuscriptDetailPage;
    expect(widget.args.manuscriptId, 'q-eq-14');
  });

  test('U6 #15 静态单源牙：12 Map extra + 1 对象 extra 分母不漂移', () {
    final src = File('lib/router/app_router.dart').readAsStringSync();
    int countOf(String needle) =>
        RegExp(RegExp.escape(needle)).allMatches(src).length;
    expect(
      countOf('state.extra as Map<String, dynamic>?'),
      12,
      reason: 'Map extra 消费点数量变化 ⇒ 12 条矩阵需同步复核',
    );
    expect(
      countOf('state.extra as SyndromeLearnerNote?'),
      1,
      reason: '对象 extra 是第 13 个消费点，不在本矩阵内',
    );
  });
}
