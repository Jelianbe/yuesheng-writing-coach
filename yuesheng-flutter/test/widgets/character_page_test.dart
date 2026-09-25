// ─────────────────────────────────────────────────────────────
// character_page_test — 角色列表页 Widget 测试（C78 批次3，FR-1/7/10）
//
// 覆盖：
//   1. 列表渲染：名字 / 首见章节 / 断言摘要
//   2. merged 源行默认不显示（合并后列表只留目标行）
//   3. 搜索：主名 / 别名 / 属性值命中过滤
//   4. 排序：首见章节升序 ↔ 最近更新降序
//   5. FR-10 最近批次视图：sinceTimestamp 过滤 + 「+N 新」角标 + 横幅如实标注
//   6. 新建角色（FR-7）→ 落库并出现在列表
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:writingcoach/features/character/character_page.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late CharacterFactRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    repo = CharacterFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<void> seedCharacter(
    String name, {
    int? firstSeen,
    required List<CharacterAssertion> assertions,
    int? updatedAt,
  }) async {
    await repo.upsertCharacter(
      manuscriptId: manuscriptId,
      name: name,
      firstSeenChapter: firstSeen,
      assertions: assertions,
    );
    if (updatedAt != null) {
      // 直接改 updatedAt 以构造「最近更新」排序差异（列表页只读不改）
      final row = await repo.getCharacter(manuscriptId, name);
      await (db.update(db.characterFacts)..where((t) => t.id.equals(row!.id)))
          .write(CharacterFactsCompanion(updatedAt: Value(updatedAt)));
    }
  }

  /// 播种章节（`sortOrder` 即**身份键**：0 基、删除不重编号、可空洞）。
  ///
  /// ADR-C95 / `N12-F3a`：`first_seen_chapter` 存的是身份键，展示要经**当前章节列表**
  /// 解析成序位 ⇒ 「首见章节」相关用例**必须**先有真实章节，否则断言的是一个
  /// 解析不出来的值（旧实现在这种夹具上「恰好」也能显示数字，是新网要杀掉的形态）。
  Future<void> seedChapters(List<int> sortOrders) async {
    final chapterRepo = ChapterRepository(db);
    for (final o in sortOrders) {
      await chapterRepo.createChapter(
        manuscriptId,
        title: '第${o + 1}章',
        sortOrder: o,
      );
    }
  }

  Widget buildHost({int? since}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: CharacterPage(manuscriptId: manuscriptId, sinceTimestamp: since),
      ),
    );
  }

  CharacterAssertion assertion(
    String attribute,
    String value, {
    int? chapter,
    int timestamp = 1000,
  }) {
    return CharacterAssertion(
      attribute: attribute,
      value: value,
      chapter: chapter,
      timestamp: timestamp,
    );
  }

  /// 列表条目文本（排除搜索框 EditableText 里的查询词）
  Finder tile(String s) =>
      find.byWidgetPredicate((w) => w is Text && w.data == s);

  group('列表渲染', () {
    testWidgets('名字 / 首见章节 / 断言摘要展示', (tester) async {
      // ADR-C95 / `N12-F3a`：`firstSeen` 是**身份键**（`chapter.sortOrder`），展示必须
      // 经章节列表解析。旧夹具写 `3` 而该稿**一章都没有** ⇒ 该值不可解析，是旧实现
      // 直渲染才「恰好」显示「第3章登场」—— **夹具本身在编码缺陷**。
      // 现改为「三章 + 序位第 3 的章（sortOrder=2）」，**断言一字未动**。
      await seedChapters([0, 1, 2]);
      await seedCharacter(
        '林晚晴',
        firstSeen: 2,
        assertions: [
          assertion('性格', '冷静', chapter: 3),
          assertion('职业', '捕快', chapter: 3),
        ],
      );
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('角色 (1)'), findsOneWidget);
      expect(find.text('林晚晴'), findsOneWidget);
      expect(find.text('第3章登场'), findsOneWidget);
      expect(find.text('性格·冷静 / 职业·捕快'), findsOneWidget);
    });

    testWidgets('merged 源行不显示，断言归并到目标行', (tester) async {
      await seedCharacter('林晚晴', firstSeen: 3, assertions: []);
      await seedCharacter('阿晴', firstSeen: 3, assertions: []);
      final source = await repo.getCharacter(manuscriptId, '阿晴');
      final target = await repo.getCharacter(manuscriptId, '林晚晴');
      await repo.mergeCharacter(targetId: target!.id, sourceId: source!.id);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('角色 (1)'), findsOneWidget);
      expect(find.text('林晚晴'), findsOneWidget);
      expect(
        find.text('阿晴'),
        findsNothing,
        reason: '合并后源行不进列表（status=merged 过滤）',
      );
    });
  });

  group('空态与控件收敛（2026-09-20 观感批）', () {
    // 本轮改造的核心：**空态下搜索框 / 排序条 / 新建按钮不再占位**。
    // 改造前实测它们占掉可区 252.0/913.0 dp = 27.6%，把唯一的空白区压在下面。
    //
    // ★ 本组必须**成对**断言（空态无 / 有数据有）：只断言「空态下不存在」
    //   的话，一个「永远不渲染这三个控件」的退化实现也能全绿 —— 那是把
    //   功能删掉冒充改进。

    testWidgets('空态：搜索框 / 排序条 / 新建按钮 均不渲染；主 CTA 存在', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('还没有角色'), findsOneWidget);
      // 三个「用不上」的控件必须收起
      expect(find.byType(TextField), findsNothing, reason: '零数据时搜索框无从搜索，不应占位');
      expect(find.text('排序'), findsNothing, reason: '零数据时排序条无意义');
      expect(find.text('新建角色'), findsNothing, reason: '改为只在空态 CTA 里出现一次');
      // 空态主打动作：一个够显眼的主 CTA
      expect(find.text('＋ 新建角色'), findsOneWidget);
    });

    testWidgets('有数据：三个控件回归（负例，防「一律不渲染」冒充改进）', (tester) async {
      await seedCharacter('林晚晴', firstSeen: 3, assertions: []);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('还没有角色'), findsNothing);
      expect(find.byType(TextField), findsOneWidget, reason: '有数据时搜索可用了');
      expect(find.text('排序'), findsOneWidget);
      expect(find.text('新建角色'), findsOneWidget);
      // 有数据时不该出现空态的 CTA 文案（两个按钮文案刻意不同，便于区分）
      expect(find.text('＋ 新建角色'), findsNothing);
    });

    testWidgets('搜索无命中：走「筛选空态」而非「首见空态」', (tester) async {
      await seedCharacter('林晚晴', firstSeen: 3, assertions: []);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '查无此人');
      await tester.pumpAndSettle();

      expect(find.text('没有匹配「查无此人」的结果'), findsOneWidget);
      // ★ 鉴别点：不能掉回首见空态（那会谎称「还没有角色」，而库里明明有）
      expect(find.text('还没有角色'), findsNothing);
    });

    testWidgets('筛选空态的「清除筛选」→ 回到全量且控件仍在', (tester) async {
      await seedCharacter('林晚晴', firstSeen: 3, assertions: []);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '查无此人');
      await tester.pumpAndSettle();
      await tester.tap(find.text('清除筛选'));
      await tester.pumpAndSettle();

      expect(find.text('林晚晴'), findsOneWidget);
      expect(find.text('没有匹配「查无此人」的结果'), findsNothing);
    });

    testWidgets('待裁决卡不受「控件收起」影响（库空但有待裁决）', (tester) async {
      // ★ 这是一条**防误伤**用例。`listPendingAssertions` 经 `listCharacters`
      //   默认排除 merged 行 ⇒ 完全可能出现「_characters 空、_pending 非空」。
      //   若把待裁决卡跟着 `if (hasAny)` 一起收起，用户的待裁决条目会**永久
      //   无法触达** —— 这是「收拾界面」最危险的副作用。
      await seedCharacter(
        '林晚晴',
        firstSeen: 3,
        assertions: [
          CharacterAssertion(
            attribute: '性格',
            value: '冷静',
            timestamp: 2000,
            status: 'pending',
            source: 'ai',
          ),
        ],
      );

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 角色本身在列表里（pending 断言不属于 merged，角色行照常显示）
      expect(find.text('林晚晴'), findsOneWidget);
      // 待裁决卡必须在（它的存在与「控件收起」无关）
      expect(find.textContaining('待确认'), findsWidgets);
    });
  });

  group('搜索与排序', () {
    Future<void> seedTwo() async {
      await seedCharacter('林晚晴', firstSeen: 3, assertions: []);
      await seedCharacter(
        '顾行之',
        firstSeen: 1,
        assertions: [assertion('身世', '孤儿', timestamp: 1000)],
      );
      // 别名行：可被别名搜索命中
      await seedCharacter('阿晴', firstSeen: 4, assertions: []);
      final row = await repo.getCharacter(manuscriptId, '阿晴');
      await (db.update(db.characterFacts)..where((t) => t.id.equals(row!.id)))
          .write(CharacterFactsCompanion(aliases: Value('["晚晴"]')));
    }

    testWidgets('按主名过滤', (tester) async {
      await seedTwo();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '顾行之');
      await tester.pumpAndSettle();

      expect(tile('顾行之'), findsOneWidget);
      expect(tile('林晚晴'), findsNothing);
      expect(tile('阿晴'), findsNothing);
    });

    testWidgets('按别名 / 属性值过滤（别名参与搜索）', (tester) async {
      await seedTwo();
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      // 「晚晴」命中 阿晴 的别名，也命中 林晚晴 主名本身（子串语义）
      await tester.enterText(find.byType(TextField), '晚晴');
      await tester.pumpAndSettle();
      expect(tile('阿晴'), findsOneWidget, reason: '别名「晚晴」命中');
      expect(tile('林晚晴'), findsOneWidget, reason: '主名包含查询词');
      expect(tile('顾行之'), findsNothing);

      await tester.enterText(find.byType(TextField), '孤儿');
      await tester.pumpAndSettle();
      expect(tile('顾行之'), findsOneWidget, reason: '断言值命中');
    });

    testWidgets('排序切换：首见章节升序 ↔ 最近更新降序', (tester) async {
      await seedTwo();
      await (db.update(db.characterFacts)..where((t) => t.name.equals('林晚晴')))
          .write(const CharacterFactsCompanion(updatedAt: Value(900)));
      await (db.update(db.characterFacts)..where((t) => t.name.equals('顾行之')))
          .write(const CharacterFactsCompanion(updatedAt: Value(950)));
      await (db.update(db.characterFacts)..where((t) => t.name.equals('阿晴')))
          .write(const CharacterFactsCompanion(updatedAt: Value(999)));

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      double topOf(String name) => tester.getTopLeft(find.text(name)).dy;

      // 默认首见章节升序：顾行之(1) < 林晚晴(3) < 阿晴(4)
      expect(topOf('顾行之') < topOf('林晚晴') && topOf('林晚晴') < topOf('阿晴'), isTrue);

      await tester.tap(find.text('最近更新'));
      await tester.pumpAndSettle();

      // 最近更新降序：阿晴(999) > 顾行之(950) > 林晚晴(900)
      expect(topOf('阿晴') < topOf('顾行之') && topOf('顾行之') < topOf('林晚晴'), isTrue);
    });
  });

  group('FR-10 最近批次过滤视图', () {
    testWidgets('since 之后有新增的角色 + 「+N 新」角标 + 横幅标注', (tester) async {
      await seedCharacter(
        '林晚晴',
        firstSeen: 3,
        assertions: [assertion('性格', '冷静', timestamp: 2000)],
      );
      await seedCharacter(
        '顾行之',
        firstSeen: 1,
        assertions: [assertion('身世', '孤儿', timestamp: 1000)],
      );
      await tester.pumpWidget(buildHost(since: 1500));
      await tester.pumpAndSettle();

      expect(find.textContaining('最近批次沉淀'), findsOneWidget);
      expect(
        find.textContaining('按断言落库时间过滤'),
        findsOneWidget,
        reason: '如实标注过滤口径',
      );
      expect(find.text('林晚晴'), findsOneWidget);
      expect(find.text('顾行之'), findsNothing);
      expect(find.text('+1 新'), findsOneWidget);
    });

    testWidgets('关闭横幅 → 回到全部角色', (tester) async {
      await seedCharacter(
        '顾行之',
        firstSeen: 1,
        assertions: [assertion('身世', '孤儿', timestamp: 1000)],
      );
      await tester.pumpWidget(buildHost(since: 1500));
      await tester.pumpAndSettle();
      expect(find.text('顾行之'), findsNothing);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('顾行之'), findsOneWidget);
    });
  });

  group('新建角色（FR-7）', () {
    testWidgets('填名字创建 → 落库并出现在列表', (tester) async {
      await seedChapters([0, 1, 2]);
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ 新建'));
      await tester.pumpAndSettle();

      // 弹窗内三个输入框：0 = 名字，1 = 设定正文（可空），2 = 首见章节
      //（必须限定在 AlertDialog 内——页面搜索框也是 TextField）
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '王建国');
      await tester.enterText(dialogFields.at(2), '2');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(find.text('王建国'), findsOneWidget);
      final row = await repo.getCharacter(manuscriptId, '王建国');
      expect(row, isNotNull);
      // ★ ADR-C95 / `N12-F3a`：用户填的是**章序位**（他在章节列表里看到的「第2章」），
      //   而本列存的是**身份键** ⇒ 落库必须是「序位 2 那一章的 sortOrder = 1」。
      //   旧断言 `2` 等于「原样存用户输入」，与展示口径**不同基**，同屏必然矛盾。
      expect(
        row!.firstSeenChapter,
        1,
        reason: '序位 2 ⇒ sortOrder 1（0 基身份键），不是用户输入的 2',
      );
      expect(find.text('第2章登场'), findsOneWidget, reason: '往返一致：序位 2 ⇒ 第2章');
    });
  });

  group('首见章节口径（ADR-C95 · 批次 N12-F3a）', () {
    /// 打开弹层 → 填名字 + 章号 → 创建。
    Future<void> createViaDialog(
      WidgetTester tester, {
      required String name,
      required String chapter,
    }) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ 新建'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), name);
      await tester.enterText(fields.at(2), chapter);
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();
    }

    testWidgets('N12F3a-1 首章 sortOrder=0 ⇒ 「第1章登场」（原实现渲染「第0章登场」）', (
      tester,
    ) async {
      await seedChapters([0, 1]);
      await seedCharacter('林晚晴', firstSeen: 0, assertions: []);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('第1章登场'), findsOneWidget);
      expect(
        find.text('第0章登场'),
        findsNothing,
        reason: '0 基身份键**不得**直出为展示号（ADR-C95 §3）',
      );
    });

    testWidgets('N12F3a-2 删过首章（sortOrder 从 1 起）⇒ 序位正确，杀死 `sortOrder + 1`', (
      tester,
    ) async {
      await seedChapters([1, 2, 3]);
      await seedCharacter('梁叔', firstSeen: 3, assertions: []);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('第3章登场'), findsOneWidget);
      expect(
        find.text('第4章登场'),
        findsNothing,
        reason: '`sortOrder + 1` 会给出「第4章」，是错的',
      );
    });

    testWidgets('N12F3a-3 引用已删章 ⇒ 解析失败即「未知」，不编造数字', (tester) async {
      await seedChapters([1, 2]); // 0 号章已被删（身份键可空洞）
      await seedCharacter('林闲', firstSeen: 0, assertions: []);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('首次登场章节未知'), findsOneWidget);
      expect(find.text('第0章登场'), findsNothing);
      expect(find.text('第1章登场'), findsNothing, reason: '不得退化成「首个现有章」');
    });

    testWidgets('N12F3a-4 用户填的序位**越界** ⇒ 不落库（不编造）+ 如实提示', (tester) async {
      await seedChapters([0]); // 只有 1 章
      await createViaDialog(tester, name: '王建国', chapter: '5');

      final row = await repo.getCharacter(manuscriptId, '王建国');
      expect(row, isNotNull);
      expect(
        row!.firstSeenChapter,
        isNull,
        reason: '作品里没有第 5 章 ⇒ 该序位不存在，**不存**（ADR-C95 裁定 2）',
      );
      expect(
        find.textContaining('没有第 5 章'),
        findsOneWidget,
        reason: '静默丢弃会让用户以为「填了没反应」——必须如实告知',
      );
    });

    testWidgets('N12F3a-5 未填章号 ⇒ 仍为「未知」（不因口径改动而回归）', (tester) async {
      await seedChapters([0]);
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await tester.tap(find.text('+ 新建'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '无名氏');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(find.text('首次登场章节未知'), findsOneWidget);
      final row = await repo.getCharacter(manuscriptId, '无名氏');
      expect(row!.firstSeenChapter, isNull);
    });
  });
}
