// ─────────────────────────────────────────────────────────────
// bookshelf_page_test — 书架页 Widget 测试
//
// 覆盖路径：
//   #1 空 DB → 显示空状态 + CTA 按钮
//   #2 创建作品 → 列表显示新卡片
//   #3 点击卡片 → 触发导航（push /manuscript-detail）
//   #4 加载中 → 显示 CircularProgressIndicator
//   #5 创建弹窗：标题为空 → 提示
//   #6 创建弹窗：标题有效 → 创建成功 + 列表更新
//   #7 多作品列表 → 按更新时间排序显示
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/manuscript_providers.dart';
import 'package:writingcoach/providers/work_import_providers.dart';
import 'package:writingcoach/router/app_router.dart';
import 'package:writingcoach/services/file_parser.dart';
import 'package:writingcoach/services/work_import_service.dart';
import 'package:writingcoach/widgets/book_import_sheet.dart';
import 'package:writingcoach/widgets/bookshelf_page.dart';
import 'package:writingcoach/widgets/manuscript_detail_page.dart';
import 'package:writingcoach/widgets/writing_page.dart';

/// 批次 35：fake 导入服务——绕过 file_picker（widget 测试不可用），
/// 覆写 importBookFromFile 直接走真实 importWork 入库链路。
class _FakeImportService extends WorkImportService {
  _FakeImportService(
    super.db,
    super.manuscriptRepo,
    super.chapterRepo,
    super.referenceRepo,
  );

  @override
  Future<WorkImportResult?> importBookFromFile() async {
    return importWork(
      sessionId: null,
      parsed: ParsedFile(
        title: '导入的小说',
        genre: '未知',
        chapters: const [
          ParsedChapter(title: '第一章', content: '内容一'),
          ParsedChapter(title: '第二章', content: '内容二'),
        ],
      ),
    );
  }
}

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        // 批次 35：fake 导入服务（file_picker 在 widget 测试不可用）
        workImportServiceProvider.overrideWithValue(
          _FakeImportService(
            db,
            ManuscriptRepository(db),
            ChapterRepository(db),
            ReferenceRepository(db),
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildBookshelfPage() {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: BookshelfPage()),
    );
  }

  group('BookshelfPage', () {
    testWidgets('#1 空 DB → 显示空状态 + CTA', (tester) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      expect(find.text('还没有作品'), findsOneWidget);
      expect(find.text('新建作品'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
    testWidgets('#2 创建作品 → 列表显示新卡片', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '测试作品', genre: '奇幻');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      expect(find.text('测试作品'), findsOneWidget);
      expect(find.text('奇幻'), findsOneWidget);
      expect(find.text('未分类'), findsNothing);
    });

    testWidgets('#3 点击空状态 CTA → 弹出创建弹窗', (tester) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('新建作品'));
      await tester.pumpAndSettle();

      expect(find.text('标题'), findsOneWidget);
      expect(find.text('简介（可选）'), findsOneWidget);
      expect(find.text('类型（可选）'), findsOneWidget);
      expect(find.text('创建'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets('#3b P0-2 弹窗打开后点击遮罩外部 → 弹窗关闭(barrier dismissible)', (
      tester,
    ) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // Step A: 通过 AppBar 右上角 + 按钮打开弹窗（避免与空状态 CTA 重名歧义）
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      // 通过弹窗内部独特标识"简介（可选）"确认弹窗存在
      expect(find.text('简介（可选）'), findsOneWidget, reason: '弹窗应已弹出');
      expect(find.text('取消'), findsOneWidget);

      // Step B: 点弹窗上方遮罩区域（AppBar 正上方 top=10，水平居中，确定在弹窗外部）
      await tester.tapAt(const Offset(200, 10));
      await tester.pumpAndSettle();

      // Step C: 断言弹窗已关闭（"简介（可选）"Label + "取消"按钮都消失）
      expect(
        find.text('简介（可选）'),
        findsNothing,
        reason: 'P0-2: 点遮罩外部未关闭弹窗（遮罩缺失或 dismissible=false）',
      );
      expect(find.text('取消'), findsNothing);
    });

    testWidgets('#4 创建弹窗：标题为空 → SnackBar 提示', (tester) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 打开弹窗
      await tester.tap(find.text('新建作品'));
      await tester.pumpAndSettle();

      // 直接点创建
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      // 应显示 SnackBar 提示
      expect(find.text('请输入作品标题'), findsOneWidget);
    });

    testWidgets('#5 创建弹窗：标题有效 → 创建成功 + 跳详情页（批次93-4）', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();
      appRouter.go(AppRoutes.bookshelf);
      await tester.pumpAndSettle();

      // 打开弹窗
      await tester.tap(find.text('新建作品'));
      await tester.pumpAndSettle();

      // 输入标题
      await tester.enterText(find.byType(TextField).first, '我的新作品');
      await tester.pumpAndSettle();

      // 点击创建
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      // 批次93-4：创建成功后立即跳作品详情页（阅文「去写作」模型）
      expect(find.byType(ManuscriptDetailPage), findsOneWidget);
      expect(find.text('我的新作品'), findsOneWidget);

      // DB 验证
      final repo = ManuscriptRepository(db);
      final manuscripts = await repo.listManuscripts();
      expect(manuscripts.length, 1);
      expect(manuscripts.first.title, '我的新作品');
    });

    testWidgets('#6 多作品列表 → 全部显示（批次93-1 无体裁不显示「未分类」）', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '第一部', genre: '奇幻');
      await repo.createManuscript(title: '第二部', genre: '都市');
      await repo.createManuscript(title: '第三部');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      expect(find.text('第一部'), findsOneWidget);
      expect(find.text('第二部'), findsOneWidget);
      expect(find.text('第三部'), findsOneWidget);
      // 批次93-1：卡片信息行改为 章节数 · 总字数（无体裁不显示「未分类」标签）
      expect(find.text('未分类'), findsNothing);
      expect(find.text('0 章 · 0字'), findsNWidgets(3));
    });

    testWidgets('#7 软删除作品 → 列表移除', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '保留的作品');
      final id2 = await repo.createManuscript(title: '要删除的作品');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 验证两个作品都存在
      expect(find.text('保留的作品'), findsOneWidget);
      expect(find.text('要删除的作品'), findsOneWidget);

      // 执行软删除
      await repo.deleteManuscript(id2);

      // 通过 container 刷新 notifier
      await container.read(manuscriptStoreProvider.notifier).loadManuscripts();
      await tester.pumpAndSettle();

      // 被删除的作品不应出现
      expect(find.text('要删除的作品'), findsNothing);
      expect(find.text('保留的作品'), findsOneWidget);
    });

    testWidgets('#8 批次38 有会话 → 书架不再显示学习进度卡（已移至设置页）', (tester) async {
      await SessionRepository(db).createBlankSession();

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 批次 38：学习进度从书架移除（书架保持纯洁），进度改在设置页展示
      expect(find.text('学习进度'), findsNothing);
      expect(find.text('0%'), findsNothing);
      expect(find.text('完成度'), findsNothing);
    });

    testWidgets('#9 批次38 有会话有数据 → 书架仍无进度卡（设置页才有）', (tester) async {
      final sessionId = await SessionRepository(db).createBlankSession();
      // 教学状态 → P2
      await (db.update(
        db.teachingState,
      )..where((t) => t.sessionId.equals(sessionId))).write(
        TeachingStateCompanion(currentPhase: const Value('P2_PRACTICE_LOOP')),
      );
      // 问题：1 active + 1 resolved → 完成度 50%
      await db
          .into(db.activeProblems)
          .insert(
            ActiveProblemsCompanion.insert(
              id: 'ap-a',
              sessionId: sessionId,
              syndromeId: 's1',
              syndromeName: const Value('情绪标签化'),
              severity: const Value('L3'),
              status: const Value('active'),
            ),
          );
      await db
          .into(db.activeProblems)
          .insert(
            ActiveProblemsCompanion.insert(
              id: 'ap-b',
              sessionId: sessionId,
              syndromeId: 's2',
              syndromeName: const Value('情节断裂'),
              severity: const Value('L2'),
              status: const Value('resolved'),
            ),
          );

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 书架纯洁：无进度卡 / 阶段徽章 / 完成度
      expect(find.text('学习进度'), findsNothing);
      expect(find.text('训练循环'), findsNothing);
      expect(find.text('50%'), findsNothing);
      expect(find.text('总问题'), findsNothing);
    });

    testWidgets('#10 批次38 书架不再直接跳转学习进度详情页（入口移至设置/成长页）', (tester) async {
      final sessionId = await SessionRepository(db).createBlankSession();
      await (db.update(
        db.teachingState,
      )..where((t) => t.sessionId.equals(sessionId))).write(
        TeachingStateCompanion(currentPhase: const Value('P2_PRACTICE_LOOP')),
      );
      await db
          .into(db.activeProblems)
          .insert(
            ActiveProblemsCompanion.insert(
              id: 'ap-a',
              sessionId: sessionId,
              syndromeId: 's1',
              syndromeName: const Value('情绪标签化'),
              severity: const Value('L3'),
              status: const Value('active'),
            ),
          );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      // 书架初始 /bookshelf，书架列表无「学习进度」入口
      expect(find.text('学习进度'), findsNothing);
      expect(find.text('诊断次数'), findsNothing);
    });

    testWidgets('#11 go_router 场景：创建弹窗确认后正常关闭（无空栈崩溃回归）', (tester) async {
      // 复现模拟器实测崩溃：showDialog 默认 useRootNavigator: true，弹窗在 root navigator；
      // 旧代码 Navigator.of(context).pop() 误 pop go_router 嵌套栈（bookshelf 是栈底）
      // → currentConfiguration.isNotEmpty 断言崩溃。修复：rootNavigator: true。
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      // appRouter 是全局单例，#10 已导航到 /progress-detail，这里显式回到书架
      appRouter.go(AppRoutes.bookshelf);
      await tester.pumpAndSettle();

      // 初始落在书架 Tab
      expect(find.text('还没有作品'), findsOneWidget);

      // 打开创建弹窗（AppBar 右上角 + 按钮）
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('简介（可选）'), findsOneWidget, reason: '弹窗应已弹出');

      // 输入标题并确认创建
      await tester.enterText(find.byType(TextField).first, 'Router 回归作品');
      await tester.tap(find.text('创建'));
      // 修复前此处触发空栈断言异常；修复后弹窗正常关闭 + 跳详情页
      await tester.pumpAndSettle();

      // 弹窗已关闭 + 批次93-4：创建后立即跳详情页（不再留在书架 + SnackBar）
      expect(find.text('简介（可选）'), findsNothing, reason: '创建成功后弹窗应关闭');
      expect(find.byType(ManuscriptDetailPage), findsOneWidget);
      expect(find.text('Router 回归作品'), findsOneWidget);

      // DB 落库验证
      final repo = ManuscriptRepository(db);
      final manuscripts = await repo.listManuscripts();
      expect(manuscripts.length, 1);
      expect(manuscripts.first.title, 'Router 回归作品');
    });

    testWidgets('#12 go_router 场景：创建弹窗点「取消」正常关闭（无空栈崩溃回归）', (tester) async {
      // 批次 32：取消路径与创建成功路径同根因——showDialog 默认 useRootNavigator: true，
      // 弹窗在 root navigator；旧 _closeCreateModal 用 Navigator.of(context).pop()
      // 误 pop go_router 嵌套栈（bookshelf 是栈底）→ 空栈断言崩溃。
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();

      appRouter.go(AppRoutes.bookshelf);
      await tester.pumpAndSettle();
      expect(find.text('还没有作品'), findsOneWidget);

      // 打开创建弹窗
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('简介（可选）'), findsOneWidget, reason: '弹窗应已弹出');

      // 输入标题后点「取消」（输入内容仅用于确认取消会清理控制器）
      await tester.enterText(find.byType(TextField).first, '取消回归测试');
      await tester.tap(find.text('取消'));
      // 修复前此处触发空栈断言异常；修复后弹窗正常关闭
      await tester.pumpAndSettle();

      // 弹窗已关闭、仍在书架、未创建任何作品
      expect(find.text('简介（可选）'), findsNothing, reason: '取消后弹窗应关闭');
      expect(find.text('还没有作品'), findsOneWidget);
      expect(find.text('取消回归测试'), findsNothing);

      final repo = ManuscriptRepository(db);
      final manuscripts = await repo.listManuscripts();
      expect(manuscripts, isEmpty, reason: '取消不应创建作品');
    });

    testWidgets('#13 批次93-7 长按作品 → 操作菜单（删除）→ 二次确认删除（软删 archived）', (
      tester,
    ) async {
      final repo = ManuscriptRepository(db);
      final keepId = await repo.createManuscript(title: '保留作品');
      final delId = await repo.createManuscript(title: '长按删除作品');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 长按作品卡片 → 操作菜单出现（批次93-7：继续写作/编辑信息/置顶/删除）
      await tester.longPress(find.text('长按删除作品'));
      await tester.pumpAndSettle();
      expect(find.text('继续写作'), findsOneWidget);
      expect(find.text('编辑信息'), findsOneWidget);
      expect(find.text('置顶'), findsOneWidget);
      expect(find.text('删除'), findsOneWidget);

      // 点删除 → 二次确认弹窗
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除作品'), findsOneWidget);

      // 取消 → 不删除
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('长按删除作品'), findsOneWidget);

      // 再次长按 → 确认删除
      await tester.longPress(find.text('长按删除作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      // 列表移除 + 保留作品仍在
      expect(find.text('长按删除作品'), findsNothing);
      expect(find.text('保留作品'), findsOneWidget);
      expect(find.text('已删除'), findsOneWidget);

      // DB 验证：软删（archived），listManuscripts 不返回
      final fromDb = await ManuscriptRepository(db).getManuscript(delId);
      expect(fromDb?.status, 'archived');
      final active = await repo.listManuscripts();
      expect(active.map((m) => m.id).toList(), [keepId]);
    });

    testWidgets('#14 批次35 新建弹窗内「从 TXT 文件导入书籍」→ 打开导入弹层', (tester) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 打开新建弹窗 → 文本导入入口存在
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.text('从 TXT 文件导入书籍'), findsOneWidget);

      // 点击 → 关闭表单弹窗 + 打开导入弹层
      await tester.tap(find.text('从 TXT 文件导入书籍'));
      await tester.pumpAndSettle();

      expect(find.text('简介（可选）'), findsNothing, reason: '表单弹窗应已关闭');
      expect(find.byType(BookImportSheet), findsOneWidget);
      expect(find.text('导入书籍'), findsOneWidget);
      expect(find.text('选择文件'), findsOneWidget);
    });

    testWidgets('#15 批次35 导入弹层选文件 → 创建书籍+章节 + 书架刷新', (tester) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 打开新建弹窗 → 文本导入 → 导入弹层
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      await tester.tap(find.text('从 TXT 文件导入书籍'));
      await tester.pumpAndSettle();

      // 点「选择文件」→ fake 导入成功（绕过 file_picker）
      await tester.tap(find.text('选择文件'));
      await tester.pumpAndSettle();

      // 导入弹层关闭 + 书架出现新书 + SnackBar
      expect(find.byType(BookImportSheet), findsNothing);
      expect(find.text('导入的小说'), findsOneWidget);
      expect(find.text('已导入《导入的小说》（2章）'), findsOneWidget);

      // DB 验证：书籍 + 2 章节，无引用（书架导入不建主引用）
      final msRepo = ManuscriptRepository(db);
      final manuscripts = await msRepo.listManuscripts();
      expect(manuscripts.length, 1);
      expect(manuscripts.first.title, '导入的小说');
      final chapters = await ChapterRepository(
        db,
      ).listChapters(manuscripts.first.id);
      expect(chapters.length, 2);
      expect(chapters[0].title, '第一章');
      expect(chapters[1].title, '第二章');
      final refs = await db.select(db.sessionReferences).get();
      expect(refs, isEmpty, reason: '书架导入无会话上下文，不应建引用');
    });
  });

  group('视觉规范（月色竹青 + 百灵极简）', () {
    testWidgets('#V1 AppBar 浅色 #F7F8F6 + 48dp + 深字 #2D3142', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '视觉测试作品');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.backgroundColor, const Color(0xFFF7F8F6));
      expect(appBar.toolbarHeight, 48);
      expect(appBar.foregroundColor, const Color(0xFF2D3142));
    });

    testWidgets('#V2 Scaffold 背景为冷青灰白 #F7F8F6', (tester) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.backgroundColor, const Color(0xFFF7F8F6));
    });

    testWidgets('#V3 作品卡片左侧 4dp 竹青色条', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '边框测试');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 卡片内部有 width=4 + 竹青色 Container（作为左侧主色锚点）
      // 由于 Border + borderRadius 不支持非均匀颜色，改用 ClipRRect + 内部色条
      final colorBar = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.constraints?.maxWidth == 4 &&
            w.color == const Color(0xFF2D5A52),
      );
      expect(colorBar, findsOneWidget);
    });

    testWidgets('#V4 首字封面（批次93-1：体裁色；无体裁用弱化灰 textTertiary）', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '作品A');
      await repo.createManuscript(title: '作品B');
      await repo.createManuscript(title: '作品C');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 精确匹配封面色块：圆角 8 + 有 color 的 Container（排除卡片本身圆角 12）
      final coverBlocks = find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color != null &&
            (w.decoration as BoxDecoration).borderRadius is BorderRadius &&
            ((w.decoration as BoxDecoration).borderRadius as BorderRadius)
                    .topLeft
                    .x ==
                8.0,
      );

      final blocks = tester.widgetList<Container>(coverBlocks).toList();
      expect(blocks.length, 3); // 3 个作品 → 3 个首字封面

      // 无体裁作品封面用弱化灰 #858B92（textTertiary）
      for (final container in blocks) {
        final deco = container.decoration as BoxDecoration;
        expect(deco.color, const Color(0xFF858B92), reason: '无体裁封面用弱化灰，不再统一竹青图标');
      }
    });

    testWidgets('#V5 列表非空时无 FAB（仅 AppBar + 入口）', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '有作品时无 FAB');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('#V6 空状态时也无 FAB（用空状态 CTA）', (tester) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.text('新建作品'), findsOneWidget);
    });
  });

  group('ManuscriptStore', () {
    test('#1 初始状态：manuscripts 空 / isLoading=false / error null', () {
      final state = container.read(manuscriptStoreProvider);
      expect(state.manuscripts, isEmpty);
      expect(state.isLoading, false);
      expect(state.error, isNull);
    });

    test('#2 loadManuscripts：从 DB 加载列表', () async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: 'Store 测试');

      await container.read(manuscriptStoreProvider.notifier).loadManuscripts();

      final state = container.read(manuscriptStoreProvider);
      expect(state.manuscripts.length, 1);
      expect(state.manuscripts.first.title, 'Store 测试');
      expect(state.isLoading, false);
    });

    test('#3 createManuscript：DB 写入 + 乐观更新', () async {
      final id = await container
          .read(manuscriptStoreProvider.notifier)
          .createManuscript(title: '乐观作品', genre: '言情');

      expect(id, isNotNull);
      expect(id, isNotEmpty);

      final state = container.read(manuscriptStoreProvider);
      expect(state.manuscripts.length, 1);
      expect(state.manuscripts.first.title, '乐观作品');
      expect(state.manuscripts.first.genre, '言情');

      // DB 验证
      final repo = ManuscriptRepository(db);
      final manuscripts = await repo.listManuscripts();
      expect(manuscripts.length, 1);
    });

    test('#4 deleteManuscript：软删除 + 列表移除', () async {
      final repo = ManuscriptRepository(db);
      final id = await repo.createManuscript(title: '待删除');

      await container.read(manuscriptStoreProvider.notifier).loadManuscripts();
      expect(container.read(manuscriptStoreProvider).manuscripts.length, 1);

      await container
          .read(manuscriptStoreProvider.notifier)
          .deleteManuscript(id);

      final state = container.read(manuscriptStoreProvider);
      expect(state.manuscripts, isEmpty);

      // DB 验证：软删除后 listManuscripts 不返回
      final manuscripts = await repo.listManuscripts();
      expect(manuscripts, isEmpty);
    });

    test('#5 clearError：清除错误', () {
      final notifier = container.read(manuscriptStoreProvider.notifier);
      notifier.clearError();
      expect(container.read(manuscriptStoreProvider).error, isNull);
    });
  });

  group('批次93：书架 P0 七大件', () {
    /// 以全路由启动书架（#93-4 创建后跳详情、#93-7 跳写作页需要）
    Future<void> pumpRouterToShelf(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: appRouter),
        ),
      );
      await tester.pumpAndSettle();
      appRouter.go(AppRoutes.bookshelf);
      await tester.pumpAndSettle();
    }

    testWidgets('#93-2 搜索：AppBar search → 搜索框 → 标题模糊过滤', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '大明王朝', genre: '历史');
      await repo.createManuscript(title: '小城故事', genre: '都市');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();
      expect(find.text('大明王朝'), findsOneWidget);
      expect(find.text('小城故事'), findsOneWidget);

      // 点搜索图标 → AppBar 变搜索框
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('bookshelf-search-field'));
      expect(field, findsOneWidget);

      // 输入 → 标题模糊过滤
      await tester.enterText(field, '大明');
      await tester.pumpAndSettle();
      expect(find.text('大明王朝'), findsOneWidget);
      expect(find.text('小城故事'), findsNothing);

      // 无匹配 → 搜索空态
      await tester.enterText(field, '不存在的书');
      await tester.pumpAndSettle();
      expect(find.text('没有找到相关作品'), findsOneWidget);

      // 退出搜索 → 恢复全量
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.text('小城故事'), findsOneWidget);
      expect(find.text('大明王朝'), findsOneWidget);
    });

    testWidgets('#93-2 排序：切换 → SnackBar 提示 + 顺序变化', (tester) async {
      final repo = ManuscriptRepository(db);
      // 手动控制 sortOrder：A(1) 在 B(0) 之后
      await repo.createManuscript(title: 'A书', genre: '奇幻', sortOrder: 1);
      await repo.createManuscript(title: 'B书', genre: '奇幻', sortOrder: 0);

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      // 切到「书名」排序
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('书名'));
      await tester.pumpAndSettle();

      // 决策提示：排序与分卷独立（不学纯纯「分卷仅在手动排序启用」的坑）
      expect(find.textContaining('卷分组不受排序影响'), findsOneWidget);
      // 书名升序：A书 在 B书 之前
      final aY = tester.getTopLeft(find.text('A书')).dy;
      final bY = tester.getTopLeft(find.text('B书')).dy;
      expect(aY, lessThan(bY));
    });

    testWidgets('#93-6 下拉刷新：fling 下拉 → 刷新完成不异常', (tester) async {
      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();
      expect(find.text('还没有作品'), findsOneWidget);

      // 空态也支持下拉（AlwaysScrollableScrollPhysics）
      await tester.fling(find.text('还没有作品'), const Offset(0, 300), 1000);
      await tester.pumpAndSettle();
      expect(find.text('还没有作品'), findsOneWidget);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    testWidgets('#93-5 体裁 Chip：选「奇幻」→ 创建落库 genre', (tester) async {
      await pumpRouterToShelf(tester);

      await tester.tap(find.text('新建作品'));
      await tester.pumpAndSettle();

      // ChoiceChip 预设（番茄作家助手模型）
      await tester.tap(find.byKey(const ValueKey('genre-chip-奇幻')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Chip 作品');
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      // 创建后跳详情页（批次93-4）
      expect(find.byType(ManuscriptDetailPage), findsOneWidget);
      final manuscripts = await ManuscriptRepository(db).listManuscripts();
      expect(manuscripts.single.genre, '奇幻');
    });

    testWidgets('#93-5 体裁 Chip：选「其他」→ 展开自定义输入 → 落库自定义', (tester) async {
      await pumpRouterToShelf(tester);

      await tester.tap(find.text('新建作品'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('genre-chip-其他')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('custom-genre-field')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('custom-genre-field')), '克苏鲁');
      await tester.enterText(find.byType(TextField).first, '自定义体裁作品');
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      final manuscripts = await ManuscriptRepository(db).listManuscripts();
      expect(manuscripts.single.genre, '克苏鲁');
    });

    testWidgets('#93-7 继续写作：长按 → 跳最新章节写作页', (tester) async {
      final msId = await ManuscriptRepository(
        db,
      ).createManuscript(title: '写作作品', genre: '奇幻');
      await ChapterRepository(db).createChapter(msId, title: '第一章');
      await ChapterRepository(db).createChapter(msId, title: '第二章');

      await pumpRouterToShelf(tester);
      expect(find.text('写作作品'), findsOneWidget);

      await tester.longPress(find.text('写作作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续写作'));
      await tester.pumpAndSettle();

      // 跳到最新章节（sort_order 最大 = 第二章）写作页
      expect(find.byType(WritingPage), findsOneWidget);
    });

    testWidgets('#93-7 置顶：长按 → 置顶 → sortOrder 最小', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(
        title: '置顶前',
        genre: '奇幻',
        sortOrder: 0,
      );
      final bId = await repo.createManuscript(
        title: '置顶对象',
        genre: '奇幻',
        sortOrder: 1,
      );

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('置顶对象'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置顶'));
      await tester.pumpAndSettle();

      expect(find.textContaining('已置顶'), findsOneWidget);
      final fromDb = await repo.getManuscript(bId);
      expect(fromDb!.sortOrder, lessThan(0));
      // 置顶前仍在
      expect(find.text('置顶前'), findsOneWidget);
    });

    testWidgets('#93-7 编辑信息：长按 → 编辑 → 改名落库', (tester) async {
      final repo = ManuscriptRepository(db);
      await repo.createManuscript(title: '旧名作品', genre: '奇幻');

      await tester.pumpWidget(buildBookshelfPage());
      await tester.pumpAndSettle();

      await tester.longPress(find.text('旧名作品'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('编辑信息'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('edit-title-field')), '新名作品');
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.text('新名作品'), findsOneWidget);
      expect(find.text('旧名作品'), findsNothing);
      final fromDb = await repo.listManuscripts();
      expect(fromDb.single.title, '新名作品');
    });

    testWidgets('#93-3 返回自动刷新：详情页新建章节后 pop 回来章节数更新', (tester) async {
      await ManuscriptRepository(
        db,
      ).createManuscript(title: '刷新作品', genre: '奇幻');
      await container.read(manuscriptStoreProvider.notifier).loadManuscripts();

      await pumpRouterToShelf(tester);
      expect(find.text('0 章 · 0字'), findsOneWidget);

      // 进详情页（push → 返回时 push().then 刷新）
      await tester.tap(find.text('刷新作品'));
      await tester.pumpAndSettle();
      expect(find.byType(ManuscriptDetailPage), findsOneWidget);
      // 批次96-3/96-4：列表「新建章节」无弹窗 → 自动创建「第一章」，不跳写作页
      await tester.tap(find.text('新建章节'));
      await tester.pumpAndSettle();
      expect(find.byType(WritingPage), findsNothing, reason: '新建章节后不跳写作页');
      expect(find.text('第一章'), findsOneWidget);

      // 详情页返回 → 书架（pop → push future resolve → 自动刷新）
      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();
      // 确实回到书架（详情页已销毁，其 AppBar 标题「刷新作品」仅剩书架卡片一处）
      expect(find.byType(ManuscriptDetailPage), findsNothing, reason: '详情页应已 pop 销毁');

      // 章节数已刷新（push().then 触发 _refreshBookshelf + stats 重新加载）
      expect(find.text('1 章 · 0字'), findsOneWidget);
    });
  });
}
