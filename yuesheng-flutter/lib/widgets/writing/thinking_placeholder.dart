// ─────────────────────────────────────────────────────────────
// 思考 / 诊断中占位组件（从 writing_coach_panel.dart 拆出）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';

/// 思考 / 诊断中的占位提示（批次49：阶段标签优先显示）
class ThinkingPlaceholder extends StatelessWidget {
  final bool isDiagnosing;

  /// 批次49：阶段标签（诊断/评估等），非空时优先显示（如「正在诊断本章…」）
  final String? label;

  const ThinkingPlaceholder({super.key, this.isDiagnosing = false, this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label ?? (isDiagnosing ? '诊断中…' : '思考中…'),
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
