// ─────────────────────────────────────────────────────────────
// yue_sheet — 月笙弹窗统一入口（批次68 弹窗弹出收敛）
//
// 收敛点（对齐 Material 标准但全局一致）：
//   - 背景：AppColors.surfaceWhite（白底弹窗，区别于页面灰白底）
//   - 圆角：AppRadius.lg（顶部大圆角）
//   - 遮罩：AppColors.overlay（批次57 令牌）
//   - 动画：200ms easeOutCubic（默认 250ms）——起步快、收尾缓，弹出更跟手
// 调用方只需传 builder + isScrollControlled，特殊背景可覆盖。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_motion.dart';
import '../config/app_theme.dart';

/// 月笙统一底部弹层入口（替代散落的 showModalBottomSheet）
/// 批次88-3：默认 useSafeArea: true——弹层内容避让系统状态栏/导航条，
/// 避免排版设置等长弹层侵占系统按键交互区；特殊弹层可显式传 false 覆盖。
Future<T?> showYueModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = true,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  Color? backgroundColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    backgroundColor: backgroundColor ?? AppColors.surfaceWhite,
    barrierColor: AppColors.overlay,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    // 批次68：弹窗弹出收敛——200ms easeOutCubic（Material 默认 250ms）
    sheetAnimationStyle: AnimationStyle(
      duration: AppMotion.durationStandard,
      reverseDuration: AppMotion.durationStandard,
      curve: AppMotion.curveStandard,
    ),
  );
}
