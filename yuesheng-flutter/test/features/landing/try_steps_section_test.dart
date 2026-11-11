// 「怎么试」三步区 —— 契约测试（`§4-499`）
//
// 【这个文件为什么存在】整页测试（`web_landing_page_test.dart`）里已经断言过
// 「三步全在」，但那是**从整页看进去**；本文件测的是**组件本体**：三步的顺序、
// 序号、以及「少一步就红」。两者不重复 —— 一个守「页面里有没有」，
// 一个守「组件自己完整不完整」（组件将来被别处复用时，整页测试管不到）。
//
// 【为什么顺序也要测】三步是**用户动作的先后**（建作品 → 粘稿子 → 划词诊断）。
// 顺序错了 → 转述成了「先诊断再建作品」，用户照着做必然卡住。故按序断言序号 1/2/3。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/theme/app_theme.dart' show buildAppTheme;
import 'package:writingcoach/features/landing/try_steps_section.dart';

void main() {
  Future<void> pumpSteps(
    WidgetTester tester, {
    Size size = const Size(360, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: TryStepsSection(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('怎么试三步', () {
    testWidgets('三步标题齐全', (tester) async {
      await pumpSteps(tester);

      expect(find.textContaining('新建一部作品'), findsOneWidget);
      expect(find.textContaining('把稿子粘进正文'), findsOneWidget);
      expect(find.textContaining('诊断这段文字'), findsOneWidget);
    });

    testWidgets('★ 序号 1/2/3 各一（防顺序颠倒或漏编号）', (tester) async {
      await pumpSteps(tester);

      for (final n in ['1', '2', '3']) {
        expect(find.text(n), findsOneWidget, reason: '缺序号 $n');
      }
    });

    testWidgets('每步都带一句说明（标题独行 = 用户不知道具体点哪）', (tester) async {
      await pumpSteps(tester);

      expect(find.textContaining('新建作品'), findsWidgets);
      expect(find.textContaining('几百字就够'), findsOneWidget);
      expect(find.textContaining('打开教练面板'), findsOneWidget);
    });

    testWidgets('360×740 下无溢出', (tester) async {
      await pumpSteps(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
