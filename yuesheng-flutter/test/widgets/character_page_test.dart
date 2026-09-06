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
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/widgets/character/character_page.dart';

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
      await seedCharacter(
        '林晚晴',
        firstSeen: 3,
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
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.tap(find.text('+ 新建'));
      await tester.pumpAndSettle();

      // 弹窗内两个输入框：0 = 名字，1 = 首见章节
      //（必须限定在 AlertDialog 内——页面搜索框也是 TextField）
      final dialogFields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(dialogFields.at(0), '王建国');
      await tester.enterText(dialogFields.at(1), '2');
      await tester.tap(find.text('创建'));
      await tester.pumpAndSettle();

      expect(find.text('王建国'), findsOneWidget);
      final row = await repo.getCharacter(manuscriptId, '王建国');
      expect(row, isNotNull);
      expect(row!.firstSeenChapter, 2);
    });
  });
}
