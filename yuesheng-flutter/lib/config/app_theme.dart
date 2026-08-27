// ─────────────────────────────────────────────────────────────
// app_theme — 月色竹青设计令牌（全局唯一视觉常量来源）
//
// 背景：E2 界面审查修复——此前 19 个 UI 文件全部硬编码色值，
// 导致主色/边框/文字色各有 5+ 种近似但不一致的灰。本文件收敛
// 为唯一真源，各组件改为引用令牌，保证视觉一致性。
//
// 视觉规范（月色竹青 + 矿物色严重度）：
//   主色       #2D5A52（竹青）
//   背景       #F7F8F6（冷青灰白）
//   卡片底     #F2F4F2（灰白）
//   米纸       #F5F1E8（写作编辑器）
//   矿物色     L1=#E8F0EE / L2=#F5E6B8 / L3=#E8C5C5
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// 月色竹青调色板
abstract final class AppColors {
  // ── 主色 ──
  static const Color primary = Color(0xFF2D5A52); // 竹青
  static const Color onPrimary = Colors.white;
  // 批次56：onPrimary 降级变体——深底前景的次级/弱化层级（对齐 RN 深底白字族）
  static const Color onPrimaryDim = Color(0xB3FFFFFF); // 70% 白（次级信息）
  static const Color onPrimaryFaint = Color(0x3DFFFFFF); // 24% 白（装饰/分隔）
  static const Color primarySoft = Color(0xFFE8F0EE); // 竹青淡（L1 共用）
  static const Color primaryDeep = Color(0xFF5B7565); // 深青次级文字

  // ── 背景 / 表面 ──
  static const Color background = Color(0xFFF7F8F6); // 冷青灰白
  static const Color surface = Color(0xFFF2F4F2); // 卡片灰白
  static const Color surfaceWhite = Color(0xFFFFFFFF); // 白底卡片（章节卡/弹窗）
  static const Color paper = Color(0xFFF5F1E8); // 米纸（写作编辑器底）
  static const Color overlay = Color(0x8A000000); // 弹窗遮罩（black54 等值，批次57 令牌化）

  // ── 文字 ──
  static const Color textPrimary = Color(0xFF2D3142); // 主文字
  static const Color textSecondary = Color(
    0xFF6B7076,
  ); // 次级文字（对比度 4.68:1，达标 AA）
  static const Color textTertiary = Color(0xFF858B92); // 弱化文字/图标（对比度 3.23:1，达标）
  static const Color textInk = Color(0xFF1A1A1A); // 编辑器正文/菜单
  static const Color textBody = Color(0xFF4A4E54); // 表单标签
  static const Color textDeep = Color(0xFF5B7565); // 深青说明文字（建议卡等）

  // ── 边框 / 分隔 ──
  static const Color border = Color(0xFFE0E4E0); // 标准边框
  static const Color borderSoft = Color(0xFFE8EAED); // 柔和边框（气泡/输入框）
  static const Color borderLight = Color(0xFFE0E0E0); // 拖拽手柄等细边框
  static const Color divider = Color(0xFFE8EAE8); // 章节卡边框/分隔

  // ── 矿物色严重度（月色竹青定型）──
  static const Color l1 = Color(0xFFE8F0EE); // 轻微
  static const Color l1Text = Color(0xFF2D5A52);
  static const Color l2 = Color(0xFFF5E6B8); // 中等
  static const Color l2Text = Color(0xFF8B6914);
  static const Color l3 = Color(0xFFE8C5C5); // 严重
  static const Color l3Text = Color(0xFF8B2323);

  // ── 状态色（统一矿物红系，废弃 Material 默认红）──
  static const Color danger = Color(0xFFB3261E); // 危险文字/按钮
  static const Color dangerBg = Color(0xFFFDF0EF); // 危险横幅底
  static const Color dangerBorder = Color(0xFFE8C5C5); // 失败气泡边框（L3 共用）
  static const Color warning = Color(0xFFB45309); // 警示文字（修改中）
  static const Color warningBg = Color(0xFFFFF4E5); // 警示底

  // ── 禁用 / 占位 ──
  static const Color disabled = Color(0xFFE8EAED); // 禁用按钮底
  static const Color disabledText = Color(0xFFBDBDBD); // 禁用文字
  static const Color placeholder = Color(0xFFD8DCE0); // 进度条未激活等
  static const Color hintText = Color(0xFF6B6E76); // 问卷示例文字

  // ── 编辑器暗夜联动色（批次 X-037-P0-1 UI 审查，供写作页 AppBar/goal bar 与暗夜 preset 配平）──
  //   对比度（对 #26282B 基底）：editorDarkText 15.1:1 / editorDarkMuted 4.56:1 / editorDarkDeepMuted 6.28:1 —— 全达 WCAG AA
  static const Color editorDarkSurface = Color(0xFF1E2126); // AppBar/工具条暗夜底
  static const Color editorDarkPanel = Color(0xFF26282B); // 暗夜正文底（与预设「暗夜」一致）
  static const Color editorDarkText = Color(0xFFE8EAED); // 暗夜主文字
  static const Color editorDarkMuted = Color(0xFFB4B9BE); // 暗夜次级文字
  static const Color editorDarkDeepMuted = Color(0xFF3A3F45); // 暗夜输入框/分隔底（深灰）

  // ── 正向色（成功/已解决，矿物色系延伸，批次22）──
  static const Color success = Color(0xFF3E7C5B); // 正向绿（深青偏绿，与竹青同色调系）
  static const Color successBg = Color(0xFFE6F0E9); // 正向淡底（L1 同族）
}

/// 月色竹青圆角令牌
abstract final class AppRadius {
  static const double xs = 4; // 微型角标 / 色块（批次58 补位）
  static const double sm = 8; // 输入框 / 小元素
  static const double md = 12; // 卡片
  static const double lg = 16; // 弹窗 / 底部面板
  static const double xl = 24; // 大号胶囊 / 大面板（X-039-Batch1 补：全局 BR 24 全库 ≥1 文件）
  static const double pill = 100; // 胶囊 / 药丸
}

/// 月色竹青间距令牌
abstract final class AppSpacing {
  static const double xxs = 2; // 像素级细缝（X-039-Batch1 补：全库 33 次，EI:2 对齐）
  static const double xs = 4;
  static const double xsm = 6; // X-039-Batch1 补：xs→sm 中间，全库 50 次 EI:6
  static const double sm = 8;
  static const double smx = 10; // X-039-Batch1 补：sm→md 中间，全库 72 次 EI:10
  static const double md = 12;
  static const double lg = 16;
  static const double section = 20; // X-039-Batch1 补：区块级内边距，全库 30 次 EI:20
  static const double xl = 24;
  static const double xxl = 32; // X-039-Batch1 补：大区块/大标题内边距，全库 17 次 EI:32
  static const double page = 16; // 页面水平边距
}

/// 月色竹青文字样式令牌
///
/// 仅收敛全库高频重复且语义稳定的 TextStyle。非标组合（如 fontSize:13、
/// 字重与颜色变体不齐整的边缘用法）按 R-019「非标值保留」约定继续原样
/// 保留，避免令牌膨胀。
abstract final class AppTextStyles {
  // ── 标题族 ──
  /// 大标题 / 空状态主文字（fontSize:18 / w600 / textPrimary，全库多处重复）
  static const TextStyle titleLg = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  /// 章节标题 / 卡片标题（fontSize:14 / w600 / textInk）
  static const TextStyle titleMd = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: AppColors.textInk,
  );

  // ── 正文族 ──
  /// 次级说明文字（fontSize:14 / textSecondary，最高频重复）
  static const TextStyle body = TextStyle(
    fontSize: 14,
    color: AppColors.textSecondary,
  );

  /// 弱化辅助文字 / caption（fontSize:12 / textTertiary）
  static const TextStyle caption = TextStyle(
    fontSize: 12,
    color: AppColors.textTertiary,
  );

  /// 次级辅助文字 / subCaption（fontSize:13 / textTertiary，比 caption 大一档）
  /// 用于操作说明、辅助提示等略大于 caption 的弱化文字。频次 15 处，2026-08-27 新增。
  static const TextStyle subCaption = TextStyle(
    fontSize: 13,
    color: AppColors.textTertiary,
  );

  /// 次级正文 / subBody（fontSize:13 / textSecondary，比 body 小一档但同色）
  /// 用于次级说明、诊断描述、设置项说明等需要 secondary 级可读性的 13px 文字。
  /// 变体用 .copyWith(fontWeight/height) 扩展。频次 42 处（24 纯形 + 18 变体），2026-08-27 新增。
  static const TextStyle subBody = TextStyle(
    fontSize: 13,
    color: AppColors.textSecondary,
  );

  /// 表单标签 / 列表项标签（fontSize:14 / w500 / textBody）
  static const TextStyle formLabel = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    color: AppColors.textBody,
  );
}

/// 月色竹青容器样式令牌
///
/// 仅收敛高频重复的容器/输入框装饰组合。特殊形状（pill 药丸、
/// 圆形首字封面等）按 R-019 保留原样，避免令牌膨胀。
abstract final class AppBoxStyles {
  /// 标准输入框装饰（form 场景高频重复）
  ///
  /// 提供统一的 filled + 矩形 border + contentPadding 配置。
  /// 调用方只需传 hintText 等动态参数，无需重复书写完整结构。
  static InputDecoration standardInput({
    required String hintText,
    String? helperText,
    Widget? suffixIcon,
    Widget? prefixIcon,
    bool isDense = false,
  }) => InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: AppColors.textTertiary),
    helperText: helperText,
    suffixIcon: suffixIcon,
    prefixIcon: prefixIcon,
    filled: true,
    fillColor: AppColors.background,
    isDense: isDense,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.smx,
    ),
  );
}

/// 月色竹青按钮样式令牌
///
/// 仅收敛高频重复的按钮 styleFrom 组合。特殊按钮（胶囊药丸、
/// 自定义图标按钮等）按 R-019 保留原样，避免令牌膨胀。
abstract final class AppButtonStyles {
  /// 主按钮（ElevatedButton 竹青主色填充，全库多处重复）
  static ButtonStyle get primary => ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.onPrimary,
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.md,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
  );

  /// 次按钮（TextButton 灰白底 + 矩形 md 圆角 + lg/md padding）
  ///
  /// 用于 AlertDialog 取消按钮等高频重复场景。Batch3 凭空定义为
  /// `padding(vertical md only)`，但全库实际高频模式是
  /// `padding(lg, md)`（session_drawer / message_list /
  /// writing_coach_panel_teaching 3 处 AlertDialog 取消按钮完全一致，
  /// bookshelf_page 第 820 行原 padding(lg, md) 被 Batch3 替换时丢失
  /// 引入回归）。本修正恢复 padding 至 (lg, md)，2026-08-27 落地。
  static ButtonStyle get secondary => TextButton.styleFrom(
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
    ),
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
  );
}
