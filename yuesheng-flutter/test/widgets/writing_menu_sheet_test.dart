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

import 'package:writingcoach/widgets/writing_menu_sheet.dart';

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

    testWidgets('渲染菜单项：打开教练面板可见，占位项已移除', (tester) async {
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});

      expect(find.text('打开教练面板'), findsOneWidget);
      // 批次82：新增「排版设置」真实入口（P0 四件套之①）
      expect(find.text('排版设置'), findsOneWidget);
      // 批次82：新增「版本时光机」入口（P0 四件套之③）
      expect(find.text('版本时光机'), findsOneWidget);
      // 批次83：新增「章节列表」章节树抽屉入口（P1）
      expect(find.text('章节列表'), findsOneWidget);
      // 批次83：新增「大纲」大纲抽屉入口（P1）
      expect(find.text('大纲'), findsOneWidget);
      // 批次96-11：新增「全文搜索」整本作品搜索入口（P1）
      expect(find.text('全文搜索'), findsOneWidget);
      // 批次84-2：新增「查找替换」全文查找替换入口（P1）
      expect(find.text('查找替换'), findsOneWidget);
      // 批次96-8：移除「我的灵感」入口（参考百灵布局）
      expect(find.text('我的灵感'), findsNothing);
      // 批次86-1：新增「回收板」长文本找回入口（P2）
      expect(find.text('回收板'), findsOneWidget);
      // 批次85-3：新增「快捷短语」常用语入口（P2）
      expect(find.text('快捷短语'), findsOneWidget);
      // 批次85-4：新增「当前文风」风格画像入口（P2）
      expect(find.text('当前文风'), findsOneWidget);
      // 批次85-5：新增「写作统计」入口（P2）
      expect(find.text('写作统计'), findsOneWidget);
      // 批次96-9：三个开关已移入排版设置，菜单只留跳转入口（参考百灵极简）
      expect(find.text('行段聚焦'), findsNothing);
      expect(find.text('智能标点'), findsNothing);
      expect(find.text('对话按钮（开）'), findsNothing);
      // 批次96-9：菜单分组标题（写作工具/教学/设置）
      expect(find.text('写作工具'), findsOneWidget);
      expect(find.text('教学'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      // 批次96-5：菜单末尾「取消」——菜单近全屏时遮罩仅剩顶部窄条，需显式关闭入口
      expect(find.text('取消'), findsOneWidget);
      // E3：其他「开发中」占位项不再渲染
      expect(find.text('撤销'), findsNothing);
      expect(find.text('重做'), findsNothing);
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

      // 菜单已 15 项，「版本时光机」在滚动区外 → 先滚动到可见再点
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

      await tapMenuBottom(tester, '写作统计');
      await tester.pumpAndSettle();

      expect(statsCalled, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('lastSavedAt=null → "未保存"；非空 → "✓ 已保存 HH:mm"', (tester) async {
      // case 1: null
      await pumpSheet(tester, lastSavedAt: null, onDiagnose: () {});
      expect(find.text('未保存'), findsOneWidget);

      // 关闭 sheet 后再来一次
      await tapMenuBottom(tester, '打开教练面板');

      // case 2: DateTime(2026, 8, 5, 15, 32)
      await pumpSheet(
        tester,
        lastSavedAt: DateTime(2026, 8, 5, 15, 32),
        onDiagnose: () {},
      );
      expect(find.text('✓ 已保存 15:32'), findsOneWidget);
    });
  });
}
