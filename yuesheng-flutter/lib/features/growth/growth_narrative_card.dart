// ─────────────────────────────────────────────────────────────
// growth_narrative_card — 「与上次相比」进步叙事卡（T-20261018-03 · B 议题）
//
// 视觉：对齐 growth_page _Card（surface + border + 圆角；成长页卡片同款容器）。
// 数据：[GrowthNarrative]（纯函数装配结果，services/growth_narrative.dart）。
// 文案：R-027 已批句式逐字渲染——本文件不含任何自造文案（锚串全在
//       NarrativeText；黑名单测试锚定条目文本无评价词）。
//
// 信息架构（设计批 §二）：置于成长主页 ListView 首位，与 FocusCard
// （当前焦点，前瞻）形成「回望 → 前瞻」对偶。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../services/growth_narrative.dart';
import '../../theme/app_typography.dart';

/// 「与上次相比」进步叙事卡。
///
/// 调用方守则：仅当 `!narrative.isEmpty` 时挂载（纯函数已保证空叙事不出卡，
/// 此处不设二级空态——不出卡即空态，对齐 A 卡纪律）。
class GrowthNarrativeCard extends StatelessWidget {
  final GrowthNarrative narrative;

  const GrowthNarrativeCard({super.key, required this.narrative});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: context.palette.surface,
          border: Border.all(color: context.palette.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                NarrativeText.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(narrative.anchorLabel, style: context.text.caption),
              const SizedBox(height: 12),
              ...narrative.items.map((item) => _buildItem(context, item)),
            ],
          ),
        ),
      ),
    );
  }

  /// 条目行：能力行为首条（略重），症候复诊行随其后（E-1 同款小字 + 图标）。
  Widget _buildItem(BuildContext context, NarrativeItem item) {
    final isAbility = item.type == NarrativeItemType.ability;
    return Padding(
      padding: EdgeInsets.only(
        bottom: isAbility ? AppSpacing.sm : AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isAbility ? Icons.trending_up : Icons.history,
            size: isAbility ? 14 : 12,
            color: context.palette.textTertiary,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              item.text,
              style: isAbility
                  ? TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.palette.textPrimary,
                    )
                  : context.text.microCaption,
            ),
          ),
        ],
      ),
    );
  }
}
