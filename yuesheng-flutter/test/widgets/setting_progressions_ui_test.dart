// ─────────────────────────────────────────────────────────────
// setting_progressions_ui_test — Progressions 时间轴 UI 测试（第三批）
//
// ★ `N12-F3b` phase 3（2026-09-18）：章标由**身份**渲染（`chapterLabel`）。
//   夹具按此重写为**判别性** —— 旧列值与身份**故意不一致**，两种实现渲染结果不同
//   （教训见 `DECISIONS §4-28`：零鉴别力的夹具改错了也全绿）。
//   ⚠️ 文案随之由 `第 N 章`（**带空格**）变为 `第N章` —— 全仓其余章标一直是后者，
//      本区块此前是唯一例外（`chapterLabel` 是口径的唯一实现点）。
//   ⚠️ 断言一律**限定在时间轴内**：瓦片与分组头也渲染同样的章标（`第1章`），
//      不限定会 `findsOneWidget` 假红。
//   ⚠️ 页面级用例必须**放大视口**（见 `pumpPage`）：`ListView` 懒构建，
//      视口外的时间轴**根本没 build** ⇒ 「没找到」与「没构建」同貌。
//
//   1. 页面级：章标只吃身份（旧列值不同也不影响）+ 存量行不进时间轴
//   2. 页面级：无身份数据 → 区块隐藏（存量旧列不算数据）
//   3. 组件级：身份在、map 解析不出（已删章）→ 「章节未知」，不编造数字
//   4. 组件级：空输入 → 隐藏
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/features/character/character_detail_page.dart';
import 'package:writingcoach/features/app_settings/setting_progressions_section.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late ManuscriptRepository msRepo;
  late ChapterRepository chapterRepo;
  late CharacterFactRepository charRepo;
  late String manuscriptId;
  late String charId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    msRepo = ManuscriptRepository(db);
    chapterRepo = ChapterRepository(db);
    charRepo = CharacterFactRepository(db);
    manuscriptId = await msRepo.createManuscript(title: 'Progressions UI 测试作品');
    // 默认标题 3 章（`sort_order` 0/1/2 ⇔ 标称号 1/2/3）—— 身份与标称号**不同基**，
    // 判别性由此成立：把旧列当展示号渲染，结果必然与按身份解析不同。
    await chapterRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: '第一段。',
      sortOrder: 0,
    );
    await chapterRepo.createChapter(
      manuscriptId,
      title: '第二章',
      content: '第二段。',
      sortOrder: 1,
    );
    await chapterRepo.createChapter(
      manuscriptId,
      title: '第三章',
      content: '第三段。',
      sortOrder: 2,
    );
    // 首见 = **身份 0**（`N12-F3a` 起该列单语义 = 身份）⇒ 序位 1 ⇒ 「第1章」
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      firstSeenChapter: 0,
    );
    charId = (await charRepo.getCharacter(manuscriptId, '林晚'))!.id;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// 页面级挂载；[id] 缺省用 setUp 里的「林晚」。
  Widget buildPage([String? id]) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CharacterDetailPage(
          characterId: id ?? charId,
          manuscriptId: manuscriptId,
        ),
      ),
    );
  }

  /// ★ 放大视口后再 pump 页面。
  ///
  /// `ListView` **懒构建**：落在视口（+cacheExtent）之外的子树**根本不会 build**。
  /// ⇒ 本文件里「找不到时间轴」既可能是**真的没有**、也可能是**还没构建**
  ///   —— 两种外观完全相同（同族陷阱：`tap` 在视口外**静默打空**，
  ///   `DECISIONS §4-31`）。首跑即栽在此处：`#1` 断言时间轴标题报
  ///   「Found 0 widgets … descending from SettingProgressionsSection」。
  /// ⇒ 页面级用例一律先把视口放大到能容纳整页，使「有 / 无」都可判定。
  Future<void> pumpPage(WidgetTester tester, [String? id]) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(buildPage(id));
    await tester.pumpAndSettle();
  }

  /// 只在**时间轴内部**找文本 —— 瓦片 / 分组头也渲染章标，不限定会假红。
  Finder inTimeline(String text) => find.descendant(
    of: find.byType(SettingProgressionsSection),
    matching: find.text(text),
  );

  testWidgets('#1 章标只吃身份：旧列值不同也不影响（判别性）', (tester) async {
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚',
      assertions: [
        // 身份 0 ⇒ 「第1章」。旧列故意写 3 —— 仍读旧列的实现会渲染「第3章」
        const CharacterAssertion(
          attribute: '出身',
          value: '临安',
          chapter: 3,
          chapterSortOrder: 0,
          timestamp: 0,
        ),
        // 身份 2 ⇒ 「第3章」。旧列故意写 9 —— 仍读旧列会渲染「第9章」
        const CharacterAssertion(
          attribute: '兵器',
          value: '绣春刀',
          chapter: 9,
          chapterSortOrder: 2,
          timestamp: 0,
        ),
        // 存量行：只有旧列、无身份 ⇒ **不进时间轴**（仍读旧列会多出一个「第2章」节点）
        const CharacterAssertion(
          attribute: '存量',
          value: '无身份',
          chapter: 2,
          timestamp: 0,
        ),
      ],
    );
    await pumpPage(tester);

    // 阳性对照：区块**确实被构建**（否则下面的 findsNothing 全是假绿）
    expect(find.byType(SettingProgressionsSection), findsOneWidget);

    // 两个节点：身份 0（首见并入）与身份 2
    expect(inTimeline('章节演进 (2 章)'), findsOneWidget);
    expect(inTimeline('第1章'), findsOneWidget);
    expect(inTimeline('第3章'), findsOneWidget);
    expect(inTimeline('首次出现'), findsOneWidget);
    expect(inTimeline('出身: 临安'), findsOneWidget);
    expect(inTimeline('兵器: 绣春刀'), findsOneWidget);

    expect(inTimeline('第9章'), findsNothing, reason: '旧列 9 不得被当展示号');
    expect(inTimeline('第2章'), findsNothing, reason: '存量行无身份 ⇒ 不出节点');
    expect(
      inTimeline('存量: 无身份'),
      findsNothing,
      reason: '该条旧列为 2（**有值**）⇒ 本条判定的正是「筛选依据是身份而非旧列」',
    );
  });

  testWidgets('#2 无身份数据 → 区块隐藏（存量旧列不算数据）', (tester) async {
    // 另建一个角色：无 `first_seen_chapter`，且只有「带旧列、无身份」的断言
    await charRepo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '沈砚',
      assertions: [
        const CharacterAssertion(
          attribute: '存量',
          value: '只有旧列',
          chapter: 2,
          timestamp: 0,
        ),
      ],
    );
    final otherId = (await charRepo.getCharacter(manuscriptId, '沈砚'))!.id;

    await pumpPage(tester, otherId);
    // 阳性对照：页面确实渲染了（否则下面的 findsNothing 只是「页面没起来」）
    expect(find.text('沈砚'), findsWidgets, reason: '页面未渲染时 findsNothing 是假绿');
    expect(
      find.textContaining('章节演进'),
      findsNothing,
      reason: '仍读旧列的实现会在这里渲染出「第2章」节点',
    );
  });

  testWidgets('#3 身份在、map 解析不出（已删章）→ 「章节未知」', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SettingProgressionsSection(
                assertions: [],
                firstSeenChapter: 7, // 不在 map 里：已删 / 回收站 / 越界
                chapterNoMap: {0: 1, 1: 2},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('章节演进'), findsOneWidget);
    expect(find.text('章节未知'), findsOneWidget);
    expect(
      find.text('第8章'),
      findsNothing,
      reason: '禁止用 sortOrder + 1 兜底（ADR-C95 口径 3）',
    );
  });

  testWidgets('#4 空输入 → 隐藏', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SettingProgressionsSection(assertions: [], chapterNoMap: {}),
          ),
        ),
      ),
    );
    expect(find.textContaining('章节演进'), findsNothing);
  });
}
