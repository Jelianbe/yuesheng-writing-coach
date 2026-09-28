// ─────────────────────────────────────────────────────────────
// yue_sheet — 月笙弹窗统一入口（批次68 弹窗弹出收敛）
//
// 收敛点（对齐 Material 标准但全局一致）：
//   - 背景：`context.palette.surfaceWhite`（白底弹窗，区别于页面灰白底）
//     ★ 2026-09-21（D1-a）：此前写死为**静态白话表面色**（`surfaceWhite` 静态
//     const）⇒ 暗色下仍是白底。此处是**全仓弹层统一入口**，扇出 35 个调用点
//     （仅 4 个显式传背景）⇒ 改这一行即收敛 ≈31 个弹层。亮色下两者
//     逐字节同值（`0xFFFFFFFF`）⇒ 像素级零变化。
//   - 圆角：AppRadius.lg（顶部大圆角）
//   - 遮罩：AppColors.overlay（批次57 令牌）
//   - 动画：200ms easeOutCubic（默认 250ms）——起步快、收尾缓，弹出更跟手
// 调用方只需传 builder + isScrollControlled，特殊背景可覆盖。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_motion.dart';
import '../config/app_palette.dart';
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
    backgroundColor: backgroundColor ?? context.palette.surfaceWhite,
    barrierColor: context.palette.overlay,
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

/// 底部 Sheet 统一骨架：标题 + 分隔线 + 内容（可滚动）+ 操作行。
///
/// P0-3：多字段表单（新建 / 编辑 / 断言 / 教练等）从居中 AlertDialog 收敛
/// 底部时复用，保证标题样式、边距、键盘上推与 [YueInputSheet] 完全一致。
/// [child] 为表单内容（Column），本组件负责 SafeArea / viewInsets 上推 /
/// 内容可滚动兜底。
class YueSheetScaffold extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  final Widget child;

  const YueSheetScaffold({
    super.key,
    required this.title,
    required this.actions,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        // 键盘弹起时上推内容，避免遮挡表单
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.section,
                AppSpacing.lg,
                AppSpacing.section,
                AppSpacing.sm,
              ),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: context.palette.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1),
            Flexible(child: SingleChildScrollView(child: child)),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.section,
                0,
                AppSpacing.section,
                AppSpacing.section,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
