// ─────────────────────────────────────────────────────────────
// pilot_metrics_card — 「引文锚定」卡（T-20261018-06 · D 议题）
//
// 视觉：对齐 growth_page _Card（ClipRRect + surface + border + 圆角；
//       成长页卡片同款容器，growth_narrative_card 同范式）。
// 数据：[PilotMetricsSummary]（纯函数装配结果，
//       services/pilot_metrics_summary.dart；经 pilotMetricsSummaryProvider）。
// 文案：R-027 已批五条逐字渲染——本文件不含任何自造文案（锚串全在
//       PilotMetricsText；黑名单测试锚定无评价词）。
//
// 隐私边界（DECISIONS §4-232 口径①②）：只呈聚合计数——payload 明细的
// 引文原文片段与症候 ID 在服务层已被丢弃（「拿不到」而非「不渲染」），
// 本卡结构上不可能出现原文；守卫 P1/P2 机器判据钉死该边界。
//
// 信息架构（设计批 §一）：置于成长主页「与上次相比」叙事卡（回望）之后，
// 不破坏「回望 → 前瞻」对偶；不出新页面/一级导航（竖屏宪法）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';
import '../../config/app_theme.dart';
import '../../services/pilot_metrics_summary.dart';
import '../../theme/app_typography.dart';

/// 「引文锚定」卡。
///
/// 调用方守则：仅当 `summary != null`（有 anchor_probe 记录）时挂载；
/// 零引文（aerPercent=null）由本卡出空态文案——不出「0%」假读数
/// （`aer: null` ≠ `aer: 0` 纪律同源）。
class PilotMetricsCard extends StatelessWidget {
  final PilotMetricsSummary summary;

  const PilotMetricsCard({super.key, required this.summary});

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
                PilotMetricsText.title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: context.palette.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(PilotMetricsText.description, style: context.text.caption),
              const SizedBox(height: 12),
              if (summary.aerPercent != null)
                _buildRateRow(context)
              else
                Text(PilotMetricsText.emptyItem, style: context.text.caption),
              const SizedBox(height: 12),
              // ⑤ 隐私注记（口径③「零外发」的诚实注记，常驻小字）
              Text(
                PilotMetricsText.privacyNote,
                style: context.text.microCaption,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ③ 数值行：「引文锚定率 {rate}% · 共 {count} 条引文」（逐字代入）。
  Widget _buildRateRow(BuildContext context) {
    final text = PilotMetricsText.rateItem
        .replaceAll('{rate}', '${summary.aerPercent}')
        .replaceAll('{count}', '${summary.evidenceCount}');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.link, size: 14, color: context.palette.textTertiary),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.palette.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
