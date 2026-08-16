// ─────────────────────────────────────────────────────────────
// AttitudeIndicator widget 测试 — 态度档位切换器
//
// 覆盖路径：
//   1. 渲染当前档位 label
//   2. 点击 → 弹出「选择态度档位」面板
//   3. 选择其它档位 → onSelect 回调触发
//   4. 当前档位显示勾选标记
//   5. 面板中显示三档的名称与语气说明
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/widgets/attitude_indicator.dart';

void main() {
  group('AttitudeIndicator', () {
    testWidgets('#1 渲染当前档位 label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttitudeIndicator(
              currentAttitude: AttitudeLevel.doubao,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('豆包'), findsOneWidget);
    });

    testWidgets('#2 点击 → 弹出选择面板（含三档名称与说明）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttitudeIndicator(
              currentAttitude: AttitudeLevel.doubao,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      expect(find.text('选择态度档位'), findsOneWidget);
      // 当前档位「豆包」出现 2 处：顶部指示器 + 面板选项
      expect(find.text('豆包'), findsNWidgets(2));
      expect(find.text('月笙如歌'), findsOneWidget);
      expect(find.text('sensei'), findsOneWidget);
      expect(find.text('温和、鼓励、先肯定'), findsOneWidget);
      expect(find.text('直接、精准、理性'), findsOneWidget);
      expect(find.text('一针见血、刺痛但不侮辱'), findsOneWidget);
    });

    testWidgets('#3 选择其它档位 → onSelect 触发', (tester) async {
      AttitudeLevel? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttitudeIndicator(
              currentAttitude: AttitudeLevel.doubao,
              onSelect: (a) => selected = a,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('月笙如歌'));
      await tester.pumpAndSettle();

      expect(selected, AttitudeLevel.yuesheng);
    });

    testWidgets('#4 当前档位显示勾选标记', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttitudeIndicator(
              currentAttitude: AttitudeLevel.sensei,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();

      // sensei 行应有 check 图标（面板中唯一）
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('#5 选择后面板关闭', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AttitudeIndicator(
              currentAttitude: AttitudeLevel.doubao,
              onSelect: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.text('选择态度档位'), findsOneWidget);

      await tester.tap(find.text('sensei'));
      await tester.pumpAndSettle();

      expect(find.text('选择态度档位'), findsNothing);
    });
  });
}
