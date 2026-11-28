// T-20261125-01 F 面环境探针：只读真实 WritingMenuSheet，不改产品逻辑。
//
// F1 用 DefaultTextStyle 合并 Text.style 后由 TextPainter 在无裁切约束下量高；
// tester.getRect(Text) 只作阳性对照，不承担未裁高度判据。
// F2 的 48dp 是判据而非现状：compact 下已知短件会量到 40dp，本用例钉住
// 实测值与判据结果，不把已知短件伪装成达标，也不在本卡擅自修产品。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/features/writing/writing_menu_sheet.dart';
import 'package:writingcoach/theme/app_theme.dart';

const _writingTools = ['章节列表', '全文搜索', '查找替换', '快捷短语', '回收板'];
const _teaching = ['当前文风', '写作统计', '打开教练面板', '世界观', '角色', '大纲'];
const _settings = ['排版设置', '版本时光机'];
const _openMenuKey = Key('t25-f-open-menu');

class _MenuProbe {
  _MenuProbe(this.tester);

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

  Color menuTextColor(String label) {
    final text = tester.widget<Text>(find.text(label));
    return text.style!.color!;
  }

  AppPalette paletteAt(String label) {
    final context = tester.element(find.text(label));
    return Theme.of(context).extension<AppPalette>()!;
  }
}

double _intactTextHeight(WidgetTester tester, String label) {
  final finder = find.text(label);
  final text = tester.widget<Text>(finder);
  final context = tester.element(finder);
  final style = DefaultTextStyle.of(context).style.merge(text.style);
  final painter = TextPainter(
    text: TextSpan(text: text.data, style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: null,
  )..layout(maxWidth: double.infinity);
  return painter.height;
}

Widget _compactControls() {
  return Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            key: const Key('f2-bare-40'),
            behavior: HitTestBehavior.opaque,
            onTap: () {},
            child: const SizedBox(width: 120, height: 40),
          ),
          IconButton(
            key: const Key('f2-icon'),
            // M3 IconButton 默认忽略 Theme.visualDensity，须在控件上显式 compact。
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            onPressed: () {},
            icon: const Icon(Icons.menu),
          ),
          TextButton(
            key: const Key('f2-text'),
            onPressed: () {},
            child: const Text('text'),
          ),
          Checkbox(
            key: const Key('f2-checkbox'),
            visualDensity: VisualDensity.compact,
            value: true,
            onChanged: (_) {},
          ),
          RadioGroup<int>(
            groupValue: 1,
            onChanged: (_) {},
            child: Radio<int>(
              key: const Key('f2-radio'),
              visualDensity: VisualDensity.compact,
              value: 1,
            ),
          ),
          Switch(key: const Key('f2-switch'), value: true, onChanged: (_) {}),
        ],
      ),
    ),
  );
}

bool _hitsTarget(WidgetTester tester, RenderObject target, Offset point) {
  return tester
      .hitTestOnBinding(point)
      .path
      .any((entry) => identical(entry.target, target));
}

double _hitHeightAtCenter(WidgetTester tester, Finder finder) {
  final target = tester.renderObject<RenderBox>(finder);
  final rect = tester.getRect(finder);
  final x = rect.center.dx;
  expect(
    _hitsTarget(tester, target, rect.center),
    isTrue,
    reason: '中心点必须先命中目标对象，否则扫描量不是该控件的命中区',
  );
  var top = rect.top;
  while (top > 0 && _hitsTarget(tester, target, Offset(x, top - 0.5))) {
    top -= 0.5;
  }
  var bottom = rect.bottom;
  final limit = tester.view.physicalSize.height;
  while (bottom < limit &&
      _hitsTarget(tester, target, Offset(x, bottom + 0.5))) {
    bottom += 0.5;
  }
  return bottom - top;
}

Future<Map<String, int>> _collectVisibleCounts(_MenuProbe probe) async {
  final counts = <String, int>{};
  for (final tab in const ['写作工具', '教学', '设置']) {
    final labels = switch (tab) {
      '写作工具' => _writingTools,
      '教学' => _teaching,
      _ => _settings,
    };
    final visible = await probe.visibleLabels(tab, labels);
    counts[tab] = visible.length;
    debugPrint('F3 $tab ${visible.length}/${labels.length} $visible');
  }
  return counts;
}

void main() {
  testWidgets('F1 字号 1.0/1.3/2.0/2.4/2.5 的未裁文字高度', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final probe = _MenuProbe(tester);
    final heights = <double, double>{};
    for (final scale in const [1.0, 1.3, 2.0, 2.4, 2.5]) {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      await probe.pump();
      expect(tester.takeException(), isNull, reason: '$scale× 不得产生布局异常');
      final intact = _intactTextHeight(tester, '章节列表');
      final rendered = tester.getRect(find.text('章节列表')).height;
      heights[scale] = intact;
      debugPrint('F1 scale=$scale intact=$intact rendered=$rendered');
      if (scale <= 2.4) {
        expect(rendered, closeTo(intact, 0.5), reason: '$scale× 未裁切时，两种量法应互证');
      }
    }
    expect(heights[2.0], inInclusiveRange(40, 48));
    expect(heights[2.5], greaterThan(48));
    expect(
      tester.getRect(find.text('章节列表')).height,
      lessThan(heights[2.5]!),
      reason: '阳性对照：2.5× 未裁高 >48，而 Text rect 被父级夹住',
    );
  });

  testWidgets('F2 compact 控件真实命中区与 48dp 判据', (tester) async {
    final theme = buildAppTheme().copyWith(
      platform: TargetPlatform.android,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.compact,
    );
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: _compactControls()),
    );
    final controls = <({String name, Finder finder, double hit, bool meets48})>[
      (
        name: 'IconButton',
        finder: find.byKey(const Key('f2-icon')),
        hit: 40,
        meets48: false,
      ),
      (
        name: 'TextButton',
        finder: find.byKey(const Key('f2-text')),
        hit: 40,
        meets48: false,
      ),
      (
        name: 'Checkbox',
        finder: find.byKey(const Key('f2-checkbox')),
        hit: 40,
        meets48: false,
      ),
      (
        name: 'Radio',
        finder: find.byKey(const Key('f2-radio')),
        hit: 40,
        meets48: false,
      ),
      (
        name: 'Switch',
        finder: find.byKey(const Key('f2-switch')),
        hit: 48,
        meets48: true,
      ),
    ];
    for (final control in controls) {
      final measured = _hitHeightAtCenter(tester, control.finder);
      final meets48 = measured >= 48;
      debugPrint('F2 ${control.name} hitH=$measured meets48=$meets48');
      expect(measured, closeTo(control.hit, 0.01), reason: control.name);
      expect(meets48, control.meets48, reason: '${control.name} 的 48dp 判据读数');
    }
    final bareFinder = find.byKey(const Key('f2-bare-40'));
    final bare = _hitHeightAtCenter(tester, bareFinder);
    debugPrint('F2 bare40 hitH=$bare meets48=${bare >= 48}');
    expect(bare, closeTo(40, 0.01), reason: '阳性对照必须精确量回 40dp');
    expect(bare >= 48, isFalse);
  });

  testWidgets('F3 393×851 与 360×800 三 tab 首屏可见数', (tester) async {
    final probe = _MenuProbe(tester);
    for (final size in const [Size(393, 851), Size(360, 800)]) {
      await probe.pump(size: size);
      expect(tester.takeException(), isNull, reason: '$size 不得有横向 overflow');
      final raw = await _collectVisibleCounts(probe);
      debugPrint('F3 $size raw=$raw');
      expect(raw['写作工具'], 5);
      expect(raw['设置'], 2);
      expect(
        raw['教学'],
        6,
        reason:
            '任务文字的 360 档 5/6 未复现：真实 Scrollable 视口到 800dp，'
            '第 6 项「大纲」文字完整可见；本用例记录真值，不伪造 5/6',
      );
    }
  });

  testWidgets('F4 亮暗 palette 与菜单文字色翻转', (tester) async {
    final probe = _MenuProbe(tester);
    final colors = <Brightness, Color>{};
    for (final theme in [buildAppTheme(), buildDarkTheme()]) {
      await probe.pump(theme: theme);
      final palette = probe.paletteAt('章节列表');
      final color = probe.menuTextColor('章节列表');
      colors[theme.brightness] = color;
      expect(color, palette.textInk);
      debugPrint(
        'F4 ${theme.brightness} surface=${palette.surface} textInk=${palette.textInk}',
      );
    }
    expect(AppPalette.light.surface, isNot(AppPalette.dark.surface));
    expect(AppPalette.light.textInk, isNot(AppPalette.dark.textInk));
    expect(colors[Brightness.light], isNot(colors[Brightness.dark]));
  });
}
