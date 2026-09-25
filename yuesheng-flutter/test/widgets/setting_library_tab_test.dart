// ─────────────────────────────────────────────────────────────
// setting_library_tab_test — 统一「资料」容器 Widget 测试
//
// 批次：2026-09-16 设定资料库第三批（容器）
// 覆盖：
//   1. 默认「角色」子列表 + 四段切换器渲染
//   2. 切「大纲」→ 大纲实体列表（含空态）
//   3. 切「世界观」→ 世界观列表
//   4. 切「其他」→ 占位提示
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/features/manuscript/setting_library_tab.dart';

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
        home: Scaffold(body: SettingLibraryTab(manuscriptId: manuscriptId)),
      ),
    );
  }

  testWidgets('#1 默认角色子列表 + 四段切换器', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    // 四段切换器
    expect(find.text('角色'), findsWidgets);
    expect(find.text('大纲'), findsOneWidget);
    expect(find.text('世界观'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    // 默认角色空态（无角色数据）
    expect(find.textContaining('还没有角色'), findsOneWidget);
  });

  testWidgets('#2 切大纲 → 空态', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('大纲'));
    await tester.pumpAndSettle();
    expect(find.textContaining('还没有大纲实体'), findsOneWidget);
  });

  testWidgets('#3 切世界观 → 列表', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('世界观'));
    await tester.pumpAndSettle();
    // 世界观空态（无数据）
    expect(find.textContaining('还没有世界观'), findsWidgets);
  });

  testWidgets('#4 切其他 → 开放容器空态', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    expect(find.textContaining('记录武器、规则、组织等自定义设定'), findsOneWidget);
  });
}
