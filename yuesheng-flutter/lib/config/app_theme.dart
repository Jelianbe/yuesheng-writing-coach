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
  static const double pill = 100; // 胶囊 / 药丸
}

/// 月色竹青间距令牌
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double page = 16; // 页面水平边距
}
