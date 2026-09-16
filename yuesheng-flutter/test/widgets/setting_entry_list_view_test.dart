// ─────────────────────────────────────────────────────────────
// setting_entry_list_view_test — 「其他」开放容器列表 Widget（第二批）
//
// 覆盖：空态 / 列表渲染（类别徽标 + 名称 + 摘要）/ 新建弹窗落库 /
// 参与诊断开关回调（listParticipating 命中）。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/setting_entry_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/setting/setting_entry_list_view.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late String manuscriptId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    manuscriptId = await ManuscriptRepository(
      db,
    ).createManuscript(title: '测试作品');
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost() {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(body: SettingEntryListView(manuscriptId: manuscriptId)),
      ),
    );
  }

  testWidgets('#1 空态引导', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(find.textContaining('记录武器、规则、组织等自定义设定'), findsOneWidget);
    expect(find.text('新建第一条'), findsOneWidget);
  });

  testWidgets('#2 列表渲染：类别徽标 + 名称 + 摘要 + 参与诊断开关', (tester) async {
    final repo = SettingEntryRepository(db);
    await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '武器',
      name: '血月刃',
      description: '以血养刃，月圆时锋锐倍增。',
    );
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(find.text('武器'), findsOneWidget);
    expect(find.text('血月刃'), findsOneWidget);
    expect(find.textContaining('以血养刃'), findsOneWidget);
    expect(find.text('参与诊断'), findsOneWidget);
    // 默认未勾选
    final switches = tester.widgetList<Switch>(find.byType(Switch));
    expect(switches.single.value, isFalse);
  });

  testWidgets('#3 新建弹窗：填名称类别正文 → 落库', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    // 弹窗表单
    await tester.enterText(find.widgetWithText(TextField, '名称'), '青霜剑');
    await tester.enterText(find.widgetWithText(TextField, '类别（新类别或选上方）'), '武器');
    await tester.enterText(
      find.widgetWithText(TextField, '设定正文'),
      '剑出如霜，百年一醒。',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    // 列表出现新条目
    expect(find.text('青霜剑'), findsOneWidget);
    expect(find.textContaining('剑出如霜'), findsOneWidget);
    final repo = SettingEntryRepository(db);
    final entries = await repo.listEntries(manuscriptId);
    expect(entries, hasLength(1));
    expect(entries.single.category, '武器');
  });

  testWidgets('#4 参与诊断开关 → setParticipate 落库', (tester) async {
    final repo = SettingEntryRepository(db);
    await repo.createEntry(
      manuscriptId: manuscriptId,
      category: '规则怪谈',
      name: '镜中人',
      description: '镜中倒影先行一步。',
    );
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    final participating = await repo.listParticipating(manuscriptId);
    expect(participating, hasLength(1), reason: '勾选后进诊断上下文');
    expect(participating.single.name, '镜中人');
  });
}
