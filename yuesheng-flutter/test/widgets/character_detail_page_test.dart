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
        const CharacterAssertion(
          attribute: '性格',
          value: '冷静',
          chapter: 3,
          timestamp: 1000,
          evidence: '握紧刀柄',
        ),
        // 已拒绝：带理由（D-7 chips 落库形态）
        const CharacterAssertion(
          attribute: '性格',
          value: '暴躁',
          chapter: 5,
          timestamp: 2000,
          status: 'rejected',
          rejectReason: '抽取错误',
        ),
        // 旧版：章节已改写（stale）
        const CharacterAssertion(
          attribute: '独生子女状态',
          value: '有妹妹',
          chapter: 15,
          timestamp: 3000,
          chapterHash: 'old-hash',
          stale: true,
        ),
        // 用户手写
        const CharacterAssertion(
          attribute: '性格',
          value: '外冷内热',
          chapter: 7,
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
      expect(find.text('第7章'), findsOneWidget, reason: 'user 断言带章号');
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
      await tester.enterText(dialogFields.at(2), '3');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final list = await dbAssertions();
      final added = list.firstWhere((a) => a.value == '孤儿');
      expect(added.source, 'user');
      expect(added.chapter, 3);
      expect(added.chapterHash, isNotNull);
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
      // 第15章不存在 → evidence 缺失 + 反查必然失败
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

      expect(find.text('清除第15章旧版断言 (1)'), findsOneWidget);
      await tester.tap(find.text('清除第15章旧版断言 (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('清除'));
      await tester.pumpAndSettle();

      final list = await dbAssertions();
      expect(list.where((a) => a.value == '有妹妹'), isEmpty);
      expect(find.text('清除第15章旧版断言 (1)'), findsNothing);
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
