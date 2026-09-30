// ─────────────────────────────────────────────────────────────
// growth_diagnosis_prefs_card_test — 折叠态「教学设置」入口回调（ADR-C110）
//
// 背景：该导航**原写在卡片内部**（卡片 → coach_settings_page），与二级页
// 内嵌卡片形成**循环依赖**（门禁 3 全量卡口；HEAD 74e77b94 实测 rc=1）。
// ADR-C110 改为「调用方注入 onOpenSettings」，断掉反向依赖。
//
// 覆盖：
//   #1 折叠态传入 onOpenSettings → 点击触发回调（导航职责已外移）
//   #2 onOpenSettings 为 null → 点击 no-op（不抛错）
//   #3 embedded=true → 不渲染折叠行（'教学设置' 文案不出现）
//
// ⚠️ 改造前 test/ 对本卡片**零引用**
//    （`git grep -ln "GrowthDiagnosisPrefsCard" -- test` 为空）
//    ⇒ 本文件是回调接线的**唯一**守护，删除它等于该改造无回归网。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/features/growth/growth_diagnosis_prefs_card.dart';
import 'package:writingcoach/providers/app_providers.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Widget buildHost(GrowthDiagnosisPrefsCard card) => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: MaterialApp(home: Scaffold(body: card)),
  );

  testWidgets('#1 折叠态传入 onOpenSettings → 点击触发回调', (tester) async {
    var fired = 0;
    await tester.pumpWidget(
      buildHost(GrowthDiagnosisPrefsCard(onOpenSettings: () => fired++)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('教学设置'), findsOneWidget);
    await tester.tap(find.textContaining('教学设置'));
    await tester.pump();

    expect(fired, 1, reason: '折叠态点击必须把动作交给调用方注入的回调');
    expect(tester.takeException(), isNull);
  });

  testWidgets('#2 onOpenSettings 为 null → 点击 no-op（不抛错）', (tester) async {
    await tester.pumpWidget(buildHost(const GrowthDiagnosisPrefsCard()));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('教学设置'));
    await tester.pump();

    // 无 Navigator.push、无回调；不抛异常即通过
    expect(tester.takeException(), isNull);
  });

  testWidgets('#3 embedded=true → 不渲染折叠行', (tester) async {
    await tester.pumpWidget(
      buildHost(
        GrowthDiagnosisPrefsCard(embedded: true, onOpenSettings: () {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('教学设置'), findsNothing);
  });
}
