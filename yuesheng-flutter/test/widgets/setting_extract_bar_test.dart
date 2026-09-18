// ─────────────────────────────────────────────────────────────
// setting_extract_bar_test — 「从正文提炼断言」条测试（创建体验 A2）
//
//   1. 无正文 → 不显示（SizedBox.shrink）
//   2. 有正文 → 按钮显示
//
// LLM 成功/失败路径不在此覆盖：真实调用依赖模型配置与网络，
// 测试环境不可控（无 key 时 dio 重试会挂起 pumpAndSettle）。
// 降级与合并语义由解析器单测 + 仓储合并测试（批次3-D2）兜底。
// ─────────────────────────────────────────────────────────────

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/providers/app_providers.dart';
import 'package:writingcoach/widgets/setting/setting_extract_bar.dart';

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

  Widget buildHost({
    required String description,
    Future<int> Function(dynamic extracted)? onExtracted,
  }) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SettingExtractBar(
            manuscriptId: 'm1',
            entityName: '林晚',
            description: description,
            chapterIdentity: 1,
            onExtracted:
                onExtracted ??
                (extracted) async {
                  return extracted.length;
                },
          ),
        ),
      ),
    );
  }

  testWidgets('#1 无正文 → 不显示', (tester) async {
    await tester.pumpWidget(buildHost(description: '   '));
    await tester.pumpAndSettle();
    expect(find.text('从正文提炼断言'), findsNothing);
  });

  testWidgets('#2 有正文 → 按钮显示', (tester) async {
    await tester.pumpWidget(buildHost(description: '她是守夜人，持青铜剑。'));
    await tester.pumpAndSettle();
    expect(find.text('从正文提炼断言'), findsOneWidget);
  });
}
