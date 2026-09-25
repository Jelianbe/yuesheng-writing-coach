// ─────────────────────────────────────────────────────────────
// world_fact_page_test — W1-T06：薄壳页 WorldFactPage 覆盖
//
// 补齐此前零覆盖的薄壳页（T03 AC⑤/⑥）：
//   ① AppBar 标题「世界观 (N)」计数 —— 至少覆盖 0 个 / 非 0 个两态；
//   ② AppBar「+ 新建」action 走**共用创建入口**（与列表头按钮同款
//      showAndCreateWorldTheme），创建后经 GlobalKey 刷新子列表 → 计数更新。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/world_fact_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/features/world/world_fact_page.dart';

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

  Widget host() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: WorldFactPage(manuscriptId: manuscriptId)),
  );

  testWidgets('AppBar 计数：0 个主题 → 「世界观 (0)」+ 空态', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('世界观 (0)'), findsOneWidget);
    expect(find.text('还没有世界观设定'), findsOneWidget);
  });

  testWidgets('AppBar 计数随列表条数变化：2 个主题 → 「世界观 (2)」', (tester) async {
    await repo.upsertWorld(manuscriptId: manuscriptId, name: 'A');
    await repo.upsertWorld(manuscriptId: manuscriptId, name: 'B');

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('世界观 (2)'), findsOneWidget);
  });

  testWidgets('「+ 新建」action → 共用创建弹层 → 落库并刷新计数', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('世界观 (0)'), findsOneWidget);

    // 薄壳 AppBar action（'+ 新建'）—— 与列表头「＋ 新建设定主题」共用同一弹层
    await tester.tap(find.text('+ 新建'));
    await tester.pumpAndSettle();
    expect(
      find.text('新建设定主题'),
      findsOneWidget,
      reason: '应弹出与列表头入口共用的 showCreateWorldThemeDialog',
    );

    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '灵气体系'); // 主题名
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(await repo.getWorld(manuscriptId, '灵气体系'), isNotNull);
    expect(
      find.text('世界观 (1)'),
      findsOneWidget,
      reason: '薄壳经 GlobalKey.refresh() 刷新子列表 → AppBar 计数更新',
    );
  });
}
