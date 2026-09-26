// ─────────────────────────────────────────────────────────────
// AttitudeSuggestionBanner — 态度建议横幅（缺口清单 A 类）
// 真源：yuesheng-android/src/components/chat/AttitudeSuggestionBanner.tsx
//
// 升级建议：黄系底（警示语义）；降级建议：竹青底（轻松语义）。
// 包含标题 + 原因 + 「切换到X」接受按钮 + 「暂不」按钮。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../services/attitude_advisor.dart';
import '../../theme/app_typography.dart';
import '../../config/app_palette.dart';

class AttitudeSuggestionBanner extends StatelessWidget {
  final AttitudeSuggestion suggestion;
  final VoidCallback onAccept;
  final VoidCallback onDismiss;

  const AttitudeSuggestionBanner({
    super.key,
    required this.suggestion,
    required this.onAccept,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isUpgrade = suggestion.direction == 'upgrade';

    final bgColor = isUpgrade
        ? context.palette.warningBg
        : context.palette.primarySoft;
    final borderColor = isUpgrade
        ? context.palette.l2
        : context.palette.primary;
    final iconColor = isUpgrade
        ? context.palette.warning
        : context.palette.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLeadingIcon(context, isUpgrade, iconColor),
          const SizedBox(width: 12),
          Expanded(child: _buildTextColumn(context, isUpgrade)),
        ],
      ),
    );
  }

  Widget _buildLeadingIcon(
    BuildContext context,
    bool isUpgrade,
    Color iconColor,
  ) {
    return Icon(
      isUpgrade ? Icons.arrow_upward : Icons.arrow_downward,
      size: 22,
      color: iconColor,
    );
  }

  Widget _buildTextColumn(BuildContext context, bool isUpgrade) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isUpgrade ? '建议提升指导强度' : '建议调整为轻松模式',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          suggestion.reason,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: context.text.subBody.copyWith(height: 1.4),
        ),
        const SizedBox(height: 10),
        _buildActionsRow(context),
      ],
    );
  }

  Widget _buildActionsRow(BuildContext context) {
    return Row(
      children: [
        _buildAcceptButton(context),
        const SizedBox(width: 12),
        _buildDismissButton(context),
      ],
    );
  }

  Widget _buildAcceptButton(BuildContext context) {
    final targetLabel = getAttitudeLabel(suggestion.targetLevel);
    return InkWell(
      onTap: onAccept,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: context.palette.textPrimary,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '切换到$targetLabel',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.palette.onPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildDismissButton(BuildContext context) {
    return InkWell(
      onTap: onDismiss,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: context.palette.onPrimary.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          '暂不',
          style: context.text.subBody.copyWith(fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
