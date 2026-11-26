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

      // ── 默认 tab「写作工具」：6 项 ──
      // 批次83：章节列表 / 大纲；C78 批次3：角色；批次96-11：全文搜索；
      // 批次84-2：查找替换；批次86-1：回收板
      for (final label in const ['章节列表', '大纲', '角色', '全文搜索', '查找替换', '回收板']) {
        expect(find.text(label), findsOneWidget, reason: '默认 tab 缺「$label」');
      }

      // ── tab 栏：标签复用原组头字面（三个都在，才能互切）──
      expect(find.text('写作工具'), findsOneWidget);
      expect(find.text('教学'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      // tab 数量恰为 3（防「多渲染一个空 tab」或「漏挂一个 tab」）
      expect(find.byType(Tab), findsNWidgets(3));

      // ── 切到「教学」：5 项 ──
      await switchTab(tester, '教学');
      for (final label in const [
        '当前文风', // 批次85-4
        '写作统计', // 批次85-5
        '打开教练面板', // 批次79 B 改名
        '世界观', // W1
        '快捷短语', // 批次85-3
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

      await tester.tap(find.text('大纲'));
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

      await tester.tap(find.text('角色'));
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

      // P1 重裁：「快捷短语」现属「教学」tab
      await switchTab(tester, '教学');
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

    testWidgets('N4-2 首屏容量契约：真机竖屏下三 tab 全部入口均在首屏内', (tester) async {
      // 393×851 = 1080×2340 @2.75，即走查所用 1080×2340 设备的逻辑尺寸
      await pumpSheetAtSize(tester, const Size(393, 851));
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});

      final sheet = tester.getRect(find.byType(BottomSheet));

      // ── 正例 1：默认 tab 的四条**直点路径**必须整行落在首屏内 ──
      //    载体：本文件 `tester.tap(find.text(...))` 与 `writing_page_test.dart`
      const directTap = ['章节列表', '大纲', '角色', '全文搜索'];
      for (final label in directTap) {
        final r = tester.getRect(find.text(label));
        expect(
          r.bottom,
          lessThanOrEqualTo(sheet.bottom + 0.5),
          reason: '「$label」被顶出首屏 ⇒ 既有直点路径失效（N4-2 实测约束）',
        );
      }

      // ── 正例 2：「写作工具」tab 六项全部可见（改后容量读数 6/6）──
      for (final label in const ['章节列表', '大纲', '角色', '全文搜索', '查找替换', '回收板']) {
        expect(
          tester.getRect(find.text(label)).bottom,
          lessThanOrEqualTo(sheet.bottom + 0.5),
          reason: '「写作工具」tab 的「$label」不在首屏 ⇒ 容量重裁未达 6/6',
        );
      }

      // ── 正例 3：「教学」5/5 ──
      await switchTab(tester, '教学');
      for (final label in const ['当前文风', '写作统计', '打开教练面板', '世界观', '快捷短语']) {
        expect(
          tester.getRect(find.text(label)).bottom,
          lessThanOrEqualTo(sheet.bottom + 0.5),
          reason: '「教学」tab 的「$label」不在首屏 ⇒ 未达 5/5',
        );
      }

      // ── 正例 4：「设置」2/2 ──
      await switchTab(tester, '设置');
      for (final label in const ['排版设置', '版本时光机']) {
        expect(
          tester.getRect(find.text(label)).bottom,
          lessThanOrEqualTo(sheet.bottom + 0.5),
          reason: '「设置」tab 的「$label」不在首屏 ⇒ 未达 2/2',
        );
      }

      // ── 正例 5：「取消」跨 tab 恒在首屏（它是关闭入口，不能被挤出）──
      expect(
        tester.getRect(find.text('取消')).bottom,
        lessThanOrEqualTo(sheet.bottom + 0.5),
        reason: '「取消」被挤出首屏 ⇒ 菜单失去显式关闭入口（批次96-5 契约）',
      );
    });

    testWidgets('N4-2b 阴性对照：同一代码在 800×600 下必须真有项出屏（防假绿）', (tester) async {
      // ★ 鉴别力来源：这段与上一条**同一份代码、同一个 tab**，唯一变量是视口高度。
      //   若上一条的「都在首屏」是真的，这条就必然有项出屏；若这条也全在，
      //   说明断言根本没在测边界（比如 rect 取错了层级）⇒ 上一条的绿不可信。
      await pumpSheetAtSize(tester, const Size(800, 600));
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});

      final sheet = tester.getRect(find.byType(BottomSheet));
      expect(
        tester.getRect(find.text('回收板')).bottom,
        greaterThan(sheet.bottom),
        reason:
            '阴性对照失败 ⇒ 800×600 下「回收板」本该在首屏外却判 IN，'
            '说明首屏判据未真正测到边界，上一条 6/6 的绿不可信',
      );
    });
  });
}
