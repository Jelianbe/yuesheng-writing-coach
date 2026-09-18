// ─────────────────────────────────────────────────────────────
// outline_drawer_test — 大纲抽屉/内容体**直接**测试（批次 N12 解绑配套）
//
// ★ 口径纠正：为什么这里「还要」新建一个测试文件
//   候选池原记「`test/` 零直接引用」—— 那是**符号零引用**，**不等于零覆盖**。
//   实测 `writing_page_test.dart` 已**端到端**覆盖抽屉主干：
//     · `#83-6` ⋮ 菜单 →「大纲」→ 抽屉打开 + 空态引导
//     · `#83-9` 右上角关闭 → 抽屉收起
//     · `#87-4` 快速确认实体 + 拒绝印象（真落库 + SnackBar）
//   故本文件**不重复**上述三条，只补它们没覆盖的网眼，并给大纲 UI 一个
//   **不依赖 3711 行写作页测试**的直接入口：
//     1. 解绑本身：内容体可脱离 `Drawer` 独立承载（本批次的目的判据）
//     2. 分组标题 + **计数** + **组序**（几何判据：人物 → 设定 → 情节）
//     3. 别名行 / 无别名不渲染该行；来源章节 tag / 无来源章节不渲染 tag
//     4. `kOutlineVisibleStatuses` **状态过滤**正负例（rejected 必须不展示）
//     5. 未知类型（volume/chapter）不展示 —— **锁当前行为**，N6 开工时随实现改
//     6. 外壳契约：右上角关闭回调被调用
//
// ★ 修订（同批后续子批 **N12-F1 · ADR-C95**）：上述缺陷**已修**。
//   `_ImpressionRow` 现按「作品当前章节列表中的序位」解析章号
//   （实现 `lib/utils/chapter_number.dart`，裁定 `docs/ADR-C95-chapter-number-convention.md`）。
//   ⇒ 本文件的章标用例改为**播种真实章节**，并补 F1 专项正负例
//     （含「删除不重编号」反例与「引用已删章」负例）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/chapter_providers.dart';
import 'package:writingcoach/providers/manuscript_providers.dart';
import 'package:writingcoach/widgets/outline_content_view.dart';
import 'package:writingcoach/widgets/outline_drawer.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;
  late OutlineRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '大纲抽屉直接测试作品');
    repo = OutlineRepository(db);
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// 按生产同形承载：Scaffold 的 `endDrawer`（写作页即如此）。
  Future<void> pumpDrawer(
    WidgetTester tester, {
    String? msId,
    VoidCallback? onClose,
    VoidCallback? onOpenCoach,
  }) async {
    final scaffoldKey = GlobalKey<ScaffoldState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            key: scaffoldKey,
            endDrawer: OutlineDrawer(
              manuscriptId: msId ?? manuscriptId,
              onClose: onClose ?? () {},
              onOpenCoach: onOpenCoach,
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      ),
    );
    scaffoldKey.currentState!.openEndDrawer();
    await tester.pumpAndSettle();
  }

  /// 直接嵌入内容体（不套任何抽屉外壳）。
  Future<void> pumpContentView(
    WidgetTester tester, {
    String? msId,
    VoidCallback? onOpenCoach,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: OutlineContentView(
              manuscriptId: msId ?? manuscriptId,
              onOpenCoach: onOpenCoach,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<String> insertEntity({
    required String type,
    required String key,
    List<String> aliases = const [],
  }) async {
    await repo.insertEntity(
      manuscriptId: manuscriptId,
      entityType: type,
      entityKey: key,
      aliases: aliases,
    );
    final all = await repo.listEntities(manuscriptId);
    return all.firstWhere((e) => e.entityKey == key).id;
  }

  /// 播种章节（ADR-C95：章标解析的数据源）。
  ///
  /// `sortOrder` **显式指定** —— 本批核心正是「`sort_order` ≠ 展示序位」；
  /// 若用默认的 `MAX+1`，就永远造不出「删除留下的空洞」，§反例也就测不出来。
  Future<void> seedChapters(List<int> sortOrders) async {
    final chapterRepo = ChapterRepository(db);
    for (final o in sortOrders) {
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第${o + 1}章',
        sortOrder: o,
      );
    }
    // chapterStoreProvider 的加载是**微任务异步**；显式 await 一次，避免
    // 首帧 pump 时章节列表尚空 ⇒ 章标偶发缺失（会把正例误判成缺陷）。
    await container
        .read(chapterStoreProvider(manuscriptId).notifier)
        .loadChapters();
  }

  // ── 1. 解绑本身 ──────────────────────────────────────────────
  group('N12 解绑：内容体与抽屉外壳分离', () {
    testWidgets('#N12-0 内容体可脱离 Drawer 独立承载（目的判据）', (tester) async {
      await insertEntity(type: 'character', key: '林晚');

      await pumpContentView(tester);

      // 正向：无任何 Drawer 外壳，内容照常渲染
      expect(find.byType(Drawer), findsNothing);
      expect(find.text('人物'), findsOneWidget);
      expect(find.text('林晚'), findsOneWidget);
      // 负向：头部标题「大纲」属**外壳**职责 ⇒ 内容体里必须没有
      expect(find.text('大纲'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('#N12-7 外壳契约：右上角关闭回调被调用', (tester) async {
      var closed = 0;
      await pumpDrawer(tester, onClose: () => closed++);

      // 与上一用例构成正负例：抽屉外壳里「大纲」标题与关闭按钮**必须在**
      expect(find.text('大纲'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(closed, 1);
    });
  });

  // ── 2. 分组标题 + 计数 + 组序 ─────────────────────────────────
  testWidgets('#N12-1 分组标题 + 计数 + 组序（人物→设定→情节）', (tester) async {
    await insertEntity(type: 'character', key: '林晚');
    await insertEntity(type: 'setting', key: '老宅');
    await insertEntity(type: 'setting', key: '渡口');
    await insertEntity(type: 'plot', key: '寻亲线');
    await insertEntity(type: 'plot', key: '旧照片');
    await insertEntity(type: 'plot', key: '婚约线');

    await pumpDrawer(tester);

    // 三个分组标题各一
    expect(find.text('人物'), findsOneWidget);
    expect(find.text('设定'), findsOneWidget);
    expect(find.text('情节'), findsOneWidget);
    // 计数 人物1 / 设定2 / 情节3（`Text('$count')`，精确匹配）
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);

    // 组序用**几何判据**（比文本出现顺序可靠）
    final yCharacter = tester.getTopLeft(find.text('人物')).dy;
    final ySetting = tester.getTopLeft(find.text('设定')).dy;
    final yPlot = tester.getTopLeft(find.text('情节')).dy;
    expect(yCharacter < ySetting, isTrue, reason: '「人物」应排在「设定」之上');
    expect(ySetting < yPlot, isTrue, reason: '「设定」应排在「情节」之上');
  });

  // ── 3. 别名行 / 来源章节 tag ─────────────────────────────────
  testWidgets('#N12-2 别名行：有别名渲染 / 无别名不渲染（正负例）', (tester) async {
    await insertEntity(type: 'character', key: '林晚', aliases: ['晚晚', '小晚']);
    await insertEntity(type: 'character', key: '周砚');

    await pumpDrawer(tester);

    expect(find.text('别名：晚晚、小晚'), findsOneWidget);
    // 负例：无别名的实体绝不产生第二个「别名：」行
    expect(find.textContaining('别名：'), findsOneWidget);
  });

  testWidgets('#N12-3 来源章节 tag：有章节号渲染 / 无则无 tag（正负例）', (tester) async {
    // ADR-C95：`sourceChapterNo` 是 0 基 `sort_order`（身份键）；
    // 播种 [0,1,2] ⇒ `sortOrder = 2` 的展示序位是 **3**。
    await seedChapters([0, 1, 2]);
    final id = await insertEntity(type: 'character', key: '林晚');
    await repo.insertImpression(
      entityId: id,
      impression: '怕黑',
      sourceChapterNo: 2,
    );
    await repo.insertImpression(entityId: id, impression: '会辨草药');

    await pumpDrawer(tester);

    expect(find.text('第3章'), findsOneWidget);
    expect(find.text('怕黑'), findsOneWidget);
    expect(find.text('会辨草药'), findsOneWidget);
    // 负例：无来源章节那条不得产生任何「…章」标签
    expect(find.textContaining('章'), findsOneWidget);
  });

  // ── 4. 状态过滤（正负例） ─────────────────────────────────────
  testWidgets('#N12-4 状态过滤：pending 展示 / rejected 不展示（正负例）', (tester) async {
    await seedChapters([0, 1, 2]);
    final id = await insertEntity(type: 'character', key: '林晚');
    await repo.insertImpression(
      entityId: id,
      impression: '怕黑',
      sourceChapterNo: 1,
    );
    final dropId = await repo.insertImpression(
      entityId: id,
      impression: '曾落水',
      sourceChapterNo: 2,
    );

    // 正例：两条都可见
    await pumpDrawer(tester);
    expect(find.text('怕黑'), findsOneWidget);
    expect(find.text('曾落水'), findsOneWidget);

    // 置 rejected 后（负例）
    await repo.rejectImpression(dropId);
    container.invalidate(outlineViewProvider(manuscriptId));
    await pumpDrawer(tester);

    expect(find.text('怕黑'), findsOneWidget, reason: '未被拒的印象不受影响');
    expect(find.text('曾落水'), findsNothing, reason: 'rejected 印象必须被过滤掉');
  });

  // ── 5. 未知类型（锁当前行为） ─────────────────────────────────
  testWidgets('#N12-6 volume/chapter 不在展示序 → 不渲染（N6 开工时随实现改）', (tester) async {
    // ⚠️ 这是**当前行为**（非期望行为）：AI 侧白名单为 character|setting|plot，
    //    故 volume/chapter 无生产写入方；但库里若存在，抽屉**静默不展示**。
    //    本断言的作用是「防止无提示地改变」——N6 大纲类型体系落地时须一并改。
    await insertEntity(type: 'volume', key: '第一卷：乡村起步');
    await insertEntity(type: 'chapter', key: '第一章：进城');

    await pumpDrawer(tester);

    expect(find.text('第一卷：乡村起步'), findsNothing);
    expect(find.text('第一章：进城'), findsNothing);
    expect(find.text('人物'), findsNothing);
    // ⚠️ 实测行为，**比「被静默过滤」更差**（本批新发现，另立批次）：
    //    `entities` 非空 ⇒ 不进空态分支；而三条分组全被跳过 ⇒
    //    抽屉渲染成**一片空白** —— 连「还没有大纲」的引导文案都没有。
    //    故此处不断言空态，而是把「空白 ListView」这一事实钉住。
    expect(find.text('还没有大纲'), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  // ── 6. 空 manuscriptId ───────────────────────────────────────
  testWidgets('#N12-5 manuscriptId 为空 → 空态（不渲染库内实体）', (tester) async {
    await insertEntity(type: 'character', key: '林晚');

    await pumpDrawer(tester, msId: '');

    expect(find.text('还没有大纲'), findsOneWidget);
    // 负例：库里确实有实体，但空 id 不得把它渲染出来
    expect(find.text('林晚'), findsNothing);
  });

  // ── 6b. N4-3 空态可操作 ────────────────────────────────────────
  group('N4-3：空态可操作（只说不做 → 有按钮）', () {
    testWidgets('#N4-3 注入 onOpenCoach → 空态出现「打开教练面板」且点击回调被调用', (tester) async {
      var called = 0;
      await pumpDrawer(tester, onOpenCoach: () => called++);

      // 空态文案仍在（不改变既有契约）
      expect(find.text('还没有大纲'), findsOneWidget);
      // 主行动按钮在场，且以 Key 可定位（供端到端用例复用）
      final btn = find.byKey(const Key('outline-empty-open-coach'));
      expect(btn, findsOneWidget);
      expect(find.text('打开教练面板'), findsOneWidget);

      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(called, 1);
    });

    testWidgets('#N4-3 未注入 onOpenCoach → 不渲染按钮（独立承载零变化）', (tester) async {
      // 负例：既有七处调用点（含 pumpContentView）都不传该参数
      await pumpContentView(tester);

      expect(find.text('还没有大纲'), findsOneWidget);
      expect(find.byKey(const Key('outline-empty-open-coach')), findsNothing);
      expect(find.text('打开教练面板'), findsNothing);
    });
  });

  // ── 7. 章号口径（子批 N12-F1 · ADR-C95）───────────────────────
  //
  // 三条判据一一对应 ADR §7：
  //   正例（判据1）· 杀死 `sortOrder + 1` 兜底（判据2）· 杀死「非 null 即渲染」（判据3）
  group('N12-F1 章号口径（ADR-C95）', () {
    testWidgets('#N12-F1-1 首章渲染「第1章」而**非**「第0章」（原缺陷直接回归）', (tester) async {
      await seedChapters([0]);
      final id = await insertEntity(type: 'character', key: '林晚');
      await repo.insertImpression(
        entityId: id,
        impression: '怕黑',
        sourceChapterNo: 0,
      );

      await pumpDrawer(tester);

      expect(find.text('第1章'), findsOneWidget);
      expect(
        find.text('第0章'),
        findsNothing,
        reason: '0 基 sort_order 是身份键，不得直接渲染',
      );
    });

    testWidgets('#N12-F1-2 删过首章的稿 ⇒ 序位正确（**杀死 `sortOrder + 1` 兜底**）', (
      tester,
    ) async {
      // 章节 [1,2]：0 号那章已被删 ⇒ 这两章现在是第 1、2 章。
      // `sortOrder + 1` 会给出 2、3 —— 与序位不等价（ADR-C95 §3 反例 1）。
      await seedChapters([1, 2]);
      final id = await insertEntity(type: 'character', key: '林晚');
      await repo.insertImpression(
        entityId: id,
        impression: '怕黑',
        sourceChapterNo: 2,
      );

      await pumpDrawer(tester);

      expect(find.text('第2章'), findsOneWidget);
      expect(
        find.text('第3章'),
        findsNothing,
        reason: '删除不重编号 ⇒ `sortOrder + 1` 在这里是错的',
      );
    });

    testWidgets('#N12-F1-3 引用已删章 ⇒ 不渲染章标（不编造数字）', (tester) async {
      await seedChapters([0, 1]);
      final id = await insertEntity(type: 'character', key: '林晚');
      await repo.insertImpression(
        entityId: id,
        impression: '雨天落水',
        sourceChapterNo: 9, // 该章已不在列表中（已删 / 回收站 / 越界）
      );

      await pumpDrawer(tester);

      expect(find.text('雨天落水'), findsOneWidget, reason: '梗概本身照常展示');
      expect(
        find.textContaining('章'),
        findsNothing,
        reason: '解析失败 ⇒ 隐藏章标，而不是编造「第10章」或保留「第9章」',
      );
    });
  });
}
