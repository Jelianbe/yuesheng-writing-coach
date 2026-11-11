// 书架 header「试用」入口 —— 契约测试（`§4-499`）
//
// 舰长 2026-11-11 22:24：「在 header 加一个试用按键切界面」。
//
// 【为什么这四条都要有】
//   1. web ⇒ 「试用」可见 —— 没有这条，入口等于没做。
//   2. 正对照：非 web ⇒ `findsNothing` —— 只写第 1 条的话，
//      `if (false) return const SizedBox.shrink();` 漏写成恒渲染也照样全绿
//      （Android 端会凭空多出一个「试用」键，而那是**用户不该看到的**）。
//   3. 点击真的推出介绍页，**且是入口态**（有返回键 + CTA「知道了，去试试」）——
//      若推出来的是首访态（无返回键、CTA 写「开始试用」），用户会被困在介绍页里，
//      且文案会让他以为自己要重新进一次应用。这是两态最容易错配的地方。
//   4. 360dp 下 AppBar 装 4 个 action 不溢出 —— 试用键是**第 4 个**，
//      前三个（搜索/排序/新建）在非空库时同时存在。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/theme/app_theme.dart' show buildAppTheme;
import 'package:writingcoach/features/landing/try_entry_button.dart';

void main() {
  /// 把试用键放进一个与书架 AppBar 同构的壳里（避免为测一个按钮去拉起全页 provider）。
  Future<void> pumpBar(
    WidgetTester tester, {
    bool? isWeb,
    bool fullActions = false,
    Size size = const Size(360, 740),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          appBar: AppBar(
            title: const Text('书架'),
            toolbarHeight: 48,
            actions: [
              TryEntryButton(isWeb: isWeb),
              if (fullActions) ...[
                IconButton(
                  icon: const Icon(Icons.search, size: 22),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.sort, size: 22),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.add, size: 22),
                  onPressed: () {},
                ),
              ],
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('header 试用入口', () {
    testWidgets('web ⇒ 「试用」可见', (tester) async {
      await pumpBar(tester, isWeb: true);
      expect(find.text('试用'), findsOneWidget);
    });

    testWidgets('★ 正对照：非 web ⇒ 不渲染（Android 端零变化）', (tester) async {
      await pumpBar(tester, isWeb: false);
      expect(find.text('试用'), findsNothing);
    });

    testWidgets('★ 点击推出介绍页，且是入口态（有返回键 · CTA 为「知道了，去试试」）', (tester) async {
      await pumpBar(tester, isWeb: true);

      await tester.tap(find.text('试用'));
      await tester.pumpAndSettle();

      // 入口态三特征：CTA 文案、返回键、首访态文案不得出现
      expect(find.text('知道了，去试试'), findsOneWidget);
      expect(find.text('开始试用'), findsNothing);
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('入口态返回键可退出（不把用户关在介绍页）', (tester) async {
      await pumpBar(tester, isWeb: true);

      await tester.tap(find.text('试用'));
      await tester.pumpAndSettle();
      expect(find.text('知道了，去试试'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // 回到书架：标题与试用键都在，介绍页内容消失
      expect(find.text('书架'), findsOneWidget);
      expect(find.text('试用'), findsOneWidget);
      expect(find.text('知道了，去试试'), findsNothing);
    });

    testWidgets('360dp 下 4 个 action 不溢出（试用键是第 4 个）', (tester) async {
      await pumpBar(tester, isWeb: true, fullActions: true);
      expect(tester.takeException(), isNull);
    });
  });
}
