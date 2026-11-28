// T-20261125-01 F 面环境探针：只读真实 WritingMenuSheet，不改产品逻辑。
//
// F1 用 DefaultTextStyle 合并 Text.style 后由 TextPainter 在无裁切约束下量高；
// tester.getRect(Text) 只作阳性对照，不承担未裁高度判据。
// F2 是「当前缺陷特征记录」，不是 ≥48dp 放行门：compact 下四类控件的
// 真实命中高为 40dp，属于已知债务；meets48=false 钉的是当前特征，不代表
// 质量门已通过。未来若修到 48dp，应更新这些期望值，并保留裸 40dp 阴性对照。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/theme/app_theme.dart';

import '../test_support/t25_f_probe_harness.dart';

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

void main() {
  testWidgets('F1 字号 1.0/1.3/2.0/2.4/2.5 的未裁文字高度', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final probe = T25FProbeHarness(tester);
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
    // 保留既有测试名；本用例只记录当前缺陷特征，不宣称 48dp 质量门通过。
    // IconButton/TextButton/Checkbox/Radio 的 40dp 是已知债务；未来修复后
    // 更新对应期望，并继续用裸 40dp 作阴性对照，证明量法仍能识别不达标。
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
    expect(bare, closeTo(40, 0.01), reason: '48dp 判据的阴性对照必须精确量回 40dp');
    expect(bare >= 48, isFalse);
  });

  testWidgets('F3 393×851 与 360×800 三 tab 首屏可见数', (tester) async {
    final probe = T25FProbeHarness(tester);
    for (final size in const [Size(393, 851), Size(360, 800)]) {
      await probe.pump(size: size);
      expect(tester.takeException(), isNull, reason: '$size 不得有横向 overflow');
      final raw = await probe.collectVisibleCounts();
      debugPrint('F3 $size raw=$raw');
      expect(raw['写作工具'], 5);
      expect(raw['设置'], 2);
      expect(
        raw['教学'],
        6,
        reason:
            '旧 F 报告的 360 档 5/6 未复现：真实 Scrollable 视口到 800dp，'
            '第 6 项「大纲」文字完整可见；本用例记录真值，不伪造 5/6',
      );
    }
  });

  testWidgets('F3 矮视口阴性对照：visibleLabels 随视口高度减少', (tester) async {
    final probe = T25FProbeHarness(tester);
    await probe.pump(size: const Size(360, 800));
    final baseline = await probe.collectVisibleCounts();

    await probe.pump(size: const Size(360, 640));
    expect(tester.takeException(), isNull, reason: '矮视口不得有布局异常');
    final shorter = await probe.collectVisibleCounts();
    debugPrint('F3 negative baseline=$baseline shorter=$shorter');

    // 只钉「更矮 ⇒ 可见数减少」这一性质，不写死旧 F 报告的 5/6。
    // 同时要求仍有可见项，避免把「全部出屏」误当作有效阴性对照。
    for (final tab in const ['写作工具', '教学']) {
      expect(
        shorter[tab],
        lessThan(baseline[tab]!),
        reason: '$tab 在 360×640 下应有更少标签完整可见',
      );
      expect(shorter[tab], greaterThan(0), reason: '$tab 阴性对照不能退化成全部不可见');
    }
  });

  testWidgets('F4 亮暗 palette 与菜单文字色翻转', (tester) async {
    final probe = T25FProbeHarness(tester);
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
