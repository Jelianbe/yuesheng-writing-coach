// ─────────────────────────────────────────────────────────────
// P1-6 成对断言：painter/const 表 palette 化后随主题翻
//
//   ① _TrendChartPainter 持有 AppPalette（build 注入 context.palette）
//      ⇒ 暗色下 painter.palette == AppPalette.dark（dynamic 读私有类属性）
//   ② 趋势 section 标题色随主题翻（textPrimary 成对断言）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart' show AppColors;
import 'package:writingcoach/services/syndrome_tracker.dart';
import 'package:writingcoach/theme/app_theme.dart'
    show buildAppTheme, buildDarkTheme;
import 'package:writingcoach/widgets/syndrome_detail_modal.dart';

SyndromeTracked _tracked(int now) => SyndromeTracked(
  syndromeId: 'P003',
  name: '情绪标签化',
  currentSeverity: 'L3',
  firstSeen: now - 86400,
  lastSeen: now,
  occurrenceCount: 2,
  trend: 'worsening',
  recentPoints: [
    SyndromeTrendPoint(
      timestamp: now - 3600,
      severity: 'L1',
      diagnosisId: 'd1',
    ),
    SyndromeTrendPoint(timestamp: now, severity: 'L3', diagnosisId: 'd2'),
  ],
);

Future<void> pump(WidgetTester t, ThemeData theme) async {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  await t.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(body: SyndromeDetailModal(syndrome: _tracked(now))),
    ),
  );
  await t.pumpAndSettle();
}

dynamic _trendPainter(WidgetTester t) {
  final cp = t
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .firstWhere(
        (w) => w.painter?.runtimeType.toString() == '_TrendChartPainter',
      );
  return cp.painter; // 私有类型经 dynamic 读 palette 字段
}

void main() {
  testWidgets(
    '亮色：painter.palette == AppPalette.light；标题 == AppColors.textPrimary',
    (tester) async {
      await pump(tester, buildAppTheme());
      expect(_trendPainter(tester).palette, AppPalette.light);
      expect(
        tester.widget<Text>(find.text('趋势变化')).style!.color,
        AppColors.textPrimary,
      );
    },
  );

  testWidgets('暗色：painter.palette == AppPalette.dark（且 != 亮）；标题暗翻', (
    tester,
  ) async {
    await pump(tester, buildDarkTheme());
    final pal = _trendPainter(tester).palette as AppPalette;
    expect(pal, AppPalette.dark);
    expect(pal, isNot(AppPalette.light));
    final c = tester.widget<Text>(find.text('趋势变化')).style!.color!;
    expect(c, AppPalette.dark.textPrimary);
    expect(c, isNot(AppColors.textPrimary));
  });
}
