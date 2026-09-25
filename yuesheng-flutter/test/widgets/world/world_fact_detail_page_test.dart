// ─────────────────────────────────────────────────────────────
// world_fact_detail_page_test — 批次 W1 世界观主题详情页 Widget 测试
//
// 覆盖（对应 W1-T03 验收标准）：
//   ① 展示全部断言（属性 / 取值 / 章节 / 是否有依据），无改写 / 删除按钮（O-2）
//   ② ＋ 追加设定：保存后断言数 +1，历史不覆盖
//   ③ 归档本主题：确认弹窗 → §6-F SnackBar + 返回
//   ④ 主题不存在：§6-G SnackBar + 返回
//   ⑤ 恢复本主题（Q1）：软恢复 + SnackBar + 返回
//
// `N12-F3c` 追加（章号口径，本页三处章标同时改吃身份）：
//   ⑥ 头部卡 / 断言瓦片 / 时间轴 —— 章标一律只由**身份载体**
//      （`first_seen_chapter` / `chapterSortOrder`）经 `chapterLabel` 解析；
//      旧列 `assertion.chapter`（**用户原写的数**）**不得**再作展示号。
//   ⑦ 世界观侧**开始出时间轴节点** —— `N12-F3b` phase 3 当时世界观无身份来源，
//      该区块恒空；本批写侧归一后，首个身份来源出现（见 `chapter_number.dart` 头）。
//
// ★ 夹具关键（`DECISIONS §4-28`）：章节刻意取 `sortOrder` 5 / 7 / 9（序位 1 / 2 / 3），
//   且旧列刻意填一个**撞得上身份**的数（如 5 ⇒ 第1章）—— 若实现仍把旧列当身份喂进
//   `chapterLabel`，界面会渲染出**一个错的号**（「第1章」而非「第2章」）。
//   在默认稿（身份 == 序位 − 1）上两种实现**渲染逐字相同** ⇒ 用例无鉴别力。
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/widgets/setting/setting_progressions_section.dart';
import 'package:writingcoach/features/world/world_fact_detail_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late WorldFactRepository repo;
  late String manuscriptId;

  /// 三章，身份 5 / 7 / 9 ⇔ 序位 1 / 2 / 3（模拟「删过首章、删除不重编号」的稿）。
  const identityOfChapter1 = 5;
  const identityOfChapter2 = 7;
  const identityOfChapter3 = 9;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    repo = WorldFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品');
    final chapterRepo = ChapterRepository(db);
    await chapterRepo.createChapter(
      manuscriptId,
      title: '第一章',
      content: 'a',
      sortOrder: identityOfChapter1,
    );
    await chapterRepo.createChapter(
      manuscriptId,
      title: '第二章',
      content: 'b',
      sortOrder: identityOfChapter2,
    );
    await chapterRepo.createChapter(
      manuscriptId,
      title: '第三章',
      content: 'c',
      sortOrder: identityOfChapter3,
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  /// 宿主：先渲染一个「open」按钮，点击后 push 详情页（使 pop 有落点）。
  Widget buildHost(String worldId) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Builder(
          builder: (c) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => WorldFactDetailPage(
                      worldId: worldId,
                      manuscriptId: manuscriptId,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDetail(WidgetTester tester, String worldId) async {
    await tester.pumpWidget(buildHost(worldId));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// ★ 放大视口后再开详情页。
  ///
  /// 页面是 `ListView`（**懒构建**）：落在视口 + cacheExtent 之外的子树**根本不 build**
  /// ⇒ 「没找到」与「没构建」外观完全相同（`DECISIONS §4-34`）。
  /// 页面级「区块有没有」类判据必须先放大视口，再看结论。
  Future<void> openDetailWide(WidgetTester tester, String worldId) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await openDetail(tester, worldId);
  }

  /// 只在**时间轴内部**找文本 —— 瓦片与头部卡也渲染章标，不限定会假红。
  Finder inTimeline(String text) => find.descendant(
    of: find.byType(SettingProgressionsSection),
    matching: find.text(text),
  );

  testWidgets('① 展示全部断言且无改写 / 删除按钮（O-2）', (tester) async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      firstSeenChapter: identityOfChapter2, // 身份 7 ⇒ 序位 2
      assertions: [
        // ★ 判别性：旧列 5 是**用户原写的数**（R1′ 不覆盖），恰好撞上**第1章**的身份。
        //   仍读旧列的实现会把这条渲染成「第1章 · ✓ 有依据」。
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '稀薄',
          chapter: 5,
          chapterSortOrder: identityOfChapter2, // 7 ⇒ 第2章（正解）
          timestamp: 100,
          evidence: '这方天地灵气稀薄',
        ),
        // 旧列 15 = AI 抄来的**标称号**，两章都不存在 ⇒ 两种错法都解析不到
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '充沛',
          chapter: 15,
          chapterSortOrder: identityOfChapter3, // 9 ⇒ 第3章
          timestamp: 200,
        ),
      ],
    );
    final id = (await repo.getWorld(manuscriptId, '灵气体系'))!.id;
    await openDetail(tester, id);

    expect(find.text('灵气体系'), findsOneWidget);
    expect(find.text('灵气浓度：稀薄'), findsOneWidget);
    expect(find.text('灵气浓度：充沛'), findsOneWidget);
    // 头部卡的「首次提出」同样只吃身份（7 ⇒ 第2章）
    expect(find.text('第2章首次提出 · 共 2 条设定'), findsOneWidget);
    expect(find.text('第2章 · ✓ 有依据'), findsOneWidget);
    expect(find.text('第3章 · — 无依据'), findsOneWidget);
    expect(
      find.text('第1章 · ✓ 有依据'),
      findsNothing,
      reason:
          '把旧列 5 喂进 chapterLabel ⇔ map[5] = 1 ⇔ 「第1章」——'
          '读者会以为这条设定出自第1章（`chapter_number.dart` 头：「传错参数不报错，只显示一个错的号」）',
    );
    expect(
      find.text('第15章 · — 无依据'),
      findsNothing,
      reason: '标称号 15 不是身份，本稿也不存在这一章',
    );
    // O-2：本批无单条改写 / 删除入口
    expect(find.text('删除'), findsNothing);
    expect(find.text('改写'), findsNothing);
  });

  testWidgets('② ＋ 追加设定 → 断言数 +1，历史不覆盖（章号写侧归一）', (tester) async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      assertions: [
        CharacterAssertion(
          attribute: '形态',
          value: '气态',
          chapter: 1, // 用户原写的序位
          chapterSortOrder: identityOfChapter1, // 身份 5 ⇒ 第1章
          timestamp: 100,
        ),
      ],
    );
    final id = (await repo.getWorld(manuscriptId, '灵气体系'))!.id;
    await openDetail(tester, id);
    expect(find.text('形态：气态'), findsOneWidget);

    await tester.tap(find.text('＋ 追加设定'));
    await tester.pumpAndSettle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '灵气浓度'); // 属性
    await tester.enterText(fields.at(1), '充沛'); // 取值
    await tester.enterText(fields.at(2), '2'); // 章节 = 用户看得见的**序位**
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('形态：气态'), findsOneWidget, reason: '历史断言不被覆盖');
    expect(find.text('灵气浓度：充沛'), findsOneWidget, reason: '新断言出现');
    expect(
      find.text('第2章 · — 无依据'),
      findsOneWidget,
      reason: '新条按身份 7 渲染成「第2章」（页内写路径与列表侧同口径）',
    );

    final added = WorldFactRepository.parseAssertions(
      (await repo.getWorld(manuscriptId, '灵气体系'))!.assertions,
    ).firstWhere((a) => a.value == '充沛');
    expect(added.chapter, 2, reason: 'R1′：用户原写的数原样保留在旧列');
    expect(
      added.chapterSortOrder,
      identityOfChapter2,
      reason: '序位 2 → 身份 7（不归一则存成 2，真稿上会被读成「sortOrder==2 的那章」）',
    );
  });

  testWidgets('③ 归档本主题 → 确认 → §6-F SnackBar + 返回', (tester) async {
    await repo.upsertWorld(manuscriptId: manuscriptId, name: '灵气体系');
    final id = (await repo.getWorld(manuscriptId, '灵气体系'))!.id;
    await openDetail(tester, id);

    await tester.tap(find.text('归档本主题'));
    await tester.pumpAndSettle();
    expect(find.text('归档设定主题'), findsOneWidget);

    await tester.tap(find.text('归档'));
    await tester.pumpAndSettle();

    expect(find.text('已归档「灵气体系」'), findsOneWidget);
    expect(find.text('open'), findsOneWidget, reason: '归档后应返回列表');
    final row = await repo.getWorld(manuscriptId, '灵气体系');
    expect(row!.status, 'archived');
  });

  testWidgets('④ 主题已不存在 → §6-G SnackBar + 返回', (tester) async {
    await openDetail(tester, 'no-such-id');
    expect(find.text('该设定主题已不存在'), findsOneWidget);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('⑤ 恢复本主题（Q1）→ 软恢复 + SnackBar + 返回', (tester) async {
    await repo.upsertWorld(manuscriptId: manuscriptId, name: '灵气体系');
    final row = await repo.getWorld(manuscriptId, '灵气体系');
    final id = row!.id;
    await (db.update(db.worldFacts)..where((t) => t.id.equals(id))).write(
      const WorldFactsCompanion(status: Value('archived')),
    );
    await openDetail(tester, id);

    expect(find.text('恢复本主题'), findsOneWidget);
    await tester.tap(find.text('恢复本主题'));
    await tester.pumpAndSettle();

    expect(find.text('已恢复「灵气体系」'), findsOneWidget);
    expect(find.text('open'), findsOneWidget);
    expect((await repo.getWorld(manuscriptId, '灵气体系'))!.status, 'active');
  });

  // ── `N12-F3c`：世界观侧时间轴**开始出节点** ──────────────────────
  //
  // `N12-F3b` phase 3 把时间轴改成只吃身份后，世界观侧两个来源都不是身份载体
  // ⇒ 该区块**恒为空**（当时 `_buildProgressionsSection` 刻意不传 `firstSeenChapter`）。
  // 本批写侧归一落地后该前提消失，故补一条**集成**判据：详情页确实把身份喂进去了。
  // 组件级行为（无身份不进桶 / 已删章 ⇒ 章节未知）已由 `setting_progressions_ui_test.dart` 覆盖。
  testWidgets('⑥ N12-F3c：时间轴开始出节点，且只吃身份（旧列不进桶）', (tester) async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      firstSeenChapter: identityOfChapter2, // 7 ⇒ 第2章
      assertions: [
        // 身份 9 ⇒ 第3章；旧列 15 是标称号，喂错列会渲染出「第15章」
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '稀薄',
          chapter: 15,
          chapterSortOrder: identityOfChapter3,
          timestamp: 100,
        ),
        // 存量行形态：**只有旧列** ⇒ 不进时间轴（瓦片侧仍照常显示「章节未知」）
        CharacterAssertion(
          attribute: '存量',
          value: '无身份',
          chapter: 3,
          timestamp: 200,
        ),
      ],
    );
    final id = (await repo.getWorld(manuscriptId, '灵气体系'))!.id;
    await openDetailWide(tester, id);

    // 阳性对照：区块确实被构建（否则下面的 findsNothing 全是假绿）
    expect(find.byType(SettingProgressionsSection), findsOneWidget);
    expect(inTimeline('章节演进 (2 章)'), findsOneWidget);
    expect(inTimeline('第2章'), findsOneWidget, reason: '首见章身份 7');
    expect(inTimeline('首次出现'), findsOneWidget);
    expect(inTimeline('第3章'), findsOneWidget, reason: '断言身份 9');
    expect(inTimeline('灵气浓度: 稀薄'), findsOneWidget);
    expect(
      inTimeline('存量: 无身份'),
      findsNothing,
      reason: '该条旧列为 3（**有值**）⇒ 判的正是「筛选依据是身份而非旧列」',
    );
    expect(inTimeline('第15章'), findsNothing, reason: '标称号不得被当身份');
    expect(inTimeline('章节未知'), findsNothing, reason: '位置有序视图**不建未知桶**（§4-33）');

    // 瓦片侧同一份数据：**逐条陈列**的视图位置不承载语义 ⇒ 无身份的行照常可见、
    // 就地标注「章节未知」（与时间轴「不进桶」是不同的落地方式，同一 `S1` 根源）。
    final legacyTile = find.widgetWithText(ListTile, '存量：无身份');
    expect(legacyTile, findsOneWidget);
    // ★ 断言**限定在瓦片内**，不用全局计数：全局计数会与另一条瓦片隐式耦合
    //   （正常实现下那条渲染「第3章」⇒ 恰好 1；退化成读旧列时两条都成「章节未知」
    //   ⇒ 计数变 2 而红）。实测：`negctl_n12f3c.py` 的 `NEG-W` 正是这样额外带红了
    //   本用例 —— 红得对，但**理由藏在计数里**，故改为显式两条。
    expect(
      find.descendant(of: legacyTile, matching: find.text('章节未知 · — 无依据')),
      findsOneWidget,
    );
    expect(
      find.text('第3章 · — 无依据'),
      findsOneWidget,
      reason: '判别点：该条身份 9 ⇒ 第3章；旧列 15 在 map 里解析不出任何章',
    );
  });
}
