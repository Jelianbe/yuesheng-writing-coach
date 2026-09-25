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
//
// ★ 修订（批次 **N6**，2026-09-18）：上述第 5 条**换代**——
//   行为由「静默不展示（且整页全白）」改为「**归入「其他」分组**」，
//   `#N12-6` 契约随之**整体替换**为 `#N6-1` 组（含投影正例与新负例）。
//
//   ⚠️ 本次同时暴露一处**判据陷阱**，全文件受影响：
//     N6 起抽屉顶部多出「章节结构」只读投影段，它会渲染**章标题**；而
//     ADR-C95 的**来源章标**在文案上可能与章标题**完全相同**（用户把章
//     命名为「第3章」时）⇒ **同名不同物**，`find.textContaining('章')`
//     这类**文本计数**判据从此无法区分二者。
//     ⇒ 凡涉及章标的断言一律改用**锚点**（`outlineImpressionTagKey`）或
//       **分段作用域**（`kOutlineStructureSectionKey`）定位。
//       这不是放宽判据：**被测命题未变**，变的是测量手段 ——
//       旧判据在新形态下已测不出该命题（`DECISIONS §4-47`：校验器自身缺陷
//       与被测对象缺陷外观相同，故先确认「测量还测得到」）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/volume_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/providers/chapter_providers.dart';
import 'package:writingcoach/providers/manuscript_providers.dart';
import 'package:writingcoach/widgets/outline_content_view.dart';
import 'package:writingcoach/features/writing/outline_drawer.dart';

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
    void Function(String chapterId, String title)? onJumpToChapter,
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
              onJumpToChapter: onJumpToChapter,
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
    void Function(String chapterId, String title)? onJumpToChapter,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: OutlineContentView(
              manuscriptId: msId ?? manuscriptId,
              onOpenCoach: onOpenCoach,
              onJumpToChapter: onJumpToChapter,
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

  /// 播种一个卷，并**等它进 provider**（N6：「章节结构」投影的数据源之一）。
  ///
  /// `volumeListProvider` 是 **FutureProvider**：首次 watch 才触发加载。
  /// 与此处 `seedChapters` 的「微任务异步」是同一个坑 ⇒ 同样显式落地，
  /// 否则首帧断言会看到**空卷列表**（投影只剩散落章节，正例被误判成缺陷）。
  Future<String> seedVolume(String title, {int sortOrder = 0}) async {
    final id = await VolumeRepository(
      db,
    ).createVolume(manuscriptId, title: title, sortOrder: sortOrder);
    await container.read(volumeListProvider(manuscriptId).future);
    return id;
  }

  /// 播种一章并载入 `chapterStore`（投影段读的就是这个 store）。
  ///
  /// 比 `seedChapters` 多两项：可指定 `volumeId`（卷内/散落）与 `content`
  /// （`wordCount = content.length`，即卷头「N 章 · M字」里的 M）。
  Future<String> seedChapter({
    required String title,
    required int sortOrder,
    String? volumeId,
    String content = '',
  }) async {
    final id = await ChapterRepository(db).createChapter(
      manuscriptId,
      title: title,
      content: content,
      sortOrder: sortOrder,
      volumeId: volumeId,
    );
    await container
        .read(chapterStoreProvider(manuscriptId).notifier)
        .loadChapters();
    return id;
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
    final tagged = await repo.insertImpression(
      entityId: id,
      impression: '怕黑',
      sourceChapterNo: 2,
    );
    final untagged = await repo.insertImpression(
      entityId: id,
      impression: '会辨草药',
    );

    await pumpDrawer(tester);

    // ★ N6：章标改用**锚点**定位 —— 抽屉顶部「章节结构」投影段会渲染同名
    //   章标题（本用例正把章命名为「第1/2/3章」）⇒ 文本计数已无法区分二者。
    expect(
      find.descendant(
        of: find.byKey(outlineImpressionTagKey(tagged)),
        matching: find.text('第3章'),
      ),
      findsOneWidget,
    );
    expect(find.text('怕黑'), findsOneWidget);
    expect(find.text('会辨草药'), findsOneWidget);
    // 负例：无来源章节那条**不得产生任何章标**（锚点不存在，而非「总数少 1」）
    expect(find.byKey(outlineImpressionTagKey(untagged)), findsNothing);
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

  // ── 5. N6：章节结构只读投影 + 「其他」兜底分组 ─────────────────
  //
  // 本组**整体替换**原 `#N12-6`（「volume/chapter 不在展示序 → 不渲染」）。
  // 旧契约只断言**「什么都不显示」**，其隐含缺陷是：`entities` 非空但一条都
  // 不属于可见分组时，抽屉既不进空态、也渲染不出分组 ⇒ **整页全白**。
  // ⇒ 新契约必须能区分两种情形（`DECISIONS §4-28` fixture 鉴别力）：
  //     · **真的没有** → 空态（「还没有大纲」）
  //     · **有但认不出** → 「其他」分组（有行、有类型原值）
  group('N6：章节结构只读投影 + 「其他」兜底分组', () {
    testWidgets('#N6-1 卷/章由投影出现；有结构数据不进空态；仍只有一个 ListView', (tester) async {
      // 结构数据来自**真源表**（`volumes` / `chapters`）的只读投影，
      // 与 `outline_entity` 里有没有行**无关** ⇒ 本用例只播真源。
      final volId = await seedVolume('第一卷：乡村起步');
      await seedChapter(
        title: '第一章：进城',
        sortOrder: 0,
        volumeId: volId,
        content: '一二三四五',
      );
      await seedChapter(
        title: '第二章：码头',
        sortOrder: 1,
        volumeId: volId,
        content: '一二三四五六七',
      );
      await seedChapter(title: '第三章：雨夜', sortOrder: 2); // 散落章节

      await pumpDrawer(tester);

      // ① 卷名 / 章名由投影出现（标题真源 = volumes.title / chapters.title）
      expect(find.text('第一卷：乡村起步'), findsOneWidget);
      expect(find.text('第一章：进城'), findsOneWidget);
      expect(find.text('第二章：码头'), findsOneWidget);
      expect(find.text('第三章：雨夜'), findsOneWidget);
      // ② 卷头 meta：章节数 + 字数（wordCount 来自 content.length：5 + 7 = 12）
      expect(find.text('2 章 · 12字'), findsOneWidget);
      // ③ 有结构数据 ⇒ **结构段在场**（即「没进整页空态」的判据）
      expect(find.byKey(kOutlineStructureSectionKey), findsOneWidget);
      // ④ 本用例**未播实体** ⇒ 要素段走**分段**空态（N6 判据，理由见
      //    `outline_content_view.dart` 头部注释）：引导**文案在**、按钮**不在**
      //    （本用例未注入 onOpenCoach）。
      //    ⚠️ 与设计稿 §4.4「有结构数据 ⇒ 不进空态」的差异就在这一条：
      //    设计稿写的是**整页**判据，落地为**分段**判据 ⇒
      //    「未进整页空态」由 ③ 结构段在场来判，而**不是**由「空态文案不出现」判
      //    （整页判据下，本用例的**结构段会被整段撤掉** —— 见文件头部注释）。
      expect(find.text('还没有大纲'), findsOneWidget);
      expect(
        find.byKey(const Key('outline-empty-open-coach')),
        findsNothing,
        reason: '未注入 onOpenCoach ⇒ 分段空态只渲染文案，不渲染按钮',
      );
      // ⑤ 两段共处**同一个**ListView（不嵌套滚动视图）
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('#N6-2 投影章节点点击 → 以 (chapterId, title) 跳转（正例）', (tester) async {
      final chId = await seedChapter(title: '第一章：进城', sortOrder: 0);

      final jumps = <String>[];
      await pumpDrawer(
        tester,
        onJumpToChapter: (id, title) => jumps.add('$id|$title'),
      );

      await tester.tap(find.byKey(outlineStructureChapterKey(chId)));
      await tester.pumpAndSettle();

      expect(jumps, ['$chId|第一章：进城']);
    });

    testWidgets('#N6-2b 未注入 onJumpToChapter ⇒ 章节点不可点、无箭头（独立承载零变化）', (
      tester,
    ) async {
      final chId = await seedChapter(title: '第一章：进城', sortOrder: 0);

      await pumpDrawer(tester); // 刻意不注入跳转回调

      // 阳性对照：标题照常渲染 ⇒ 证明下面的 findsNothing 是「锚点不在」，
      // 而不是「整个投影段没渲染」（否则会假绿）
      expect(find.text('第一章：进城'), findsOneWidget);
      expect(find.byKey(outlineStructureChapterKey(chId)), findsNothing);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('#N6-3 ★ 仅含未知类型实体 ⇒ 必须渲染「其他」分组（关键负例）', (tester) async {
      // 这是本组的**重点负例**：旧契约下这一条会让抽屉**整页全白**。
      await insertEntity(type: 'unknown_xyz', key: '幽灵条目');

      await pumpDrawer(tester);

      // ① 有显式出口：不静默丢弃
      expect(find.text('其他'), findsOneWidget);
      expect(find.text('幽灵条目'), findsOneWidget);
      // ② 类型**原值**一并打出，使「有但认不出」与「真的没有」可区分
      expect(find.text('unknown_xyz'), findsOneWidget);
      // ③ 负例对照：**不得**进空态 —— 空态的语义是「真的没有」，而这里有行
      expect(find.text('还没有大纲'), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    });

    /// 构造旧缺陷的触发条件：`entities` **非空**，但**没有任何可见项**。
    ///
    /// `rejected` 是 `outline_entity` 的合法状态（`tables.dart:627/642`），
    /// 但当前**无生产写入口**（仓储只有 `approveEntity: pending→active`）
    /// ⇒ 此处经直写构造该状态；这是**构造**，不是生产路径的复现。
    Future<void> seedRejectedEntity() async {
      final id = await insertEntity(type: 'character', key: '林晚');
      await (db.update(db.outlineEntities)..where((t) => t.id.equals(id)))
          .write(const OutlineEntitiesCompanion(status: Value('rejected')));
    }

    testWidgets('#N6-4 有章节结构 + 实体全被状态过滤 ⇒ 结构照常 + 要素段分段空态', (tester) async {
      await seedRejectedEntity();
      await seedChapter(title: '第一章：进城', sortOrder: 0);

      final opened = <int>[];
      await pumpDrawer(tester, onOpenCoach: () => opened.add(1));

      expect(find.text('林晚'), findsNothing, reason: 'rejected 实体不得展示');
      // 旧行为：`entities` 非空 ⇒ 不进空态；分组又全被跳过 ⇒ **整页空白**。
      // 新行为：结构段照常渲染 + 要素段**分段**空态（文案与主行动都在）。
      expect(find.byKey(kOutlineStructureSectionKey), findsOneWidget);
      expect(find.text('第一章：进城'), findsOneWidget);
      expect(find.text('还没有大纲'), findsOneWidget);

      await tester.tap(find.byKey(const Key('outline-empty-open-coach')));
      await tester.pumpAndSettle();
      expect(opened, [1], reason: '分段空态的主行动仍可用');
    });

    testWidgets('#N6-4b 无章节结构 + 实体全被状态过滤 ⇒ 整页空态（判据的另一分支）', (tester) async {
      await seedRejectedEntity();

      await pumpDrawer(tester);

      // 两段皆空 ⇒ **整页**空态：结构段锚点**不在**，且**没有 ListView**
      // —— 这正是与 `#N6-4` 的判别点：同样「可见分组为空」，两条不同出口。
      expect(find.byKey(kOutlineStructureSectionKey), findsNothing);
      expect(find.text('还没有大纲'), findsOneWidget);
      expect(find.byType(ListView), findsNothing);
    });
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
      final impId = await repo.insertImpression(
        entityId: id,
        impression: '怕黑',
        sourceChapterNo: 0,
      );

      await pumpDrawer(tester);

      // N6：定位**章标**（不是投影段里同名的章标题）⇒ 用锚点作用域
      expect(
        find.descendant(
          of: find.byKey(outlineImpressionTagKey(impId)),
          matching: find.text('第1章'),
        ),
        findsOneWidget,
      );
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
      final impId = await repo.insertImpression(
        entityId: id,
        impression: '怕黑',
        sourceChapterNo: 2,
      );

      await pumpDrawer(tester);

      final tag = find.byKey(outlineImpressionTagKey(impId));
      expect(
        find.descendant(of: tag, matching: find.text('第2章')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tag, matching: find.text('第3章')),
        findsNothing,
        reason: '删除不重编号 ⇒ `sortOrder + 1` 在这里是错的',
      );
      // ★ 阳性对照：投影段**确实**渲染了「第3章」这个**章标题**
      //   ⇒ 证明上一条 findsNothing 是「章标不等于第3章」，
      //     而不是「第3章 全抽屉不存在」（否则该断言毫无鉴别力）
      expect(
        find.descendant(
          of: find.byKey(kOutlineStructureSectionKey),
          matching: find.text('第3章'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('#N12-F1-3 引用已删章 ⇒ 不渲染章标（不编造数字）', (tester) async {
      await seedChapters([0, 1]);
      final id = await insertEntity(type: 'character', key: '林晚');
      final impId = await repo.insertImpression(
        entityId: id,
        impression: '雨天落水',
        sourceChapterNo: 9, // 该章已不在列表中（已删 / 回收站 / 越界）
      );

      await pumpDrawer(tester);

      expect(find.text('雨天落水'), findsOneWidget, reason: '梗概本身照常展示');
      expect(
        find.byKey(outlineImpressionTagKey(impId)),
        findsNothing,
        reason: '解析失败 ⇒ 隐藏章标，而不是编造「第10章」或保留「第9章」',
      );
      // ★ 阳性对照：投影段照常渲染两个章标题 ⇒ 证明「无章标」不是整段没渲染
      final section = find.byKey(kOutlineStructureSectionKey);
      expect(
        find.descendant(of: section, matching: find.text('第1章')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: section, matching: find.text('第2章')),
        findsOneWidget,
      );
    });
  });
}
