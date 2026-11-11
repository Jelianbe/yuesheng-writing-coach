// 试用介绍页 —— 契约测试（`§4-498` 首访态 + `§4-499` 入口态）
//
// 验的不是「画得好看」，而是七条**会真的坏掉**的性质：
//   1. 两态的 CTA 文案**不同**，且点击都真的调 `onStart`（否则按钮是装饰）
//   2. 首访态**没有返回键**（此时无栈可回，给一个返回键就是假出口）
//   3. 入口态**有返回键**且点击真的调 `onBack`（否则用户被困在介绍页里）
//   4. **边界声明必须可见** —— 这是本页唯一不能删的东西：web 上没有真实 LLM 通道，
//      而示例模式（`llm_client.dart:254`）固定回「本次未进行诊断」。
//      删掉声明 ⇒ 本页就在承诺一个不存在的诊断结果。
//   5. 三步全在 —— 少一步，用户就卡在那一步（介绍页的价值全在「怎么试」）
//   6. 未配置下载地址 ⇒ **不渲染**下载按钮（防「按钮在、点了没反应」的死路）
//   7. 360×740 两态均无溢出（最小竖屏；本页是首次触达点，溢出即第一印象崩）
//
// 断言口径：`textContaining` 而非全等，避免措辞微调就把测试弄红；
// 但「不调用真实模型」与「本次未进行诊断」两句**分开**断言 ⇒ 少任何一句都会红。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/theme/app_theme.dart' show buildAppTheme;
import 'package:writingcoach/features/landing/web_landing_page.dart';

void main() {
  Future<void> pumpLanding(
    WidgetTester tester, {
    required VoidCallback onStart,
    VoidCallback? onBack,
    Size size = const Size(360, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: WebLandingPage(onStart: onStart, onBack: onBack),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('首访态（onBack == null）', () {
    testWidgets('CTA 为「开始试用」，点击真的触发 onStart', (tester) async {
      var started = 0;
      await pumpLanding(tester, onStart: () => started++);

      expect(find.text('开始试用'), findsOneWidget);
      await tester.tap(find.text('开始试用'));
      await tester.pumpAndSettle();

      expect(started, 1);
    });

    testWidgets('★ 无返回键（无栈可回时不给假出口）', (tester) async {
      await pumpLanding(tester, onStart: () {});

      expect(find.byIcon(Icons.arrow_back), findsNothing);
    });

    testWidgets('360×740 下无溢出', (tester) async {
      await pumpLanding(tester, onStart: () {});
      expect(tester.takeException(), isNull);
    });
  });

  group('入口态（onBack != null，从书架 header 推入）', () {
    testWidgets('CTA 改为「知道了，去试试」，点击触发 onStart', (tester) async {
      var started = 0;
      await pumpLanding(tester, onStart: () => started++, onBack: () {});

      expect(find.text('知道了，去试试'), findsOneWidget);
      // 入口态不得再出现首访态文案：两态混写会让用户分不清自己点的是哪个
      expect(find.text('开始试用'), findsNothing);
      await tester.tap(find.text('知道了，去试试'));
      await tester.pumpAndSettle();

      expect(started, 1);
    });

    testWidgets('★ 有返回键，点击真的触发 onBack（否则用户被困在介绍页）', (tester) async {
      var backed = 0;
      await pumpLanding(tester, onStart: () {}, onBack: () => backed++);

      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(backed, 1);
    });

    testWidgets('360×740 下无溢出', (tester) async {
      await pumpLanding(tester, onStart: () {}, onBack: () {});
      expect(tester.takeException(), isNull);
    });
  });

  group('两态共用内容', () {
    testWidgets('★ 边界声明必须可见（不调用真实模型 + 本次未进行诊断）', (tester) async {
      await pumpLanding(tester, onStart: () {});

      expect(find.textContaining('不调用真实模型'), findsOneWidget);
      expect(find.textContaining('本次未进行诊断'), findsOneWidget);
    });

    testWidgets('三步全在（少一步用户就卡在那一步）', (tester) async {
      await pumpLanding(tester, onStart: () {});

      expect(find.textContaining('新建一部作品'), findsOneWidget);
      expect(find.textContaining('把稿子粘进正文'), findsOneWidget);
      expect(find.textContaining('诊断这段文字'), findsOneWidget);
    });

    testWidgets('未配置下载地址 ⇒ 不渲染下载按钮（防死路）', (tester) async {
      // 本仓测试命令不带 `--dart-define=ANDROID_DOWNLOAD_URL`
      // ⇒ 编译期常量为空。若将来有人带该 define 跑，本例会红 —— 属预期，
      // 因为那时「未配置」的前提已不成立。
      await pumpLanding(tester, onStart: () {});

      expect(find.text('下载 Android 版'), findsNothing);
    });
  });
}
