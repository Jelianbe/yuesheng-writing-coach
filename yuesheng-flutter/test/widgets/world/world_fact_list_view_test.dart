// ─────────────────────────────────────────────────────────────
// world_fact_list_view_test — 批次 W1 世界观可嵌入列表组件 Widget 测试
//
// 覆盖（对应 W1-T02 验收标准）：
//   ①② 无 Scaffold / AppBar（可嵌入）；列表项 名字 + 首见章节 + 有效断言摘要前 3
//   ③   「＋ 新建设定主题」在列表上方
//   ④   空态文案（§6-A）与 CTA；搜索无结果文案（§6-B）
//   ⑤   新建 / 追加表单含「原文依据」+「章节」字段（A2）
//   ⑥   表单常驻依据提示、无阻断（Q2）
//   ⑦   空主题（无有效断言）列表项有视觉标识（Q3）
//   ⑧   onCountChanged 正确上报过滤 + 排序后行数
// ─────────────────────────────────────────────────────────────

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/types/character_types.dart';
import 'package:writingcoach/widgets/world/world_dialogs.dart';
import 'package:writingcoach/widgets/world/world_fact_list_view.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late WorldFactRepository repo;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    repo = WorldFactRepository(db);
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost({ValueChanged<int>? onCount}) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: WorldFactListView(
            manuscriptId: manuscriptId,
            onCountChanged: onCount,
          ),
        ),
      ),
    );
  }

  CharacterAssertion a(
    String attr,
    String val, {
    int? chapter,
    int ts = 1000,
    String? evidence,
  }) => CharacterAssertion(
    attribute: attr,
    value: val,
    chapter: chapter,
    timestamp: ts,
    evidence: evidence,
  );

  group('可嵌入性与列表渲染', () {
    testWidgets('无 Scaffold / AppBar（可嵌入）', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsNothing);
    });

    testWidgets('列表项：主题名 + 首见章节 + 有效断言摘要', (tester) async {
      await repo.upsertWorld(
        manuscriptId: manuscriptId,
        name: '灵气体系',
        firstSeenChapter: 3,
        assertions: [a('灵气浓度', '稀薄', chapter: 3), a('形态', '气态', chapter: 3)],
      );
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('灵气体系'), findsOneWidget);
      expect(find.text('第3章首次提出'), findsOneWidget);
      expect(find.text('灵气浓度·稀薄 / 形态·气态'), findsOneWidget);
    });

    testWidgets('摘要最多 3 条（有效断言 confirmed 且非 stale）', (tester) async {
      await repo.upsertWorld(
        manuscriptId: manuscriptId,
        name: '多断言',
        firstSeenChapter: 1,
        assertions: [
          a('甲', '1', chapter: 1),
          a('乙', '2', chapter: 1),
          a('丙', '3', chapter: 1),
          a('丁', '4', chapter: 1),
        ],
      );
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      expect(find.text('甲·1 / 乙·2 / 丙·3'), findsOneWidget);
      expect(find.textContaining('丁·4'), findsNothing);
    });

    testWidgets('首次提出章节未知（firstSeenChapter=null）', (tester) async {
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '无章');
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      expect(find.text('首次提出章节未知'), findsOneWidget);
    });

    testWidgets('空主题（无有效断言）列表项有视觉标识 暂无设定（Q3）', (tester) async {
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '地理·北境');
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      expect(find.text('暂无设定'), findsOneWidget);
    });
  });

  group('空态与入口', () {
    testWidgets('空态文案（§6-A）+ CTA', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      expect(find.text('还没有世界观设定'), findsOneWidget);
      expect(find.text('手动记录你的世界规则与设定，写作时教练会据此复查前后是否一致。'), findsOneWidget);
      expect(find.text('＋ 新建设定主题'), findsOneWidget);
    });

    testWidgets('「＋ 新建设定主题」在列表上方（A1）', (tester) async {
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '灵气体系');
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      final buttonY = tester.getTopLeft(find.text('＋ 新建设定主题')).dy;
      final tileY = tester.getTopLeft(find.text('灵气体系')).dy;
      expect(buttonY < tileY, isTrue, reason: '新建入口应置于列表上方');
    });

    testWidgets('搜索无结果（§6-B）', (tester) async {
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '灵气体系');
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '不存在');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配「不存在」的设定主题'), findsOneWidget);
    });

    testWidgets('搜索按属性 / 取值过滤', (tester) async {
      await repo.upsertWorld(
        manuscriptId: manuscriptId,
        name: '灵气体系',
        assertions: [a('灵气浓度', '稀薄')],
      );
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '地理');
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '稀薄');
      await tester.pumpAndSettle();
      expect(find.text('灵气体系'), findsOneWidget);
      expect(find.text('地理'), findsNothing);
    });
  });

  group('onCountChanged 上报', () {
    testWidgets('上报过滤 + 排序后行数', (tester) async {
      await repo.upsertWorld(manuscriptId: manuscriptId, name: 'A');
      await repo.upsertWorld(manuscriptId: manuscriptId, name: 'B');
      int? reported;
      await tester.pumpWidget(buildHost(onCount: (n) => reported = n));
      await tester.pumpAndSettle();
      expect(reported, 2);

      await tester.enterText(find.byType(TextField), 'A');
      await tester.pumpAndSettle();
      expect(reported, 1, reason: '过滤后应重新上报');
    });
  });

  group('新建 / 追加弹层（A2 / Q2）', () {
    testWidgets('新建表单含「原文依据」+「章节」+ 常驻提示', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await tester.tap(find.text('＋ 新建设定主题'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      // 设定库第四批：断言区收进「结构化这条设定（可选）」折叠区（正文优先）
      await tester.tap(find.text('结构化这条设定（可选）'));
      await tester.pumpAndSettle();
      expect(find.text('原文依据（选填）'), findsOneWidget);
      expect(find.text('章节（选填）'), findsOneWidget);
      expect(find.textContaining('填了「原文依据」的设定才会参与一致性检查'), findsOneWidget);
    });

    testWidgets('新建：主题名空 → §6-C 错误提示且不关闭', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await tester.tap(find.text('＋ 新建设定主题'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('请填写主题名'), findsOneWidget);
      expect(find.byType(AlertDialog), findsOneWidget, reason: '校验失败不得关闭');
    });

    testWidgets('新建：属性填而取值空 → §6-D 错误提示', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await tester.tap(find.text('＋ 新建设定主题'));
      await tester.pumpAndSettle();

      // 展开「结构化这条设定」折叠区（正文优先：断言区默认收起）
      await tester.tap(find.text('结构化这条设定（可选）'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '灵气体系'); // 主题名
      await tester.enterText(fields.at(2), '灵气浓度'); // 属性（0=名 1=正文 2=属性）
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('属性和取值不能为空'), findsOneWidget);
    });

    testWidgets('新建：仅主题名也可保存（Q3 允许空主题，无阻断）', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await tester.tap(find.text('＋ 新建设定主题'));
      await tester.pumpAndSettle();

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '空主题');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing, reason: '空主题应放行（Q3）');
      expect(find.text('空主题'), findsOneWidget, reason: '新主题应出现在列表');
    });

    testWidgets('追加表单含「原文依据」+「章节」+ 常驻提示', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold(body: SizedBox());
            },
          ),
        ),
      );
      showAppendAssertionDialog(ctx, themeName: '灵气体系');
      await tester.pumpAndSettle();

      expect(find.text('追加设定 · 灵气体系'), findsOneWidget);
      expect(find.text('原文依据（选填）'), findsOneWidget);
      expect(find.text('章节（选填）'), findsOneWidget);
      expect(find.textContaining('留空则仅记录、不参与'), findsOneWidget);
    });

    // ── W1-T05 负向守卫（UI 侧）：不填依据 → 存 null → 不进一致性检查 ──
    testWidgets('守卫：新建时不填「原文依据」→ 落库 evidence 为 null', (tester) async {
      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();
      await tester.tap(find.text('＋ 新建设定主题'));
      await tester.pumpAndSettle();

      // 展开「结构化这条设定」折叠区（正文优先：断言区默认收起）
      await tester.tap(find.text('结构化这条设定（可选）'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), '灵气体系'); // 主题名
      await tester.enterText(fields.at(2), '灵气浓度'); // 属性
      await tester.enterText(fields.at(3), '稀薄'); // 取值
      await tester.enterText(fields.at(4), '3'); // 章节
      // fields.at(5) = 原文依据，刻意留空
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final row = await repo.getWorld(manuscriptId, '灵气体系');
      final assertion = WorldFactRepository.parseAssertions(
        row!.assertions,
      ).single;
      expect(assertion.source, 'user');
      expect(
        assertion.evidence,
        isNull,
        reason: 'UI 留空依据须落 null —— 该断言不进一致性检查（设计态契约）',
      );
    });
  });

  testWidgets('设定库第四批：新建填正文 → description 落库（用户写入优先）', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('＋ 新建设定主题'));
    await tester.pumpAndSettle();

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '灵气体系'); // 主题名
    await tester.enterText(
      fields.at(1),
      '灵气是天地间流动的能量，浓度由北方向南方递减。',
    ); // 设定正文（正文优先：首个可选输入）
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('灵气体系'), findsOneWidget);
    final row = await repo.getWorld(manuscriptId, '灵气体系');
    expect(row!.description, contains('浓度由北方向南方递减'));
  });

  // ── W1-T06：列表交互覆盖（排序 / 归档开关 / 已归档角标）──
  group('列表交互（W1-T06）：排序 / 归档开关 / 已归档角标', () {
    testWidgets('R8 排序切换：首见章节升序 ↔ 最近更新降序', (tester) async {
      await repo.upsertWorld(
        manuscriptId: manuscriptId,
        name: '早章',
        firstSeenChapter: 1,
      );
      await repo.upsertWorld(
        manuscriptId: manuscriptId,
        name: '晚章',
        firstSeenChapter: 9,
      );
      // upsert 同一秒内 updatedAt 相同 → 显式落不同 updatedAt，使两档排序可区分
      final early = (await repo.getWorld(manuscriptId, '早章'))!;
      final late = (await repo.getWorld(manuscriptId, '晚章'))!;
      await (db.update(db.worldFacts)..where((t) => t.id.equals(early.id)))
          .write(const WorldFactsCompanion(updatedAt: Value(1000)));
      await (db.update(db.worldFacts)..where((t) => t.id.equals(late.id)))
          .write(const WorldFactsCompanion(updatedAt: Value(9000)));

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      double yOf(String s) => tester.getTopLeft(find.text(s)).dy;
      expect(yOf('早章') < yOf('晚章'), isTrue, reason: '默认「首见章节」升序');

      await tester.tap(find.text('最近更新'));
      await tester.pumpAndSettle();
      expect(
        yOf('晚章') < yOf('早章'),
        isTrue,
        reason: '切「最近更新」降序：updatedAt 9000 应排在 1000 之前',
      );
    });

    testWidgets('归档开关：默认隐藏 archived；开启后显示 + 「已归档」角标', (tester) async {
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '在用');
      await repo.upsertWorld(manuscriptId: manuscriptId, name: '废弃');
      final gone = (await repo.getWorld(manuscriptId, '废弃'))!;
      await repo.archiveWorld(gone.id);

      await tester.pumpWidget(buildHost());
      await tester.pumpAndSettle();

      expect(find.text('在用'), findsOneWidget);
      expect(find.text('废弃'), findsNothing, reason: '默认排除 archived');
      expect(find.text('已归档'), findsNothing);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.text('废弃'), findsOneWidget, reason: '开启「显示已归档」后应出现');
      expect(find.text('已归档'), findsOneWidget, reason: '归档行带「已归档」角标');
    });
  });
}
