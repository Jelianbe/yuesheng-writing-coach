// ─────────────────────────────────────────────────────────────
// manuscript_detail_page_test — 作品详情页 Widget 测试
//
// 覆盖路径：
//   #1 空章节 → 显示空状态 + CTA 按钮
//   #2 有章节 → 章节列表正确渲染（序号、标题、字数、状态）
//   #3 章节空状态 CTA → 弹出创建弹窗
//   #4 创建弹窗：标题为空 → SnackBar 提示
//   #5 创建弹窗：标题有效 → 创建成功 + 列表更新
//   #6 多章节 → 全量显示，按 sort_order 排序
//   #7 作品信息卡 → 标题/简介/类型/总字数显示
//   #8 创建章节带内容 → wordCount 同步正确
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/chapter_providers.dart';
import 'package:writingcoach/providers/manuscript_providers.dart';
import 'package:writingcoach/providers/session_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/router/app_routes.dart';
import 'package:writingcoach/widgets/bookshelf_page.dart';
import 'package:writingcoach/widgets/chapter_recycle_bin_page.dart';
import 'package:writingcoach/widgets/chat_page.dart';
import 'package:writingcoach/widgets/manuscript_detail_page.dart';
import 'package:writingcoach/widgets/project_settings_page.dart';
import 'package:writingcoach/widgets/writing_page.dart';

import '../helpers/mock_last_session_storage.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // 批次 50：隔离 flutter_secure_storage 平台通道（testWidgets 下未 mock 的通道调用会挂起）
        lastSessionStorageProvider.overrideWithValue(
          MemoryLastSessionStorage(),
        ),
      ],
    );
    // 预置一个作品
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品', description: '这是一个测试作品的简介', genre: '奇幻');
    // 先把作品加载到 manuscriptStore，供页面使用
    await container.read(manuscriptStoreProvider.notifier).loadManuscripts();
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildDetailPage({String? title}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: ManuscriptDetailPage(
          args: ManuscriptDetailArgs(manuscriptId: manuscriptId, title: title),
        ),
      ),
    );
  }

  /// 批次92-3：带 GoRouter 的最小详情页（新建章节成功后需 push 写作页）
  /// /writing/:chapterId 用 Marker 占位（断言「创建后立即跳写作页」）
  Future<void> pumpDetailWithRouter(WidgetTester tester, {String? title}) async {
    final router = GoRouter(
      initialLocation: '/detail',
      routes: [
        GoRoute(
          path: '/detail',
          builder: (context, state) => ManuscriptDetailPage(
            args: ManuscriptDetailArgs(
              manuscriptId: manuscriptId,
              title: title,
            ),
          ),
        ),
        GoRoute(
          path: '/writing/:chapterId',
          builder: (context, state) => const SizedBox(
            key: Key('writing-marker'),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ManuscriptDetailPage', () {
    testWidgets('#1 空章节 → 显示空状态 + CTA', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('还没有章节'), findsOneWidget);
      expect(find.text('新建章节'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('#2 有章节 → 列表渲染：标题/字数/状态（批次90：移除序号色块）', (tester) async {
      final repo = ChapterRepository(db);
      await repo.createChapter(
        manuscriptId,
        title: '第一章：启程',
        content: '这是内容测试' * 10,
      );
      await repo.createChapter(manuscriptId, title: '第二章：相遇');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 标题
      expect(find.text('第一章：启程'), findsOneWidget);
      expect(find.text('第二章：相遇'), findsOneWidget);
      // 状态
      expect(find.text('草稿'), findsNWidgets(2));
      // 字数
      expect(find.textContaining('字'), findsWidgets);
      // 批次90：序号色块已移除 → 不再有纯数字 1/2 的节点
      expect(
        find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints?.maxWidth == 36 &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color != null),
        findsNothing,
      );
    });

    testWidgets('#3 空状态 CTA → 直接创建「第一章」，不跳转', (tester) async {
      await pumpDetailWithRouter(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('新建章节'));
      await tester.pumpAndSettle();

      // 批次96-3/96-4：空态「新建章节」无弹窗直接创建，且不跳写作页
      expect(find.text('章节标题'), findsNothing);
      expect(find.text('创建'), findsNothing);
      expect(find.byKey(const Key('writing-marker')), findsNothing);
      // 仍在详情页：空态消失，列表出现「第一章」
      expect(find.text('还没有章节'), findsNothing);
      expect(find.text('第一章'), findsOneWidget);

      final chs = await ChapterRepository(db).listChapters(manuscriptId);
      expect(chs.single.title, '第一章');
      expect(chs.single.volumeId, isNull);
    });

    testWidgets('#5 右上角「+」→ 新建卷弹窗 → 创建成功（唯一真源）', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 批次96-3：右上角「+」= 新建卷唯一入口（列表头不再有「新建卷」按钮）
      expect(find.text('新建卷'), findsNothing);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();

      expect(find.text('新建卷'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('detail-new-volume-field')),
        '第一卷',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      final vols = await VolumeRepository(db).listVolumes(manuscriptId);
      expect(vols.single.title, '第一卷');
    });

    testWidgets('#6 多章节 → 按 sort_order 排序显示', (tester) async {
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: '第一章');
      await repo.createChapter(manuscriptId, title: '第二章');
      await repo.createChapter(manuscriptId, title: '第三章');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('第二章'), findsOneWidget);
      expect(find.text('第三章'), findsOneWidget);

      // sort_order 验证
      final chapters = await repo.listChapters(manuscriptId);
      expect(chapters[0].sortOrder, 0);
      expect(chapters[1].sortOrder, 1);
      expect(chapters[2].sortOrder, 2);
    });

    testWidgets('#7 作品元信息条 → 仅体裁（批次90：章节数移到列表头右侧）', (tester) async {
      final repo = ChapterRepository(db);
      // 两个章节
      await repo.createChapter(manuscriptId, title: 'A', content: '一' * 100);
      await repo.createChapter(manuscriptId, title: 'B', content: '一' * 200);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 标题只在 AppBar（信息卡已移除大标题）
      expect(find.text('测试作品'), findsOneWidget);
      // 批次90 修复2：元信息条只保留体裁单行，章节数移到列表头右侧
      expect(find.text('奇幻'), findsOneWidget);
      // 章节数不再出现在元信息条，改出现在列表头部右侧（「章节列表 2 章」）
      expect(find.text('奇幻 · 2 个章节'), findsNothing);
      // 批次96-3：新建卷入口收敛到右上角「+」，列表头不再有「新建卷」按钮
      expect(find.text('新建卷'), findsNothing);
      // 简介与总字数胶囊不再展示（简化，对齐 RN）
      expect(find.text('这是一个测试作品的简介'), findsNothing);
      expect(find.text('300 字'), findsNothing);
    });

    testWidgets('#9 AppBar 标题回退逻辑：manuscript.title > args.title > "作品详情"', (
      tester,
    ) async {
      // 情况1：有 args.title
      await tester.pumpWidget(buildDetailPage(title: '传进来的标题'));
      await tester.pumpAndSettle();
      // 因为 manuscriptStore 里有 title，应该优先用「测试作品」。
      // 批次 37：标题只在 AppBar 显示一次（信息卡已简化）
      expect(find.text('测试作品'), findsOneWidget);
    });

    testWidgets('#10 点击章节卡片 → 跳转到写作页', (tester) async {
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: '点击测试章');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      // 跳转到作品详情页
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(
        AppRoutes.manuscriptDetail,
        extra: {'manuscriptId': manuscriptId, 'title': '测试作品'},
      );
      await tester.pumpAndSettle();

      // 点击章节卡片 → 跳转到写作页
      await tester.tap(find.text('点击测试章'));
      await tester.pumpAndSettle();

      expect(find.byType(WritingPage), findsOneWidget);
    });

    testWidgets('#11 章节列表「导入」按钮存在（空态 + 有章节）', (tester) async {
      // 空态
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();
      expect(find.text('导入'), findsOneWidget);

      // 有章节
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: '第一章');
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();
      expect(find.text('导入'), findsOneWidget);
    });

    testWidgets('#12 更多菜单 → 菜单项显示（项目设置/删除项目/取消，WIP 已移除）', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      // 批次77：导出/分享 WIP 死菜单项已移除，只保留真实功能
      expect(find.text('导出项目'), findsNothing);
      expect(find.text('分享'), findsNothing);
      expect(find.text('项目设置'), findsOneWidget);
      expect(find.text('删除项目'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);

      // 取消关闭
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('项目设置'), findsNothing);
    });

    testWidgets('#13 更多菜单「项目设置」→ 跳转项目设置页', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(
        AppRoutes.manuscriptDetail,
        extra: {'manuscriptId': manuscriptId, 'title': '测试作品'},
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('项目设置'));
      await tester.pumpAndSettle();

      expect(find.byType(ProjectSettingsPage), findsOneWidget);
      expect(find.text('作品名称'), findsWidgets); // label + hint 各一处
    });

    testWidgets('#14 更多菜单「删除项目」→ 确认 → archived + 回书架', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(
        AppRoutes.manuscriptDetail,
        extra: {'manuscriptId': manuscriptId, 'title': '测试作品'},
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除项目'));
      await tester.pumpAndSettle();

      // 二次确认弹窗（批次59：对齐真实软删语义）
      expect(
        find.text('确定删除《测试作品》吗？删除后将不再显示，章节和诊断记录会保留。'),
        findsOneWidget,
      );
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      final m = await ManuscriptRepository(db).getManuscript(manuscriptId);
      expect(m?.status, 'archived');
      // 回到书架
      expect(find.byType(BookshelfPage), findsOneWidget);
    });

    testWidgets('#15 批次28 三 Tab 切换：章节/文件/相关对话', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 三个 Tab 标签存在
      expect(find.text('章节'), findsOneWidget);
      expect(find.text('文件'), findsOneWidget);
      expect(find.text('相关对话'), findsOneWidget);

      // 默认 Tab0 章节：空态可见
      expect(find.text('还没有章节'), findsOneWidget);

      // Tab1 文件：切到文件区
      await tester.tap(find.text('文件'));
      await tester.pumpAndSettle();
      expect(find.text('添加素材'), findsOneWidget);

      // Tab2 相关对话：切到空态
      await tester.tap(find.text('相关对话'));
      await tester.pumpAndSettle();
      expect(find.text('还没有相关对话'), findsOneWidget);
    });

    testWidgets('#16 批次28 相关对话 Tab：有数据 → 列表渲染', (tester) async {
      // 预置章节 + 章节级会话（getOrCreateSessionForChapter 建引用）
      final chRepo = ChapterRepository(db);
      final chId = await chRepo.createChapter(manuscriptId, title: '第一章');
      final sesRepo = SessionRepository(db);
      final sessionId = await sesRepo.getOrCreateSessionForChapter(
        manuscriptId,
        chId,
      );
      await sesRepo.addMessage(sessionId, 'user', '诊断第一章的内容');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('相关对话'));
      await tester.pumpAndSettle();

      // 会话卡片渲染（标题 + 阶段标签 + 预览 + 相对时间）
      expect(find.text('还没有相关对话'), findsNothing);
      // 批次61：章节会话用章节标题命名（诊断·第一章）
      expect(find.text('诊断·第一章'), findsOneWidget);
      expect(find.text('诊断第一章的内容'), findsOneWidget);
    });

    testWidgets('#17 批次30 相关对话点击 → 跳转对话页并切换会话', (tester) async {
      // 1. 预置章节 + 章节级会话（目标会话）
      final chRepo = ChapterRepository(db);
      final chId = await chRepo.createChapter(manuscriptId, title: '第一章');
      final sesRepo = SessionRepository(db);
      final relatedId = await sesRepo.getOrCreateSessionForChapter(
        manuscriptId,
        chId,
      );
      await sesRepo.addMessage(relatedId, 'user', '诊断第一章的内容');
      // 2. related 会话 updatedAt 调旧，保证 bootstrap 默认会话是后面新建的空白会话
      await (db.update(
        db.sessions,
      )..where((t) => t.id.equals(relatedId))).write(
        SessionsCompanion(
          updatedAt: Value(
            DateTime.now().millisecondsSinceEpoch ~/ 1000 - 1000,
          ),
        ),
      );
      await sesRepo.createBlankSession();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      // 跳转到作品详情页
      final ctx = tester.element(find.byType(Navigator).first);
      GoRouter.of(ctx).go(
        AppRoutes.manuscriptDetail,
        extra: {'manuscriptId': manuscriptId, 'title': '测试作品'},
      );
      await tester.pumpAndSettle();

      // 切到「相关对话」Tab，点击会话卡片
      await tester.tap(find.text('相关对话'));
      await tester.pumpAndSettle();
      // 批次61：章节会话用章节标题命名（诊断·第一章）
      expect(find.text('诊断·第一章'), findsOneWidget);

      await tester.tap(find.text('诊断·第一章'));
      await tester.pumpAndSettle();

      // 已进入对话页，且会话切换到目标会话
      expect(find.byType(ChatPage), findsOneWidget);
      final bootstrap = container.read(sessionBootstrapProvider).valueOrNull;
      expect(bootstrap?.sessionId, relatedId);
    });

    testWidgets('#18 批次34 长按章节 → 操作菜单 → 二次确认删除', (tester) async {
      final repo = ChapterRepository(db);
      final cid = await repo.createChapter(manuscriptId, title: '长按删除章');
      final keepId = await repo.createChapter(manuscriptId, title: '保留章');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 长按章节卡片 → 操作菜单出现
      await tester.longPress(find.text('长按删除章'));
      await tester.pumpAndSettle();
      expect(find.text('删除《长按删除章》'), findsOneWidget);

      // 取消 → 不删除
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('长按删除章'), findsOneWidget);

      // 再次长按 → 确认删除
      await tester.longPress(find.text('长按删除章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除《长按删除章》'));
      await tester.pumpAndSettle();
      expect(find.text('删除章节'), findsOneWidget);
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      // 列表移除 + 保留章仍在（批次94-2：改为软删，提示「已移入回收站」）
      expect(find.text('长按删除章'), findsNothing);
      expect(find.text('保留章'), findsOneWidget);
      expect(find.text('已移入回收站'), findsOneWidget);

      // DB 验证：章节软删进回收站（listChapters 不含，listArchivedChapters 含）
      final chapters = await repo.listChapters(manuscriptId);
      expect(chapters.map((c) => c.id).toList(), [keepId]);
      final archived = await repo.listArchivedChapters(manuscriptId);
      expect(archived.map((c) => c.id).toList(), [cid]);
    });

    testWidgets('#18b 批次79 章节卡行尾删除图标 → 操作菜单 → 确认删除', (tester) async {
      final repo = ChapterRepository(db);
      final delId = await repo.createChapter(manuscriptId, title: '图标删除章');
      await repo.createChapter(manuscriptId, title: '保留章2');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 行尾可见删除入口（对齐 file_section 批次75，修复前仅长按可删）
      expect(find.byIcon(Icons.delete_outline), findsWidgets);

      // 点第一个章节卡的删除图标 → 操作菜单（复用长按删除流程）
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();
      expect(find.text('删除《图标删除章》'), findsOneWidget);

      // 确认删除 → 物理删行 + 保留章仍在
      await tester.tap(find.text('删除《图标删除章》'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(find.text('图标删除章'), findsNothing);
      expect(find.text('保留章2'), findsOneWidget);
      final chapters = await repo.listChapters(manuscriptId);
      expect(chapters.map((c) => c.id).contains(delId), isFalse);
    });
  });

  group('视觉规范（月色竹青 + 百灵极简）', () {
    testWidgets('#V1 AppBar 浅色 #F7F8F6 + 48dp + 深字 #2D3142', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFFF7F8F6));
      expect(appBar.toolbarHeight, 48);
      expect(appBar.foregroundColor, const Color(0xFF2D3142));
    });

    testWidgets('#V2 Scaffold 背景为冷青灰白 #F7F8F6', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFFF7F8F6));
    });

    testWidgets('#V3 批次90 元信息条：仅体裁单行（章节数改到列表头右侧）', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 元信息条只显示体裁（空章节时也一致）
      expect(find.text('奇幻'), findsOneWidget);
      // 旧的「体裁 · 0 个章节」不再存在
      expect(find.text('奇幻 · 0 个章节'), findsNothing);
      // 旧信息卡已移除：不再有 4dp 竹青色条
      final colorBar = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 4 &&
            w.color == const Color(0xFF2D5A52),
      );
      expect(colorBar, findsNothing);
      // 不再展示简介
      expect(find.text('这是一个测试作品的简介'), findsNothing);
    });

    testWidgets('#V4 批次90 元信息条无信息胶囊（章节数改列表头右侧）', (tester) async {
      // 创建章节 → 若存在胶囊会渲染
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: 'A', content: '一' * 100);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 信息胶囊（padding 10,4,10,4 + 浅竹青底）应不存在
      final chips = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == const Color(0xFFE8F0EE) &&
            w.padding ==
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      );
      expect(chips, findsNothing);
      // 元信息条仅体裁；章节数移到列表头右侧（「章节列表 1 章」）
      expect(find.text('奇幻'), findsOneWidget);
      expect(find.text('奇幻 · 1 个章节'), findsNothing);
    });

    testWidgets('#V5 章节卡片无阴影（百灵扁平风）', (tester) async {
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: '阴影测试章');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 找到所有带 boxShadow 的 Container，章节卡片（白底）不应有
      final withShadow = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            ((w.decoration as BoxDecoration).boxShadow?.isNotEmpty ?? false),
      );
      expect(withShadow, findsNothing);
    });

    testWidgets('#V6 批次90：序号色块已移除（纯文字列表）', (tester) async {
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: '章一');
      await repo.createChapter(manuscriptId, title: '章二');
      await repo.createChapter(manuscriptId, title: '章三');
      await repo.createChapter(manuscriptId, title: '章四');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 章节标题仍在
      expect(find.text('章一'), findsOneWidget);
      expect(find.text('章四'), findsOneWidget);
      // 批次90 修复1：序号色块（36x36 圆角色块）已移除
      final indexBlocks = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 36 &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color != null,
      );
      expect(indexBlocks, findsNothing, reason: '批次90：序号色块已移除，改为纯文字列表');
    });

    testWidgets('#V7 状态标签矿物色：草稿 = #E0E4E0 底 + #5B7565 字', (tester) async {
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: '草稿章');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 找到 "草稿" 标签所在的 Container
      final draftLabel = find.ancestor(
        of: find.text('草稿'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFE0E4E0),
        ),
      );
      expect(draftLabel, findsOneWidget);
    });

    testWidgets('#V8 状态标签矿物色：完成 = #E8F0EE 底 + #2D5A52 字', (tester) async {
      final repo = ChapterRepository(db);
      final cid = await repo.createChapter(manuscriptId, title: '完成章');
      // 直接 DB 把状态改为 complete（绕过 store，避免扩大 repo API）
      await (db.update(db.chapters)..where((c) => c.id.equals(cid))).write(
        ChaptersCompanion(status: const Value('complete')),
      );
      // 刷新 store
      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .loadChapters();

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      final completeLabel = find.ancestor(
        of: find.text('完成'),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Container &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == const Color(0xFFE8F0EE),
        ),
      );
      expect(completeLabel, findsOneWidget);
    });
  });

  group('ChapterListStore', () {
    test('#1 初始状态：chapters 空 / isLoading=false / error null', () {
      final state = container.read(chapterStoreProvider(manuscriptId));
      expect(state.chapters, isEmpty);
      expect(state.isLoading, false);
      expect(state.error, isNull);
    });

    test('#2 loadChapters：从 DB 加载列表', () async {
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: 'Store 测试章');

      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .loadChapters();

      final state = container.read(chapterStoreProvider(manuscriptId));
      expect(state.chapters.length, 1);
      expect(state.chapters.first.title, 'Store 测试章');
      expect(state.isLoading, false);
    });

    test('#3 createChapter：DB 写入 + 列表追加', () async {
      final id = await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .createChapter(title: '乐观创建章', content: 'abc123');

      expect(id, isNotNull);
      expect(id, isNotEmpty);

      final state = container.read(chapterStoreProvider(manuscriptId));
      expect(state.chapters.length, 1);
      expect(state.chapters.first.title, '乐观创建章');
      expect(state.chapters.first.wordCount, 6);

      final repo = ChapterRepository(db);
      final chapters = await repo.listChapters(manuscriptId);
      expect(chapters.length, 1);
    });

    test('#4 updateChapterTitle：标题更新正确', () async {
      final repo = ChapterRepository(db);
      final cid = await repo.createChapter(manuscriptId, title: '旧标题');
      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .loadChapters();

      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .updateChapterTitle(cid, '新标题');

      final state = container.read(chapterStoreProvider(manuscriptId));
      expect(state.chapters.first.title, '新标题');

      final fromDb = await repo.getChapter(cid);
      expect(fromDb?.title, '新标题');
    });

    test('#5 saveChapterContent：内容和 wordCount 更新', () async {
      final repo = ChapterRepository(db);
      final cid = await repo.createChapter(
        manuscriptId,
        title: 'C',
        content: '旧',
      );
      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .loadChapters();

      const newContent = '新内容共十个字';
      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .saveChapterContent(cid, newContent);

      final state = container.read(chapterStoreProvider(manuscriptId));
      expect(state.chapters.first.content, newContent);
      expect(state.chapters.first.wordCount, newContent.length);
    });

    test('#6 adoptContentToChapter：previousContent 正确备份', () async {
      final repo = ChapterRepository(db);
      final cid = await repo.createChapter(
        manuscriptId,
        title: 'C',
        content: '旧内容',
      );
      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .loadChapters();

      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .adoptContentToChapter(cid, '新内容');

      final state = container.read(chapterStoreProvider(manuscriptId));
      expect(state.chapters.first.content, '新内容');
      expect(state.chapters.first.previousContent, '旧内容');

      final fromDb = await repo.getChapter(cid);
      expect(fromDb?.previousContent, '旧内容');
    });

    test('#7 updateChapterDiagnosedAt：lastDiagnosedAt 非空', () async {
      final repo = ChapterRepository(db);
      final cid = await repo.createChapter(manuscriptId, title: 'C');
      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .loadChapters();

      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .updateChapterDiagnosedAt(cid);

      final state = container.read(chapterStoreProvider(manuscriptId));
      expect(state.chapters.first.lastDiagnosedAt, isNotNull);
    });

    test('#8 clearError：清除错误状态', () {
      final notifier = container.read(
        chapterStoreProvider(manuscriptId).notifier,
      );
      notifier.clearError();
      expect(container.read(chapterStoreProvider(manuscriptId)).error, isNull);
    });
  });

  group('批次92：详情页卷分组闭环', () {
    testWidgets('#92-1 有卷 → 卷分组渲染（卷头 + 卷内章 + 未分卷组 + 卷总字数）', (
      tester,
    ) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '卷一之章', content: '字' * 50, volumeId: vid);
      await ChapterRepository(db).createChapter(manuscriptId, title: '散章');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 批次96-4：散落章节直接平铺（无「未分卷」组头），卷组按全局序穿插
      expect(find.text('第一卷'), findsOneWidget);
      expect(find.text('卷一之章'), findsOneWidget);
      expect(find.text('未分卷'), findsNothing);
      expect(find.text('散章'), findsOneWidget);
      // 卷头聚合信息：仅第一卷卷头计章节数（散落章平铺无卷头）
      expect(find.text('1 章'), findsOneWidget);
      // 50字 = 卷头总字数（size 11）+ 章节卡字数（size 12）两处
      expect(find.text('50字'), findsNWidgets(2));
      // 卷头吸顶（批次92-5：SliverPersistentHeader pinned）
      final headers = tester
          .widgetList<SliverPersistentHeader>(find.byType(SliverPersistentHeader))
          .toList();
      expect(headers, isNotEmpty);
      expect(headers.first.pinned, isTrue);
    });

    testWidgets('#92-4 卷头整行可点击折叠：点击卷头 → 卷内章节隐藏/展开', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '卷内之章', volumeId: vid);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();
      expect(find.text('卷内之章'), findsOneWidget);

      // 点击卷头（整行可点，非小箭头）→ 折叠
      await tester.tap(find.text('第一卷'));
      await tester.pumpAndSettle();
      expect(find.text('卷内之章'), findsNothing);

      // 再点 → 展开
      await tester.tap(find.text('第一卷'));
      await tester.pumpAndSettle();
      expect(find.text('卷内之章'), findsOneWidget);
    });

    testWidgets('#92-2 长按卷头 → 重命名卷 → 落库 + 卷头更新', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '旧卷名');
      // 卷头仅在章节列表渲染（空章节走空态）→ 预置卷内章节
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '卷内章', volumeId: vid);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('旧卷名'));
      await tester.pumpAndSettle();
      expect(find.text('重命名卷'), findsOneWidget);
      await tester.tap(find.text('重命名卷'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('detail-rename-volume-field')),
        '新卷名',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('新卷名'), findsOneWidget);
      expect(find.text('旧卷名'), findsNothing);
      final vols = await vRepo.listVolumes(manuscriptId);
      expect(vols.single.title, '新卷名');
    });

    testWidgets('#92-2 卷头铅笔图标 → 直接弹重命名', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '铅笔卷');
      // 卷头仅在章节列表渲染 → 预置卷内章节
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '卷内章', volumeId: vid);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 卷头行尾铅笔图标（edit_outlined 也用于章节卡重命名 → 限定在卷头行）
      await tester.tap(find.byIcon(Icons.edit_outlined).first);
      await tester.pumpAndSettle();

      expect(find.text('重命名卷'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('detail-rename-volume-field')),
        '铅笔改名卷',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final vols = await vRepo.listVolumes(manuscriptId);
      expect(vols.single.title, '铅笔改名卷');
    });

    testWidgets('#92-2 长按卷头 → 删除卷 → 卷内章节一并删除（进回收站）', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '待删卷');
      final cid = await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '卷内章', volumeId: vid);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('待删卷'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除卷'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      expect(find.text('待删卷'), findsNothing);
      // 批次96-4：卷内章节不再散落，一并删除（列表消失 + 状态 archived）
      expect(find.text('卷内章'), findsNothing);
      final ch = await ChapterRepository(db).getChapter(cid);
      expect(ch, isNotNull);
      expect(ch!.status, 'archived', reason: '删卷后卷内章节软删进回收站');
    });
  });

  group('批次94-1：导出（TXT/Markdown）', () {
    testWidgets('#94-1 更多菜单出现「导出整书」项', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('导出整书'), findsOneWidget);
      expect(find.text('项目设置'), findsOneWidget);
      expect(find.text('删除项目'), findsOneWidget);
    });

    testWidgets('#94-1 点「导出整书」→ 弹出「导出为」格式选择（TXT/Markdown）', (
      tester,
    ) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('导出整书'));
      await tester.pumpAndSettle();

      expect(find.text('导出为'), findsOneWidget);
      expect(find.text('TXT 纯文本'), findsOneWidget);
      expect(find.text('Markdown'), findsOneWidget);
    });

    testWidgets('#94-1 长按章节 → 操作菜单出现「导出本章」', (tester) async {
      await ChapterRepository(db).createChapter(
        manuscriptId,
        title: '第一章：启程',
        content: '正文',
      );
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('第一章：启程'));
      await tester.pumpAndSettle();

      expect(find.textContaining('导出《第一章：启程》'), findsOneWidget);
    });

    testWidgets('#94-1 长按卷头 → 操作菜单出现「导出本卷」', (tester) async {
      final volRepo = VolumeRepository(db);
      final v1 = await volRepo.createVolume(manuscriptId, title: '第一卷');
      await ChapterRepository(db).createChapter(
        manuscriptId,
        title: '第一章',
        content: '正文',
        volumeId: v1,
      );
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('第一卷'));
      await tester.pumpAndSettle();

      expect(find.text('导出本卷'), findsOneWidget);
    });
  });

  group('批次94-2：章节回收站', () {
    testWidgets('#94-2 更多菜单出现「回收站」入口', (tester) async {
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('回收站'), findsOneWidget);
    });

    testWidgets('#94-2 软删章节 → 列表消失 + 进回收站（DB status=archived）', (
      tester,
    ) async {
      final repo = ChapterRepository(db);
      await repo.createChapter(manuscriptId, title: '软删章');
      await repo.createChapter(manuscriptId, title: '保留章');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('软删章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除《软删章》'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(find.text('软删章'), findsNothing);
      expect(find.text('保留章'), findsOneWidget);

      final archived = await repo.listArchivedChapters(manuscriptId);
      expect(archived.map((c) => c.title).toList(), contains('软删章'));
      expect(archived.single.status, 'archived');
    });

    testWidgets('#94-2 回收站页：恢复章节 → 回列表', (tester) async {
      final repo = ChapterRepository(db);
      // 预置一条 archived 章节（单条避免同秒排序不稳定）
      final chId = await repo.createChapter(manuscriptId, title: '回收章2');
      await repo.softDeleteChapter(chId);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ChapterRecycleBinPage(
              manuscriptId: manuscriptId,
              manuscriptTitle: '测试作品',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('回收章2'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.restore).first);
      await tester.pumpAndSettle();

      expect(find.text('回收章2'), findsNothing);
      final restored = await repo.getChapter(chId);
      expect(restored!.status, 'draft');
      // 恢复后章节出现在正常列表
      final active = await repo.listChapters(manuscriptId);
      expect(active.map((c) => c.id), contains(chId));
    });

    testWidgets('#94-2 回收站页：永久删除 → DB 物理消失', (tester) async {
      final repo = ChapterRepository(db);
      final chId = await repo.createChapter(manuscriptId, title: '永久删章');
      await repo.softDeleteChapter(chId);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ChapterRecycleBinPage(
              manuscriptId: manuscriptId,
              manuscriptTitle: '测试作品',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_forever_outlined).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('永久删除').last);
      await tester.pumpAndSettle();

      expect(find.text('永久删章'), findsNothing);
      expect(await repo.getChapter(chId), isNull);
    });

    testWidgets('#94-2 回收站空态文案', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ChapterRecycleBinPage(
              manuscriptId: manuscriptId,
              manuscriptTitle: '测试作品',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('回收站是空的'), findsOneWidget);
    });

    // 批次94-2 模拟器走查回归：恢复后详情页列表未刷新（真源 chapterStoreProvider
    // 是 StateNotifier，仅 invalidate FutureProvider 版 chapterListProvider 不够）
    testWidgets('#94-2 回收站恢复 → chapterStoreProvider 同步刷新', (tester) async {
      final repo = ChapterRepository(db);
      final chId = await repo.createChapter(manuscriptId, title: '同步刷新章');
      await repo.softDeleteChapter(chId);

      // 先让详情页真源加载（此时列表不含被删章）
      await container
          .read(chapterStoreProvider(manuscriptId).notifier)
          .loadChapters();
      expect(
        container
            .read(chapterStoreProvider(manuscriptId))
            .chapters
            .map((c) => c.id),
        isNot(contains(chId)),
      );

      // 打开回收站页 → 恢复（真实路径：恢复 + 双通道刷新）
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: ChapterRecycleBinPage(
              manuscriptId: manuscriptId,
              manuscriptTitle: '测试作品',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.restore).first);
      await tester.pumpAndSettle();

      // 详情页真源已刷新：章节回到列表
      final chapters = container
          .read(chapterStoreProvider(manuscriptId))
          .chapters;
      expect(chapters.map((c) => c.id), contains(chId));
    });
  });

  group('批次96-1：章节归属与顺序调整', () {
    testWidgets('#96-1 长按章节 → 菜单含 上移/下移/移动到卷', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '排序章', volumeId: vid);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('排序章'));
      await tester.pumpAndSettle();

      expect(find.text('上移'), findsOneWidget);
      expect(find.text('下移'), findsOneWidget);
      expect(find.text('移动到卷'), findsOneWidget);
    });

    testWidgets('#96-1 卷内下移：两章 swap sort_order → 列表顺序翻转 + 落库', (tester) async {
      final vRepo = VolumeRepository(db);
      final cRepo = ChapterRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      final aId = await cRepo.createChapter(
        manuscriptId,
        title: '第一章',
        volumeId: vid,
        sortOrder: 1,
      );
      final bId = await cRepo.createChapter(
        manuscriptId,
        title: '第二章',
        volumeId: vid,
        sortOrder: 2,
      );

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 初始顺序：第一章 在 第二章 上方
      final before = tester.getTopLeft(find.text('第一章')).dy;
      final before2 = tester.getTopLeft(find.text('第二章')).dy;
      expect(before, lessThan(before2));

      // 长按第二章 → 下移（已在最末 → 提示）
      await tester.longPress(find.text('第二章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下移'));
      await tester.pumpAndSettle();
      expect(find.text('已在最后'), findsOneWidget);

      // 长按第一章 → 下移 → 顺序翻转
      await tester.longPress(find.text('第一章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下移'));
      await tester.pumpAndSettle();

      final after = tester.getTopLeft(find.text('第一章')).dy;
      final after2 = tester.getTopLeft(find.text('第二章')).dy;
      expect(after, greaterThan(after2));

      // 落库：sort_order 已交换
      final chs = await cRepo.listChapters(manuscriptId);
      int orderOf(String id) => chs.firstWhere((c) => c.id == id).sortOrder;
      expect(orderOf(aId), 2);
      expect(orderOf(bId), 1);
    });

    testWidgets('#96-1 上移：最前章上移 → 提示已在最前', (tester) async {
      final vRepo = VolumeRepository(db);
      final cRepo = ChapterRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      await cRepo.createChapter(
        manuscriptId,
        title: '首章',
        volumeId: vid,
        sortOrder: 1,
      );
      await cRepo.createChapter(
        manuscriptId,
        title: '次章',
        volumeId: vid,
        sortOrder: 2,
      );

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('首章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('上移'));
      await tester.pumpAndSettle();

      expect(find.text('已在最前'), findsOneWidget);
      // 顺序未变
      final top1 = tester.getTopLeft(find.text('首章')).dy;
      final top2 = tester.getTopLeft(find.text('次章')).dy;
      expect(top1, lessThan(top2));
    });

    testWidgets('#96-1 移动到卷：长按 → 移动到卷 → 选目标卷 → 归属变更 + 落库', (tester) async {
      final vRepo = VolumeRepository(db);
      final cRepo = ChapterRepository(db);
      final vid1 = await vRepo.createVolume(manuscriptId, title: '第一卷');
      final vid2 = await vRepo.createVolume(manuscriptId, title: '第二卷');
      final chId = await cRepo.createChapter(
        manuscriptId,
        title: '游走章',
        volumeId: vid1,
        sortOrder: 1,
      );

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('游走章'));
      await tester.pumpAndSettle();
      expect(find.text('移动到卷'), findsOneWidget);
      await tester.tap(find.text('移动到卷'));
      await tester.pumpAndSettle();

      // 弹层展示两个卷 + 未分卷（卷头也有同名文本 → 用 .last 定位弹层项）
      expect(find.text('第一卷'), findsWidgets);
      expect(find.text('第二卷'), findsWidgets);
      expect(find.text('未分卷'), findsOneWidget);

      await tester.tap(find.text('第二卷').last);
      await tester.pumpAndSettle();

      // 归属已变 + 落库
      final ch = await cRepo.getChapter(chId);
      expect(ch!.volumeId, vid2);
      final chapters = container
          .read(chapterStoreProvider(manuscriptId))
          .chapters;
      expect(chapters.firstWhere((c) => c.id == chId).volumeId, vid2);
    });

    testWidgets('#96-1 移动到未分卷：从卷内移到未分卷组', (tester) async {
      final vRepo = VolumeRepository(db);
      final cRepo = ChapterRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      final chId = await cRepo.createChapter(
        manuscriptId,
        title: '出卷章',
        volumeId: vid,
        sortOrder: 1,
      );

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('出卷章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动到卷'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('未分卷'));
      await tester.pumpAndSettle();

      final ch = await cRepo.getChapter(chId);
      expect(ch!.volumeId, isNull);
    });

    testWidgets('#96-1 移到目标卷后落末位：sort_order 大于目标卷已有章节', (tester) async {
      final vRepo = VolumeRepository(db);
      final cRepo = ChapterRepository(db);
      final vid1 = await vRepo.createVolume(manuscriptId, title: '第一卷');
      final vid2 = await vRepo.createVolume(manuscriptId, title: '第二卷');
      final existing = await cRepo.createChapter(
        manuscriptId,
        title: '卷二已有章',
        volumeId: vid2,
        sortOrder: 10,
      );
      final moving = await cRepo.createChapter(
        manuscriptId,
        title: '迁入章',
        volumeId: vid1,
        sortOrder: 1,
      );

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('迁入章'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移动到卷'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第二卷').last);
      await tester.pumpAndSettle();

      final chs = await cRepo.listChapters(manuscriptId);
      final existingOrder =
          chs.firstWhere((c) => c.id == existing).sortOrder;
      final movingOrder = chs.firstWhere((c) => c.id == moving).sortOrder;
      expect(movingOrder, greaterThan(existingOrder));
    });
  });

  group('批次96-2：列表级新建章节入口 + 卷折叠持久化', () {
    testWidgets('#96-2 无卷有章节 → 列表末尾显示「新建章节」行', (tester) async {
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '第一章');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      expect(find.text('第一章'), findsOneWidget);
      // 列表末尾「新建章节」行（无卷 → 未分卷）
      expect(find.byKey(const ValueKey('new-chapter-row-unassigned')), findsOneWidget);
      expect(find.text('新建章节'), findsOneWidget);
    });

    testWidgets('#96-2 有卷 → 每个分组末尾各一个「新建章节」行（卷内 + 未分卷）', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '卷内章', volumeId: vid);
      await ChapterRepository(db).createChapter(manuscriptId, title: '散章');

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();

      // 卷内入口 + 未分卷组入口 = 2 个「新建章节」行
      expect(find.byKey(ValueKey('new-chapter-row-$vid')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('new-chapter-row-unassigned')),
        findsOneWidget,
      );
      expect(find.text('新建章节'), findsNWidgets(2));
    });

    testWidgets('#96-2 卷内「新建章节」→ 自动命名 + 归属该卷 + 不跳转', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '第一章', volumeId: vid);

      await pumpDetailWithRouter(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(ValueKey('new-chapter-row-$vid')));
      await tester.pumpAndSettle();

      // 批次96-4：只创建不跳转——仍在详情页，列表出现「第二章」
      expect(find.byKey(const Key('writing-marker')), findsNothing);
      expect(find.text('第二章'), findsOneWidget);
      final chs = await ChapterRepository(db).listChapters(manuscriptId);
      expect(chs.length, 2);
      expect(chs.last.title, '第二章');
      expect(chs.last.volumeId, vid);
    });

    testWidgets('#96-2 列表末尾「新建章节」→ 归属未分卷（不跳转）', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '第一章', volumeId: vid);
      await ChapterRepository(db).createChapter(manuscriptId, title: '散章');

      await pumpDetailWithRouter(tester);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('new-chapter-row-unassigned')),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('writing-marker')), findsNothing);
      final chs = await ChapterRepository(db).listChapters(manuscriptId);
      expect(chs.last.volumeId, isNull, reason: '列表末尾入口新建 → 散落');
    });

    testWidgets('#96-2 折叠状态持久化：折叠卷 → app_state 落库 → 重建页面恢复', (tester) async {
      final vRepo = VolumeRepository(db);
      final vid = await vRepo.createVolume(manuscriptId, title: '第一卷');
      await ChapterRepository(
        db,
      ).createChapter(manuscriptId, title: '卷内章', volumeId: vid);

      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();
      expect(find.text('卷内章'), findsOneWidget);

      // 点击卷头折叠
      await tester.tap(find.text('第一卷'));
      await tester.pumpAndSettle();
      expect(find.text('卷内章'), findsNothing);

      // app_state 已落库
      final saved = await AppStateRepository(
        db,
      ).getCollapsedVolumes(manuscriptId);
      expect(saved, contains(vid));

      // 重建页面 → 折叠状态恢复
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(buildDetailPage());
      await tester.pumpAndSettle();
      expect(find.text('卷内章'), findsNothing);
      expect(find.text('第一卷'), findsOneWidget);

      // 展开 → 清空持久化
      await tester.tap(find.text('第一卷'));
      await tester.pumpAndSettle();
      expect(find.text('卷内章'), findsOneWidget);
      final afterExpand = await AppStateRepository(
        db,
      ).getCollapsedVolumes(manuscriptId);
      expect(afterExpand, isNot(contains(vid)));
    });
  });
}
