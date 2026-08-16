// ─────────────────────────────────────────────────────────────
// ImportSuccessSheet 测试 — 导入成功反馈弹层（缺口清单 B 类）
//
// 覆盖：渲染（成功图标/标题/章节数/引导文案/双按钮）+
// 立即诊断回调 + 稍后再说回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/widgets/import_success_sheet.dart';

void main() {
  Widget buildHost({
    required VoidCallback onDiagnose,
    required VoidCallback onClose,
    bool diagnoseEnabled = true,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => ImportSuccessSheet(
                  manuscriptTitle: '测试作品',
                  chapterCount: 3,
                  manuscriptId: 'm1',
                  chapterId: 'c1',
                  diagnoseEnabled: diagnoseEnabled,
                  onDiagnose: onDiagnose,
                  onClose: onClose,
                ),
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('渲染：成功图标 + 标题 + 章节数 + 引导文案 + 双按钮', (tester) async {
    await tester.pumpWidget(buildHost(onDiagnose: () {}, onClose: () {}));
    await openSheet(tester);

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.text('导入成功！'), findsOneWidget);
    expect(find.text('已成功导入 3 个章节到\n「测试作品」'), findsOneWidget);
    expect(find.text('是否立即发送给月笙诊断？'), findsOneWidget);
    expect(find.text('立即诊断'), findsOneWidget);
    expect(find.text('稍后再说'), findsOneWidget);
  });

  testWidgets('点击「立即诊断」→ onDiagnose 回调 + 弹层关闭', (tester) async {
    var diagnosed = false;
    await tester.pumpWidget(
      buildHost(onDiagnose: () => diagnosed = true, onClose: () {}),
    );
    await openSheet(tester);

    await tester.tap(find.text('立即诊断'));
    await tester.pumpAndSettle();

    expect(diagnosed, isTrue);
    expect(find.text('导入成功！'), findsNothing);
  });

  testWidgets('点击「稍后再说」→ onClose 回调 + 弹层关闭', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      buildHost(onDiagnose: () {}, onClose: () => closed = true),
    );
    await openSheet(tester);

    await tester.tap(find.text('稍后再说'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(find.text('导入成功！'), findsNothing);
  });

  testWidgets('批次78 diagnoseEnabled=false → 隐藏诊断引导，单按钮「返回作品」', (tester) async {
    await tester.pumpWidget(
      buildHost(onDiagnose: () {}, onClose: () {}, diagnoseEnabled: false),
    );
    await openSheet(tester);

    expect(find.text('导入成功！'), findsOneWidget);
    expect(find.text('是否立即发送给月笙诊断？'), findsNothing);
    expect(find.text('立即诊断'), findsNothing);
    expect(find.text('稍后再说'), findsNothing);
    expect(find.text('返回作品'), findsOneWidget);
  });
}
