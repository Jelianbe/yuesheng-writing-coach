// ─────────────────────────────────────────────────────────────
// writing_page 视图层：页面骨架件（错误视图 / 划词浮动菜单 / 可拖动对话按钮）
//
// 由 C92-6a 伪拆分清偿自 writing_page.dart 提取为独立 StatelessWidget
// （R-019：独立类 / 显式接口，非 part 伪拆分）。
// 行为与原实现逐字等价：Key（`aiChatFab`）/ 文案 / 令牌 / 拖动语义零变化。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';

/// 加载失败视图（含重试）
class WritingErrorView extends StatelessWidget {
  const WritingErrorView({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        // X-039-Batch1：32→xxl
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

/// B3 划词诊断：浮动菜单（批次82 P0-④ 扩展为 诊断/改写/续写 三动作，
/// 现收敛为「诊断这段文字」单项）
/// 批次95-1：菜单跟随选区（RenderEditable 定位 + 屏幕外翻转）
class WritingSelectionMenu extends StatelessWidget {
  const WritingSelectionMenu({
    super.key,
    required this.position,
    required this.onDiagnose,
  });

  /// 相对正文 Stack 的左上角（已由宿主完成定位与翻转计算）
  final Offset position;

  final VoidCallback onDiagnose;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: position.dx,
      top: position.dy,
      child: Material(
        color: AppColors.surfaceWhite,
        elevation: 2,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _WritingSelectionMenuItem(
              label: '诊断这段文字',
              icon: Icons.search,
              onTap: onDiagnose,
            ),
          ],
        ),
      ),
    );
  }
}

/// 批次82 P0-④：划词浮动菜单项（icon + 文字，点击执行动作）
class _WritingSelectionMenuItem extends StatelessWidget {
  const _WritingSelectionMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        // X-039-Batch1：12→md / 8→sm
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 批次88-2：对话按钮（body Stack 内可拖动浮层）
/// 长按拖动换位 + 松手持久化（持久化由宿主 onDragEnd 负责）；
/// 点击 = 切换教练面板（与长按拖动互不冲突）。
class WritingDraggableFab extends StatelessWidget {
  const WritingDraggableFab({
    super.key,
    required this.left,
    required this.top,
    required this.isPanelOpen,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onPressed,
  });

  /// 浮层左上角（宿主已完成默认位/拖动位的 clamp 计算）
  final double left;
  final double top;

  final bool isPanelOpen;

  /// 长按开始：回传手势全局坐标（宿主据此记录拖动起点基准）
  final void Function(Offset globalPosition) onDragStart;

  /// 长按移动：回传手势全局坐标（宿主用全局位移差值计算新位置，避免坐标系漂移）
  final void Function(Offset globalPosition) onDragUpdate;

  final VoidCallback onDragEnd;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: (details) => onDragStart(details.globalPosition),
        onLongPressMoveUpdate: (details) =>
            onDragUpdate(details.globalPosition),
        onLongPressEnd: (_) => onDragEnd(),
        child: FloatingActionButton(
          key: const Key('aiChatFab'),
          backgroundColor: AppColors.primary,
          // 点击 = 切换教练面板（与长按拖动互不冲突）
          onPressed: onPressed,
          child: Icon(
            isPanelOpen ? Icons.close : Icons.chat_bubble_outline,
            color: AppColors.onPrimary,
          ),
        ),
      ),
    );
  }
}
