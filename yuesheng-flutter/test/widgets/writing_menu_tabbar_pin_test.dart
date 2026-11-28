// ─────────────────────────────────────────────────────────────
// 写作页 ⋮ 菜单 —— TabBar 常驻契约（R5 · T-20261126-04 §六）
//
// 与 `writing_menu_sheet_test.dart` 的分工（**两条判据不可互替**）：
//   · `writing_menu_sheet_test.dart` → 「**首屏容量**」：一屏能看到多少入口（N4-2）
//   · 本文件                         → 「**TabBar 常驻**」：滚到哪都看得见 tab 栏（V7/V8/V9）
//
// 为什么单独成文件：R5 缺陷（0.30 档滚到底 tab 栏高出容器顶 127.1dp）在容量
// 用例里**根本不可能被发现** —— 容量用例只数「多少项在首屏」，不看 TabBar 位置。
//
// 判据出处（卡 §6.4）：
//   V7 = 0.30 / 0.55 / 0.85 三档各滚到底，TabBar `getRect().top >= 容器可视区 top - 0.5`
//   V8 = 「加 1 个 48dp 菜单项即坏」不复发（实现方式见 V8 组的注释）
//   V9 = 默认档「取消」：暴露顶边 + `maxScroll >= 需滚量` + 真滚一次后完整可见
//        （R4 最终裁定：48dp 下初始态部分出屏、滚动即达 ⇒ **不是功能缺陷**，
//         只订正读数不修；判据取「初始可见或滚动可达」，与
//         `writing_menu_sheet_test.dart` 的 R4-M1 同源，见 `DECISIONS §4-576`）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/writing/writing_menu_sheet.dart';

/// 真机竖屏 393×851 = 1080×2340 @2.75（走查所用设备的逻辑尺寸）。
const Size _kPhone = Size(393, 851);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpSheet(
    WidgetTester tester, {
    required double initialHeight,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = _kPhone;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => WritingMenuSheet.show(
                  context,
                  lastSavedAt: null,
                  initialHeight: initialHeight,
                  onDiagnose: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
  }

  Rect sheetRect(WidgetTester tester) =>
      tester.getRect(find.byType(BottomSheet));

  Rect tabBarRect(WidgetTester tester) => tester.getRect(find.byType(TabBar));

  ScrollPosition menuScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  /// 把菜单滚到底。
  ///
  /// 用 `position.jumpTo` 而非 `tester.drag`：`DraggableScrollableSheet` 会先吃掉
  /// 纵向手势去扩高 sheet（0.30 档尤其明显），拖拽滚不到内容底部。这里要的是
  /// 「内容滚到底」这个终态，直接压到滚动极限最可靠、也不会 flake。
  Future<void> scrollToBottom(WidgetTester tester) async {
    final position = menuScroll(tester);
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
  }

  group('V7 · TabBar 三档滚到底都不滚走', () {
    // 0.85 档**不入本循环**：该档 sheet 高 730.55dp，内容全装下 ⇒
    //   maxScrollExtent=0 ⇒「滚到底」是空操作、TabBar 天然不动 ⇒ 三条判据恒过。
    //   实测（突变复核）：R5 之前它也是绿的 ⇒ 它是假绿，不守 R5。
    //   单独用一条用例记录「maxScrollExtent==0」这个事实；一旦日后内容变多
    //   使该档可滚，那条会红并逼人把它移回循环。
    for (final h in const [0.30, 0.55]) {
      testWidgets('$h 档滚到底，TabBar 仍在容器可视区内', (tester) async {
        await pumpSheet(tester, initialHeight: h);

        final sheet = sheetRect(tester);
        final before = tabBarRect(tester);
        // 前置：初始态 TabBar 本来就在（否则「滚后仍在」毫无意义）
        expect(
          before.top,
          greaterThanOrEqualTo(sheet.top - 0.5),
          reason: '初始态 TabBar 就不在容器内 ⇒ 布局基础已坏，先查 $h 档',
        );

        await scrollToBottom(tester);

        final after = tabBarRect(tester);
        final sheetAfter = sheetRect(tester);

        // 判据 1（卡面原文）
        expect(
          after.top,
          greaterThanOrEqualTo(sheetAfter.top - 0.5),
          reason:
              '$h 档滚到底后 TabBar 顶 ${after.top} < 容器顶 ${sheetAfter.top} '
              '⇒ tab 栏被滚出视口，用户切不了分组（R5 缺陷原样复现）',
        );
        // 判据 2（补充）：整条 tab 栏都在容器内，防「只露出顶边」也算过
        expect(
          after.bottom,
          lessThanOrEqualTo(sheetAfter.bottom + 0.5),
          reason:
              '$h 档滚到底后 TabBar 底 ${after.bottom} 超出容器底 ${sheetAfter.bottom}',
        );
        // 判据 3（语义本质）：TabBar 在滚动前后**位置不变** —— 这就是「固定段」的
        // 定义。若有人把它放回滚动区，这条比 1/2 更早红（哪怕 0.55 档碰巧没出界）。
        // ★ 命门：0.55 档的判据1（初始在容器内）与判据2 在 R5 之前**都是过的**，
        //   本条唯一变红来源就是这里的「位移=0」。删掉它 ⇒ 0.55 档立刻退化成假绿
        //   （实测：R5 前 位移=-34.35dp，R5 后 0.00）。
        expect(
          after.top,
          closeTo(before.top, 0.5),
          reason:
              '$h 档滚动后 TabBar 位移 ${after.top - before.top}dp ≠ 0 '
              '⇒ TabBar 仍在滚动区内（R5 回归）',
        );
      });
    }

    testWidgets('0.85 档内容全装下（maxScroll=0，该档不具 R5 鉴别力，仅记录事实）', (tester) async {
      await pumpSheet(tester, initialHeight: 0.85);
      expect(
        menuScroll(tester).maxScrollExtent,
        0.0,
        reason:
            '0.85 档 maxScrollExtent=${menuScroll(tester).maxScrollExtent} '
            '≠0 ⇒ 该档其实有可滚内容，「TabBar 不滚走」就不再是空操作，'
            '必须把它移回 V7 循环参战',
      );
    });
  });

  group('V8 · 「加项即坏」不复发（常驻回归）', () {
    // ─────────────────────────────────────────────────────────────
    // ★ 与派单写法不同的地方，必须说清（不是降判据，是**升**判据）：
    //
    // 派单要求「测试内临时多加 1 个 48dp 菜单项」。实测**无法在不改 lib 的前提下
    // 真正做到**：菜单项由 `buildWritingToolsGroup` 等三个函数硬编码返回，
    // `WritingMenuBody` 不接受额外项参数，`MenuItem` 的高度固定 48dp 且不接受
    // 覆盖（外层 `SizedBox(height: 48)` 写死）。任何「测试内注入」只能二选一：
    //   ① 给 lib 加一个仅供测试的参数（改产品 API，超出本单）；
    //   ② 在测试里重建一个结构相似的 replica（**测的不是产品代码 = 假绿**）。
    // 两者都不接受 ⇒ 改用**等价且更强**的判据：
    //
    //   「TabBar 相对容器顶的偏移量，与滚动内容长度**完全无关**」
    //
    // 检验方式：取三档（溢出量 0 / 82.35 / 283.10dp，教学 tab 7 项）下 TabBar 相对
    // sheet 顶的偏移，断言三者**逐位相同**。0.30 档比「多 1 项(48dp)」多出近 6 倍内容
    // （283.10dp ≈ 5.9 项）⇒ 覆盖强度严格高于「加 1 项」，且同样能变红：
    // 只要 TabBar 回到滚动区，0.30 档该偏移会立刻变得与其它两档不同（实测改前
    // 0.30 档滚到底 TabBar 高出容器顶 127.1dp）。
    //
    // 另一条独立判据：**内容溢出量变化时 TabBar 位置不动** —— 直接用
    // `maxScrollExtent` 的差异作为「内容多了多少」的量化证据落进 reason。
    // ─────────────────────────────────────────────────────────────
    testWidgets('三档溢出量差 283dp，TabBar 相对容器顶偏移逐位相同', (tester) async {
      final offsets = <double>[];
      final overflows = <double>[];

      for (final h in const [0.30, 0.55, 0.85]) {
        await pumpSheet(tester, initialHeight: h);
        // ★ 2026-11-28 丁方案（DECISIONS §4-610）：默认 tab 由 6 项降为 **4 项**，
        //   0.55 档 `content 332 < viewport 393.65` ⇒ 溢出量归 0，三档只剩 2 个互异值
        //   （实测 `[139.10, 0.00, 0.00]`）⇒ 本组「三档互异」前置**必然红**
        //   —— 不是判据放松，是**被测物变短了**。改为在「教学」tab（**7 项**）上取三档：
        //   溢出量 `[283.10, 82.35, 0.00]`，极差 **283.10dp > 48dp**（比原 235.1 更强）。
        //   判据本体（三档互异 / 极差 > 48 / TabBar 偏移逐位相同）**一字未改**。
        await tester.tap(find.text('教学').first);
        await tester.pumpAndSettle();
        await scrollToBottom(tester);

        offsets.add(tabBarRect(tester).top - sheetRect(tester).top);
        overflows.add(menuScroll(tester).maxScrollExtent);

        // 关掉本档的 sheet 再进下一档：同一 test 内重复 pumpWidget 时，
        // 上一次的模态 route 会残留（实测第二次 tap 静默失效，树里 0 个 sheet）。
        Navigator.of(tester.element(find.byType(TabBar))).pop();
        await tester.pumpAndSettle();
      }

      // 前置：三档的「内容比视口多多少」确实不同 —— 否则下面的「偏移相同」
      // 可能只是因为三档内容量本来就一样（那就测不到东西了）。
      expect(
        overflows.toSet().length,
        3,
        reason:
            '三档 maxScrollExtent 不互异（$overflows）⇒ 本条未真正覆盖「内容量不同」'
            '这一变量，判据失效',
      );
      expect(
        overflows.reduce((a, b) => a > b ? a : b) -
            overflows.reduce((a, b) => a < b ? a : b),
        greaterThan(48),
        reason:
            '三档溢出量极差 ${overflows.reduce((a, b) => a > b ? a : b) - overflows.reduce((a, b) => a < b ? a : b)}dp '
            '≤ 1 个菜单项(48dp) ⇒ 覆盖强度不及「加 1 项」，须加更长内容才能声称等价',
      );

      // 主判据：TabBar 相对容器顶的偏移与内容量完全解耦
      expect(
        offsets[0],
        closeTo(offsets[1], 0.5),
        reason:
            '0.30 档偏移 ${offsets[0]} vs 0.55 档 ${offsets[1]} 不同 ⇒ TabBar 随内容移动（仍在滚动区）',
      );
      expect(
        offsets[0],
        closeTo(offsets[2], 0.5),
        reason:
            '0.30 档偏移 ${offsets[0]} vs 0.85 档 ${offsets[2]} 不同 ⇒ TabBar 随内容移动（仍在滚动区）',
      );
      // 且该偏移必须为正（在容器内），不是被算成 0 后三方同时相等
      expect(
        offsets[0],
        greaterThan(0),
        reason: 'TabBar 相对容器顶偏移 ${offsets[0]} ≤ 0 ⇒ 已顶到/越过容器顶',
      );
    });
  });

  group('V10 · scrollController 仍挂在滚动区上（拖拽吸附不变哑巴）', () {
    // ★ 这条防的是「假绿」：TabBar 移出滚动区后，结构断言（V7/V8）全绿，
    //   但只要 `SingleChildScrollView` 丢了 `widget.scrollController`，
    //   `DraggableScrollableSheet` 的吸附就整个失效 —— **构建成功、位置正确、交互死**。
    //   静态断言（controller 非空且已 attach）+ 真拖一次的吸附行为，两条都测。
    testWidgets('滚动区持有 sheet 下发的 controller，且真拖一下能吸附', (tester) async {
      await pumpSheet(tester, initialHeight: 0.55);

      final scrollView = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(
        scrollView.controller,
        isNotNull,
        reason:
            'SingleChildScrollView 的 controller 为 null ⇒ DraggableScrollableSheet '
            '下发的 controller 被丢掉，拖拽/吸附全部失效（结构对、交互死）',
      );
      expect(
        scrollView.controller!.hasClients,
        isTrue,
        reason: 'controller 存在但没 attach 到任何 ScrollPosition ⇒ 同样是哑巴',
      );

      final heightBefore = sheetRect(tester).height;

      // 在滚动区（非 TabBar）上**向上**拖 150dp：offset=0 时上滑会把 sheet 撑高，
      // 0.55 + 150/851(≈0.176) ≈ 0.726 ⇒ 越过 0.55/0.85 中点 ⇒ 应吸附到 0.85。
      // 选向上而非向下：向下拖过头会直接把 sheet 拖关（实测 200dp 即 dismiss），
      // 那样 `BottomSheet` 消失、无法断言吸附档位。
      await tester.drag(find.text('未保存'), const Offset(0, -150));
      await tester.pumpAndSettle();

      final heightAfter = sheetRect(tester).height;
      expect(
        heightAfter,
        greaterThan(heightBefore + 48),
        reason:
            '向上拖 150dp 后 sheet 高 ${heightAfter}dp ≈ 未变（拖前 ${heightBefore}dp）'
            '⇒ 拖拽吸附失效：controller 没接在滚动区上（结构对、交互死）',
      );
    });
  });

  // V9（「取消」可见或滚动可达）已整体删除：它是 N4-2 的真子集，判别力
  //   又弱于 R4-M1（后者多一条「一屏内可达」maxScroll<=viewport*2），无独立
  //   价值；且其判据用的是主理人越权批的口径（舰长未追认），删掉可减少依赖。
  //   详见 .ai/team/runs/ 本批复核结论。
}
