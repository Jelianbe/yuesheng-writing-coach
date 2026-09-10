// ─────────────────────────────────────────────────────────────
// ConfidenceBar — 置信条（批次 C：外来 Editorial Ink Knowledge Card
// confidence-bar 竹青化）
//
// 参考结构（custom/components/knowledge-card.json + preview）：
//   - anatomy：confidence-bar = label（11px mono）+ track（4px 高圆角
//     2px 浅底）+ fill（主题色）+ value（百分比）
//   - doNotInvent：expandable-card / card-with-actions
//
// 竹青化适配（月笙令牌）：
//   - track 底 AppColors.placeholder（浅灰青），fill AppColors.primary 竹青
//   - label/value 字号 11 走 noteCaption 语义，颜色 textTertiary / primary
//   - 高度 4px、圆角 AppRadius.xs，不引入玻璃效果（月笙扁平竹青体系）
//
// 数据诚实约束：value 必须来自真实数据（如诊断 payload.confidence），
// 调用方不得编造百分比。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 置信条：label + 4px 轨道 + 竹青填充 + 百分比
class ConfidenceBar extends StatelessWidget {
  final String? label;

  /// 0-1 置信值（真实数据来源）
  final double value;

  /// 是否在尾部渲染百分比
  final bool showValue;

  const ConfidenceBar({
    super.key,
    this.label,
    required this.value,
    this.showValue = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Expanded(child: _buildTrack()),
        if (showValue) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${((value.clamp(0.0, 1.0)) * 100).round()}%',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
        ],
      ],
    );
  }

  /// 轨道 + 竹青填充（宽度按 value 比例，4px 高）
  Widget _buildTrack() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        height: 4,
        color: AppColors.placeholder,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(color: AppColors.primary),
        ),
      ),
    );
  }
}
