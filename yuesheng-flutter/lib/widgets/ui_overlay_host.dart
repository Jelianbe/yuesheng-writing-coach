// ─────────────────────────────────────────────────────────────
// ui_overlay_host — 全局覆盖层渲染（toast 队列 + 模态 confirm）
//
// 挂在 MaterialApp.builder 顶层，监听 uiOverlayProvider：
// - toast：顶部/底部轻提示，队列顺序展示，超时自动消失
// - confirm：模态确认（Promise 化 resolve 由 provider 驱动），
//   遮罩 + 卡片走现有竹青令牌，不引入新视觉
// 纯增量：存量 SnackBar/Dialog 调用点不动，新代码经 uiOverlayProvider
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../providers/ui_overlay_provider.dart';

/// 全局覆盖层宿主（挂 MaterialApp.builder）
class UiOverlayHost extends ConsumerWidget {
  const UiOverlayHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(uiOverlayProvider);
    return Stack(
      children: [
        // confirm 模态（至多一个挂起）
        if (state.confirm != null)
          Positioned.fill(
            child: _ConfirmScrim(
              key: ValueKey(state.confirm!.title),
              request: state.confirm!,
              onResolve: (result) {
                ref.read(uiOverlayProvider.notifier).resolveConfirm(result);
              },
            ),
          ),
        // toast 队列（底部堆叠，新 toast 在上）
        if (state.toasts.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final toast in state.toasts.reversed)
                    Padding(
                      padding: const EdgeInsets.only(
                        left: 24,
                        right: 24,
                        bottom: 8,
                      ),
                      child: _ToastCard(toast: toast),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Toast 卡片（竹青令牌：语义色字 + 白底卡片 + 圆角）
class _ToastCard extends StatelessWidget {
  final UiToast toast;
  const _ToastCard({required this.toast});

  Color get _accent {
    switch (toast.kind) {
      case UiToastKind.success:
        return AppColors.success;
      case UiToastKind.warning:
        return AppColors.warning;
      case UiToastKind.error:
        return AppColors.danger;
      case UiToastKind.info:
        return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              toast.message,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 模态确认遮罩 + 卡片
class _ConfirmScrim extends StatelessWidget {
  final UiConfirmRequest request;
  final ValueChanged<bool> onResolve;
  const _ConfirmScrim({
    super.key,
    required this.request,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 点遮罩 = 取消
      onTap: () => onResolve(false),
      child: Container(
        color: AppColors.overlay,
        alignment: Alignment.center,
        child: GestureDetector(
          onTap: () {},
          child: Container(
            width: 300,
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceWhite,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  request.message,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => onResolve(false),
                      child: Text(
                        request.cancelText,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => onResolve(true),
                      child: Text(
                        request.confirmText,
                        style: const TextStyle(
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
