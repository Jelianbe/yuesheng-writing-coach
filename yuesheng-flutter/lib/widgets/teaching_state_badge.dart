// ─────────────────────────────────────────────────────────────
// TeachingStateBadge — 教学状态徽章（缺口清单第 5 项）
// 真源：yuesheng-android/src/components/chat/TeachingStateBadge.tsx
//
// 结构（对齐 RN）：
//   - 色点 + 可选标签（sm/md/lg 三档尺寸）
//   - identified    → 刚识别（warning 矿物黄）
//   - in_progress   → 训练中（info：primaryDeep 深青）
//   - consolidating → 趋稳中（success：竹青）
//   - mastered      → 已掌握（disabledText 灰）
//
// 使用位置（对齐 RN StudentProfilePanel）：成长/画像页症候状态行
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../types/teaching_types.dart';

/// 徽章尺寸档位（对齐 RN BADGE_LAYOUT.sizes）
enum TeachingStateBadgeSize { sm, md, lg }

/// 教学状态文案（对齐 RN stateConfig.label）
const Map<TeachingState, String> teachingStateLabels = {
  TeachingState.identified: '刚识别',
  TeachingState.inProgress: '训练中',
  TeachingState.consolidating: '趋稳中',
  TeachingState.mastered: '已掌握',
};

class TeachingStateBadge extends StatelessWidget {
  /// 教学状态（identified/in_progress/consolidating/mastered）
  final TeachingState state;

  /// 尺寸档位（sm=6px 点 / md=8px / lg=10px）
  final TeachingStateBadgeSize size;

  /// 是否显示文字标签
  final bool showLabel;

  const TeachingStateBadge({
    super.key,
    required this.state,
    this.size = TeachingStateBadgeSize.md,
    this.showLabel = false,
  });

  /// 状态色（对齐 RN warning/info/success/textDisabled 语义）
  Color get _dotColor => switch (state) {
    TeachingState.identified => AppColors.warning,
    TeachingState.inProgress => AppColors.primaryDeep,
    TeachingState.consolidating => AppColors.primary,
    TeachingState.mastered => AppColors.disabledText,
  };

  double get _dotSize => switch (size) {
    TeachingStateBadgeSize.sm => 6,
    TeachingStateBadgeSize.md => 8,
    TeachingStateBadgeSize.lg => 10,
  };

  double get _fontSize => switch (size) {
    TeachingStateBadgeSize.sm => 10,
    TeachingStateBadgeSize.md => 11,
    TeachingStateBadgeSize.lg => 12,
  };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _dotSize,
          height: _dotSize,
          decoration: BoxDecoration(color: _dotColor, shape: BoxShape.circle),
        ),
        if (showLabel) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            teachingStateLabels[state]!,
            style: TextStyle(
              fontSize: _fontSize,
              fontWeight: FontWeight.w500,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
