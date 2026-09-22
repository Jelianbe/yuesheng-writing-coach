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
import '../config/app_palette.dart';

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
  ///
  /// ★ 2026-09-22（批次 M3）：由 `get _dotColor` 改为**接受 `BuildContext` 的方法**。
  ///   动因：令牌迁到 `context.palette.*` 后，getter 无法拿到 `BuildContext`
  ///   ⇒ `dart analyze` 报 `undefined_identifier`。本仓 P1 批同型处置先例：
  ///   `progress_detail_page._severityColor` / `manuscript_detail_modal._trendColor`
  ///   均改为「方法 + `BuildContext` 首参」，而非回退静态令牌。
  Color _dotColorOf(BuildContext context) => switch (state) {
    TeachingState.identified => context.palette.warning,
    TeachingState.inProgress => context.palette.primaryDeep,
    TeachingState.consolidating => context.palette.primary,
    TeachingState.mastered => context.palette.disabledText,
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
          decoration: BoxDecoration(
            color: _dotColorOf(context),
            shape: BoxShape.circle,
          ),
        ),
        if (showLabel) ...[
          const SizedBox(width: AppSpacing.sm),
          Text(
            teachingStateLabels[state]!,
            style: TextStyle(
              fontSize: _fontSize,
              fontWeight: FontWeight.w500,
              color: context.palette.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
