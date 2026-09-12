// ─────────────────────────────────────────────────────────────
// WritingCoachPanel 的展示型 Widget（独立类，正常 import，无 part）
//
// R-019 真分解：从 _WritingCoachPanelState 抽出的纯展示组件——
//   WritingCoachButtonRow    按钮行（快速观察 | 诊断本章 | ✕ 关闭）
//   WritingCoachErrorBanner  错误横幅
//   WritingCoachInputBar     输入栏（TextField + 发送/停止按钮）
// 所有状态与回调都通过构造参数显式传入，不隐式依赖任何 State 私有成员。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../providers/chat_store.dart';

/// 按钮行：快速观察 | 诊断本章（左）| 关闭 ✕（右）
///
/// D5-A：流式/诊断中时禁用按钮，避免重复触发
/// 批次69（A7 双通道）：「快速观察」= 实时通道（轻 prompt，Editor 观察）
class WritingCoachButtonRow extends StatelessWidget {
  final bool isStreaming;
  final VoidCallback onObserve;
  final VoidCallback onDiagnose;
  final VoidCallback onClose;

  const WritingCoachButtonRow({
    super.key,
    required this.isStreaming,
    required this.onObserve,
    required this.onDiagnose,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // 批次82 P0-④：侧栏宽度受限 → 收紧按钮内边距，避免窄屏溢出
    final btnStyle = TextButton.styleFrom(
      // X-039-Batch1：8→sm
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      minimumSize: const Size(0, 36),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    return Row(
      children: [
        _iconButton(
          style: btnStyle,
          icon: Icons.bolt,
          label: '快速观察',
          onPressed: isStreaming ? null : onObserve,
        ),
        _iconButton(
          style: btnStyle,
          icon: Icons.analytics_outlined,
          label: '诊断本章',
          onPressed: isStreaming ? null : onDiagnose,
        ),
        const Spacer(),
        IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      ],
    );
  }

  /// 单个图标按钮（禁用态置灰，保持与旧实现一致的配色）。
  Widget _iconButton({
    required ButtonStyle style,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) {
    final color = onPressed == null
        ? AppColors.disabledText
        : AppColors.primary;
    return TextButton.icon(
      style: style,
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      label: Text(label, style: TextStyle(fontSize: 13, color: color)),
    );
  }
}

/// 错误横幅：浅红底 + 错误图标 + 错误文本 + 关闭按钮
class WritingCoachErrorBanner extends StatelessWidget {
  /// 原始错误文本（release 下静默，不展示技术细节）
  final String error;

  /// 关闭（清除错误）回调
  final VoidCallback onDismiss;

  const WritingCoachErrorBanner({
    super.key,
    required this.error,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.dangerBg,
      // X-039-Batch1：12→md
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // release 静默：不向用户展示异常技术细节（对齐 P2-7 铁律）
              kDebugMode ? error : '发送失败，请稍后重试',
              style: const TextStyle(color: AppColors.danger, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close, size: 16, color: AppColors.danger),
          ),
        ],
      ),
    );
  }
}

/// 输入栏：TextField + 发送/停止按钮，回车发送
///
/// ADR-C87：流式进行中发送按钮变「停止生成」按钮（对齐主流 AI 对话）。
class WritingCoachInputBar extends StatelessWidget {
  final ChatState chatState;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final VoidCallback onStop;

  const WritingCoachInputBar({
    super.key,
    required this.chatState,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    // P1-7 修复：键盘弹起时输入栏需要加上 viewInsets.bottom 的 padding，
    // 否则输入栏会被键盘完全顶出可视区。
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      // X-039-Batch1：16→lg / 8→sm / +bottomInset（动态值，不令牌）
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm + bottomInset,
      ),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderLight)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(
                hintText: '问教练...',
                border: OutlineInputBorder(
                  // X-039-Batch1：24→xl
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  // X-039-Batch1：16→lg / 10→smx
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.smx,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildSendStopButton(),
        ],
      ),
    );
  }

  /// ADR-C87：发送 / 停止生成按钮（流式进行中切换为停止，可中止生成）。
  Widget _buildSendStopButton() {
    return IconButton(
      icon: chatState.isStreaming
          ? const Icon(Icons.stop, color: AppColors.primary)
          : const Icon(Icons.send, color: AppColors.primary),
      tooltip: chatState.isStreaming ? '停止生成' : '发送',
      onPressed: chatState.isStreaming ? onStop : onSend,
    );
  }
}
