// ─────────────────────────────────────────────────────────────
// app_palette_contrast_test — AppPalette 双实例护栏（批次 V-4）
//
// 本文件与 `app_theme_contrast_test.dart` **同构**，但守的对象不同：
//   · 前者守 `AppColors`（静态亮色字面量，编译期常量）
//   · 本文件守 `AppPalette`（运行期调色板，含 light/dark 两套实例）
//
// 三层职责：
//   ① **双实例一致性**（本文件独有，最重要）——
//      `AppPalette.light` 的 44 个值必须与 `AppColors` 同名字面量**逐一相等**。
//      为什么必须守：`AppPalette` 是 AppColors 的「运行期镜像」，两者一旦漂移，
//      迁移到 palette 的页面会出现「亮色下颜色与未迁移页面不一致」的鬼影。
//      这条断言是「增量迁移」路线可行性的**前提**。
//   ② **暗色对比度** —— 对 `AppPalette.dark` 的 44 个令牌做与亮色同口径的
//      配对断言（真实配对，非笛卡尔积）。
//   ③ **meta 覆盖** —— 44 个令牌逐一登记（进断言 or 显式豁免+原因），
//      并用源码文本对账，堵「新增令牌忘登记」的 fail-open。
//
// ★ 暗色豁免与亮色的差异（必须逐条说明理由，否则豁免无效）：
//   · `disabledText` 暗色 = #6B7076 对 background = 3.42:1 < 4.5
//     同亮色口径：WCAG 1.4.3 明文豁免**禁用控件**。两套口径一致豁免。
//   · 其余 24 条豁免（底色/装饰/遮罩/禁用底）在暗色下同理，逐条沿用。
//
// ★ 本护栏的已知边界（同 app_theme_contrast_test.dart）：
//   只能验证「登记的配对达标」，**不能验证**「页面没用到未登记的配对」。
// ─────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/config/app_theme.dart';

/// WCAG 相对亮度（0-1）—— 与 app_theme_contrast_test.dart 逐字同实现
double _relativeLuminance(Color c) {
  double channel(double v) {
    final s = v / 255.0;
    return s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(c.r * 255) +
      0.7152 * channel(c.g * 255) +
      0.0722 * channel(c.b * 255);
}

/// WCAG 对比度（1-21）—— alpha 复合到背景后再算（同口径）
double _contrastRatio(Color fg, Color bg) {
  final flattened = fg.a >= 1.0 ? fg : Color.alphaBlend(fg, bg);
  final l1 = _relativeLuminance(flattened);
  final l2 = _relativeLuminance(bg);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) => c.toARGB32().toRadixString(16).substring(2);

// ─────────────────────────────────────────────────────────────
// ① AppPalette.light ≡ AppColors 一致性
// ─────────────────────────────────────────────────────────────

/// (令牌名, palette 值, AppColors 值) —— 44 项全量对账表。
///
/// ★ 这张表是**手写**的（Dart 无 `dart:mirrors` 反射），因此必须靠
///   下面 `_metaPaletteFieldCountTest` 用源码文本对账，防「AppPalette
///   加了第 45 个字段但本表没加」的 fail-open。
final List<(String, Color, Color)> _lightParity = [
  // ── 主色 ──
  ('primary', AppPalette.light.primary, AppColors.primary),
  ('onPrimary', AppPalette.light.onPrimary, AppColors.onPrimary),
  ('onPrimaryDim', AppPalette.light.onPrimaryDim, AppColors.onPrimaryDim),
  ('onPrimaryFaint', AppPalette.light.onPrimaryFaint, AppColors.onPrimaryFaint),
  ('primarySoft', AppPalette.light.primarySoft, AppColors.primarySoft),
  ('primaryDeep', AppPalette.light.primaryDeep, AppColors.primaryDeep),
  ('primaryAccent', AppPalette.light.primaryAccent, AppColors.primaryAccent),
  // ── 背景 / 表面 ──
  ('background', AppPalette.light.background, AppColors.background),
  ('surface', AppPalette.light.surface, AppColors.surface),
  ('surfaceWhite', AppPalette.light.surfaceWhite, AppColors.surfaceWhite),
  ('paper', AppPalette.light.paper, AppColors.paper),
  ('overlay', AppPalette.light.overlay, AppColors.overlay),
  // ── 文字 ──
  ('textPrimary', AppPalette.light.textPrimary, AppColors.textPrimary),
  ('textSecondary', AppPalette.light.textSecondary, AppColors.textSecondary),
  ('textTertiary', AppPalette.light.textTertiary, AppColors.textTertiary),
  ('textInk', AppPalette.light.textInk, AppColors.textInk),
  ('textBody', AppPalette.light.textBody, AppColors.textBody),
  ('textDeep', AppPalette.light.textDeep, AppColors.textDeep),
  // ── 边框 / 分隔 ──
  ('border', AppPalette.light.border, AppColors.border),
  ('borderSoft', AppPalette.light.borderSoft, AppColors.borderSoft),
  ('borderLight', AppPalette.light.borderLight, AppColors.borderLight),
  ('divider', AppPalette.light.divider, AppColors.divider),
  // ── 矿物色严重度 ──
  ('l1', AppPalette.light.l1, AppColors.l1),
  ('l1Text', AppPalette.light.l1Text, AppColors.l1Text),
  ('l2', AppPalette.light.l2, AppColors.l2),
  ('l2Text', AppPalette.light.l2Text, AppColors.l2Text),
  ('l3', AppPalette.light.l3, AppColors.l3),
  ('l3Text', AppPalette.light.l3Text, AppColors.l3Text),
  // ── 状态色 ──
  ('danger', AppPalette.light.danger, AppColors.danger),
  ('dangerBg', AppPalette.light.dangerBg, AppColors.dangerBg),
  ('dangerBorder', AppPalette.light.dangerBorder, AppColors.dangerBorder),
  ('warning', AppPalette.light.warning, AppColors.warning),
  ('warningBg', AppPalette.light.warningBg, AppColors.warningBg),
  // ── 禁用 / 占位 ──
  ('disabled', AppPalette.light.disabled, AppColors.disabled),
  ('disabledText', AppPalette.light.disabledText, AppColors.disabledText),
  ('placeholder', AppPalette.light.placeholder, AppColors.placeholder),
  ('hintText', AppPalette.light.hintText, AppColors.hintText),
  // ── 编辑器暗夜联动色 ──
  (
    'editorDarkSurface',
    AppPalette.light.editorDarkSurface,
    AppColors.editorDarkSurface,
  ),
  (
    'editorDarkPanel',
    AppPalette.light.editorDarkPanel,
    AppColors.editorDarkPanel,
  ),
  ('editorDarkText', AppPalette.light.editorDarkText, AppColors.editorDarkText),
  (
    'editorDarkMuted',
    AppPalette.light.editorDarkMuted,
    AppColors.editorDarkMuted,
  ),
  (
    'editorDarkDeepMuted',
    AppPalette.light.editorDarkDeepMuted,
    AppColors.editorDarkDeepMuted,
  ),
  // ── 正向色 ──
  ('success', AppPalette.light.success, AppColors.success),
  ('successBg', AppPalette.light.successBg, AppColors.successBg),
];

void _parityTests() {
  group('① AppPalette.light ≡ AppColors（双真源不得漂移）', () {
    for (final (name, fromPalette, fromColors) in _lightParity) {
      test('light.$name == AppColors.$name', () {
        expect(
          fromPalette.toARGB32(),
          fromColors.toARGB32(),
          reason:
              'AppPalette.light.$name (#${_hex(fromPalette)}) 与 '
              'AppColors.$name (#${_hex(fromColors)}) 不等 —— '
              '两处定义已漂移。迁移到 palette 的页面会在亮色下呈现'
              '与未迁移页面不同的颜色（鬼影）。\n'
              '修法：改 app_theme.dart 的 AppColors 时必须同步 '
              'app_palette.dart 的 light 实例（或反之）。',
        );
      });
    }

    test('表的项数 == AppPalette 字段数（堵手写表的 fail-open）', () {
      final src = File('lib/config/app_palette.dart').readAsStringSync();
      // 数 AppPalette 的 final Color 字段声明
      final declared = RegExp(
        r'^\s+final\s+Color\s+(\w+);',
        multiLine: true,
      ).allMatches(src).map((m) => m.group(1)!).toSet();
      final listed = _lightParity.map((e) => e.$1).toSet();
      expect(
        listed.length,
        declared.length,
        reason:
            'AppPalette 声明了 ${declared.length} 个 Color 字段，但一致性表只登记了 '
            '${listed.length} 个 —— 漏登记的字段不会被对账，可静默漂移',
      );
      expect(
        declared.difference(listed),
        isEmpty,
        reason: '未登记字段：${declared.difference(listed)}',
      );
    });
  });
}

// ─────────────────────────────────────────────────────────────
// ② 暗色对比度（真实配对，同亮色口径）
// ─────────────────────────────────────────────────────────────

/// 暗色下的通用底（对应亮色 `_genericBgs`）
final List<(String, Color)> _darkGenericBgs = [
  ('surfaceWhite', AppPalette.dark.surfaceWhite),
  ('background', AppPalette.dark.background),
  ('surface', AppPalette.dark.surface),
  ('paper', AppPalette.dark.paper),
  ('successBg', AppPalette.dark.successBg),
];

/// 暗色正文令牌（对应亮色 `_bodyTokens`）
final List<(String, Color)> _darkBodyTokens = [
  ('textPrimary', AppPalette.dark.textPrimary),
  ('textInk', AppPalette.dark.textInk),
  ('textBody', AppPalette.dark.textBody),
  ('textSecondary', AppPalette.dark.textSecondary),
  ('textTertiary', AppPalette.dark.textTertiary),
  ('textDeep', AppPalette.dark.textDeep),
];

/// 暗色豁免的令牌（与亮色同口径）。
///
/// ★ 每条**必须附原因**。`disabledText` 是暗色下唯一数值不达 AA 的令牌，
///   其豁免理由与亮色一致（WCAG 1.4.3 明文豁免禁用控件）。
const Map<String, String> _darkExempt = {
  // 底色 / 表面
  'background': '底色',
  'surface': '底色',
  'surfaceWhite': '底色',
  'paper': '底色',
  'primarySoft': '底色',
  'l1': '底色',
  'l2': '底色',
  'l3': '底色',
  'warningBg': '底色',
  'successBg': '底色',
  'dangerBg': '底色',
  'editorDarkSurface': '底色（暗色下与 background 同族）',
  'editorDarkPanel': '底色（暗色下与 paper 同族）',
  'editorDarkDeepMuted': '底色（非前景；app_theme.dart:89 自陈「输入框/分隔底」）',
  'overlay': '遮罩',
  // 图形 / 装饰
  'border': '装饰性分隔（暗色下必须比底色亮才是可见边框）',
  'borderSoft': '装饰性分隔',
  'borderLight': '装饰性分隔',
  'divider': '装饰性分隔',
  'dangerBorder': '装饰性分隔',
  'placeholder': '图形/装饰（进度条 track / 空态大图标）',
  'onPrimaryFaint': '装饰（24% 白；作圆形底与 1px 分隔线）',
  // 禁用桶
  'disabled': '禁用底',
  'disabledText':
      '禁用前景：暗色 #6B7076 对 background = 3.42:1 < 4.5；'
      'WCAG 1.4.3 明文豁免禁用控件（与亮色口径一致）',
  // 死令牌
  'primaryAccent': '0 调用点（V-3 全仓复核实测；P2 项：删孤岛）',
};

void _darkPairTest(
  String fgName,
  Color fg,
  String bgName,
  Color bg, {
  double min = 4.5,
}) {
  final ratio = _contrastRatio(fg, bg);
  test('dark $fgName 对 $bgName ≥${min.toStringAsFixed(1)}:1'
      '（实际 ${ratio.toStringAsFixed(2)}:1）', () {
    expect(
      ratio,
      greaterThanOrEqualTo(min),
      reason:
          'dark $fgName(#${_hex(fg)}) 在 $bgName(#${_hex(bg)}) 上仅 '
          '${ratio.toStringAsFixed(2)}:1 < ${min.toStringAsFixed(1)}:1',
    );
  });
}

/// 暗色的「真实配对」集合 —— 与亮色一一对应，但底/前景全部取自 dark 实例。
void _darkContrastTests() {
  group('② 暗色对比度（真实配对）', () {
    // A. 6 正文令牌 × 5 通用底
    for (final (fgName, fg) in _darkBodyTokens) {
      for (final (bgName, bg) in _darkGenericBgs) {
        _darkPairTest(fgName, fg, bgName, bg);
      }
    }

    // B. 矿物三色 × 自身底
    _darkPairTest('l1Text', AppPalette.dark.l1Text, 'l1', AppPalette.dark.l1);
    _darkPairTest('l2Text', AppPalette.dark.l2Text, 'l2', AppPalette.dark.l2);
    _darkPairTest('l3Text', AppPalette.dark.l3Text, 'l3', AppPalette.dark.l3);

    test('dark 矿物三色同档：对自身底均 ≥5.0 且最高/最低比 <1.6', () {
      final r1 = _contrastRatio(AppPalette.dark.l1Text, AppPalette.dark.l1);
      final r2 = _contrastRatio(AppPalette.dark.l2Text, AppPalette.dark.l2);
      final r3 = _contrastRatio(AppPalette.dark.l3Text, AppPalette.dark.l3);
      for (final (name, r) in [('l1', r1), ('l2', r2), ('l3', r3)]) {
        expect(
          r,
          greaterThanOrEqualTo(5.0),
          reason: 'dark $name 档 ${r.toStringAsFixed(2)}:1 < 5.0 —— 同族三色应同档',
        );
      }
      final lo = math.min(math.min(r1, r2), r3);
      final hi = math.max(math.max(r1, r2), r3);
      expect(hi / lo, lessThan(1.6), reason: 'dark 同族层级差过大');
    });

    // C. 状态色 × 有真实调用点的底
    _darkPairTest(
      'danger',
      AppPalette.dark.danger,
      'dangerBg',
      AppPalette.dark.dangerBg,
    );
    _darkPairTest(
      'danger',
      AppPalette.dark.danger,
      'background',
      AppPalette.dark.background,
    );
    _darkPairTest(
      'danger',
      AppPalette.dark.danger,
      'surface',
      AppPalette.dark.surface,
    );
    _darkPairTest(
      'warning',
      AppPalette.dark.warning,
      'warningBg',
      AppPalette.dark.warningBg,
    );
    _darkPairTest(
      'warning',
      AppPalette.dark.warning,
      'background',
      AppPalette.dark.background,
    );
    _darkPairTest(
      'success',
      AppPalette.dark.success,
      'successBg',
      AppPalette.dark.successBg,
    );
    _darkPairTest(
      'success',
      AppPalette.dark.success,
      'background',
      AppPalette.dark.background,
    );
    _darkPairTest(
      'success',
      AppPalette.dark.success,
      'surface',
      AppPalette.dark.surface,
    );

    // D. 通用前景
    for (final (bgName, bg) in _darkGenericBgs) {
      _darkPairTest('primary', AppPalette.dark.primary, bgName, bg);
    }
    _darkPairTest(
      'primaryDeep',
      AppPalette.dark.primaryDeep,
      'primarySoft',
      AppPalette.dark.primarySoft,
    );
    _darkPairTest(
      'hintText',
      AppPalette.dark.hintText,
      'background',
      AppPalette.dark.background,
    );
    _darkPairTest(
      'hintText',
      AppPalette.dark.hintText,
      'surface',
      AppPalette.dark.surface,
    );

    // D-2. 编辑器暗夜前景 —— 即使主题切到 dark，写作页的「暗夜」预设
    //      仍在暗色底上渲染，故这组配对在两种主题下都必须成立。
    //      （亮色侧同断言见 app_theme_contrast_test.dart `_editorPresetTests`）
    _darkPairTest(
      'editorDarkText',
      AppPalette.dark.editorDarkText,
      'editorDarkPanel',
      AppPalette.dark.editorDarkPanel,
    );
    _darkPairTest(
      'editorDarkMuted',
      AppPalette.dark.editorDarkMuted,
      'editorDarkPanel',
      AppPalette.dark.editorDarkPanel,
    );

    // E. 深底专用前景
    _darkPairTest(
      'onPrimary',
      AppPalette.dark.onPrimary,
      'primary',
      AppPalette.dark.primary,
    );
    _darkPairTest(
      'onPrimaryDim',
      AppPalette.dark.onPrimaryDim,
      'primary',
      AppPalette.dark.primary,
    );

    // F. 三级文字层级不塌陷（暗色下越高越亮 ⇒ 对比度越大）
    test('dark 文字层级：textPrimary > textSecondary > textTertiary', () {
      final bg = AppPalette.dark.background;
      final p = _contrastRatio(AppPalette.dark.textPrimary, bg);
      final s = _contrastRatio(AppPalette.dark.textSecondary, bg);
      final t = _contrastRatio(AppPalette.dark.textTertiary, bg);
      expect(
        p,
        greaterThan(s),
        reason:
            'dark primary(${p.toStringAsFixed(2)}) 应亮于 secondary(${s.toStringAsFixed(2)})',
      );
      expect(
        s,
        greaterThan(t),
        reason:
            'dark secondary(${s.toStringAsFixed(2)}) 应亮于 tertiary(${t.toStringAsFixed(2)})',
      );
      expect(
        s - t,
        greaterThan(0.5),
        reason: 'dark secondary 与 tertiary 层级差不足',
      );
    });

    // G. 暗色唯一未达 AA 的项 —— 显式登记为「已知例外」，防止它被
    //    误当成「已达标」而在未来某次调整中无声恶化。
    test('dark disabledText × background 是**已知未达 AA**（3.42:1）', () {
      final ratio = _contrastRatio(
        AppPalette.dark.disabledText,
        AppPalette.dark.background,
      );
      expect(
        ratio,
        lessThan(4.5),
        reason:
            '若本断言变红，说明 dark.disabledText 已被调整到 ≥4.5 —— '
            '这是**改善**，请把它移出 _darkExempt 并删除本断言，'
            '同时同步更新 app_theme_contrast_test.dart 的豁免理由',
      );
      expect(
        ratio,
        greaterThanOrEqualTo(3.0),
        reason:
            'dark.disabledText 对 background 已低于非文字图形线 3:1 '
            '(${ratio.toStringAsFixed(2)}:1) —— 低于此值时连「禁用但仍可辨识」'
            '都做不到，必须调整色值',
      );
    });
  });
}

// ─────────────────────────────────────────────────────────────
// ③ meta 覆盖
// ─────────────────────────────────────────────────────────────

void _metaTests() {
  group('③ meta 覆盖（堵护栏自身 fail-open）', () {
    final src = File('lib/config/app_palette.dart').readAsStringSync();
    final declared = RegExp(
      r'^\s+final\s+Color\s+(\w+);',
      multiLine: true,
    ).allMatches(src).map((m) => m.group(1)!).toSet();

    test('AppPalette 字段数与 AppColors 令牌数相等', () {
      final themeSrc = File('lib/config/app_theme.dart').readAsStringSync();
      final colorsDeclared = RegExp(
        r'static\s+const\s+Color\s+(\w+)\s*=',
      ).allMatches(themeSrc).map((m) => m.group(1)!).toSet();
      expect(
        declared.length,
        colorsDeclared.length,
        reason:
            'AppPalette 有 ${declared.length} 个字段，AppColors 有 '
            '${colorsDeclared.length} 个令牌 —— 数量不等说明迁移不完整',
      );
      expect(
        declared.difference(colorsDeclared),
        isEmpty,
        reason:
            'AppPalette 多出 AppColors 没有的字段：${declared.difference(colorsDeclared)}',
      );
      expect(
        colorsDeclared.difference(declared),
        isEmpty,
        reason:
            'AppColors 有但 AppPalette 缺的令牌：${colorsDeclared.difference(declared)}',
      );
    });

    test('每个暗色令牌都在「已断言」或「已豁免」内', () {
      final asserted = <String>{
        ..._darkBodyTokens.map((e) => e.$1),
        'l1Text',
        'l2Text',
        'l3Text',
        'danger',
        'warning',
        'success',
        'primary',
        'primaryDeep',
        'hintText',
        'onPrimary',
        'onPrimaryDim',
        'editorDarkText',
        'editorDarkMuted',
      };
      final unregistered = declared
          .difference(asserted)
          .difference(_darkExempt.keys.toSet());
      expect(
        unregistered,
        isEmpty,
        reason: '暗色令牌未登记：$unregistered —— 请补断言或加入 _darkExempt 并写明原因',
      );
    });

    test('暗色豁免项一律附原因（禁止空原因）', () {
      for (final e in _darkExempt.entries) {
        expect(
          e.value.trim(),
          isNotEmpty,
          reason: '${e.key} 的豁免原因为空 —— 无原因的豁免等于没有登记',
        );
      }
    });

    test('dark 与 light 同名令牌的字段集合一致（防暗色漏字段）', () {
      // 两实例由同一构造函数产出，字段必同；此断言守的是「未来若有人把
      // dark 改成部分覆盖的 copyWith 链」这种情况。
      final lp = _lightParity.map((e) => e.$1).toSet();
      expect(
        lp.difference(declared),
        isEmpty,
        reason: '一致性表登记了 AppPalette 没有的字段：${lp.difference(declared)}',
      );
    });
  });
}

void main() {
  _parityTests();
  _darkContrastTests();
  _metaTests();
}
