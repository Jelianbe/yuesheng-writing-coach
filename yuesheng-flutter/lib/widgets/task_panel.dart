// ─────────────────────────────────────────────────────────────
// TaskPanel — 活跃问题面板（缺口清单 C 类：弹层与工具）
// 真源：yuesheng-android/src/components/chat/TaskPanel.tsx
//
// 记忆硬约束：TaskPanel 仅保留活跃问题列表，教学建议部分移除
// （教学建议已移至对话流 TeacherSuggestionCard）。
//
// 结构：
//   1. 空态（无活跃问题）：✅ + 「暂无活跃问题」+「完成诊断后会显示需要解决的问题」
//   2. Header：「练习任务」+ 数量徽标「N 个问题」+ 分隔线
//   3. 问题行：severity 色左边框 + 圆点 + 症候名 + 严重度中文标签 + 「完成」按钮
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/repositories/diagnosis_repository.dart';

/// 严重度中文标签（对齐 RN SEVERITY_LABELS）
const Map<String, String> _severityLabels = {
  'L1': '建议',
  'L2': '注意',
  'L3': '严重',
};

/// 严重度 → （文字/圆点/边框色, 底色）
({Color text, Color bg}) _severityColors(String severity) {
  switch (severity) {
    case 'L2':
      return (text: AppColors.l2Text, bg: AppColors.l2);
    case 'L3':
      return (text: AppColors.l3Text, bg: AppColors.l3);
    default:
      return (text: AppColors.l1Text, bg: AppColors.l1);
  }
}

class TaskPanel extends StatelessWidget {
  /// 活跃问题列表（ActiveProblemView：syndromeId/syndromeName/severity）
  final List<ActiveProblemView> problems;

  /// 「完成」按钮回调；为 null 时不显示按钮（对齐 RN onMarkComplete 可选）
  final void Function(String syndromeId)? onMarkComplete;

  /// 批次75：「移除」按钮回调；为 null 时不显示按钮。
  /// 语义与「完成」不同——移除 = 学员主观不想再追踪该条目（物理删行）。
  final void Function(String syndromeId)? onRemove;

  const TaskPanel({
    super.key,
    required this.problems,
    this.onMarkComplete,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (problems.isEmpty) {
      // 空态（对齐 RN EmptyState：icon ✅ + 标题 + 描述）
      return Container(
        color: AppColors.background,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 28),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 批次66：✅ emoji → Material 图标（taste 审核：UI 图标走图标库）
            Icon(
              Icons.check_circle_outline,
              size: 40,
              color: AppColors.primary,
            ),
            SizedBox(height: 10),
            Text(
              '暂无活跃问题',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '完成诊断后会显示需要解决的问题',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            ),
          ],
        ),
      );
    }

    return Container(
      color: AppColors.background,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header：练习任务 + N 个问题徽标
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '练习任务',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smx,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Text(
                    '${problems.length} 个问题',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          // 问题行
          for (final problem in problems) _buildProblemRow(problem),
        ],
      ),
    );
  }

  /// 问题行：severity 色左边框 + 圆点 + 症候名 + 严重度标签 + 完成按钮
  Widget _buildProblemRow(ActiveProblemView problem) {
    final severity = _severityColors(problem.severity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surface, width: 1)),
      ),
      child: Row(
        children: [
          // severity 色左边框（3dp）+ 圆点（8dp）
          Container(
            padding: const EdgeInsets.only(left: AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: severity.text, width: 3)),
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: severity.text,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 170),
                  child: Text(
                    problem.syndromeName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _severityLabels[problem.severity] ?? problem.severity,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: severity.text,
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (onMarkComplete != null)
            InkWell(
              onTap: () => onMarkComplete!(problem.syndromeId),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xsm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.onPrimary,
                  ),
                ),
              ),
            ),
          if (onRemove != null) ...[
            const SizedBox(width: 8),
            // 批次75：移除按钮——学员主观不再追踪该条目（物理删行）
            InkWell(
              onTap: () => onRemove!(problem.syndromeId),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xsm,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.danger),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Text(
                  '移除',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.danger,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
