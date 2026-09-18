// ─────────────────────────────────────────────────────────────
// character_detail_page_test — 角色详情页 Widget 测试（C78 批次3）
//
// 覆盖（方案 §6.2 / ADR-C78 §6）：
//   1. 断言按属性分组 + 来源标记 [AI]/[手]
//   2. 双灰显语义强制分离：rejected = 删除线 + 「已拒绝」；
//      stale = 无删除线 + 「章节已改写」（验收红线）
//   3. 拒绝（理由 chips）/ 修正（原条留痕 + user 断言）/ 补充（纯手动）
//   4. 查看原文：evidence 命中展示原文；反查失败如实显示「未定位到原文」
//   5. 一键清除本章旧版断言（FR-9，接 clearStaleChapter）
//   6. 并入主角色（D-5）：断言迁移 + 源名收进别名 + 源行消失
//   7. 相关事件：别名参与匹配（FR-3）；未记录章节 → 轻提示不假装跳转
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/widgets/character/character_assertion_tile.dart';
import 'package:writingcoach/widgets/character/character_detail_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late CharacterFactRepository repo;
  late ChapterRepository chapterRepo;
  late EventFactRepository eventRepo;
  late String manuscriptId;
  late String characterId;

  /// 第3章正文：供「查看原文」反查命中
  const chapter3Content = '林晚晴握紧刀柄。夜色深沉。';

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    repo = CharacterFactRepository(db);
    chapterRepo = ChapterRepository(db);
    eventRepo = EventFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品');
    await chapterRepo.createChapter(
      manuscriptId,
      title: '第三章',
      content: chapter3Content,
      sortOrder: 3,
    );
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: '林晚晴',
      firstSeenChapter: 3,
      assertions: [
        // 可定位原文：evidence 是正文子串
        // `chapterSortOrder: 3` = 本稿唯一章（sortOrder 3 ⇒ 序位 1）
        // ⇒ `N12-F3b` phase 2 起，瓦片章标由**身份**渲染 = 「第1章」。
        const CharacterAssertion(
          attribute: '性格',
          value: '冷静',
          chapter: 3,
          chapterSortOrder: 3,
          timestamp: 1000,
          evidence: '握紧刀柄',
        ),
        // 已拒绝：带理由（D-7 chips 落库形态）
        // ★ 刻意**不给身份**（存量行形态）：`chapter: 5` 是 AI 标称号，
        //   界面必须显示「章节未知」而**不得**渲染「第5章」。
        const CharacterAssertion(
          attribute: '性格',
          value: '暴躁',
          chapter: 5,
          timestamp: 2000,
          status: 'rejected',
          rejectReason: '抽取错误',
        ),
        // 旧版：章节已改写（stale）
        // ★ `chapter` 15 是 AI 标称号（该章其实不存在），`chapterSortOrder` 3 才是身份
        //   —— 正是「一列三源」的真实形态：显示走身份（第1章），反查走身份（第 1 章正文）。
        const CharacterAssertion(
          attribute: '独生子女状态',
          value: '有妹妹',
          chapter: 15,
          chapterSortOrder: 3,
          timestamp: 3000,
          chapterHash: 'old-hash',
          stale: true,
        ),
        // 用户手写
        // ★ `N12-F3b` phase 2：这里是**真实链路形态** —— 用户在弹层填的是
        //   他看得见的**序位**（1），写侧归一后存 `chapter: 1`（原值保留）
        //   ＋ `chapterSortOrder: 3`（身份）⇒ 显示「第1章」。
        const CharacterAssertion(
          attribute: '性格',
          value: '外冷内热',
          chapter: 1,
          chapterSortOrder: 3,
          timestamp: 4000,
          source: 'user',
        ),
      ],
    );
    final row = await repo.getCharacter(manuscriptId, '林晚晴');
    characterId = row!.id;
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CharacterDetailPage(
          characterId: characterId,
          manuscriptId: manuscriptId,
        ),
      ),
    );
  }

  group('首见章节口径（ADR-C95 · 批次 N12-F3a）', () {
    testWidgets('头部卡「首次登场」按**序位**解析（本稿 sortOrder=3 ⇒ 第1章）', (tester) async {
      // 本文件 setUp 只造 1 章（`sortOrder = 3`，即删过首章的稿），角色也指向 3。
      // 两种错法都要杀掉：**直渲染身份键** ⇒ 「首次登场：第3章」；
      // **`sortOrder + 1` 兜底** ⇒ 「首次登场：第4章」。正确解是序位 ⇒ 第1章。
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.textContaining('首次登场：第1章'), findsOneWidget);
      expect(
        find.textContaining('首次登场：第4章'),
        findsNothing,
        reason: '身份键 3 不得直出，也不得 +1（ADR-C95 §3）',
      );
      expect(find.textContaining('首次登场：未知'), findsNothing);
    });
  });

  Future<List<CharacterAssertion>> dbAssertions() async {
    final row = await repo.getCharacterById(characterId);
    return CharacterFactRepository.parseAssertions(row!.assertions);
  }

  group('分组与来源标记', () {
    testWidgets('属性分组渲染 + [AI]/[手] 标记 + 拒绝理由展示', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // AppBar 标题与头部卡名字各一处
      expect(find.text('林晚晴'), findsNWidgets(2));
      expect(find.text('性格 (3)'), findsOneWidget);
      expect(find.text('独生子女状态 (1)'), findsOneWidget);
      expect(find.text('AI'), findsWidgets);
      expect(find.text('手'), findsOneWidget);
      expect(find.text('理由·抽取错误'), findsOneWidget);
      expect(
        find.text('第1章'),
        findsWidgets,
        reason:
            'user 断言同样由身份渲染（N12-F3b phase 2；原断言写的是「第7章」'
            '—— 那是把旧列原值直接当展示号的旧行为）',
      );
    });
  });

  group('双灰显语义（验收红线）', () {
    testWidgets('rejected 有删除线 + 已拒绝角标；stale 无删除线 + 章节已改写角标', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      Text textOf(String value) => tester.widget<Text>(
        find.byWidgetPredicate((w) => w is Text && w.data == value),
      );

      // rejected：删除线 + 灰
      expect(textOf('暴躁').style!.decoration, TextDecoration.lineThrough);
      expect(find.text('已拒绝'), findsOneWidget);
      // stale：无删除线 + 灰 + 不同语义角标——两者不得共用一种样式
      expect(
        textOf('有妹妹').style!.decoration,
        isNot(TextDecoration.lineThrough),
      );
      expect(find.text('章节已改写'), findsOneWidget);
      // 灰显一致（同为 tertiary），区分靠删除线与角标语义
      expect(textOf('暴躁').style!.color, textOf('有妹妹').style!.color);
    });
  });

  group('拒绝 / 修正 / 补充', () {
    testWidgets('拒绝 → 理由 chip → rejected + 理由落库', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 「冷静」条的拒绝按钮（每条 actionable 断言都有「拒绝 ✗」）
      await tester.tap(find.text('拒绝 ✗').first);
      await tester.pumpAndSettle();

      await tester.tap(find.text('抽取错误'));
      await tester.pumpAndSettle();

      final list = await dbAssertions();
      final rejected = list.firstWhere((a) => a.value == '冷静');
      expect(rejected.status, 'rejected');
      expect(rejected.rejectReason, '抽取错误');
      expect(find.text('已拒绝'), findsWidgets);
    });

    testWidgets('修正 → 原条 rejected 留痕 + 新增 user 断言', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('修正').first);
      await tester.pumpAndSettle();

      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      // 表单预填原值「冷静」，改成「机警」
      await tester.enterText(dialogFields.at(1), '机警');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final list = await dbAssertions();
      expect(list.firstWhere((a) => a.value == '冷静').status, 'rejected');
      final corrected = list.firstWhere((a) => a.value == '机警');
      expect(corrected.source, 'user');
      expect(corrected.status, 'confirmed');
      expect(corrected.attribute, '性格');
    });

    testWidgets('补充 → 新增 user 断言 + 该章指纹（R-009 纯手动）', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('补充').first);
      await tester.pumpAndSettle();

      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(1), '孤儿');
      // 弹层标签是「章节（可选，如：7）」⇒ 用户填的是他看得见的**序位**。
      // 本 fixture 只有一章（`sortOrder: 3`、标题「第三章」）⇒ 序位 1 才是能
      // 解析到的那个数。此处是**判别性**选择：旧实现拿用户填的数直接查
      // `sort_order == 1` ⇒ 必然查不到 ⇒ 指纹为 null；新实现先归一到身份 3
      // ⇒ 才算得出指纹（`ADR-C96 §1.3` 第 1 行，本批修的就是它）。
      await tester.enterText(dialogFields.at(2), '1');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final list = await dbAssertions();
      final added = list.firstWhere((a) => a.value == '孤儿');
      expect(added.source, 'user');
      expect(added.chapter, 1, reason: 'R1′：用户原写的数原样保留，不被归一改写');
      expect(
        added.chapterSortOrder,
        3,
        reason: '序位 1 → 身份 sortOrder 3（ADR-C96 §2 裁定 2 的写侧归一）',
      );
      expect(
        added.chapterHash,
        isNotNull,
        reason: '身份解析成功 ⇒ 该章指纹算得出（旧实现此处恒 null）',
      );
    });
  });

  group('章标口径（N12-F3b phase 2 / 方案 S1）', () {
    testWidgets('章标只吃身份载体：有身份 ⇒ 序位；无身份 ⇒ 不编造号', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 正例：带身份的断言（`chapterSortOrder: 3`，本稿唯一章 ⇒ 序位 1）。
      expect(find.text('第1章'), findsWidgets);

      // 反例（本批的核心判据）：存量行**没有身份** ⇒ 显示「章节未知」，
      // **不得**把 `chapter` 的旧值（AI 标称号 5）渲染成章号。
      // 旧写法（`ch == null ? '章节未知' : '第$ch章'`）会渲染出「第5章」。
      expect(find.text('章节未知'), findsWidgets);
      expect(find.text('第5章'), findsNothing);
    });
  });

  // ── 判别性夹具（N12-F3b phase 2）─────────────────────────────────
  //
  // ★ 为什么要单独一组：上面 `setUp` 造的稿只有**一章**（`sortOrder: 3`），带身份那条
  //   断言 `chapter == chapterSortOrder == 3` ⇒ **两种读法渲染完全相同** ⇒ 它
  //   **杀不掉**「把旧列原值喂进 `chapterLabel`」这个错法。而 `chapter_number.dart`
  //   文件头警告的正是它：「传错参数不会报错，只会显示一个错的号」。
  //   本组改为**默认标题稿**（`sortOrder` 0/1/2 ⇔ 标称号 1/2/3），让**旧列值恰好撞上
  //   另一章的身份键** —— 这是「显示一个错的号」唯一可判别的形态。
  group('章标口径 · 判别性夹具（N12-F3b phase 2）', () {
    setUp(() async {
      // 覆盖外层 setUp 的稿（外层只有一章，造不出撞号）。
      // 默认标题 ⇒ 标称号 == 序位，于是「AI 报第2章」这种真实形态下，
      // 旧列 2 同时也是**第三章**的身份键 —— 撞号就此发生。
      manuscriptId = await ManuscriptRepository(
        db,
      ).createManuscript(title: '判别稿');
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第一章',
        content: '开场白。',
        sortOrder: 0,
      );
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第二章',
        content: '林晚晴握紧刀柄。夜色深沉。',
        sortOrder: 1,
      );
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第三章',
        content: '「有妹妹。」她低声说。',
        sortOrder: 2,
      );
      await repo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '林晚晴',
        assertions: [
          // AI 报「第2章」⇒ 写侧归一身份 = 1（序位 2）。旧列 2 撞第三章身份。
          // evidence 落在第二章正文 ⇒ 反查命中，弹层标题可判别。
          const CharacterAssertion(
            attribute: '性格',
            value: '冷静',
            chapter: 2,
            chapterSortOrder: 1,
            timestamp: 1000,
            evidence: '握紧刀柄',
          ),
          // 同属性第二个不同值 ⇒ F05 冲突卡出条（该卡自渲染章标）
          const CharacterAssertion(
            attribute: '性格',
            value: '外冷内热',
            chapter: 2,
            chapterSortOrder: 1,
            timestamp: 2000,
          ),
          // stale ⇒ 清除按钮（key 必须用身份 1 ⇒ 序位 2）
          const CharacterAssertion(
            attribute: '独生子女状态',
            value: '有妹妹',
            chapter: 2,
            chapterSortOrder: 1,
            timestamp: 3000,
            chapterHash: 'old-hash',
            stale: true,
          ),
          // 存量行：**无身份**；旧列 2 撞第三章身份 ⇒ 必须「章节未知」
          const CharacterAssertion(
            attribute: '职业',
            value: '捕快',
            chapter: 2,
            timestamp: 4000,
          ),
        ],
      );
      characterId = (await repo.getCharacter(manuscriptId, '林晚晴'))!.id;
    });

    /// 本组全部判据的锚点：旧列 2 撞的是**第三章**（序位 3）。
    /// 任何「第3章」的出现都等于「有人又把旧列当展示号了」。
    testWidgets('瓦片章标只吃身份：存量行的旧列撞号不得被渲染出来', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      final aiTile = find.widgetWithText(CharacterAssertionTile, '冷静');
      await tester.scrollUntilVisible(
        aiTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: aiTile, matching: find.text('第2章')),
        findsOneWidget,
        reason: '身份 1 ⇒ 序位 2；**不是**旧列 2 撞上的「第3章」',
      );

      final legacyTile = find.widgetWithText(CharacterAssertionTile, '捕快');
      await tester.scrollUntilVisible(
        legacyTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(of: legacyTile, matching: find.text('章节未知')),
        findsOneWidget,
        reason: '存量行无身份 ⇒ 方案 S1：不编造（旧列 2 是 AI 标称号，不是身份）',
      );
      expect(
        find.descendant(of: legacyTile, matching: find.text('第3章')),
        findsNothing,
        reason: '把旧列喂进 chapterLabel ⇔ map[2] = 3 ⇔ 「第3章」',
      );
    });

    testWidgets('原文摘录标题的章标也只吃身份', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      final tile = find.widgetWithText(CharacterAssertionTile, '冷静');
      final link = find.descendant(of: tile, matching: find.text('查看原文'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // ★ 必须再 `ensureVisible`：`scrollUntilVisible` 只保证控件**被构建并进入布局**，
      //   不保证它落在视口内。实测它停在 y=631 —— **超出 800×600 视口** ⇒ `tap`
      //   **静默打空**（Flutter 只在日志里 warn，不抛异常），弹层没开 ⇒ 随后的断言
      //   失败**看起来像功能缺陷**。踩过一次，记在此处。
      await tester.ensureVisible(link);
      await tester.pumpAndSettle();
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.text('原文摘录（第2章）'), findsOneWidget);
      expect(find.textContaining('原文摘录（第3章）'), findsNothing);
    });

    testWidgets('F05 冲突卡自渲染的章标只吃身份', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 措辞由 sections 自渲染，**不复用** ConflictObservation.description ——
      // 那条描述走的是旧列 `a.chapter`（conflict_detector.dart:258-261），
      // 正是本批要与之剥离的口径。故此断言同时守住「措辞分家」。
      expect(find.text('性格：第2章「冷静」 → 第2章「外冷内热」'), findsOneWidget);
    });

    testWidgets('清除按钮与确认框的章标只吃身份', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('清除第2章旧版断言 (1)'), findsOneWidget);
      await tester.tap(find.text('清除第2章旧版断言 (1)'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('删除第2章的全部旧版断言'),
        findsOneWidget,
        reason: '确认框文案同样只吃身份（本批之前无任何断言覆盖这一段）',
      );
      expect(find.textContaining('删除第3章'), findsNothing);

      // 本用例只验文案 ⇒ 取消，不落库
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    });

    testWidgets('相关事件的章标只吃身份', (tester) async {
      // AI 报「1」（序位 1 = 第一章，其标称号也是 1）⇒ 写侧归一身份 = 0。
      // 旧列 1 撞**第二章**身份 ⇒ 喂错列会渲染「第2章」；正确渲染是「第1章」。
      await eventRepo.upsertEvent(
        manuscriptId: manuscriptId,
        name: '巷口重逢',
        eventType: '转折',
        chapter: 1,
        chapterSortOrder: 0,
        participants: ['林晚晴'],
        description: '林晚晴在巷口认出故人',
      );
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('相关事件 (1)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      // 断言瓦片全部渲染「第2章」（身份 1）、存量行「章节未知」、清除按钮与冲突卡
      // 都是组合串 ⇒ 全屏**只有**这一处渲染出精确的「第1章」。
      expect(
        find.text('第1章'),
        findsOneWidget,
        reason: '事件身份 0 ⇒ 序位 1；旧列 1 会撞成「第2章」',
      );
    });
  });

  group('查看原文（诚实降级）', () {
    testWidgets('evidence 命中 → 弹层展示原文', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看原文').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('原文摘录'), findsOneWidget);
      expect(find.textContaining('握紧刀柄'), findsOneWidget);
      expect(find.text('未定位到原文'), findsNothing);
    });

    testWidgets('反查失败 → 如实显示「未定位到原文」', (tester) async {
      // evidence 缺失 ⇒ 走「该断言所属章」正文反查；该条身份 = 第 1 章
      // （`chapterSortOrder: 3`），而正文里没有「有妹妹」⇒ 反查必然失败。
      // `N12-F3b` phase 2：反查用**身份**，不再拿 AI 标称号 15 去查库。
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 分组顺序：性格组（冷静/暴躁/外冷内热）在前，独生子女状态组（有妹妹）
      // 在后 → 「查看原文」第 4 个即「有妹妹」条；先滚到可见再点
      final target = find.text('查看原文').at(3);
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();

      expect(find.text('未定位到原文'), findsOneWidget);
    });
  });

  group('FR-9 清除本章旧版断言', () {
    testWidgets('按钮显示章号与条数 → 确认 → stale 断言删除', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // `N12-F3b` phase 2：按钮上的章标**只吃身份**（`chapterSortOrder: 3` ⇒ 序位 1），
      // **不渲染** `chapter` 里的 AI 标称号（15）—— 那既不存在于本章列表，
      // 渲染出来还会让用户以为「有一章叫第15章」。
      expect(find.text('清除第1章旧版断言 (1)'), findsOneWidget);
      await tester.tap(find.text('清除第1章旧版断言 (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();

      final list = await dbAssertions();
      expect(list.where((a) => a.value == '有妹妹'), isEmpty);
      expect(find.text('清除第1章旧版断言 (1)'), findsNothing);
      // 其他断言不受影响
      expect(list.where((a) => a.value == '冷静'), isNotEmpty);
    });
  });

  group('并入主角色（D-5）', () {
    testWidgets('选源 → 确认 → 断言迁移 + 源名收进别名 + 源行消失', (tester) async {
      await repo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: '阿晴',
        firstSeenChapter: 4,
        assertions: [
          const CharacterAssertion(
            attribute: '身份',
            value: '捕快之女',
            chapter: 4,
            timestamp: 5000,
          ),
        ],
      );
      final source = await repo.getCharacter(manuscriptId, '阿晴');
      final target = await repo.getCharacter(manuscriptId, '林晚晴');
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('并入主角色'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('阿晴'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('并入'));
      await tester.pumpAndSettle();

      final targetRow = await repo.getCharacterById(target!.id);
      final targetAssertions = CharacterFactRepository.parseAssertions(
        targetRow!.assertions,
      );
      expect(
        targetAssertions.any((a) => a.attribute == '身份'),
        isTrue,
        reason: '源行断言迁入目标行',
      );
      expect(parseJsonStringList(targetRow.aliases), contains('阿晴'));
      final sourceRow = await repo.getCharacterById(source!.id);
      expect(sourceRow!.status, 'merged', reason: '源行标记制软删');
    });
  });

  group('相关事件（FR-3/FR-4）', () {
    testWidgets('别名参与事件匹配；未记录章节 → 轻提示不假装跳转', (tester) async {
      // participants 用别名「阿晴」——「主名 ∪ 别名」匹配应命中
      await eventRepo.upsertEvent(
        manuscriptId: manuscriptId,
        name: '巷口重逢',
        eventType: '转折',
        participants: ['阿晴'],
        description: '林晚晴在巷口认出故人',
      );
      // 目标行的别名收编「阿晴」
      final row = await repo.getCharacterById(characterId);
      await (db.update(db.characterFacts)..where((t) => t.id.equals(row!.id)))
          .write(CharacterFactsCompanion(aliases: Value('["阿晴"]')));

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 相关事件区在 ListView 尾部（视口外不构建）→ 滚动到可见
      await tester.scrollUntilVisible(
        find.text('相关事件 (1)'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('相关事件 (1)'), findsOneWidget);
      expect(find.text('巷口重逢'), findsOneWidget);
      expect(find.text('转折'), findsOneWidget);

      // 条目仍可能压在视口底边外 → 先确保可见再点
      final eventTile = find.text('巷口重逢');
      await tester.ensureVisible(eventTile);
      await tester.pumpAndSettle();
      await tester.tap(eventTile);
      await tester.pumpAndSettle();

      expect(find.text('该事件未记录章节'), findsOneWidget);
    });
  });
}
