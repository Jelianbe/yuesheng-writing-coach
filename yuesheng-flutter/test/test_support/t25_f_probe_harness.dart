// T-20261125-01 F 面探针的测试支撑：菜单 harness、视口、tab 切换与可见性。
// 只支撑 widget probe，不含产品逻辑；主测试保留判据与断言。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/features/writing/writing_menu_sheet.dart';
import 'package:writingcoach/theme/app_theme.dart';

const _writingTools = ['章节列表', '全文搜索', '查找替换', '快捷短语', '回收板'];
const _teaching = ['当前文风', '写作统计', '打开教练面板', '世界观', '角色', '大纲'];
const _settings = ['排版设置', '版本时光机'];
const _openMenuKey = Key('t25-f-open-menu');

class T25FProbeHarness {
  T25FProbeHarness(this.tester);

  final WidgetTester tester;

  Future<void> pump({
    Size size = const Size(393, 851),
    ThemeData? theme,
  }) async {
    // 先拆掉上一轮 MaterialApp，避免旧 sheet 遮住新一轮打开按钮。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? buildAppTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: _openMenuKey,
                onPressed: () => WritingMenuSheet.show(
                  context,
                  lastSavedAt: null,
                  onDiagnose: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(_openMenuKey));
    await tester.pumpAndSettle();
  }

  Future<void> switchTab(String label) async {
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  Future<List<String>> visibleLabels(String tab, List<String> labels) async {
    await switchTab(tab);
    final viewport = tester.getRect(
      find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    return [
      for (final label in labels)
        if (find.text(label).evaluate().isNotEmpty &&
            tester.getRect(find.text(label)).top >= viewport.top - 0.5 &&
            tester.getRect(find.text(label)).bottom <= viewport.bottom + 0.5)
          label,
    ];
  }

  Future<Map<String, int>> collectVisibleCounts() async {
    final counts = <String, int>{};
    for (final tab in const ['写作工具', '教学', '设置']) {
      final labels = switch (tab) {
        '写作工具' => _writingTools,
        '教学' => _teaching,
        _ => _settings,
      };
      final visible = await visibleLabels(tab, labels);
      counts[tab] = visible.length;
      debugPrint('F3 $tab ${visible.length}/${labels.length} $visible');
    }
    return counts;
  }

  Color menuTextColor(String label) {
    final text = tester.widget<Text>(find.text(label));
    return text.style!.color!;
  }

  AppPalette paletteAt(String label) {
    final context = tester.element(find.text(label));
    return Theme.of(context).extension<AppPalette>()!;
  }
}
