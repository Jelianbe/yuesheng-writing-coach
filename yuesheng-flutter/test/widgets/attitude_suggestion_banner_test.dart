// ─────────────────────────────────────────────────────────────
// AttitudeSuggestionBanner 组件测试
//
// 覆盖：升级/降级渲染（标题/按钮/原因）、接受/暂不交互回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/services/attitude_advisor.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/attitude_suggestion_banner.dart';

Widget _build({
  required AttitudeSuggestion suggestion,
  VoidCallback? onAccept,
  VoidCallback? onDismiss,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AttitudeSuggestionBanner(
        suggestion: suggestion,
        onAccept: onAccept ?? () {},
        onDismiss: onDismiss ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('升级建议 → 标题/箭头/切换到目标/原因', (tester) async {
    final suggestion = AttitudeSuggestion(
      direction: 'upgrade',
      targetLevel: AttitudeLevel.yuesheng,
      reason: '当前发现 2 个写作问题，问题严重度偏高，建议切换到「月笙」模式',
    );
    await tester.pumpWidget(_build(suggestion: suggestion));

    expect(find.text('建议提升指导强度'), findsOneWidget);
    expect(find.text('切换到月笙'), findsOneWidget);
    expect(find.text('暂不'), findsOneWidget);
    expect(find.textContaining('当前发现 2 个写作问题'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
  });

  testWidgets('降级建议 → 标题/箭头/切换到目标', (tester) async {
    final suggestion = AttitudeSuggestion(
      direction: 'downgrade',
      targetLevel: AttitudeLevel.doubao,
      reason: '当前问题较少，建议切换到「豆包」模式，保持轻松学习氛围',
    );
    await tester.pumpWidget(_build(suggestion: suggestion));

    expect(find.text('建议调整为轻松模式'), findsOneWidget);
    expect(find.text('切换到豆包'), findsOneWidget);
    expect(find.textContaining('当前问题较少'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
  });

  testWidgets('点击「切换到…」触发 onAccept', (tester) async {
    var accepted = false;
    final suggestion = AttitudeSuggestion(
      direction: 'upgrade',
      targetLevel: AttitudeLevel.sensei,
      reason: '已进入训练阶段，建议切换到「老师」模式',
    );
    await tester.pumpWidget(
      _build(suggestion: suggestion, onAccept: () => accepted = true),
    );

    await tester.tap(find.text('切换到老师'));
    expect(accepted, isTrue);
  });

  testWidgets('点击「暂不」触发 onDismiss', (tester) async {
    var dismissed = false;
    final suggestion = AttitudeSuggestion(
      direction: 'downgrade',
      targetLevel: AttitudeLevel.doubao,
      reason: '状态不错',
    );
    await tester.pumpWidget(
      _build(suggestion: suggestion, onDismiss: () => dismissed = true),
    );

    await tester.tap(find.text('暂不'));
    expect(dismissed, isTrue);
  });

  testWidgets('sensei 目标显示「老师」', (tester) async {
    final suggestion = AttitudeSuggestion(
      direction: 'upgrade',
      targetLevel: AttitudeLevel.sensei,
      reason: '学习状态良好，建议切换到「老师」模式，获得更严格专业的指导',
    );
    await tester.pumpWidget(_build(suggestion: suggestion));

    expect(find.text('切换到老师'), findsOneWidget);
    expect(find.textContaining('更严格专业的指导'), findsOneWidget);
  });
}
