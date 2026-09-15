// ─────────────────────────────────────────────────────────────
// ChatPlusPanel — 聊天输入栏「+」按钮正上方的功能面板
//
// 设计动因（舰长 2026-09-15 真机反馈）：
//   - 「+」回归输入胶囊**左侧**，点击不再直接弹覆盖式 bottom sheet，
//     而是在「+」正上方浮出一块小面板；
//   - 原常驻于输入框上方的「思考」二值开关**收进本面板**，
//     不再单独占用一行垂直空间；
//   - 面板承载的仍是「+」原有功能（上传作品）+ 思考开关。
//
// 职责边界：本组件只描述面板**内容**；定位、防溢出钳制与关闭
// （点击外部 / 选中功能项后收起）由宿主 ChatInput 负责。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 「+」面板内容：功能项列表（当前为 上传作品 / 思考开关）。
class ChatPlusPanel extends StatelessWidget {
  /// 面板固定宽度（宿主按此值做水平防溢出钳制）。
  static const double width = 224;

  /// 上传作品项回调；null 时不渲染该项。
  final VoidCallback? onUpload;

  /// 思考开关当前状态（true = 档位非「关闭思考」）。
  final bool thinkingEnabled;

  /// 档位展示名（关闭态由本组件改写为「已关闭」）。
  final String reasoningTierLabel;

  /// 思考开关回调；null 时不渲染该项。
  final ValueChanged<bool>? onThinkingToggle;

  /// 生成中：开关禁用（防中途换档，与已发出的请求不一致）。
  final bool isStreaming;

  const ChatPlusPanel({
    super.key,
    this.onUpload,
    this.thinkingEnabled = true,
    this.reasoningTierLabel = '标准',
    this.onThinkingToggle,
    this.isStreaming = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasDivider = onUpload != null && onThinkingToggle != null;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.borderSoft, width: 0.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      // Overlay 子树中没有 Material 祖先，InkWell 会断言失败 ⇒ 自带一层
      // 透明 Material；ClipRRect 把水波纹裁进圆角。
      child: Material(
        type: MaterialType.transparency,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onUpload != null)
                _PanelActionRow(
                  icon: Icons.upload_file,
                  title: '上传作品',
                  subtitle: '导入稿件，开始诊断',
                  onTap: onUpload!,
                ),
              if (hasDivider) const _PanelDivider(),
              if (onThinkingToggle != null)
                _PanelThinkingRow(
                  enabled: thinkingEnabled,
                  tierLabel: reasoningTierLabel,
                  onChanged: isStreaming ? null : onThinkingToggle,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 面板内分隔线（左右留白，避免与外框圆角相撞）。
class _PanelDivider extends StatelessWidget {
  const _PanelDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(
      height: 1,
      thickness: 0.5,
      indent: AppSpacing.md,
      endIndent: AppSpacing.md,
      color: AppColors.borderSoft,
    );
  }
}

/// 面板内功能项行：图标 + 标题 + 副标题。
class _PanelActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PanelActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.smx,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.primary),
            const SizedBox(width: AppSpacing.smx),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 面板内思考开关行：图标 + 「思考」+ 档位副文案 + 开关。
/// 交互与旧的输入框上方开关行一致（只有开关自身可点，行本身不响应）。
class _PanelThinkingRow extends StatelessWidget {
  final bool enabled;
  final String tierLabel;
  final ValueChanged<bool>? onChanged;

  const _PanelThinkingRow({
    required this.enabled,
    required this.tierLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.primary : AppColors.textTertiary;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.psychology : Icons.psychology_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: AppSpacing.smx),
          const Text(
            '思考',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.xsm),
          Flexible(
            child: Text(
              enabled ? tierLabel : '已关闭',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          const Spacer(),
          // shrinkWrap + scale：把 Material 默认 48 高触控区压到与文案等高
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: enabled,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}
