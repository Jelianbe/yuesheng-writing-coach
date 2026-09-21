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
import '../theme/app_typography.dart';
import '../config/app_palette.dart';

/// 严重度中文标签（对齐 RN SEVERITY_LABELS）
const Map<String, String> _severityLabels = {
  'L1': '建议',
  'L2': '注意',
  'L3': '严重',
};

/// 严重度 → （文字/圆点/边框色, 底色）
({Color text, Color bg}) _severityColors(
  BuildContext context,
  String severity,
) {
  switch (severity) {
    case 'L2':
      return (text: context.palette.l2Text, bg: context.palette.l2);
    case 'L3':
      return (text: context.palette.l3Text, bg: context.palette.l3);
    default:
      return (text: context.palette.l1Text, bg: context.palette.l1);
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

  /// 交互批 #5：「自选练习」页脚入口回调；为 null 时**整行不渲染**（不留死按钮）。
  /// 只在**非空态**接线——空态下自选候选必空，给按钮=假按钮（P0-3 护栏同纪律）。
  final VoidCallback? onSelfPractice;

  const TaskPanel({
    super.key,
    required this.problems,
    this.onMarkComplete,
    this.onRemove,
    this.onSelfPractice,
  });

  @override
  Widget build(BuildContext context) {
    if (problems.isEmpty) {
      // 空态（对齐 RN EmptyState：icon ✅ + 标题 + 描述）
      return Container(
        color: context.palette.background,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 28,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 批次66：✅ emoji → Material 图标（taste 审核：UI 图标走图标库）
            Icon(
              Icons.check_circle_outline,
              size: 40,
              color: context.palette.primary,
            ),
            SizedBox(height: 10),
            Text(
              '暂无活跃问题',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.palette.textPrimary,
              ),
            ),
            SizedBox(height: 6),
            Text(
              '完成诊断后会显示需要解决的问题',
              textAlign: TextAlign.center,
              style: context.text.subCaption,
            ),
          ],
        ),
      );
    }

    return Container(
      color: context.palette.background,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          // Header：练习任务 + N 个问题徽标
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '练习任务',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: context.palette.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smx,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: context.palette.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Text(
                    '${problems.length} 个问题',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.palette.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.palette.divider),
          // 问题行
          for (final problem in problems) _buildProblemRow(context, problem),
          // 交互批 #5：「练」的常驻可达点——「练」是六步闭环一环，此前唯一
          // 自选入口只挂在欢迎态（有历史即消失）。页脚挂在面板非空态：
          // 活跃问题在场 = 反向漏斗有候选 = 入口赚到了它的位置。
          if (onSelfPractice != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('self-practice-footer'),
                  onPressed: onSelfPractice,
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text(
                    '换个问题练？自选练习',
                    style: TextStyle(fontSize: 13),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: context.palette.primary,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 问题行：severity 色左边框 + 圆点 + 症候名 + 严重度标签 + 完成按钮
  Widget _buildProblemRow(BuildContext context, ActiveProblemView problem) {
    final severity = _severityColors(context, problem.severity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: context.palette.surface, width: 1),
        ),
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: context.palette.textPrimary,
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
                  color: context.palette.primary,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '完成',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.palette.onPrimary,
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
                  border: Border.all(color: context.palette.danger),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '移除',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: context.palette.danger,
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
