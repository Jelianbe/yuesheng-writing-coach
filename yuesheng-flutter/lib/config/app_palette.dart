// ─────────────────────────────────────────────────────────────
// app_palette — 运行期调色板（ThemeExtension）
//
// 【为什么需要它】
// `AppColors`（app_theme.dart）是 `static const Color` 集合 —— 编译期常量。
// 常量无法随 theme 变化，因此凡是写在 `const TextStyle(...)` /
// `const Icon(...)` 里的颜色，在暗色下**依然是亮色**，这是
// `main.dart:123-128`「批次99」把 buildDarkTheme 降级为假暗色的根因。
//
// `AppPalette` 走 `ThemeExtension<AppPalette>`，颜色在**运行期**从
// `Theme.of(context).extension<AppPalette>()` 取，因此可随 light/dark 切换。
//
// 【定位：铺路批次，不是暗色批次】
// 本批**只**新增调色板与注册，不改动任何页面代码。
// 存量 1737 处 `AppColors.*` 引用（其中 785 处在 739 个 const 表达式内，
// 见 `.ai/tmp/const_ctx_v2c.txt`）保持原样，可**逐文件增量迁移**到本调色板。
// ⇒ 本批落地后**用户看不到任何暗色变化**，这是预期行为。
//
// 【迁移方式（供后续批次）】
//   // 改前（const，颜色焊死）
//   child: const Text('标题', style: TextStyle(color: AppColors.textPrimary)),
//   // 改后（运行期，随主题变色）
//   final palette = Theme.of(context).extension<AppPalette>()!;
//   child: Text('标题', style: TextStyle(color: palette.textPrimary)),
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 运行期调色板：44 个语义令牌，light / dark 两套实例。
///
/// 字段与 [AppColors] **一一对应**（同名同义），便于逐文件迁移与对照。
/// 一致性由 `test/config/app_palette_contrast_test.dart` 的护栏守住：
///   - 字段数必须与 AppColors 令牌数相等（44）
///   - `AppPalette.light` 的每个值必须与 `AppColors` 同名字面量**相等**
///     （防止两套真源漂移）
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.primary,
    required this.onPrimary,
    required this.onPrimaryDim,
    required this.onPrimaryFaint,
    required this.primarySoft,
    required this.primaryDeep,
    required this.primaryAccent,
    required this.background,
    required this.surface,
    required this.surfaceWhite,
    required this.paper,
    required this.overlay,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textInk,
    required this.textBody,
    required this.textDeep,
    required this.border,
    required this.borderSoft,
    required this.borderLight,
    required this.divider,
    required this.l1,
    required this.l1Text,
    required this.l2,
    required this.l2Text,
    required this.l3,
    required this.l3Text,
    required this.danger,
    required this.dangerBg,
    required this.dangerBorder,
    required this.warning,
    required this.warningBg,
    required this.disabled,
    required this.disabledText,
    required this.placeholder,
    required this.hintText,
    required this.editorDarkSurface,
    required this.editorDarkPanel,
    required this.editorDarkText,
    required this.editorDarkMuted,
    required this.editorDarkDeepMuted,
    required this.success,
    required this.successBg,
  });

  // ── 主色 ──
  /// 品牌主色（竹青）
  final Color primary;

  /// 主色之上的前景色（深底白字族基色）
  final Color onPrimary;

  /// onPrimary 的次级变体（70% 白，次级信息）
  final Color onPrimaryDim;

  /// onPrimary 的弱化变体（24% 白，装饰/分隔）
  final Color onPrimaryFaint;

  /// 竹青淡（L1 共用底）
  final Color primarySoft;

  /// 深青次级文字
  final Color primaryDeep;

  /// 教学强调色（批注/重点提示，竹青同系加深一档）
  final Color primaryAccent;

  // ── 背景 / 表面 ──
  /// 页面背景
  final Color background;

  /// 卡片底
  final Color surface;

  /// 白底卡片（章节卡/弹窗）
  final Color surfaceWhite;

  /// 米纸（写作编辑器底）
  final Color paper;

  /// 弹窗遮罩（半透明黑）
  final Color overlay;

  // ── 文字 ──
  /// 主文字
  final Color textPrimary;

  /// 次级文字
  final Color textSecondary;

  /// 弱化文字/图标（caption 级）
  final Color textTertiary;

  /// 编辑器正文/菜单
  final Color textInk;

  /// 表单标签
  final Color textBody;

  /// 深青说明文字（建议卡等）
  final Color textDeep;

  // ── 边框 / 分隔 ──
  /// 标准边框
  final Color border;

  /// 柔和边框（气泡/输入框）
  final Color borderSoft;

  /// 细边框（拖拽手柄等）
  final Color borderLight;

  /// 章节卡边框/分隔
  final Color divider;

  // ── 矿物色严重度 ──
  /// 轻微（底）
  final Color l1;

  /// 轻微（文字）
  final Color l1Text;

  /// 中等（底）
  final Color l2;

  /// 中等（文字）
  final Color l2Text;

  /// 严重（底）
  final Color l3;

  /// 严重（文字）
  final Color l3Text;

  // ── 状态色 ──
  /// 危险文字/按钮
  final Color danger;

  /// 危险横幅底
  final Color dangerBg;

  /// 失败气泡边框
  final Color dangerBorder;

  /// 警示文字（修改中）
  final Color warning;

  /// 警示底
  final Color warningBg;

  // ── 禁用 / 占位 ──
  /// 禁用按钮底
  final Color disabled;

  /// 禁用文字
  final Color disabledText;

  /// 进度条未激活等
  final Color placeholder;

  /// 问卷示例文字
  final Color hintText;

  // ── 编辑器暗夜联动色 ──
  /// 写作页 AppBar/工具条暗夜底
  final Color editorDarkSurface;

  /// 暗夜正文底
  final Color editorDarkPanel;

  /// 暗夜主文字
  final Color editorDarkText;

  /// 暗夜次级文字
  final Color editorDarkMuted;

  /// 暗夜输入框/分隔底（**底色**，非前景）
  final Color editorDarkDeepMuted;

  // ── 正向色 ──
  /// 正向绿（深青偏绿）
  final Color success;

  /// 正向淡底
  final Color successBg;

  // ───────────────────────────────────────────────────────────
  // 亮色调色板
  //
  // ⚠️ 本实例的 44 个值**必须**与 `app_theme.dart` 的 `AppColors` 同名字面量
  //    完全相等。这是一条硬约束，由测试 `app_palette_contrast_test.dart`
  //    在编译期常量层面对账（防止两套真源漂移）。
  //    ⇒ 改动 AppColors 时**必须**同步本实例，否则测试变红。
  // ───────────────────────────────────────────────────────────
  static const AppPalette light = AppPalette(
    // 主色
    primary: Color(0xFF2D5A52),
    onPrimary: Colors.white,
    onPrimaryDim: Color(0xB3FFFFFF),
    onPrimaryFaint: Color(0x3DFFFFFF),
    primarySoft: Color(0xFFE8F0EE),
    primaryDeep: Color(0xFF4E6A5A),
    primaryAccent: Color(0xFF23574D),
    // 背景 / 表面
    background: Color(0xFFF7F8F6),
    surface: Color(0xFFF2F4F2),
    surfaceWhite: Color(0xFFFFFFFF),
    paper: Color(0xFFF5F1E8),
    overlay: Color(0x8A000000),
    // 文字
    textPrimary: Color(0xFF2D3142),
    textSecondary: Color(0xFF5F646B),
    textTertiary: Color(0xFF656C76),
    textInk: Color(0xFF1A1A1A),
    textBody: Color(0xFF4A4E54),
    textDeep: Color(0xFF4E6A5A),
    // 边框 / 分隔
    border: Color(0xFFE0E4E0),
    borderSoft: Color(0xFFE8EAED),
    borderLight: Color(0xFFE0E0E0),
    divider: Color(0xFFE8EAE8),
    // 矿物色严重度
    l1: Color(0xFFE8F0EE),
    l1Text: Color(0xFF2D5A52),
    l2: Color(0xFFF5E6B8),
    l2Text: Color(0xFF725610),
    l3: Color(0xFFE8C5C5),
    l3Text: Color(0xFF8B2323),
    // 状态色
    danger: Color(0xFFB3261E),
    dangerBg: Color(0xFFFDF0EF),
    dangerBorder: Color(0xFFE8C5C5),
    warning: Color(0xFFB45309),
    warningBg: Color(0xFFFFF4E5),
    // 禁用 / 占位
    disabled: Color(0xFFE8EAED),
    disabledText: Color(0xFFBDBDBD),
    placeholder: Color(0xFFD8DCE0),
    hintText: Color(0xFF6B6E76),
    // 编辑器暗夜联动色（亮色主题下沿用既有暗夜值，保持写作页暗夜预设可用）
    editorDarkSurface: EditorDarkAxis.surface,
    editorDarkPanel: EditorDarkAxis.panel,
    editorDarkText: EditorDarkAxis.text,
    editorDarkMuted: EditorDarkAxis.muted,
    editorDarkDeepMuted: EditorDarkAxis.deepMuted,
    // 正向色
    success: Color(0xFF3A7355),
    successBg: Color(0xFFE6F0E9),
  );

  // ───────────────────────────────────────────────────────────
  // 暗色调色板
  //
  // 推导依据（舰长裁定「从现有 editorDark* 令牌推导」）：
  //   - 基底锚点：`editorDarkPanel` #26282B（暗夜正文底）
  //   - 层级锚点：`editorDarkSurface` #1E2126（更深） / `editorDarkDeepMuted` #3A3F45（更浅）
  //   - 前景锚点：`editorDarkText` #E8EAED / `editorDarkMuted` #B4B9BE
  //   ⇒ 底族取 #1A1C1F ~ #2A2E34 区间（围绕锚点展开）
  //     文字族取 #E8EAED ~ #6B7076 区间（保持反向层级差）
  //     主色族把亮色 primary #2D5A52 提亮为 #6FA694（暗底上保对比度）
  //
  // 对比度已复算：28 个真实配对中 27 个达 WCAG AA(4.5)。
  //   唯一例外 `disabledText × background = 3.42` —— 属**禁用态**，
  //   WCAG 1.4.3 明确豁免禁用控件；在护栏测试中以具名豁免登记。
  //   详见 `.ai/tmp/v4_dark_draft.txt`。
  // ───────────────────────────────────────────────────────────
  static const AppPalette dark = AppPalette(
    // 主色（暗底需提亮，否则竹青在深底上对比度不足）
    // ⇒ **连带后果**：primary 变浅后，onPrimary 族必须**反向变深**。
    //   否则「浅底 + 浅字」不可读（实测：照抄亮色 70% 白得 1.84:1）。
    //   亮色是「深竹青底 + 白字」，暗色是「浅竹青底 + 深墨字」，语义不变、明度反转。
    primary: Color(0xFF6FA694),
    onPrimary: Color(0xFF10201C),
    // onPrimaryDim 在暗色下**改用实色而非 alpha**（#1A2E28 对 primary = 5.16:1）。
    // 原因：亮色的 70% 白在深底上能达 AA（实测 4.80），但把同一 alpha 搬到
    // 「浅底 + 深字」方向只有 3.59:1 —— 明度差在两个方向**不对称**。
    // 与其调 alpha（85% 才够，已失去「次级」语义），不如给一个同色相的实色：
    // 既保住「比 onPrimary 弱一档」的层级（5.16 vs 6.07），又避开
    // alpha 复合在跨层叠底时的歧义。
    onPrimaryDim: Color(0xFF1A2E28),
    onPrimaryFaint: Color(0x3D10201C),
    primarySoft: Color(0xFF24332E),
    primaryDeep: Color(0xFF9CC4B6),
    primaryAccent: Color(0xFF7FB5A3),
    // 背景 / 表面（层级：background 最深 → surfaceWhite 最浅）
    background: Color(0xFF1A1C1F),
    surface: Color(0xFF22252A),
    surfaceWhite: Color(0xFF2A2E34),
    paper: Color(0xFF1E2126),
    overlay: Color(0x8A000000),
    // 文字（反向层级：textPrimary 最亮 → hintText 最暗）
    textPrimary: Color(0xFFE8EAED),
    textSecondary: Color(0xFFBEC3C8),
    textTertiary: Color(0xFF9AA0A6),
    textInk: Color(0xFFECEEF0),
    textBody: Color(0xFFC4C9CE),
    textDeep: Color(0xFF8FB3A8),
    // 边框 / 分隔（暗底边框须比底色**亮**才是可见边框）
    border: Color(0xFF34383E),
    borderSoft: Color(0xFF2E3238),
    borderLight: Color(0xFF31353B),
    divider: Color(0xFF2C3035),
    // 矿物色严重度（底压暗、文字提亮，保持「同色相不同明度」语义）
    l1: Color(0xFF22332E),
    l1Text: Color(0xFF8FC7B4),
    l2: Color(0xFF3A3320),
    l2Text: Color(0xFFE0C070),
    l3: Color(0xFF3A2528),
    l3Text: Color(0xFFE89A9A),
    // 状态色（暗底上提亮，保 AA）
    danger: Color(0xFFE88880),
    dangerBg: Color(0xFF3A2528),
    dangerBorder: Color(0xFF4A2E31),
    warning: Color(0xFFE0A860),
    warningBg: Color(0xFF3A3120),
    // 禁用 / 占位
    disabled: Color(0xFF2C3035),
    disabledText: Color(0xFF6B7076),
    placeholder: Color(0xFF3F444A),
    hintText: Color(0xFF8A9098),
    // 编辑器暗夜联动色（暗色主题下与页面同调，不再需要单独一套暗夜底）
    editorDarkSurface: EditorDarkAxis.surface,
    editorDarkPanel: EditorDarkAxis.panel,
    editorDarkText: EditorDarkAxis.text,
    editorDarkMuted: EditorDarkAxis.muted,
    editorDarkDeepMuted: EditorDarkAxis.deepMuted,
    // 正向色（暗底上提亮，保 AA）
    success: Color(0xFF6FC08E),
    successBg: Color(0xFF22332A),
  );

  @override
  AppPalette copyWith({
    Color? primary,
    Color? onPrimary,
    Color? onPrimaryDim,
    Color? onPrimaryFaint,
    Color? primarySoft,
    Color? primaryDeep,
    Color? primaryAccent,
    Color? background,
    Color? surface,
    Color? surfaceWhite,
    Color? paper,
    Color? overlay,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textInk,
    Color? textBody,
    Color? textDeep,
    Color? border,
    Color? borderSoft,
    Color? borderLight,
    Color? divider,
    Color? l1,
    Color? l1Text,
    Color? l2,
    Color? l2Text,
    Color? l3,
    Color? l3Text,
    Color? danger,
    Color? dangerBg,
    Color? dangerBorder,
    Color? warning,
    Color? warningBg,
    Color? disabled,
    Color? disabledText,
    Color? placeholder,
    Color? hintText,
    Color? editorDarkSurface,
    Color? editorDarkPanel,
    Color? editorDarkText,
    Color? editorDarkMuted,
    Color? editorDarkDeepMuted,
    Color? success,
    Color? successBg,
  }) {
    return AppPalette(
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      onPrimaryDim: onPrimaryDim ?? this.onPrimaryDim,
      onPrimaryFaint: onPrimaryFaint ?? this.onPrimaryFaint,
      primarySoft: primarySoft ?? this.primarySoft,
      primaryDeep: primaryDeep ?? this.primaryDeep,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceWhite: surfaceWhite ?? this.surfaceWhite,
      paper: paper ?? this.paper,
      overlay: overlay ?? this.overlay,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textInk: textInk ?? this.textInk,
      textBody: textBody ?? this.textBody,
      textDeep: textDeep ?? this.textDeep,
      border: border ?? this.border,
      borderSoft: borderSoft ?? this.borderSoft,
      borderLight: borderLight ?? this.borderLight,
      divider: divider ?? this.divider,
      l1: l1 ?? this.l1,
      l1Text: l1Text ?? this.l1Text,
      l2: l2 ?? this.l2,
      l2Text: l2Text ?? this.l2Text,
      l3: l3 ?? this.l3,
      l3Text: l3Text ?? this.l3Text,
      danger: danger ?? this.danger,
      dangerBg: dangerBg ?? this.dangerBg,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      warning: warning ?? this.warning,
      warningBg: warningBg ?? this.warningBg,
      disabled: disabled ?? this.disabled,
      disabledText: disabledText ?? this.disabledText,
      placeholder: placeholder ?? this.placeholder,
      hintText: hintText ?? this.hintText,
      editorDarkSurface: editorDarkSurface ?? this.editorDarkSurface,
      editorDarkPanel: editorDarkPanel ?? this.editorDarkPanel,
      editorDarkText: editorDarkText ?? this.editorDarkText,
      editorDarkMuted: editorDarkMuted ?? this.editorDarkMuted,
      editorDarkDeepMuted: editorDarkDeepMuted ?? this.editorDarkDeepMuted,
      success: success ?? this.success,
      successBg: successBg ?? this.successBg,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) {
      return this;
    }
    return AppPalette(
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      onPrimaryDim: Color.lerp(onPrimaryDim, other.onPrimaryDim, t)!,
      onPrimaryFaint: Color.lerp(onPrimaryFaint, other.onPrimaryFaint, t)!,
      primarySoft: Color.lerp(primarySoft, other.primarySoft, t)!,
      primaryDeep: Color.lerp(primaryDeep, other.primaryDeep, t)!,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceWhite: Color.lerp(surfaceWhite, other.surfaceWhite, t)!,
      paper: Color.lerp(paper, other.paper, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textInk: Color.lerp(textInk, other.textInk, t)!,
      textBody: Color.lerp(textBody, other.textBody, t)!,
      textDeep: Color.lerp(textDeep, other.textDeep, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderSoft: Color.lerp(borderSoft, other.borderSoft, t)!,
      borderLight: Color.lerp(borderLight, other.borderLight, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      l1: Color.lerp(l1, other.l1, t)!,
      l1Text: Color.lerp(l1Text, other.l1Text, t)!,
      l2: Color.lerp(l2, other.l2, t)!,
      l2Text: Color.lerp(l2Text, other.l2Text, t)!,
      l3: Color.lerp(l3, other.l3, t)!,
      l3Text: Color.lerp(l3Text, other.l3Text, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBg: Color.lerp(dangerBg, other.dangerBg, t)!,
      dangerBorder: Color.lerp(dangerBorder, other.dangerBorder, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningBg: Color.lerp(warningBg, other.warningBg, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      disabledText: Color.lerp(disabledText, other.disabledText, t)!,
      placeholder: Color.lerp(placeholder, other.placeholder, t)!,
      hintText: Color.lerp(hintText, other.hintText, t)!,
      editorDarkSurface: Color.lerp(
        editorDarkSurface,
        other.editorDarkSurface,
        t,
      )!,
      editorDarkPanel: Color.lerp(editorDarkPanel, other.editorDarkPanel, t)!,
      editorDarkText: Color.lerp(editorDarkText, other.editorDarkText, t)!,
      editorDarkMuted: Color.lerp(editorDarkMuted, other.editorDarkMuted, t)!,
      editorDarkDeepMuted: Color.lerp(
        editorDarkDeepMuted,
        other.editorDarkDeepMuted,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      successBg: Color.lerp(successBg, other.successBg, t)!,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// editorDarkAxis — 编辑器「暗夜预设轴」的常量真源
//
// 为何单独成类，而不挂在 `AppPalette` 里：
//   Dart **禁止静态成员与实例成员同名** ⇒ 无法在 `AppPalette` 内既声明实例字段
//   `editorDarkSurface` 又声明同名静态常量（实测报 `conflicting_static_and_instance`）。
//   ⇒ 静态便捷值必须另起命名空间。
//
// 与 `AppPalette.editorDark*`（实例字段）的关系：
//   两者的值**必须一致**。一致性由 `test/config/app_palette_contrast_test.dart`
//   的成对断言守着 —— 它不是「又一份真源」，而是**无 BuildContext 语境下的视图**。
//
// ⚠️ 这是**过渡形态**：`editor_background_presets.dart` 的 `const` 列表在无
//    BuildContext 时只能读 const 字面量，故暂需本例。预设表迁往 palette 驱动
//    （批次 M2）后，本类应随之删除。
//
// 取值依据：`AppPalette.light` 与 `AppPalette.dark` 本组 5 值**实测逐字节相同**
// （编辑器预设轴独立于全局 ThemeMode —— R4 裁定 + Visual Studio 官方文档同构：
// 「editor color setting is separate from the IDE color theme」），故常量无歧义。
// ─────────────────────────────────────────────────────────────
abstract final class EditorDarkAxis {
  static const Color surface = Color(0xFF1E2126); // AppBar/工具条暗夜底
  static const Color panel = Color(0xFF26282B); // 暗夜正文底
  static const Color text = Color(0xFFE8EAED); // 暗夜主文字
  static const Color muted = Color(0xFFB4B9BE); // 暗夜次级文字
  static const Color deepMuted = Color(0xFF3A3F45); // 暗夜输入框/分隔底
}

/// 便捷取用扩展：`context.palette.textPrimary`
///
/// 迁移时比 `Theme.of(context).extension<AppPalette>()!` 更短。
///
/// ⚠️ 取不到扩展时**回退 [AppPalette.light] 并 debugPrint 告警**，而非抛错。
///   理由：生产里 MaterialApp 恒由主题注册表提供 extensions（不会缺）；缺扩展只会
///   发生在「未注册 AppPalette 的测试 harness（裸 MaterialApp）」或「局部 Theme 覆盖漏带
///   extensions」。抛错会让前者整批 widget 测试崩、后者难定位；回退 light 语义安全
///   （最坏是某子树在暗色下仍显示亮色 —— 视觉不一致，非崩溃/非数据错误），且 debug 下
///   仍打印告警保留可观测性。
extension AppPaletteContext on BuildContext {
  /// 取当前主题的运行期调色板；未注册时回退亮色并告警（见上）。
  AppPalette get palette {
    final p = Theme.of(this).extension<AppPalette>();
    if (p == null) {
      if (kDebugMode) {
        debugPrint(
          '[AppPalette] 当前 Theme 未注册 AppPalette 扩展，已回退 AppPalette.light。'
          '常见原因：测试用裸 MaterialApp，或局部 Theme(...) 覆盖漏带 extensions。',
        );
      }
      return AppPalette.light;
    }
    return p;
  }
}
