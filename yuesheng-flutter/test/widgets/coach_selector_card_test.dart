// ─────────────────────────────────────────────────────────────
// CoachSelectorCard widget 测试 — 自定义教练（D1）编辑入口通路
//
// 覆盖路径（此前为孤儿能力，无测试守护）：
//   #1 渲染：加载完成后出现「自定义教练」入口
//   #2 新建：填名称+语气 → 保存 → 自定义人格入列
//      （2026-09-28 重构后：名称唯一必填，语气选填；
//       「列表简介/阈值」收进默认收起的高级折叠区 ⇒ 主界面仅 2 个 TextField）
//   #3 编辑入口：自定义人格行出现「编辑」图标（Icons.edit_outlined）
//   #4 编辑弹出：点编辑图标 → 对话框标题为「编辑自定义教练」且名称字段预填
//   #5 只填名称即可保存（语气留空 → 注入层回退默认态度档，由
//      coach_persona_injection_test 守护注入侧）
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/features/app_settings/coach_selector_card.dart';
import 'package:writingcoach/providers/app_providers.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() {
    container.dispose();
    db.close();
  });

  Widget buildHost() => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(home: Scaffold(body: const CoachSelectorCard())),
  );

  testWidgets('#1 加载后渲染「自定义教练」入口', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();
    expect(find.text('自定义教练'), findsOneWidget);
    // 系统预设 3 个，无编辑图标（仅自定义才有）
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('#2-#4 新建后可点编辑图标打开预填对话框', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    // #2 新建自定义教练
    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();
    expect(find.text('新建自定义教练'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '毒舌编辑'); // 名称
    await tester.enterText(fields.at(1), '说话带刺，直给'); // 语气设定（选填）
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    // 自定义人格入列
    expect(find.text('毒舌编辑'), findsWidgets);

    // #3 自定义人格行出现编辑图标
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

    // #4 点编辑图标 → 预填对话框
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(find.text('编辑自定义教练'), findsOneWidget);
    expect(tester.widget<TextField>(fields.at(0)).controller?.text, '毒舌编辑');
  });

  testWidgets('#5 只填名称即可保存（语气留空合法）', (tester) async {
    await tester.pumpWidget(buildHost());
    await tester.pumpAndSettle();

    await tester.tap(find.text('自定义教练'));
    await tester.pumpAndSettle();

    // 主界面折叠收起时只有 2 个字段：名称 + 语气
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    // 高级选项默认收起：列表简介/阈值不在主界面
    expect(find.text('高级选项'), findsOneWidget);
    expect(find.text('列表简介（选填，仅展示）'), findsNothing);

    await tester.enterText(fields.at(0), '只取名教练');
    await tester.pump();

    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();

    // 保存成功（不再要求语气必填）
    expect(find.text('只取名教练'), findsWidgets);
  });
}
