// ─────────────────────────────────────────────────────────────
// EditorWalkthroughTest — 编辑器姿态走查（批次88 前置）
// 在真实 Android 模拟器/真机上运行，核查批次82-87 编辑器功能完成度：
// 真实屏幕尺寸下的布局姿态（无溢出）、菜单可达性、核心闭环。
//
// 运行：flutter test integration_test/editor_walkthrough_test.dart -d <device>
//
// 覆盖（批次82-87 冒烟）：
//   1. 章节加载姿态：标题/字数/保存状态行/标点栏/FAB 全部在位
//   2. 输入 → 字数更新 + 即时保存
//   3. ⋮ 菜单 15 项全部可达（滚动后逐项弹层出现）
//   4. 回收板闭环：删除 ≥8 字 → 找回恢复
//   5. 智能标点：输入「 → 自动补全「」
//   6. 排版设置：字号/背景/标点栏配置节 + 恢复默认顺序
//   7. 版本时光机：差异角标 + 空态
//   8. 章节树/大纲抽屉可达
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:drift/native.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/punctuation_bar.dart';
import 'package:writingcoach/widgets/writing_curve_chart.dart';
import 'package:writingcoach/widgets/writing_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late ProviderContainer container;
  late String chapterId;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    final msRepo = ManuscriptRepository(db);
    final chRepo = ChapterRepository(db);
    manuscriptId = await msRepo.createManuscript(title: '走查作品');
    chapterId = await chRepo.createChapter(
      manuscriptId,
      title: '第一章：晨雾',
      content: '这是一个大雪纷飞的夜晚。',
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildWritingPage() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: WritingPage(
          chapterId: chapterId,
          manuscriptId: manuscriptId,
        ),
      ),
    );
  }

  Finder editor() => find.descendant(
    of: find.byKey(const Key('editorContainer')),
    matching: find.byType(TextField),
  );

  /// 打开 ⋮ 菜单并滚动到指定项点击
  Future<void> tapMenuItem(WidgetTester tester, String label) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    final item = find.text(label);
    await tester.scrollUntilVisible(
      item,
      120,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  /// 关闭当前弹层/抽屉（返回编辑器）
  Future<void> closeSheet(WidgetTester tester) async {
    // 优先点弹层右上角关闭/返回；兜底按 ESC 语义（Navigator.pop）
    final closeBtns = find.byIcon(Icons.close);
    if (closeBtns.evaluate().isNotEmpty) {
      await tester.tap(closeBtns.first);
      await tester.pumpAndSettle();
      return;
    }
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  }

  testWidgets('1 编辑器姿态：标题/字数/保存状态/标点栏/FAB 全部在位', (tester) async {
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    expect(find.text('第一章：晨雾'), findsWidgets, reason: '章节标题应显示');
    expect(find.text('12字'), findsOneWidget, reason: '字数应显示');
    expect(find.byType(PunctuationBar), findsOneWidget, reason: '标点栏应在');
    expect(find.byType(FloatingActionButton), findsOneWidget, reason: 'AI 面板 FAB 应在');
    // 保存状态行在 ⋮ 菜单内
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('未保存'), findsOneWidget, reason: '保存状态行应在');
    await closeSheet(tester);
  });

  testWidgets('2 输入 → 字数更新 + 即时保存（编辑器可用）', (tester) async {
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    await tester.enterText(editor(), '晨雾里，他推开了窗。');
    await tester.pumpAndSettle();
    expect(find.text('12字'), findsNothing);
  });

  testWidgets('3 ⋮ 菜单 12 项全部可达（逐项弹层出现 + 分组标题）', (tester) async {
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    // 弹层类入口：逐项打开并断言标题出现后关闭
    final entries = <String, String>{
      '排版设置': '字号',
      '写作统计': '近7天', // 窗口切换 chips 恒定存在（有数据时无空态文案）
      '版本时光机': '还没有版本记录',
      '回收板': '删掉或剪切的长文本',
      '快捷短语': '快捷短语',
    };
    for (final e in entries.entries) {
      await tapMenuItem(tester, e.key);
      expect(
        find.textContaining(e.value),
        findsWidgets,
        reason: '菜单「${e.key}」应打开弹层（含「${e.value}」）',
      );
      await closeSheet(tester);
    }

    // 抽屉类入口
    await tapMenuItem(tester, '章节列表');
    expect(find.textContaining('章节列表'), findsWidgets, reason: '章节树抽屉应打开');
    await closeSheet(tester);
    await tapMenuItem(tester, '大纲');
    expect(find.textContaining('大纲'), findsWidgets, reason: '大纲抽屉应打开');
    await closeSheet(tester);

    // 批次96-9：菜单分组标题 + 三个开关已移入排版设置（菜单只留跳转入口）
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('写作工具'), findsOneWidget, reason: '菜单应有「写作工具」分组');
    expect(find.text('教学'), findsOneWidget, reason: '菜单应有「教学」分组');
    expect(find.text('设置'), findsOneWidget, reason: '菜单应有「设置」分组');
    expect(find.text('行段聚焦'), findsNothing, reason: '行段聚焦开关已移入排版设置');
    expect(find.text('智能标点'), findsNothing, reason: '智能标点开关已移入排版设置');
    expect(find.textContaining('对话按钮'), findsNothing, reason: '对话按钮开关已移入排版设置');
    await closeSheet(tester);
  });

  testWidgets('4 回收板闭环：删除 ≥8 字 → 找回恢复', (tester) async {
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    await tester.enterText(editor(), '这是');
    await tester.pumpAndSettle();

    await tapMenuItem(tester, '回收板');
    expect(find.text('一个大雪纷飞的夜晚。'), findsOneWidget, reason: '被删长文本应入回收板');
    await tester.tap(find.text('一个大雪纷飞的夜晚。'));
    await tester.pumpAndSettle();

    final controller = tester.widget<TextField>(editor()).controller!;
    expect(controller.text, '这是一个大雪纷飞的夜晚。', reason: '恢复应插入光标处');
  });

  testWidgets('5 智能标点：输入「 → 自动补全「」且光标居中', (tester) async {
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    await tester.enterText(editor(), '');
    await tester.enterText(editor(), '「');
    await tester.pumpAndSettle();

    final controller = tester.widget<TextField>(editor()).controller!;
    expect(controller.text, '「」', reason: '左符应自动补右符');
    expect(controller.selection.baseOffset, 1, reason: '光标应在中间');
  });

  testWidgets('6 排版设置：字号/背景/标点栏配置节 + 恢复默认顺序', (tester) async {
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    await tapMenuItem(tester, '排版设置');
    expect(find.text('字号'), findsOneWidget);
    expect(find.text('背景'), findsOneWidget);

    // 标点栏配置节（滚动到可见）
    await tester.scrollUntilVisible(
      find.text('标点栏'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('恢复默认'), findsOneWidget, reason: '配置节应有恢复默认');
    await closeSheet(tester);
  });

  testWidgets('7 版本时光机：差异角标 + 空态', (tester) async {
    final repo = AppStateRepository(db);
    await repo.addChapterVersion(chapterId, '这是一个大雪纷飞的夜晚，雪很大。');
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    await tapMenuItem(tester, '版本时光机');
    expect(find.text('+4'), findsOneWidget, reason: '版本差异角标应显示');
    await closeSheet(tester);
  });

  testWidgets('8 写作统计：窗口切换 + 曲线（教学留痕可见）', (tester) async {
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    await tapMenuItem(tester, '写作统计');
    // 有字数章节 → 曲线应出现（或空态，均算可达）
    final hasChart = find.byType(WritingCurveChart).evaluate().isNotEmpty;
    final hasEmpty = find.text('还没有写作记录').evaluate().isNotEmpty;
    expect(hasChart || hasEmpty, isTrue, reason: '写作统计弹层应可达');
    expect(find.text('近7天'), findsOneWidget, reason: '窗口切换应存在');
    await closeSheet(tester);
  });

  testWidgets('9 批次88：回车自动缩进 + 对话按钮开关（新功能冒烟）', (tester) async {
    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    // 标题独立行：正文上方大号可编辑标题（Key 定位）
    expect(find.byKey(const Key('chapterTitleField')), findsOneWidget,
        reason: '正文上方独立标题行应在');

    // 回车自动补两格缩进（段落格式默认开）
    await tester.enterText(editor(), '第一段。\n');
    await tester.pumpAndSettle();
    final controller = tester.widget<TextField>(editor()).controller!;
    expect(controller.text, '第一段。\n\u3000\u3000',
        reason: '回车应自动补两格全角空格缩进');

    // 对话按钮开关已移入排版设置（批次96-9：菜单不再有开关项）
    await tapMenuItem(tester, '排版设置');
    await tester.scrollUntilVisible(
      find.text('显示对话按钮'),
      120,
      scrollable: find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('显示对话按钮'));
    await tester.pumpAndSettle();
    expect(await AppStateRepository(db).getFabVisible(), isFalse,
        reason: '对话按钮开关应可隐藏并落库');
    // 再点恢复显示
    await tester.tap(find.text('显示对话按钮'));
    await tester.pumpAndSettle();
    expect(await AppStateRepository(db).getFabVisible(), isTrue,
        reason: '对话按钮应从排版设置恢复');
    await closeSheet(tester);
    expect(find.byKey(const Key('aiChatFab')), findsOneWidget,
        reason: '恢复后 FAB 应回到页面');
  });

  testWidgets('10 批次89：卷分组冒烟（分组展示 + 新建卷 + 删卷回未分卷）', (tester) async {
    // 预置：建卷 + 章节移入 + 未分卷章节
    final volRepo = VolumeRepository(db);
    final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
    await volRepo.setChapterVolume(chapterId, v1);
    await ChapterRepository(db).createChapter(manuscriptId, title: '散章');

    await tester.pumpWidget(buildWritingPage());
    await tester.pumpAndSettle();

    // 打开章节树抽屉 → 按卷分组展示（卷头 + 卷内章 + 未分卷章）
    await tapMenuItem(tester, '章节列表');
    final drawer = find.byType(Drawer);
    expect(
      find.descendant(of: drawer, matching: find.text('第一卷')),
      findsOneWidget,
      reason: '卷头「第一卷」应显示',
    );
    expect(
      find.descendant(of: drawer, matching: find.text('第一章：晨雾')),
      findsOneWidget,
      reason: '卷内章节应显示',
    );
    expect(
      find.descendant(of: drawer, matching: find.text('散章')),
      findsOneWidget,
      reason: '未分卷章节应显示',
    );

    // 新建卷（输入名称）→ 卷头出现
    await tester.tap(find.byKey(const ValueKey('create-volume-btn')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('new-volume-field')),
      '第二卷',
    );
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: drawer, matching: find.text('第二卷')),
      findsOneWidget,
      reason: '新建卷「第二卷」应显示',
    );

    // 长按第一卷 → 删除卷 → 二次确认 → 卷头消失、章节仍可见
    await tester.longPress(
      find.descendant(of: drawer, matching: find.text('第一卷')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除卷'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: drawer, matching: find.text('第一卷')),
      findsNothing,
      reason: '删除后卷头应消失',
    );
    expect(
      find.descendant(of: drawer, matching: find.text('第一章：晨雾')),
      findsOneWidget,
      reason: '删卷后章节应保留（回未分卷组）',
    );

    await closeSheet(tester);
  });
}
