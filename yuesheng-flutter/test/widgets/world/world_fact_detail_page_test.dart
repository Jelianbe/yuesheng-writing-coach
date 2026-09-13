// ─────────────────────────────────────────────────────────────
// world_fact_detail_page_test — 批次 W1 世界观主题详情页 Widget 测试
//
// 覆盖（对应 W1-T03 验收标准）：
//   ① 展示全部断言（属性 / 取值 / 章节 / 是否有依据），无改写 / 删除按钮（O-2）
//   ② ＋ 追加设定：保存后断言数 +1，历史不覆盖
//   ③ 归档本主题：确认弹窗 → §6-F SnackBar + 返回
//   ④ 主题不存在：§6-G SnackBar + 返回
//   ⑤ 恢复本主题（Q1）：软恢复 + SnackBar + 返回
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
import 'package:writingcoach/widgets/world/world_fact_detail_page.dart';

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

  testWidgets('① 展示全部断言且无改写 / 删除按钮（O-2）', (tester) async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      firstSeenChapter: 3,
      assertions: [
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '稀薄',
          chapter: 3,
          timestamp: 100,
          evidence: '这方天地灵气稀薄',
        ),
        CharacterAssertion(
          attribute: '灵气浓度',
          value: '充沛',
          chapter: 20,
          timestamp: 200,
        ),
      ],
    );
    final id = (await repo.getWorld(manuscriptId, '灵气体系'))!.id;
    await openDetail(tester, id);

    expect(find.text('灵气体系'), findsOneWidget);
    expect(find.text('灵气浓度：稀薄'), findsOneWidget);
    expect(find.text('灵气浓度：充沛'), findsOneWidget);
    expect(find.text('第3章 · ✓ 有依据'), findsOneWidget);
    expect(find.text('第20章 · — 无依据'), findsOneWidget);
    // O-2：本批无单条改写 / 删除入口
    expect(find.text('删除'), findsNothing);
    expect(find.text('改写'), findsNothing);
  });

  testWidgets('② ＋ 追加设定 → 断言数 +1，历史不覆盖', (tester) async {
    await repo.upsertWorld(
      manuscriptId: manuscriptId,
      name: '灵气体系',
      assertions: [
        CharacterAssertion(
          attribute: '形态',
          value: '气态',
          chapter: 3,
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
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('形态：气态'), findsOneWidget, reason: '历史断言不被覆盖');
    expect(find.text('灵气浓度：充沛'), findsOneWidget, reason: '新断言出现');
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
}
