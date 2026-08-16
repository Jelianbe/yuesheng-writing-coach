// ─────────────────────────────────────────────────────────────
// SubphaseIndicator — P2 子阶段胶囊指示（缺口清单第 5 项）
// 真源：yuesheng-android/src/components/chat/SubphaseIndicator.tsx
//
// 结构（对齐 RN）：
//   - 彩色胶囊：色点 + 子阶段文案
//   - DIAGNOSIS → 诊断中（info：primaryDeep）
//   - PRACTICE  → 练习中（warning：矿物黄）
//   - FEEDBACK  → 反馈中（success：竹青）
//   - subphase 为 null 时渲染空（对齐 RN return null）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../types/teaching_types.dart';

/// 子阶段文案（对齐 RN SUBPHASE_LABELS）
const Map<TeachingSubphase, String> subphaseLabels = {
  TeachingSubphase.diagnosis: '诊断中',
  TeachingSubphase.practice: '练习中',
  TeachingSubphase.feedback: '反馈中',
};

class SubphaseIndicator extends StatelessWidget {
  /// 当前子阶段（null 时不渲染）
  final TeachingSubphase? subphase;

  const SubphaseIndicator({super.key, this.subphase});

  @override
  Widget build(BuildContext context) {
    if (subphase == null) return const SizedBox.shrink();

    final (bg, text, dot) = switch (subphase!) {
      TeachingSubphase.diagnosis => (
        AppColors.primarySoft,
        AppColors.primaryDeep,
        AppColors.primaryDeep,
      ),
      TeachingSubphase.practice => (
        AppColors.warningBg,
        AppColors.warning,
        AppColors.warning,
      ),
      TeachingSubphase.feedback => (
        AppColors.primarySoft,
        AppColors.primary,
        AppColors.primary,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            subphaseLabels[subphase!]!,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: text,
            ),
          ),
        ],
      ),
    );
  }
}
