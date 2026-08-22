// ─────────────────────────────────────────────────────────────
// EditorSettingsSheet widget 测试 — 排版设置弹层
//
// 覆盖路径：
//   #1 标点栏配置节渲染：15 个可见标点（无「已隐藏」区）
//   #2 隐藏「，」→ 移入已隐藏 + 落库（punctuation_bar_config）
//   #3 上移「。」→ 顺序变化 + 落库
//   #4 恢复「，」→ 回到可见列表 + 落库
//   #5 持久化：隐藏后重开弹层 → 仍隐藏（用户级跨章节生效）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/editor_settings_sheet.dart';
import 'package:writingcoach/widgets/punctuation_bar.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String chapterId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    final msId = await msRepo.createManuscript(title: '测试作品');
    chapterId = await chRepo.createChapter(msId, title: '第一章：启程');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// 泵一个带 Scaffold 的宿主，再打开排版设置弹层
  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    final ctx = tester.element(find.byType(Scaffold));
    EditorSettingsSheet.show(ctx, chapterId: chapterId);
    await tester.pumpAndSettle();
  }

  /// 滚动到目标控件可见（弹层内容超出屏高时）
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  /// 「，」所在配置行（_ConfigRow 为 Row）
  Finder commaRow() =>
      find.ancestor(of: find.text('，'), matching: find.byType(Row)).first;

  /// 「。」所在配置行
  Finder periodRow() =>
      find.ancestor(of: find.text('。'), matching: find.byType(Row)).first;

  group('批次86-②：自定义工具栏（标点栏配置节）', () {
    testWidgets('#86-2 打开排版设置 → 标点栏配置节渲染 15 个可见标点', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, find.text('标点栏'));
      expect(find.text('标点栏'), findsOneWidget);
      expect(find.textContaining('隐藏不常用的'), findsOneWidget);

      // 15 个可见标点行，每行都有「隐藏」按钮
      expect(find.text('隐藏'), findsNWidgets(15));
      // 未隐藏任何项 → 无「已隐藏」区
      expect(find.text('已隐藏'), findsNothing);
    });

    testWidgets('#86-2 隐藏「，」→ 移入已隐藏 + 落库', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, commaRow());
      await tester.tap(
        find.descendant(of: commaRow(), matching: find.text('隐藏')),
      );
      await tester.pumpAndSettle();

      // UI：可见行少一个，「已隐藏」区出现「，」行（带「恢复」）
      expect(find.text('隐藏'), findsNWidgets(14));
      expect(find.text('已隐藏'), findsOneWidget);
      expect(
        find.descendant(of: commaRow(), matching: find.text('恢复')),
        findsOneWidget,
      );

      // 落库：comma 不在配置列表
      final ids = await AppStateRepository(db).getPunctuationBarConfig();
      expect(ids, isNotNull);
      expect(ids, isNot(contains('comma')));
      expect(ids, hasLength(14));
    });

    testWidgets('#86-2 上移「。」→ 顺序变化 + 落库', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, periodRow());
      await tester.tap(
        find.descendant(
          of: periodRow(),
          matching: find.byIcon(Icons.arrow_upward),
        ),
      );
      await tester.pumpAndSettle();

      // 落库：period 从 index 1 移到 index 0
      final ids = await AppStateRepository(db).getPunctuationBarConfig();
      expect(ids, isNotNull);
      expect(ids!.indexOf('period'), 0);
      expect(ids.indexOf('comma'), 1);
    });

    testWidgets('#86-2 隐藏后恢复「，」→ 回到可见列表尾部 + 落库', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, commaRow());
      await tester.tap(
        find.descendant(of: commaRow(), matching: find.text('隐藏')),
      );
      await tester.pumpAndSettle();

      // 恢复（comma 行现在在「已隐藏」区）
      await reveal(tester, commaRow());
      await tester.tap(
        find.descendant(of: commaRow(), matching: find.text('恢复')),
      );
      await tester.pumpAndSettle();

      final ids = await AppStateRepository(db).getPunctuationBarConfig();
      expect(ids, isNotNull);
      expect(ids, contains('comma'));
      expect(ids, hasLength(15));
      // 恢复追加到尾部（默认顺序中 comma 在 index 0，恢复后应回到尾部）
      expect(ids!.last, 'comma');
    });

    testWidgets('#86-2 持久化：隐藏后重开弹层 → 仍隐藏', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, commaRow());
      await tester.tap(
        find.descendant(of: commaRow(), matching: find.text('隐藏')),
      );
      await tester.pumpAndSettle();

      // 关闭弹层后重开
      Navigator.of(tester.element(find.byType(EditorSettingsSheet))).pop();
      await tester.pumpAndSettle();
      await pumpSheet(tester);

      await reveal(tester, find.text('已隐藏'));
      expect(find.text('已隐藏'), findsOneWidget);
      expect(
        find.descendant(of: commaRow(), matching: find.text('恢复')),
        findsOneWidget,
      );
    });

    testWidgets('#87-1 恢复默认顺序 → 15 项可见 + 落库默认顺序', (tester) async {
      await pumpSheet(tester);

      // 先制造自定义配置：隐藏 comma + 上移 period
      await reveal(tester, commaRow());
      await tester.tap(
        find.descendant(of: commaRow(), matching: find.text('隐藏')),
      );
      await tester.pumpAndSettle();
      await reveal(tester, periodRow());
      await tester.tap(
        find.descendant(
          of: periodRow(),
          matching: find.byIcon(Icons.arrow_upward),
        ),
      );
      await tester.pumpAndSettle();

      // 一键还原
      await reveal(tester, find.text('恢复默认'));
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();

      // UI：15 项全部可见 + 无「已隐藏」区
      expect(find.text('隐藏'), findsNWidgets(15));
      expect(find.text('已隐藏'), findsNothing);
      // 落库：配置等于默认顺序
      final ids = await AppStateRepository(db).getPunctuationBarConfig();
      expect(ids, defaultPunctuationIds);
    });
  });

  group('批次88-5：标点栏自定义增删', () {
    testWidgets('#88-5 添加自定义标点 → 列表出现 + 落库（custom + 可见列表）', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, find.text('添加标点'));
      await tester.tap(find.text('添加标点'));
      await tester.pumpAndSettle();

      // 弹输入框 → 输入「『」→ 确定
      await tester.enterText(find.byType(TextField).last, '『');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      await reveal(tester, find.text('『'));
      expect(find.text('『'), findsOneWidget);

      // 落库：自定义项 + 可见列表含其 id
      final repo = AppStateRepository(db);
      final customs = await repo.getPunctuationCustomItems();
      expect(customs, hasLength(1));
      expect(customs.first.display, '『');
      final ids = await repo.getPunctuationBarConfig();
      expect(ids, contains(customs.first.id));
    });

    testWidgets('#88-5 添加重复标点 → 提示 + 不落库', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, find.text('添加标点'));
      await tester.tap(find.text('添加标点'));
      await tester.pumpAndSettle();
      // 内置已存在的「，」
      await tester.enterText(find.byType(TextField).last, '，');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('这个标点已经在工具栏里了'), findsOneWidget);
      expect(await AppStateRepository(db).getPunctuationCustomItems(), isEmpty);
    });

    testWidgets('#88-5 删除自定义标点 → 行移除 + 落库清空', (tester) async {
      final repo = AppStateRepository(db);
      await repo.setPunctuationCustomItems(const [
        PunctuationItem('custom_01', '『', '『'),
      ]);
      await repo.setPunctuationBarConfig(['comma', 'period', 'custom_01']);

      await pumpSheet(tester);

      await reveal(tester, find.text('『'));
      // 自定义行显示删除按钮
      final row = find
          .ancestor(of: find.text('『'), matching: find.byType(Row))
          .first;
      await tester.tap(
        find.descendant(of: row, matching: find.byIcon(Icons.delete_outline)),
      );
      await tester.pumpAndSettle();

      expect(find.text('『'), findsNothing);
      expect(await repo.getPunctuationCustomItems(), isEmpty);
      final ids = await repo.getPunctuationBarConfig();
      expect(ids, isNot(contains('custom_01')));
      expect(ids, hasLength(2));
    });

    testWidgets('#88-5 恢复默认 → 清空自定义项', (tester) async {
      final repo = AppStateRepository(db);
      await repo.setPunctuationCustomItems(const [
        PunctuationItem('custom_01', '『', '『'),
      ]);
      await repo.setPunctuationBarConfig(['comma', 'custom_01']);

      await pumpSheet(tester);
      await reveal(tester, find.text('恢复默认'));
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();

      expect(await repo.getPunctuationCustomItems(), isEmpty);
      final ids = await repo.getPunctuationBarConfig();
      expect(ids, defaultPunctuationIds);
    });
  });

  group('批次96-9：三开关移入排版设置', () {
    testWidgets('#96-9 行段聚焦开关：默认关 → 点击开启 + 落库', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, find.text('行段聚焦'));
      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '行段聚焦'),
      );
      expect(sw.value, isFalse);

      await tester.tap(find.text('行段聚焦'));
      await tester.pumpAndSettle();

      final sw2 = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '行段聚焦'),
      );
      expect(sw2.value, isTrue);
      expect(await AppStateRepository(db).getValue('editor_focus_mode'), '1');
    });

    testWidgets('#96-9 智能标点开关：默认开 → 点击关闭 + 落库', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, find.text('智能标点'));
      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '智能标点'),
      );
      expect(sw.value, isTrue);

      await tester.tap(find.text('智能标点'));
      await tester.pumpAndSettle();

      final sw2 = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '智能标点'),
      );
      expect(sw2.value, isFalse);
      expect(
        await AppStateRepository(db).getSmartPunctuationEnabled(),
        isFalse,
      );
    });

    testWidgets('#96-9 显示对话按钮开关：默认开 → 点击关闭 + 落库', (tester) async {
      await pumpSheet(tester);

      await reveal(tester, find.text('显示对话按钮'));
      final sw = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '显示对话按钮'),
      );
      expect(sw.value, isTrue);

      await tester.tap(find.text('显示对话按钮'));
      await tester.pumpAndSettle();

      final sw2 = tester.widget<SwitchListTile>(
        find.widgetWithText(SwitchListTile, '显示对话按钮'),
      );
      expect(sw2.value, isFalse);
      expect(await AppStateRepository(db).getFabVisible(), isFalse);
    });
  });
}
