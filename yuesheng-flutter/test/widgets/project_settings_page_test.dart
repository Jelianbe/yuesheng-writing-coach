// ─────────────────────────────────────────────────────────────
// project_settings_page_test — 项目设置页 Widget 测试
//
// 覆盖路径：
//   #1 渲染（名称/体裁 chips/简介/标签区初始 genre/统计/危险区）
//   #2 名称空保存 → 拦截提示 + DB 不变
//   #3 保存成功 → DB title 更新 + 提示 + 回书架
//   #4 切换体裁保存 → DB genre 更新
//   #5 添加标签（dialog 输入）
//   #6 删除标签
//   #7 删除项目：取消 → 不删；确认 → archived + 回书架
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/project_settings_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品', description: '简介内容', genre: '奇幻');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost() {
    final router = GoRouter(
      initialLocation: '/project-settings',
      routes: [
        GoRoute(
          path: '/project-settings',
          builder: (context, state) => ProjectSettingsPage(
            manuscriptId: manuscriptId,
            initialTitle: '测试作品',
          ),
        ),
        GoRoute(
          path: '/bookshelf',
          builder: (context, state) => const Scaffold(body: Text('书架测试页')),
        ),
      ],
    );
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    );
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.tap(find.text('保存'));
    await tester.pump();
  }

  group('ProjectSettingsPage', () {
    testWidgets('#1 渲染', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('项目设置'), findsOneWidget);
      // 名称已填充
      expect(find.text('测试作品'), findsOneWidget);
      // 体裁 chips
      expect(find.text('长篇小说'), findsOneWidget);
      expect(find.text('中篇'), findsOneWidget);
      expect(find.text('短篇'), findsOneWidget);
      // 简介已填充
      expect(find.text('简介内容'), findsOneWidget);
      // 标签区：初始 = [genre]
      expect(find.text('标签'), findsOneWidget);
      expect(find.text('奇幻'), findsOneWidget);
      // 统计信息
      expect(find.textContaining('创建于'), findsOneWidget);
      // 危险区
      expect(find.text('删除项目'), findsOneWidget);
      expect(find.text('删除后作品将不再显示，章节和诊断记录会保留'), findsOneWidget);
    });

    testWidgets('#2 名称空保存 → 拦截提示 + DB 不变', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 清空名称
      await tester.enterText(find.byType(TextField).first, '');
      await tapSave(tester);
      await tester.pump();

      expect(find.text('请输入作品名称'), findsOneWidget);

      final m = await ManuscriptRepository(db).getManuscript(manuscriptId);
      expect(m?.title, '测试作品');
    });

    testWidgets('#3 保存成功 → DB 更新 + 提示 + 回书架', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '改名后的作品');
      await tapSave(tester);
      await tester.pump();

      expect(find.text('设置已保存'), findsOneWidget);

      final m = await ManuscriptRepository(db).getManuscript(manuscriptId);
      expect(m?.title, '改名后的作品');

      // 800ms 延迟后返回书架
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
      expect(find.text('书架测试页'), findsOneWidget);
    });

    testWidgets('#4 切换体裁保存 → DB genre 更新', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('短篇'));
      await tester.pumpAndSettle();
      await tapSave(tester);
      // 让 updateManuscript 异步落库完成
      await tester.pump(const Duration(milliseconds: 100));

      final m = await ManuscriptRepository(db).getManuscript(manuscriptId);
      expect(m?.genre, '短篇');

      // 推进保存后 800ms 返回 timer，避免 pending timer 断言
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });

    testWidgets('#5 添加标签', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ 添加标签'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).last, '新标签');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(find.text('新标签'), findsOneWidget);
    });

    testWidgets('#6 删除标签', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 初始标签「奇幻」
      expect(find.text('奇幻'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('奇幻'), findsNothing);
    });

    testWidgets('#7 删除项目：取消 → 不删；确认 → archived + 回书架', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 危险区在视口外，先滚动到可见
      await tester.ensureVisible(find.text('删除项目'));
      await tester.pumpAndSettle();

      // 取消
      await tester.tap(find.text('删除项目'));
      await tester.pumpAndSettle();
      // 批次59：确认文案对齐真实软删语义
      expect(find.text('确定删除《测试作品》吗？删除后将不再显示，章节和诊断记录会保留。'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      var m = await ManuscriptRepository(db).getManuscript(manuscriptId);
      expect(m?.status, 'active');

      // 确认删除
      await tester.ensureVisible(find.text('删除项目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除项目'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();

      m = await ManuscriptRepository(db).getManuscript(manuscriptId);
      expect(m?.status, 'archived');
      expect(find.text('书架测试页'), findsOneWidget);
    });
  });

  group('批次94-5 标签落库 + 热门Chip', () {
    testWidgets('#1 落库标签优先加载（不再回退 genre）', (tester) async {
      // 预置落库标签（genre 仍为奇幻）
      await ManuscriptRepository(
        db,
      ).updateManuscript(manuscriptId, tags: ['重生', '系统']);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('重生'), findsOneWidget);
      expect(find.text('系统'), findsOneWidget);
      // 落库标签非空 → 不再回退 genre
      expect(find.text('奇幻'), findsNothing);
    });

    testWidgets('#2 无落库标签回退 [genre]', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // setUp 未传 tags → 空 → 回退 [genre]
      expect(find.text('奇幻'), findsOneWidget);
    });

    testWidgets('#3 热门Chip 点击加入 + 保存落库', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 滚动到热门标签区
      await tester.ensureVisible(find.text('+ 重生'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ 重生'));
      await tester.pumpAndSettle();

      // 已加入：标签 Wrap 出现「重生」，热门Chip 消失
      expect(find.text('重生'), findsOneWidget);
      expect(find.text('+ 重生'), findsNothing);

      // 保存 → DB 落库
      await tapSave(tester);
      await tester.pump(const Duration(milliseconds: 100));
      final m = await ManuscriptRepository(db).getManuscript(manuscriptId);
      expect(ManuscriptRepository.parseTags(m!), contains('重生'));

      // 推进保存后 800ms 返回 timer，避免 pending timer 断言
      await tester.pump(const Duration(milliseconds: 900));
      await tester.pumpAndSettle();
    });

    testWidgets('#4 已含标签的热门Chip 不显示', (tester) async {
      await ManuscriptRepository(
        db,
      ).updateManuscript(manuscriptId, tags: ['重生']);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('+ 重生'), findsNothing);
      // 其他预设仍显示
      expect(find.text('+ 系统'), findsOneWidget);
    });
  });
}
