// web 站点门面 —— 契约测试（`§4-498`）
//
// 验的不是「画得好看」，而是四条**会真的坏掉**的性质：
//   1. 主 CTA 在，且点了真的调 `onStart`（否则门面是个装饰）
//   2. **「示例模式 · 不调用真实模型」必须可见** —— 这是本页唯一不能删的东西：
//      web 上没有任何真实 LLM 通道（不存 key + 平台垫付未接），若把这行删掉，
//      门面就在承诺一个不存在的能力。
//   3. 未配置下载地址时**不渲染**下载按钮 —— 防「按钮在、点了没反应」的死路
//      （本批的立意就是修死路，不能再造一条）。
//   4. 360×740 下无溢出（最小竖屏；门面页是首次触达点，溢出即第一印象崩）。
//
// 断言口径：用 `textContaining` 而非全等，避免措辞微调就把测试弄红；
// 但「示例模式」与「不调用真实模型」两句分开断言 ⇒ 少任何一句都会红。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/theme/app_theme.dart' show buildAppTheme;
import 'package:writingcoach/features/landing/web_landing_page.dart';

void main() {
  Future<void> pumpLanding(
    WidgetTester tester, {
    required VoidCallback onStart,
    Size size = const Size(360, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: WebLandingPage(onStart: onStart),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('web 站点门面', () {
    testWidgets('主 CTA 存在，且点击真的触发 onStart', (tester) async {
      var started = 0;
      await pumpLanding(tester, onStart: () => started++);

      expect(find.text('立即试用'), findsOneWidget);
      await tester.tap(find.text('立即试用'));
      await tester.pumpAndSettle();

      expect(started, 1);
    });

    testWidgets('★ 示例模式声明必须可见（不调用真实模型）', (tester) async {
      await pumpLanding(tester, onStart: () {});

      expect(find.textContaining('示例模式'), findsOneWidget);
      expect(find.textContaining('不调用真实模型'), findsOneWidget);
    });

    testWidgets('未配置下载地址 ⇒ 不渲染下载按钮（防死路）', (tester) async {
      // 本仓测试命令不带 `--dart-define=ANDROID_DOWNLOAD_URL`
      // ⇒ 编译期常量为空。若将来有人带该 define 跑，本例会红 —— 属预期，
      // 因为那时「未配置」的前提已不成立。
      await pumpLanding(tester, onStart: () {});

      expect(find.text('下载 Android 版'), findsNothing);
    });

    testWidgets('360×740 下无溢出', (tester) async {
      await pumpLanding(tester, onStart: () {});
      expect(tester.takeException(), isNull);
    });
  });
}
