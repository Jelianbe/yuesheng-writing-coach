// ─────────────────────────────────────────────────────────────
// app_theme_contrast_test — 文字令牌对比度护栏（批次99b；批次 V-3 扩面）
//
// 背景：用户反馈「部分系统字体与背景色色差不足、可读性差」。
// 已查证：textTertiary（#858B92）对背景 #F7F8F6 仅 3.23:1，
// caption/microCaption/subCaption 等 11-13px 小号文字不达 WCAG AA
// 正文标准（4.5:1）。批次99b 加深 textSecondary / textTertiary /
// textDeep / primaryDeep。
//
// ── 批次 V-3 扩面（2026-09-19）──
// 1. 背景集合由**字面量**改为**令牌引用**，并新增第 5 底 `successBg`
//    （编辑器「护眼」预设的真实底色；其上 textTertiary = 4.55:1，
//     是全系统最薄余量且此前零守卫）。
// 2. ★ 口径：**只断言「真实配对」**（产品里真实出现过的 前景×底），
//    不做「前景色 × 全部底色」的笛卡尔积。
//    反例（实测）：若按机械口径，l2Text 对 4 个通用底是 5.09/4.77/4.60/4.51
//    **全部通过** ⇒ 它唯一的那条真红（对**自己的底** l2 = 4.09:1）会被完全漏掉。
//    判据：**「数值不达标」≠「缺陷」** —— 一条断言成立须同时满足
//    ① 数值 < 阈值 且 ② 该配对有真实调用点；缺 ② 即**假红**。
// 3. 新增 meta 断言两层（堵 fail-open）：
//    · `AppTextStyles` 档数 **读源码文本对账** —— Dart 无 `dart:mirrors`，
//      只能手工维护列表；不加对账则「新增第 10 档忘登记」不会红。
//    · `AppColors` **每个令牌都必须登记**（进断言 or 显式豁免+原因）——
//      新增令牌不致无声地落在护栏视野外（P0-5 正是这样漏掉的）。
// 4. 修 P0-5：编辑器「暗夜」预设下占位提示对 editorDarkPanel 仅 **2.79:1**
//    （连非文字 3:1 都不到）⇒ hint 色改为随预设联动并纳入本护栏。
//
// ★ 本护栏的**已知边界**：它只能验证「登记的配对达标」，**不能验证**
//   「产品没有用到未登记的配对」——后者需用法级扫描，另见报告待办。
// ─────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/config/editor_background_presets.dart';
import 'package:writingcoach/main.dart' show buildAppTheme, buildDarkTheme;

/// WCAG 相对亮度（0-1）
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

/// WCAG 对比度（1-21）
///
/// 前景若带 alpha（如 `onPrimaryDim` = 70% 白），**必须先复合到背景**再算亮度。
/// 否则 alpha 被忽略、把它当成纯白 —— 实测会把 4.80:1 误算成 7.79:1
/// （即「深底专用前景」被误判为「浅底上也达标」）。
double _contrastRatio(Color fg, Color bg) {
  final flattened = fg.a >= 1.0 ? fg : Color.alphaBlend(fg, bg);
  final l1 = _relativeLuminance(flattened);
  final l2 = _relativeLuminance(bg);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) => c.toARGB32().toRadixString(16).substring(2);

/// 通用浅底：白 / 页 / 卡 / 米纸 / 护眼
///
/// 前 4 项为批次99b 既有；`successBg` 为 V-3 新增（编辑器「护眼」预设的真实底色）。
const List<(String, Color)> _genericBgs = [
  ('白底 surfaceWhite', AppColors.surfaceWhite),
  ('页底 background', AppColors.background),
  ('卡片底 surface', AppColors.surface),
  ('米纸底 paper', AppColors.paper),
  ('护眼底 successBg', AppColors.successBg),
];

/// 正文/说明文字令牌（6 个，批次99b 既有；矩阵形态保持不变）
const List<(String, Color)> _bodyTokens = [
  ('textPrimary', AppColors.textPrimary),
  ('textInk', AppColors.textInk),
  ('textBody', AppColors.textBody),
  ('textSecondary', AppColors.textSecondary),
  ('textTertiary', AppColors.textTertiary),
  ('textDeep', AppColors.textDeep),
];

/// 一条「真实配对」检查：底用**令牌**而非字面量，阈值默认 AA 正文 4.5:1
void _pairTest(
  String fgName,
  Color fg,
  String bgName,
  Color bg, {
  double min = 4.5,
}) {
  final ratio = _contrastRatio(fg, bg);
  test(
    '$fgName 对 $bgName ≥${min.toStringAsFixed(1)}:1（实际 ${ratio.toStringAsFixed(2)}:1）',
    () {
      expect(
        ratio,
        greaterThanOrEqualTo(min),
        reason:
            '$fgName(#${_hex(fg)}) 在 $bgName(#${_hex(bg)}) 上仅 '
            '${ratio.toStringAsFixed(2)}:1 < ${min.toStringAsFixed(1)}:1',
      );
    },
  );
}

void main() {
  group('AppColors 文字令牌对比度（批次99b 护栏 + 批次 V-3 扩面）', () {
    _genericMatrixTests();
    _mineralTests();
    _semanticStateTests();
    _generalForegroundTests();
    _darkBackgroundOnlyTokensTests();
    _hierarchyTest();
    _editorPresetTests();
    _popupMenuTests();
    _metaCoverageTests();
  });
}

/// A. 6 个正文/说明令牌 × 5 个通用浅底（既有矩阵形态 + 新增 successBg 一列）
void _genericMatrixTests() {
  for (final (fgName, fg) in _bodyTokens) {
    for (final (bgName, bg) in _genericBgs) {
      _pairTest(fgName, fg, bgName, bg);
    }
  }
}

/// B. 矿物严重度三色 × **各自的底**（真实配对；边界项 5：同族应同档）
void _mineralTests() {
  _pairTest('l1Text', AppColors.l1Text, 'l1（轻微底）', AppColors.l1);
  _pairTest('l2Text', AppColors.l2Text, 'l2（中等底）', AppColors.l2);
  _pairTest('l3Text', AppColors.l3Text, 'l3（严重底）', AppColors.l3);

  test('矿物三色同档：对自身底均 ≥5.0 且最高/最低比 <1.6', () {
    final r1 = _contrastRatio(AppColors.l1Text, AppColors.l1);
    final r2 = _contrastRatio(AppColors.l2Text, AppColors.l2);
    final r3 = _contrastRatio(AppColors.l3Text, AppColors.l3);
    for (final (name, r) in [('l1', r1), ('l2', r2), ('l3', r3)]) {
      expect(
        r,
        greaterThanOrEqualTo(5.0),
        reason:
            '$name 档对比度 ${r.toStringAsFixed(2)}:1 < 5.0 —— 同族三色应同档，'
            '不应有一色掉队（V-3 前 l2Text 仅 4.09:1）',
      );
    }
    final lo = math.min(math.min(r1, r2), r3);
    final hi = math.max(math.max(r1, r2), r3);
    expect(
      hi / lo,
      lessThan(1.6),
      reason:
          '同族三色层级差过大：${hi.toStringAsFixed(2)}'
          ' / ${lo.toStringAsFixed(2)} = ${(hi / lo).toStringAsFixed(2)}',
    );
  });
}

/// C. 状态/教学语义色 × 有真实调用点的底（配对来源见各行注释）
void _semanticStateTests() {
  // danger：app_router.dart:58（页底空态图标）/ abandon_practice_modal.dart:73；
  //         gen_ui_quiz.dart:172 与 dangerBg 配对
  _pairTest('danger', AppColors.danger, 'dangerBg', AppColors.dangerBg);
  _pairTest(
    'danger',
    AppColors.danger,
    '白底 surfaceWhite',
    AppColors.surfaceWhite,
  );
  _pairTest('danger', AppColors.danger, '页底 background', AppColors.background);
  _pairTest('danger', AppColors.danger, '卡片底 surface', AppColors.surface);
  // warning：chapter_tree_drawer.dart:39（与 warningBg 配对）/ ability_chart.dart:28
  _pairTest('warning', AppColors.warning, 'warningBg', AppColors.warningBg);
  _pairTest(
    'warning',
    AppColors.warning,
    '白底 surfaceWhite',
    AppColors.surfaceWhite,
  );
  _pairTest('warning', AppColors.warning, '卡片底 surface', AppColors.surface);
  // success：version_time_machine_sheet.dart:403 与 gen_ui_quiz.dart:170（successBg 配对）；
  //          gen_ui_card.dart:302 是卡片上的**真文字**
  _pairTest('success', AppColors.success, 'successBg', AppColors.successBg);
  _pairTest(
    'success',
    AppColors.success,
    '白底 surfaceWhite',
    AppColors.surfaceWhite,
  );
  _pairTest(
    'success',
    AppColors.success,
    '页底 background',
    AppColors.background,
  );
  _pairTest('success', AppColors.success, '卡片底 surface', AppColors.surface);
  _pairTest('success', AppColors.success, '米纸底 paper', AppColors.paper);
}

/// D. 通用主色 / 次级说明文字（引用面广，取通用浅底）
void _generalForegroundTests() {
  // primary：全库 322 处引用（主色/图标/文字）
  for (final (bgName, bg) in _genericBgs) {
    _pairTest('primary', AppColors.primary, bgName, bg);
  }
  // primaryDeep：message_bubble.dart:372（primarySoft 气泡内）/
  //              teaching_state_badge.dart:51（卡片上的教学状态点）
  _pairTest(
    'primaryDeep',
    AppColors.primaryDeep,
    'primarySoft（竹青淡底）',
    AppColors.primarySoft,
  );
  _pairTest(
    'primaryDeep',
    AppColors.primaryDeep,
    '白底 surfaceWhite',
    AppColors.surfaceWhite,
  );
  _pairTest(
    'primaryDeep',
    AppColors.primaryDeep,
    '卡片底 surface',
    AppColors.surface,
  );
  // hintText：search_replace_sheet.dart:440 / quick_phrase_sheet.dart:140（输入框 hint）
  _pairTest(
    'hintText',
    AppColors.hintText,
    '白底 surfaceWhite',
    AppColors.surfaceWhite,
  );
  _pairTest('hintText', AppColors.hintText, '卡片底 surface', AppColors.surface);
}

/// E. 深底专用前景（`onPrimary` 族）—— 正向断言 + 语义契约
void _darkBackgroundOnlyTokensTests() {
  _pairTest('onPrimary', AppColors.onPrimary, 'primary（专底）', AppColors.primary);
  _pairTest(
    'onPrimaryDim',
    AppColors.onPrimaryDim,
    'primary（专底）',
    AppColors.primary,
  );

  test('契约：onPrimary 系「深底专用」，在任何浅底上必须 <3:1', () {
    // ⚠️ 诚实标注：本断言**不检查「谁用了它」**，只把「深底专用」这条语义
    // 写成机器判据。它的价值 = 当 primary 或某个浅底被改到语义漂移
    // （onPrimary 在浅底上变得「可读」）时能发现，而非阻止误用。
    // 真正的用法级守卫另见报告待办（P2）。
    for (final (bgName, bg) in _genericBgs) {
      expect(
        _contrastRatio(AppColors.onPrimary, bg),
        lessThan(3.0),
        reason:
            'onPrimary 在 $bgName 上不应达到非文字图形线 3:1 —— '
            '若此断言变红，说明 onPrimary 与浅底的关系已语义漂移，需人工复核',
      );
    }
  });
}

/// F. 三级文字层级不塌陷（批次99b 既有）
void _hierarchyTest() {
  test('文字层级：textPrimary > textSecondary > textTertiary（白底对比度）', () {
    const white = Color(0xFFFFFFFF);
    final p = _contrastRatio(AppColors.textPrimary, white);
    final s = _contrastRatio(AppColors.textSecondary, white);
    final t = _contrastRatio(AppColors.textTertiary, white);
    expect(
      p,
      greaterThan(s),
      reason:
          'primary(${p.toStringAsFixed(2)}) 应深于 '
          'secondary(${s.toStringAsFixed(2)})',
    );
    expect(
      s,
      greaterThan(t),
      reason:
          'secondary(${s.toStringAsFixed(2)}) 应深于 '
          'tertiary(${t.toStringAsFixed(2)})',
    );
    // 相邻层级至少拉开 0.5 对比度点，避免同屏糊成一团
    expect(s - t, greaterThan(0.5), reason: 'secondary 与 tertiary 层级差不足');
  });
}

/// G. 编辑器暗夜联动色 + 三预设立 hint 契约（P0-5）
void _editorPresetTests() {
  test('暗夜编辑色对 editorDarkPanel ≥4.5:1', () {
    final text = _contrastRatio(
      AppColors.editorDarkText,
      AppColors.editorDarkPanel,
    );
    final muted = _contrastRatio(
      AppColors.editorDarkMuted,
      AppColors.editorDarkPanel,
    );
    expect(text, greaterThanOrEqualTo(4.5));
    expect(muted, greaterThanOrEqualTo(4.5));
  });

  // P0-5 契约：每个预设的 hint 色对其**自身底色**必须 ≥4.5。
  // 该断言正是为堵住「预设底 × 未联动的写死 hint 色」这一类缺陷
  // （暗夜预设下 textTertiary 曾仅 2.79:1，而既有暗夜用例恰好绕开了它）。
  for (final preset in editorBackgroundPresets) {
    final ratio = _contrastRatio(preset.hintColor, preset.color);
    test('编辑器预设「${preset.label}」hint 色对自身底 ≥4.5:1'
        '（实际 ${ratio.toStringAsFixed(2)}:1）', () {
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            '预设「${preset.label}」底(#${_hex(preset.color)}) 上的 '
            'hint 色(#${_hex(preset.hintColor)}) 仅 ${ratio.toStringAsFixed(2)}:1 '
            '< 4.5:1 —— 空输入框时占位提示对用户不可读',
      );
    });
  }
}

/// H. PopupMenu 浮层钉白底深字（真机三批#3 护栏，批次99b 既有）
void _popupMenuTests() {
  final themes = [('亮主题', buildAppTheme()), ('暗主题', buildDarkTheme())];

  for (final (name, theme) in themes) {
    test('$name popupMenu 底=surfaceWhite、字=textPrimary', () {
      final pm = theme.popupMenuTheme;
      expect(
        pm.color,
        AppColors.surfaceWhite,
        reason: 'popupMenu 底色必须钉 surfaceWhite，防 M3 surfaceContainer 漂移',
      );
      expect(
        pm.textStyle?.color,
        AppColors.textPrimary,
        reason: 'popupMenu 文字必须钉 textPrimary',
      );
    });

    test('$name popupMenu 底×字对比度 ≥4.5:1', () {
      final bg = theme.popupMenuTheme.color!;
      final fg = theme.popupMenuTheme.textStyle!.color!;
      final ratio = _contrastRatio(fg, bg);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason:
            'popupMenu 文字 ${fg.toARGB32().toRadixString(16)} 对底色 '
            '${bg.toARGB32().toRadixString(16)} 仅 ${ratio.toStringAsFixed(2)}:1 '
            '< 4.5:1',
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────
// I. meta 覆盖：把「护栏自身会不会漏」变成机器判据
// ─────────────────────────────────────────────────────────────

/// `AppTextStyles` 的 9 档及各自颜色令牌名（Dart 无 `dart:mirrors`，只能手工维护）
const List<(String, TextStyle, String)> _textStyleTokens = [
  ('titleLg', AppTextStyles.titleLg, 'textPrimary'),
  ('titleMd', AppTextStyles.titleMd, 'textInk'),
  ('body', AppTextStyles.body, 'textSecondary'),
  ('microCaption', AppTextStyles.microCaption, 'textTertiary'),
  ('caption', AppTextStyles.caption, 'textTertiary'),
  ('noteCaption', AppTextStyles.noteCaption, 'textSecondary'),
  ('subCaption', AppTextStyles.subCaption, 'textTertiary'),
  ('subBody', AppTextStyles.subBody, 'textSecondary'),
  ('formLabel', AppTextStyles.formLabel, 'textBody'),
];

/// 已进入本护栏断言的令牌（19 个）
const Set<String> _coveredTokens = {
  // 通用矩阵（6）
  'textPrimary',
  'textInk',
  'textBody',
  'textSecondary',
  'textTertiary',
  'textDeep',
  // 通用前景，有调用点取证（6）
  'primary', 'primaryDeep', 'danger', 'warning', 'success', 'hintText',
  // 专底前景（5）
  'l1Text', 'l2Text', 'l3Text', 'onPrimary', 'onPrimaryDim',
  // 暗夜前景（2）
  'editorDarkText', 'editorDarkMuted',
};

/// 显式豁免的令牌（25 个）—— 每条**必须附原因**，否则 meta 断言不认可
const Map<String, String> _exemptTokens = {
  // 底色 / 表面（不判对比度）
  'background': '底色',
  'surface': '底色',
  'surfaceWhite': '底色（亦作 popupMenu 背景期望值）',
  'paper': '底色',
  'primarySoft': '底色',
  'l1': '底色',
  'l2': '底色',
  'l3': '底色',
  'warningBg': '底色',
  'successBg': '底色',
  'dangerBg': '底色',
  'editorDarkSurface': '底色',
  'editorDarkPanel': '底色',
  'editorDarkDeepMuted': '底色（非前景；app_theme.dart:89 自陈「输入框/分隔底」）',
  'overlay': '遮罩',
  // 图形 / 装饰（边界项 2：不卡 3:1 —— 卡了会一次红 4-6 处且无从修复）
  'border': '装饰性分隔',
  'borderSoft': '装饰性分隔',
  'borderLight': '装饰性分隔',
  'divider': '装饰性分隔',
  'dangerBorder': '装饰性分隔',
  'placeholder': '图形/装饰（进度条 track / 空态大图标）',
  'onPrimaryFaint': '装饰（24% 白；作圆形底与 1px 分隔线）',
  // 禁用桶（WCAG 1.4.3 明文豁免）
  'disabled': '禁用底',
  'disabledText': '禁用前景（豁免；其 ~44 处语义误用面另立 P2 项）',
  // 死令牌
  'primaryAccent': '0 调用点（V-3 全仓复核实测；P2 项：删孤岛）',
};

/// 取源码里某个 `abstract final class X { ... }` 的类体文本
String _classBody(String src, String className) {
  final m = RegExp(
    'abstract\\s+final\\s+class\\s+$className\\s*\\{(.*?)\\n\\}',
    dotAll: true,
  ).firstMatch(src);
  if (m == null) {
    fail(
      '未能在 lib/config/app_theme.dart 中定位 $className 类体 —— '
      '类名或结构已变，meta 对账失效',
    );
  }
  return m.group(1)!;
}

/// I. meta 覆盖：拆成 4 个小组（R-019 函数 ≤50 行）
void _metaCoverageTests() {
  _metaTextStyleCountTest();
  _metaTextStyleColorTest();
  _metaColorRegistryTest();
  _metaExemptReasonTest();
}

/// I-1. `AppTextStyles` 档数与源码文本对账。
///
/// Dart 无 `dart:mirrors` ⇒ 上面那个手工列表无法自动生成。手工列表的
/// fail-open 是「新增第 10 档字阶时若忘记登记，覆盖断言不会红」——
/// 而这恰是它要防的场景。故此处**读源码文本**对账。
void _metaTextStyleCountTest() {
  final src = File('lib/config/app_theme.dart').readAsStringSync();
  final declared = RegExp(
    r'static\s+const\s+TextStyle\s+\w+\s*=',
  ).allMatches(_classBody(src, 'AppTextStyles')).length;
  test('AppTextStyles 档数与源码文本对账（堵 fail-open）', () {
    expect(
      _textStyleTokens.length,
      declared,
      reason:
          'app_theme.dart 声明了 $declared 档 TextStyle，但测试只登记了 '
          '${_textStyleTokens.length} 档 —— 新增档未登记会让覆盖断言静默失效',
    );
  });
}

/// I-2. 每一档字阶的颜色都必须是「已进断言的令牌」
void _metaTextStyleColorTest() {
  test('AppTextStyles 每档 color 都落在已覆盖令牌内', () {
    for (final (name, style, tokenName) in _textStyleTokens) {
      expect(style.color, isNotNull, reason: '$name 无 color');
      expect(
        _coveredTokens.contains(tokenName),
        isTrue,
        reason:
            '$name 使用令牌 $tokenName，但该令牌不在已覆盖集合内 —— '
            '它没有对比度断言保护',
      );
    }
  });
}

/// I-3. `AppColors` 令牌登记完整性 —— 堵的正是 P0-5 的成因：
/// 护栏建在缺陷旁边、偏偏漏掉缺陷。
void _metaColorRegistryTest() {
  final src = File('lib/config/app_theme.dart').readAsStringSync();
  final declared = RegExp(
    r'static\s+const\s+Color\s+(\w+)\s*=',
  ).allMatches(_classBody(src, 'AppColors')).map((m) => m.group(1)!).toSet();

  test('AppColors 每个令牌都已登记（进断言 or 显式豁免）', () {
    final unregistered = declared
        .difference(_coveredTokens)
        .difference(_exemptTokens.keys.toSet());
    expect(
      unregistered,
      isEmpty,
      reason:
          '新增令牌未登记：$unregistered —— 请把它加入 _coveredTokens'
          '（并补断言）或 _exemptTokens（并写明原因）',
    );
  });

  test('登记表不含已不存在的令牌（防僵尸登记）', () {
    final ghost = _coveredTokens
        .union(_exemptTokens.keys.toSet())
        .difference(declared);
    expect(ghost, isEmpty, reason: '登记了不存在的令牌：$ghost —— 令牌可能已被删除或改名');
  });
}

/// I-4. 豁免必须附原因（无原因 = 没登记）
void _metaExemptReasonTest() {
  test('豁免项一律附原因（禁止空原因）', () {
    for (final entry in _exemptTokens.entries) {
      expect(
        entry.value.trim(),
        isNotEmpty,
        reason: '${entry.key} 的豁免原因为空 —— 无原因的豁免等于没有登记',
      );
    }
  });
}
