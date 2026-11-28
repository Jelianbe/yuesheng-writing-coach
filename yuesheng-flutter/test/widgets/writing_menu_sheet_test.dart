// ─────────────────────────────────────────────────────────────
// WritingMenuSheet widget 测试 — 写作页 ⋮ 菜单
//
// 覆盖路径（E3：移除 4 个「开发中」占位项后）：
//   1. 渲染菜单项：保存状态 + 打开教练面板（占位项已移除；批次79 B 由「诊断本章」改名）
//   2. 点击"打开教练面板" → onDiagnose 触发 + sheet 关闭
//   3. lastSavedAt=null → "未保存"；lastSavedAt=DateTime(2026,8,5,15,32) → "✓ 已保存 15:32"
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/features/writing/writing_menu_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 通用 harness：用按钮触发 WritingMenuSheet.show()
  Future<void> pumpSheet(
    WidgetTester tester, {
    required DateTime? lastSavedAt,
    required VoidCallback onDiagnose,
    // 批次96-7：拖拽调整篇幅
    double initialHeight = 0.55,
    ValueChanged<double>? onHeightChanged,
    VoidCallback? onOpenSettings,
    VoidCallback? onOpenVersions,
    VoidCallback? onOpenChapterTree,
    VoidCallback? onOpenOutline,
    // 批次96-11：全文搜索入口
    VoidCallback? onOpenFullTextSearch,
    VoidCallback? onOpenFindReplace,
    // C78 批次3：角色页入口
    VoidCallback? onOpenCharacters,
    VoidCallback? onOpenQuickPhrases,
    VoidCallback? onOpenStyleProfile,
    VoidCallback? onOpenWritingStats,
    VoidCallback? onOpenRecycleBin,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => WritingMenuSheet.show(
                  context,
                  lastSavedAt: lastSavedAt,
                  initialHeight: initialHeight,
                  onHeightChanged: onHeightChanged,
                  onDiagnose: onDiagnose,
                  onOpenChapterTree: onOpenChapterTree,
                  onOpenOutline: onOpenOutline,
                  onOpenCharacters: onOpenCharacters,
                  onOpenFullTextSearch: onOpenFullTextSearch,
                  onOpenFindReplace: onOpenFindReplace,
                  onOpenRecycleBin: onOpenRecycleBin,
                  onOpenQuickPhrases: onOpenQuickPhrases,
                  onOpenStyleProfile: onOpenStyleProfile,
                  onOpenWritingStats: onOpenWritingStats,
                  onOpenSettings: onOpenSettings,
                  onOpenVersions: onOpenVersions,
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

  group('WritingMenuSheet', () {
    /// P1 重裁后菜单分三 tab ⇒ 跨 tab 的项必须先切 tab 再点。
    Future<void> switchTab(WidgetTester tester, String label) async {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
    }

    /// 菜单项增多后底部项在滚动区内 → 先滚动到可见再点（批次86-1 起菜单 14 项）
    Future<void> tapMenuBottom(WidgetTester tester, String label) async {
      final item = find.text(label);
      await tester.scrollUntilVisible(
        item,
        120,
        scrollable: find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(item);
      await tester.pumpAndSettle();
    }

    testWidgets('渲染菜单项：三个 tab 内各项齐备，占位项已移除', (tester) async {
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});

      // ── 默认 tab「写作工具」：5 项 ──
      // 批次83：章节列表；批次96-11：全文搜索；批次84-2：查找替换；
      // 批次85-3：快捷短语；批次86-1：回收板
      // 2026-11-28 戊方案（DECISIONS §4-611）：大纲（批次83）、角色（C78 批次3）移入教学；
      // 快捷短语（批次85-3）由教学移回写作工具 ⇒ 分布 5/6/2
      for (final label in const ['章节列表', '全文搜索', '查找替换', '快捷短语', '回收板']) {
        expect(find.text(label), findsOneWidget, reason: '默认 tab 缺「$label」');
      }

      // ── tab 栏：标签复用原组头字面（三个都在，才能互切）──
      expect(find.text('写作工具'), findsOneWidget);
      expect(find.text('教学'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      // tab 数量恰为 3（防「多渲染一个空 tab」或「漏挂一个 tab」）
      expect(find.byType(Tab), findsNWidgets(3));

      // ── 切到「教学」：6 项 ──
      await switchTab(tester, '教学');
      for (final label in const [
        '当前文风', // 批次85-4
        '写作统计', // 批次85-5
        '打开教练面板', // 批次79 B 改名
        '世界观', // W1
        '角色', // C78 批次3（2026-11-28 戊方案移入）
        '大纲', // 批次83（2026-11-28 戊方案移入）
      ]) {
        expect(find.text(label), findsOneWidget, reason: '教学 tab 缺「$label」');
      }

      // ── 切到「设置」：2 项 ──
      await switchTab(tester, '设置');
      expect(find.text('排版设置'), findsOneWidget); // 批次82 P0 四件套之①
      expect(find.text('版本时光机'), findsOneWidget); // 批次82 P0 四件套之③

      // ── 跨 tab 恒在：保存状态行（上）与「取消」（下）──
      // 批次96-5：菜单近全屏时遮罩仅剩顶部窄条，需显式关闭入口
      expect(find.text('取消'), findsOneWidget);
      // 保存状态行在切到「设置」后仍可见（它不随 tab 变，是跨 tab 共享区）
      expect(find.text('未保存'), findsOneWidget);

      // 批次96-8：移除「我的灵感」入口（参考百灵布局）
      expect(find.text('我的灵感'), findsNothing);
      // 批次96-9：三个开关已移入排版设置，菜单只留跳转入口（参考百灵极简）
      expect(find.text('行段聚焦'), findsNothing);
      expect(find.text('智能标点'), findsNothing);
      expect(find.text('对话按钮（开）'), findsNothing);
      // E3：其他「开发中」占位项不再渲染
      expect(find.text('撤销'), findsNothing);
      expect(find.text('重做'), findsNothing);

      // ★ 反向判据（防「三个 tab 全渲染同一份列表」冒充分组）：
      //   默认 tab 里不得同时出现只属「教学」「设置」的项。
      await switchTab(tester, '写作工具');
      for (final label in const ['排版设置', '版本时光机', '当前文风', '写作统计']) {
        expect(
          find.text(label),
          findsNothing,
          reason: '「$label」不该出现在「写作工具」tab ⇒ tab 未真正分区',
        );
      }
    });

    testWidgets('批次96-5 点击"取消" → sheet 关闭且不触发任何回调', (tester) async {
      bool diagnoseCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () => diagnoseCalled = true,
      );

      expect(find.byType(BottomSheet), findsOneWidget);

      await tapMenuBottom(tester, '取消');

      // sheet 已关闭 + 未误触其他菜单回调
      expect(find.byType(BottomSheet), findsNothing);
      expect(diagnoseCalled, isFalse);
    });

    testWidgets('批次96-7 DraggableScrollableSheet 渲染 + 阈值档位正确', (tester) async {
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});

      final dss = tester.widget<DraggableScrollableSheet>(
        find.byType(DraggableScrollableSheet),
      );
      expect(dss.initialChildSize, closeTo(0.55, 0.001));
      expect(dss.minChildSize, closeTo(0.30, 0.001));
      expect(dss.maxChildSize, closeTo(0.85, 0.001));
      expect(dss.snap, isTrue);
    });

    testWidgets('批次96-7 拖拽调整篇幅 → onHeightChanged 上报阈值内高度', (tester) async {
      double? reported;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onHeightChanged: (h) => reported = h,
      );

      final scrollable = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      // 连续上推：先滚动内容，触底后 DraggableScrollableSheet 扩展高度 → 上报 extent
      for (var i = 0; i < 8; i++) {
        await tester.drag(scrollable, const Offset(0, -300));
        await tester.pumpAndSettle();
      }
      expect(reported, isNotNull);
      expect(reported!, inInclusiveRange(0.30, 0.85));
    });

    testWidgets('点击"打开教练面板" → onDiagnose 触发 + sheet 关闭', (tester) async {
      bool diagnoseCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () => diagnoseCalled = true,
      );

      // sheet 当前可见
      expect(find.byType(BottomSheet), findsOneWidget);

      await switchTab(tester, '教学');
      await tapMenuBottom(tester, '打开教练面板');

      // 回调触发 + sheet 已关闭
      expect(diagnoseCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次82 点击"排版设置" → onOpenSettings 触发 + sheet 关闭', (tester) async {
      bool settingsCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenSettings: () => settingsCalled = true,
      );

      await switchTab(tester, '设置');
      await tapMenuBottom(tester, '排版设置');

      expect(settingsCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次82 点击"版本时光机" → onOpenVersions 触发 + sheet 关闭', (
      tester,
    ) async {
      bool versionsCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenVersions: () => versionsCalled = true,
      );

      // P1 重裁：「版本时光机」现属「设置」tab（原为单列滚动区外）
      await switchTab(tester, '设置');
      await tapMenuBottom(tester, '版本时光机');
      await tester.pumpAndSettle();

      expect(versionsCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次83 点击"章节列表" → onOpenChapterTree 触发 + sheet 关闭', (
      tester,
    ) async {
      bool treeCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenChapterTree: () => treeCalled = true,
      );

      await tester.tap(find.text('章节列表'));
      await tester.pumpAndSettle();

      expect(treeCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次83 点击"大纲" → onOpenOutline 触发 + sheet 关闭', (tester) async {
      bool outlineCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenOutline: () => outlineCalled = true,
      );

      // 2026-11-28 戊方案（DECISIONS §4-611）：「大纲」已移入教学 tab
      await switchTab(tester, '教学');
      await tapMenuBottom(tester, '大纲');
      await tester.pumpAndSettle();

      expect(outlineCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次84-2 点击"查找替换" → onOpenFindReplace 触发 + sheet 关闭', (
      tester,
    ) async {
      bool findReplaceCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenFindReplace: () => findReplaceCalled = true,
      );

      // C78 批次3：菜单新增「角色」项后「查找替换」下移出首屏 → 滚动后点击
      await tapMenuBottom(tester, '查找替换');
      await tester.pumpAndSettle();

      expect(findReplaceCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('C78 批次3 点击"角色" → onOpenCharacters 触发 + sheet 关闭', (
      tester,
    ) async {
      bool charactersCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenCharacters: () => charactersCalled = true,
      );

      // 2026-11-28 戊方案（DECISIONS §4-611）：「角色」已移入教学 tab
      await switchTab(tester, '教学');
      await tapMenuBottom(tester, '角色');
      await tester.pumpAndSettle();

      expect(charactersCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次86-1 点击"回收板" → onOpenRecycleBin 触发 + sheet 关闭', (
      tester,
    ) async {
      bool recycleBinCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenRecycleBin: () => recycleBinCalled = true,
      );

      // 批次96-6：菜单非全屏（最大 9/16 屏高），「回收板」在滚动区外 → 滚动后点击
      await tapMenuBottom(tester, '回收板');
      await tester.pumpAndSettle();

      expect(recycleBinCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次85-3 点击"快捷短语" → onOpenQuickPhrases 触发 + sheet 关闭', (
      tester,
    ) async {
      bool quickPhrasesCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenQuickPhrases: () => quickPhrasesCalled = true,
      );

      // 2026-11-28 戊方案（DECISIONS §4-611）：「快捷短语」已由「教学」移回
      // 「写作工具」（默认 tab）⇒ 不再切 tab，滚动到可见后点击。
      await tapMenuBottom(tester, '快捷短语');
      await tester.pumpAndSettle();

      expect(quickPhrasesCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次96-11 点击"全文搜索" → onOpenFullTextSearch 触发 + sheet 关闭', (
      tester,
    ) async {
      bool searchCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenFullTextSearch: () => searchCalled = true,
      );

      await tester.tap(find.text('全文搜索'));
      await tester.pumpAndSettle();

      expect(searchCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次85-4 点击"当前文风" → onOpenStyleProfile 触发 + sheet 关闭', (
      tester,
    ) async {
      bool styleProfileCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenStyleProfile: () => styleProfileCalled = true,
      );

      // P1 重裁：「当前文风」现属「教学」tab
      await switchTab(tester, '教学');
      await tapMenuBottom(tester, '当前文风');
      await tester.pumpAndSettle();

      expect(styleProfileCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('批次85-2 点击"行段聚焦" → 已移入排版设置，菜单不再渲染开关', (tester) async {
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});

      // 批次96-9：开关移入排版设置，菜单不渲染（防止误点击开关类项）
      expect(find.text('行段聚焦'), findsNothing);
      expect(find.text('智能标点'), findsNothing);
      expect(find.text('对话按钮（开）'), findsNothing);
      expect(find.text('对话按钮（关）'), findsNothing);
    });

    testWidgets('批次85-5 点击"写作统计" → onOpenWritingStats 触发 + sheet 关闭', (
      tester,
    ) async {
      bool statsCalled = false;
      await pumpSheet(
        tester,
        lastSavedAt: null,
        onDiagnose: () {},
        onOpenWritingStats: () => statsCalled = true,
      );

      // P1 重裁：「写作统计」现属「教学」tab
      await switchTab(tester, '教学');
      await tapMenuBottom(tester, '写作统计');
      await tester.pumpAndSettle();

      expect(statsCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('lastSavedAt=null → "未保存"；非空 → "✓ 已保存 HH:mm"', (tester) async {
      // case 1: null
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});
      expect(find.text('未保存'), findsOneWidget);

      // 关闭 sheet 后再来一次（「打开教练面板」在「教学」tab）
      await switchTab(tester, '教学');
      await tapMenuBottom(tester, '打开教练面板');

      // case 2: DateTime(2026, 8, 5, 15, 32)
      await pumpSheet(
        tester,
        lastSavedAt: DateTime(2026, 8, 5, 15, 32),
        onDiagnose: () {},
      );
      expect(find.text('✓ 已保存 15:32'), findsOneWidget);
    });

    // ─────────────────────────────────────────────────────────────
    // N4-2：首屏容量契约（防「重分组 / 加项」把既有直点路径顶掉）
    //
    // 来历：N4-2 原计划按语义重分组（世界观上移与角色同组）。**实测否掉了它**——
    // 默认 0.55 下 sheet 高 351.6dp，「章节列表/大纲/角色/全文搜索」四行已
    // **恰好占满**（全文搜索底 599.4 vs 视口底 600.0，余量 0.6dp），
    // 在其之前插入任何一行（项 48 / 组头 23）都会把它顶出首屏，
    // 而 `writing_menu_sheet_test.dart` 与 `writing_page_test.dart` 对它是**直点**。
    //
    // ★ P1 重裁（T-20261126-04）后本契约的**两处变更**，都写清理由：
    //   ① **视口**：原用 Flutter 测试默认 800×600。该视口逻辑高 600dp，
    //      **不是手机尺寸**（1080×2340 @2.75 的真机逻辑高是 851dp）。
    //      实测 800×600 容器仅 351.6dp，扣掉拖拽条 + 保存行 + tab 栏 +
    //      分隔线 + 取消（约 188dp）后只剩约 164dp ≈ 3.4 项 ⇒ 6 项装不下。
    //      ⇒ 本契约改在**真机竖屏**尺寸下断言（393×851），这是产品真实使用面。
    //   ② **阴性对照**：原对照 `版本时光机` 是「滚动区外的项」。A 案把它移进
    //      「设置」tab 后，**默认 tab 里根本不存在该文本** ⇒ `find.text` 抛
    //      not found，那是**假红不是鉴别力**（报批稿 §三 已预埋此坑）。
    //      替代对照 = **800×600 视口下的 `回收板`**：同一份代码、同一 tab、
    //      只是视口更矮 ⇒ 它确实在首屏外。这保证「首屏」判据真的在测边界，
    //      而不是「反正都在」。
    // ─────────────────────────────────────────────────────────────

    /// 在指定逻辑尺寸下渲染菜单（真机竖屏用 393×851）。
    Future<void> pumpSheetAtSize(WidgetTester tester, Size logical) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = logical;
      addTearDown(tester.view.reset);
    }

    testWidgets('N4-2 首屏容量契约：三 tab 首屏可见入口合计 ≥12/14', (tester) async {
      // ─────────────────────────────────────────────────────────────
      // 判据出处：`T-20261126-04` 卡面 V1 原文 ——
      //   「首屏可见可点入口 ≥12/14。判据：`tester.getRect(...).bottom <=
      //     sheet.bottom + 0.5` **计数的入口数**」
      //
      // ★ 计数口径（易错，务必读完再改本用例）：
      //   卡面的「14」是**单列形态**下的 14 个可点项。A 案分成三 tab 后，
      //   这些项分布在三个 tab 里（写作工具 6 + 教学 5 + 设置 2 = 13 个功能项，
      //   外加跨 tab 恒在的「取消」= 14）⇒ 用户一次只看到一个 tab，
      //   **单个 tab 最多 7 项，不可能单 tab 达 12**。
      //   ⇒ 故「≥12」必须在**跨 tab 合计**上判：13 功能项 + 1 取消 = 14 个可点入口。
      //
      // ★ 沿革（R4 裁定，`DECISIONS §4-576` / 卡面 §二 V1 附注）：
      //   本用例改前只断「每一项都 ≤ sheet.bottom」⇒ 默认 tab 的「取消」
      //   初始态超界 8.35dp（`859.35 vs 851.00`，48dp 保存行布局）⇒ 恒红。
      //   现改为卡面原文「**数个数**」，并把「取消」的完整性判据放宽到
      //   卡面 §6.3a 自己的定性：「初始态部分可见 + 滚动可达 ⇒ 不是功能缺陷」。
      //   ⇒ 48dp 与 36dp **两种保存行高度下均绿**，而把「取消」推出容器、
      //     或断掉滚动，仍会红（变异已验，见回执）。
      //   ⚠️ 本注释**不声称某一种高度是已采用的实现** —— 保存行高度属
      //     `R4-M4②`，其取舍见卡面 §6.3a，不由测试背书。
      // ─────────────────────────────────────────────────────────────
      await pumpSheetAtSize(tester, const Size(393, 851));
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});

      const tolerance = 0.5;

      /// 某 tab 下「计入首屏可见」的入口标签（判据与卡面 V1 逐字同源）。
      ///
      /// 返回值里带读数，`reason` 会打印出来 ⇒ 下一轮复核可看着数字判绿，
      /// 不看数字的绿会被判假绿。
      List<String> visibleOn(String tab, List<String> labels) {
        final sheet = tester.getRect(find.byType(BottomSheet));
        return [
          for (final label in labels)
            if (find.text(label).evaluate().isNotEmpty &&
                tester.getRect(find.text(label)).bottom <=
                    sheet.bottom + tolerance)
              label,
        ];
      }

      var total = 0;
      final report = <String>[];

      // ── tab 1「写作工具」：5 项功能入口 + 取消（戊方案 5/6/2） ──
      const writingTools = ['章节列表', '全文搜索', '查找替换', '快捷短语', '回收板'];
      final wtVisible = visibleOn('写作工具', [...writingTools, '取消']);
      total += wtVisible.length;
      report.add('写作工具 ${wtVisible.length}/${writingTools.length + 1}');

      // ── 三 tab 的「取消」读数：**先采集、后断言**（见下方注释） ──
      //
      // ★ 为什么采集与断言要分离（这是 team-lead 上轮点出的「遮蔽」问题的正解）：
      //   若把断言散在三次切 tab 之间，**任一条先失败都会遮蔽后面的读数** ——
      //   实测过：把「取消」推出容器时，红的是「教学」tab 的 `contains`，
      //   默认 tab 的 `top` 判据根本没机会执行，复核者看不到它到底多少。
      //   ⇒ 故三步走：① 三 tab 全采集；② 拼一条含全部读数的 `evidence`；
      //     ③ 每条断言的 `reason` 都带同一个 `evidence` ⇒ 谁红都能看到三行数。
      final cancelTop = <String, double>{};
      final cancelBottom = <String, double>{};
      final sheetBottomByTab = <String, double>{};
      final maxScrollByTab = <String, double>{};

      Future<void> collectCancel(String tab) async {
        await switchTab(tester, tab);
        final sheet = tester.getRect(find.byType(BottomSheet));
        final cancel = tester.getRect(find.text('取消'));
        final scrollable = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        );
        cancelTop[tab] = cancel.top;
        cancelBottom[tab] = cancel.bottom;
        sheetBottomByTab[tab] = sheet.bottom;
        maxScrollByTab[tab] = tester
            .state<ScrollableState>(scrollable.first)
            .position
            .maxScrollExtent;
      }

      await collectCancel('教学');
      const teaching = ['当前文风', '写作统计', '打开教练面板', '世界观', '角色', '大纲'];
      final tVisible = visibleOn('教学', [...teaching, '取消']);
      total += tVisible.length;
      report.add('教学 ${tVisible.length}/${teaching.length + 1}');

      await collectCancel('设置');
      const settings = ['排版设置', '版本时光机'];
      final sVisible = visibleOn('设置', [...settings, '取消']);
      total += sVisible.length;
      report.add('设置 ${sVisible.length}/${settings.length + 1}');

      // 默认 tab 必须**最后**采集前先回到它（上面已经切到「设置」）
      await switchTab(tester, '写作工具');
      {
        final sheet = tester.getRect(find.byType(BottomSheet));
        final cancel = tester.getRect(find.text('取消'));
        final scrollable = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        );
        cancelTop['写作工具'] = cancel.top;
        cancelBottom['写作工具'] = cancel.bottom;
        sheetBottomByTab['写作工具'] = sheet.bottom;
        maxScrollByTab['写作工具'] = tester
            .state<ScrollableState>(scrollable.first)
            .position
            .maxScrollExtent;
      }

      /// 三 tab「取消」读数的单行汇总 —— 挂进**每一条**相关断言的 `reason`。
      String cancelLine(String t) {
        final top = cancelTop[t]!.toStringAsFixed(2);
        final bottom = cancelBottom[t]!.toStringAsFixed(2);
        final sheet = sheetBottomByTab[t]!.toStringAsFixed(2);
        final max = maxScrollByTab[t]!.toStringAsFixed(2);
        return '$t: top=$top bottom=$bottom sheet.bottom=$sheet max=$max';
      }

      final cancelEvidence =
          '【取消读数】${[
            for (final t in const ['写作工具', '教学', '设置']) cancelLine(t),
          ].join(' | ')}';

      // ★ 卡面 V1 的唯一断言：跨 tab 合计 ≥ 12/14
      //
      // 顺序说明：本条**排在 V2 直点断言之前**。原因是 V2 若先失败会遮蔽本条
      // 的读数（`wtVisible` 只剩 3 项时，看不出「合计到底多少」）。
      // 先跑本条 ⇒ 失败信息里 `report` 会把三个 tab 的分项读数一次打全，
      // 下一轮复核可直接判断是哪个 tab 掉项。
      expect(
        total,
        greaterThanOrEqualTo(12),
        reason:
            '首屏可见可点入口合计 $total/14（${report.join(' · ')}）'
            '未达卡面 V1 下限 12 ⇒ 容量重裁失守',
      );

      // V2 硬约束：四条**直点路径**必须整行在首屏内（本文件与
      // writing_page_test.dart 对它们是裸 `tester.tap`，不可滚）
      // 2026-11-28 戊方案（DECISIONS §4-611）：角色 / 大纲 已移入教学 tab
      // ⇒ 直点契约由 4/4 降为 **2/4**（舰长已批准该降级，见报批稿 §六）。
      // 本列表收窄到 2 项，不是放宽判据：仍在默认 tab 的两条直点路径必须整行在首屏内。
      for (final label in const ['章节列表', '全文搜索']) {
        expect(
          wtVisible,
          contains(label),
          reason: '「$label」被顶出首屏 ⇒ 既有直点路径失效（卡面 V2）',
        );
      }

      // ── 「取消」跨 tab 可得性（原「假绿」修复本体 · 简知微 M1） ──
      //
      // ★ 假绿原始形态（HEAD `:541-546`）：断言名为「取消跨 tab 恒在首屏」，
      //   但它在**切到「设置」tab 之后**才执行一次 ⇒ **默认 tab 从未验过**。
      //   而默认 tab（写作工具）恰是「取消」被挤出首屏的现场。
      //   ⇒ 修复 = **三个 tab 各验一次**，不是「在某个 tab 验一次」。
      //
      // ★ 判据取卡面 §6.3a 自己的定性，而非「必须整行在屏内」：
      //     「初始态部分可见、滚动可达 ⇒ **不是功能缺陷**」
      //   「必须整行在屏内」是对卡面更强的要求，在 48dp 布局下必然红
      //   （`859.35 > 851.00`），且与 §6.3a 冲突 ⇒ 不能用。
      //
      // ★ 每个 tab 的「可得」= 两个条件缺一不可：
      //   ① `top < sheet.bottom` —— 至少露出顶边。**这条是防恒绿的关键**：
      //      只测 ② 时，把「取消」推到 `bottom=1200` 也照样绿（只要滚动距离够）。
      //      ① 把它钉在「只被切边、不是消失」—— 用户得先看得见这个入口。
      //   ② 完整可见，或 `maxScroll >= 出屏量`（滚得到）。
      //
      // ★ 断言里**全部**带 `cancelEvidence` ⇒ 任一条红都能一次看到三 tab 读数。
      //   这条纪律来自本轮实测：把「取消」推出容器时，先红的是「教学」tab，
      //   默认 tab 的读数根本没机会打印 ⇒ 复核者无法判断坏在哪一环。
      for (final tab in const ['写作工具', '教学', '设置']) {
        final top = cancelTop[tab]!;
        final sheetBottom = sheetBottomByTab[tab]!;
        final over = cancelBottom[tab]! - (sheetBottom + tolerance);
        final maxScroll = maxScrollByTab[tab]!;

        // ① 顶边必须在容器内（不是整行被推到外面）
        expect(
          top,
          lessThan(sheetBottom),
          reason:
              '【$tab】「取消」整行被推到容器外（top=$top ≥ sheet.bottom=$sheetBottom）'
              '⇒ 用户不知道有这个入口（§6.3a 只接受「部分可见」，不接受「消失」）。'
              '$cancelEvidence',
        );

        // ② 完整可见 或 滚动可达
        final visibleOrReachable = over <= 0 || maxScroll >= over;
        expect(
          visibleOrReachable,
          isTrue,
          reason:
              '【$tab】「取消」既不在首屏、也滚不到'
              '（超容差=${over.toStringAsFixed(2)}, 可滚=$maxScroll）'
              '⇒ 菜单在该 tab 失去可用的关闭入口（批次96-5 契约）。'
              '$cancelEvidence',
        );
      }
    });

    // ─────────────────────────────────────────────────────────────
    // R4-M1：默认 tab 的「取消」——「要么完整在首屏，要么滚动可达」
    //
    // 判据出处：`T-20261126-04 §二 V1 附注` + `DECISIONS §4-576`
    //   R4 定性：初始态部分可见 + `maxScroll ≥ 裁切量` ⇒ 滚动可达
    //   ⇒ **不是功能级缺陷**，`initialHeight` 产品参数不动。
    //
    // 沿革 / 分支覆盖（**两种保存行高度都要能过**，故不写死任何一侧的现状）。
    //
    // ⚠️ 下表两行各自是一整套布局，**不是只差保存行高度**：
    //    「HEAD 版」= 保存行 48dp + TabBar **在**滚动区内（R5 未做，body:110）
    //    「工作区」= 保存行 36dp + TabBar **已移出**滚动区（R5 已做，body:106）
    //    ⇒ 两行的差异**同时含两个变量**，**不可单归因于那 12dp**
    //      （视口差 48 = `TabBar` 高度，与 12dp 无关；详见下方说明）。
    //
    //  | 布局      | 保存行 | TabBar 位置 | 0.55 档视口 | 0.55 分支 | 0.30 分支 |
    //  |:----------|-------:|:------------|------------:|:----------|:----------|
    //  | HEAD `5ed1b97f` | 48dp | 滚动区内    | 441.65      | **B**（over=+7.85, max=34.35） | B（over=208.60, max=235.10） |
    //  | 工作区          | 36dp | 滚动区外    | 393.65      | **A**（over=−4.15）            | B（over=196.60, max=223.10） |
    //
    //   ⇒ **A / B 两条分支都被真实执行**，无死代码（这是本用例参数的唯一目的）。
    //   ⇒ 不暗示哪一种高度是既定实现（保存行取舍见卡面 §6.3a，**不由测试背书**）。
    //
    // ★ 为什么按**两个 snap 档**各跑一遍（这是本用例的鉴别力来源）：
    //   若只跑 0.55，「滚动可达」分支在 36dp 布局下会成为**不可达代码** ⇒ 恒绿。
    //   故对 `snapSizes` 的两个合法档位（0.30 / 0.55）都断言同一不变量。
    //   ⇒ 若有人断掉滚动（physics 不可滚）或压缩内容导致滚不到，
    //     0.30 档这一遍会红。
    //
    // ★ 视口两版差 48.00 的成因（**已实测，非推算**）：
    //   证明用「**固定区高度**」= `sheetH − vpH`（不依赖任何跨布局等式）：
    //     HEAD  （TabBar 在滚动区内）：489.65 − 441.65 = **48.00**（仅拖拽把手）
    //     工作区（TabBar 已移出）    ：489.65 − 393.65 = **96.00**（把手 48 + TabBar 48）
    //   ⇒ 差 **48.00** = `TabBar` 高度 ⇒ 视口差的 48 **全部来自 R5 结构改动**，
    //     **不是** 保存行 48→36 的 12dp（两版 `TabBar` 高度都是 48.00）。
    //
    //   ⚠️ **不要**用「TabBar 底 == 视口顶」去证：该等式**仅在工作区成立**
    //      （457.35 == 457.35）；HEAD 里 TabBar 在滚动内容内部，位置由滚动量
    //      决定，与视口顶部无关 —— 实测两档都是 `tab.bottom − vp.top = 108.00`：
    //        0.55 档：tab.bottom 517.35 vs vp.top 409.35
    //        0.30 档：tab.bottom 718.10 vs vp.top 610.10
    //      ⇒ 用该等式证「跨布局差值」是把同布局内部关系误用到跨布局比较。
    //
    //   第二重独立证明（三账闭环）：
    //     内容 `476.00 − 416.00 = 60.00` = TabBar 48 + Save 12
    //     视口 `441.65 − 393.65 = 48.00` = TabBar 48
    //     `maxScroll 34.35 − 22.35 = 12.00` = Save 12  ⇒ `60 − 48 = 12` ✅
    //
    //   本用例**不依赖**这个分解：判据只用 `maxScroll` 与 rect，两版均达标。
    //
    // ── 为什么 R5 修完「取消」仍未完整可见（定量，勿凭直觉）──
    //
    // 0.55 档实测（表中三列可直接对账）：
    //   HEAD   （TabBar 在滚动区内 · SaveStatusRow 48）：
    //          视口 441.65 · 内容 476.00 · maxScroll 34.35
    //   工作区 （TabBar 移出 · SaveStatusRow 36）：
    //          视口 393.65 · 内容 416.00 · maxScroll 22.35
    //
    // ⇒ **内容减 60**（`TabBar 48 + Save 12`）
    //   **视口减 48**（`TabBar`）
    //   ⇒ **溢出减 12**（`Save`）—— 三条账互相闭合：
    //     `60 − 48 = 12`，且 `maxScroll 34.35 − 22.35 = 12.00` ✅
    //
    // ⇒ **`TabBar` 移出滚动区对溢出零贡献**：
    //     `DECISIONS §4-575`「内容减 X 且视口也减 X ⇒ 溢出恒等」的同型变体
    //     （此处 X 不等：60 vs 48，故溢出不恒等，而是恰好减掉差额 12）。
    //   ⇒ **只有「压缩 `SaveStatusRow`」才改善「取消」的初始可见性。**
    //     这条务必写明：否则后人会以为「R5 做完，滚动问题就都解决了」。
    //
    // ⚠️ 本段只作**事实记录**，**不构成对 36dp 的支持**：
    //    `SaveStatusRow` 高度取舍见卡面 §6.3a，**不由测试背书**。
    //    本用例在 48dp 与 36dp 下均绿（分支 A/B 各被真实执行）。
    // ─────────────────────────────────────────────────────────────
    for (final initialHeight in const [0.55, 0.30]) {
      testWidgets('R4-M1 默认 tab「取消」@$initialHeight：初始可见或滚动可达（二者必居其一）', (
        tester,
      ) async {
        await pumpSheetAtSize(tester, const Size(393, 851));
        await pumpSheet(
          tester,
          lastSavedAt: null,
          onDiagnose: () {},
          initialHeight: initialHeight,
        );

        const tolerance = 0.5;
        final sheetRect = tester.getRect(find.byType(BottomSheet));
        final sheetBottom = sheetRect.bottom;

        /// 「超出容差的量」——**不是裁切量**。
        ///
        /// 命名刻意如此：几何裁切 = `bottom - sheetBottom`（如 859.35−851.00=8.35）；
        /// 本变量再减 `tolerance` ⇒ 两者差 0.5。若把它叫 `clipped`，下一个读代码的
        /// 人会误以为它是裁切量并与 `maxScrollExtent` 对比（`DECISIONS §4-575` 的
        /// 数值语义混淆已为此付过三笔代价）。
        double overTolerance() =>
            tester.getRect(find.text('取消')).bottom - (sheetBottom + tolerance);

        final before = overTolerance();

        // ⓪ 【仅默认档 0.55】「取消」必须**至少露出顶边**（防「恒绿」的关键判据）
        //
        //   只看 ①（`maxScroll ≥ 出屏量`）会恒绿：把「取消」推到 `bottom=1200`，
        //   只要滚动距离够长，① 照样满足 —— 但用户根本不知道菜单有这个入口。
        //   ⇒ 必须先钉住「只被切边，不是消失」：`top < sheet.bottom`。
        //   实测：48dp 版 `top=839.35 < 851.0`；推到容器外时 `top=1039.35`
        //   ⇒ 立刻红（变异已验，见回执）。
        //
        // ★ 为什么 0.30 档**豁免**这条（本行是本用例的边界，别顺手删）：
        //   0.30 是 `snapSizes` 的合法收缩档（`writing_menu_sheet.dart:91`
        //   `minChildSize: 0.30`，:94 `snapSizes: [0.30, 0.55, 0.85]`）：**sheet 高 288.90dp · 视口仅 192.90dp**；
        //   「取消」`top = 1028.10`，**比容器底 851.00 深出 177.10dp**。
        //   ⇒ 该档「取消」初始态**必然全出屏**，套 `top` 判据**必红且无法修**
        //     （除非改 `snapSizes`，那是产品参数）。
        //   ⇒ 故本档**只判「滚动可达」**（`maxScroll 223.10 ≥ 出屏量`），不判 `top`。
        //
        // ⚠️ 这**不是**「设计预期所以合理」，而是**已知的收缩态可用性劣化**：
        //    要把 `bottom 1048.10` 滚进 `851 + 容差` 内需滚 **196.60dp**
        //    （`maxScroll 223.10` 足够 ⇒ 可达，但用户极可能不知道下方还有「取消」）。
        //    注：`177.10` 是 `top` 超出容器底的量，与「需滚量 196.60」是两个数，
        //    别混用（`DECISIONS §4-575` 的数值语义混淆已为此付过代价）。
        //    是否改善（提高 `minChildSize` / 收缩态保留页脚）是**独立议题**，
        //    不在本卡范围 —— 记在案，别当它不存在。
        if (initialHeight > 0.5) {
          expect(
            tester.getRect(find.text('取消')).top,
            lessThan(sheetBottom),
            reason:
                '「取消」整行被推到容器外'
                '（top=${tester.getRect(find.text('取消')).top}, '
                'sheet.bottom=$sheetBottom）⇒ 用户不知道有这个入口'
                '（卡面 §6.3a 只接受「部分可见」，不接受「消失」）',
          );
        }

        if (before <= 0) {
          // 分支 A：初始态完整可见 —— 无需滚动，但仍须证明 rect 取对了层级
          expect(
            tester.getRect(find.text('取消')).top,
            greaterThanOrEqualTo(sheetRect.top - tolerance),
            reason: '「取消」rect 落在 sheet 之上 ⇒ rect 取错层级，本用例的绿不可信',
          );
          return;
        }

        // 分支 B：初始态部分出屏 ⇒ 必须滚动可达，否则是真功能缺陷
        final scrollable = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(Scrollable),
        );
        final position = tester
            .state<ScrollableState>(scrollable.first)
            .position;

        // ① 距离条件：可滚距离必须**覆盖**出屏量（否则滚到底也看不见）
        expect(
          position.maxScrollExtent,
          greaterThanOrEqualTo(before),
          reason:
              '可滚动距离 < 出屏量 ⇒ 「取消」滚到底仍不可见 = **真功能缺陷**'
              '（maxScroll=${position.maxScrollExtent}, 超容差=$before）',
        );

        // ② ★ 一屏内可达条件（本条是本用例真正的鉴别力所在）
        //
        // 只有 ① 是**结构性恒真**的：只要「取消」是滚动内容的最后一项，
        // `maxScrollExtent == 内容高 − 视口高 ≥ 出屏量` 就必然成立
        // ⇒ 单向 ① 抓不到任何回归（实测：在取消前插 8 个 48dp 填充项，
        //    ① 仍绿，因为多滚几屏还是能到达）。
        //   ⇒ 故补 ②：**「取消」必须在滚一屏之内就能到达**，否则用户要
        //     连续滚多屏才能找到关闭入口 —— 那才是真正该红的体验缺陷。
        //   实测基线：0.30 档 maxScroll=294.0 ≤ 视口 240.9？否 ⇒ 见下。
        //   判据取 `maxScrollExtent <= viewportDimension * 2`
        //   （一次半屏滚动可覆盖，留一屏余量避免文案微调误红）。
        expect(
          position.maxScrollExtent,
          lessThanOrEqualTo(position.viewportDimension * 2),
          reason:
              '「取消」需滚 ${(position.maxScrollExtent / position.viewportDimension).toStringAsFixed(2)}'
              ' 屏才可达 ⇒ 关闭入口藏得太深（一次半屏滚动内应可达）'
              '（maxScroll=${position.maxScrollExtent}, viewport=${position.viewportDimension}）',
        );

        // 真滚一次，验证终态确实完整可见（不只靠算术）
        await tester.scrollUntilVisible(
          find.text('取消'),
          60,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();

        expect(
          overTolerance(),
          lessThanOrEqualTo(0),
          reason: '滚到底后「取消」仍未完整可见 ⇒ 与 maxScroll 断言矛盾',
        );
      });
    }

    testWidgets('N4-2b 阴性对照：同一代码在 800×600 下必须真有项出屏（防假绿）', (tester) async {
      // ★ 鉴别力来源：这段与上一条**同一份代码、同一个 tab**，唯一变量是视口高度。
      //   若上一条的「都在首屏」是真的，这条就必然有项出屏；若这条也全在，
      //   说明断言根本没在测边界（比如 rect 取错了层级）⇒ 上一条的绿不可信。
      await pumpSheetAtSize(tester, const Size(800, 600));
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});

      final sheet = tester.getRect(find.byType(BottomSheet));

      // 2026-11-28 戊方案（DECISIONS §4-611）：默认 tab 由 6 项降为 5 项。
      //   800×600 下 `sheet_top=248.40`、`viewport_top=344.40`、`viewport=255.60`
      //   ⇒ 按当前布局闭式解，第 5 项「回收板」行 top = 344.40 + 60 + 48×4 = 596.40，
      //      底 = 644.40 > 600 ⇒ 已不能把「回收板整行可见」当作首屏探针。
      //   改用「取消」作边界探针：`取消` top = 344.40 + 60 + 48×5 + 20 = **664.40 > 600**
      //   ⇒ 仍然必然出屏，鉴别力不变（仍是同一份代码、同一个 tab，只改视口高度）。
      expect(
        tester.getRect(find.text('取消')).top,
        greaterThan(sheet.bottom),
        reason:
            '阴性对照失败 ⇒ 800×600 下「取消」本该在首屏外却判 IN，'
            '说明首屏判据未真正测到边界，上一条的绿不可信',
      );
    });
  });
}
