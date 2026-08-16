// ─────────────────────────────────────────────────────────────
// AttitudeSuggestionBanner — 态度建议横幅（缺口清单 A 类）
// 真源：yuesheng-android/src/components/chat/AttitudeSuggestionBanner.tsx
//
// 升级建议：黄系底（警示语义）；降级建议：竹青底（轻松语义）。
// 包含标题 + 原因 + 「切换到X」接受按钮 + 「暂不」按钮。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../services/attitude_advisor.dart';

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
    final targetLabel = getAttitudeLabel(suggestion.targetLevel);

    final bgColor = isUpgrade ? AppColors.warningBg : AppColors.primarySoft;
    final borderColor = isUpgrade ? AppColors.l2 : AppColors.primary;
    final iconColor = isUpgrade ? AppColors.warning : AppColors.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isUpgrade ? Icons.arrow_upward : Icons.arrow_downward,
            size: 22,
            color: iconColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUpgrade ? '建议提升指导强度' : '建议调整为轻松模式',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  suggestion.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    // 接受：切换到目标档位
                    InkWell(
                      onTap: onAccept,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.textPrimary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '切换到$targetLabel',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.onPrimary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 暂不：关闭横幅
                    InkWell(
                      onTap: onDismiss,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.onPrimary.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '暂不',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
