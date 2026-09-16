// ─────────────────────────────────────────────────────────────
// PracticeTaskCard — 练习任务卡片
// 复刻 yuesheng-android/src/components/diagnosis/PracticeTaskCard.tsx
//
// 结构：
//   1. Header：练习任务
//   2. 症候名 chip（竹青淡底）
//   3. 任务描述
//   4. 练习目标
//   5. 作答输入（多行 TextField）
//   5.5 自评区（P0-1 教学线，全部可选）：信心 1-5 / 解释 / 迁移
//   6. 操作：跳过 | 提交作答
//
// 视觉规范（月色竹青）：
//   - 卡片：#F7F8F6 + 圆角 12 + 边框
//   - 症候 chip：竹青淡 #E8F0EE + 竹青字
//   - 主按钮「提交作答」：竹青底 + 白字
//   - 次按钮「跳过」：浅灰底 + 次级文字
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../providers/practice_providers.dart';
import '../types/teaching_types.dart';

class PracticeTaskCard extends StatefulWidget {
  final PracticeTask task;
  final bool submitting;

  /// 提交作答（内容已 trim 非空）；自评可选（null = 未填）
  final void Function(String content, TrainingSelfAssessment? assessment)
  onSubmit;

  /// 跳过练习
  final VoidCallback onSkip;

  const PracticeTaskCard({
    super.key,
    required this.task,
    required this.submitting,
    required this.onSubmit,
    required this.onSkip,
  });

  @override
  State<PracticeTaskCard> createState() => _PracticeTaskCardState();
}

class _PracticeTaskCardState extends State<PracticeTaskCard> {
  final _answerController = TextEditingController();
  final _explanationController = TextEditingController();
  final _transferController = TextEditingController();
  int? _confidenceRating;

  @override
  void dispose() {
    _answerController.dispose();
    _explanationController.dispose();
    _transferController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final trimmed = _answerController.text.trim();
    if (trimmed.isEmpty || widget.submitting) return;
    final explanation = _explanationController.text.trim();
    final transfer = _transferController.text.trim();
    final hasAny =
        _confidenceRating != null ||
        explanation.isNotEmpty ||
        transfer.isNotEmpty;
    widget.onSubmit(
      trimmed,
      hasAny
          ? TrainingSelfAssessment(
              confidenceRating: _confidenceRating,
              explanationText: explanation.isEmpty ? null : explanation,
              transferText: transfer.isEmpty ? null : transfer,
            )
          : null,
    );
  }

  /// P0-1 自评区（全部可选，R-009 不强制）。
  /// 三个字段对齐 mastery_evidence 契约：
  /// 信心 1-5 / 解释文本 / 迁移文本。
  Widget _buildSelfAssessmentSection() {
    if (widget.submitting) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          '提交前自评（可选）',
          style: AppTextStyles.subBody.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        const Text(
          '填得越完整，掌握判定越准',
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 8),
        const Text(
          '你觉得这次改得怎么样？',
          style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        _buildConfidenceChips(),
        const SizedBox(height: 10),
        _buildAssessmentField(
          controller: _explanationController,
          hint: '为什么这样改？说说你的判断',
        ),
        const SizedBox(height: 8),
        _buildAssessmentField(
          controller: _transferController,
          hint: '如果换个写法/场景，你会怎么做？',
        ),
      ],
    );
  }

  /// 信心 1-5 选择（ChoiceChip 单选）。
  Widget _buildConfidenceChips() {
    return Row(
      children: List.generate(5, (i) {
        final value = i + 1;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text('$value'),
            selected: _confidenceRating == value,
            onSelected: (_) => setState(() => _confidenceRating = value),
          ),
        );
      }),
    );
  }

  /// 自评文本域（解释/迁移共用）。
  Widget _buildAssessmentField({
    required TextEditingController controller,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      maxLines: 2,
      minLines: 1,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textTertiary),
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header：练习任务 ──
          Row(
            children: [
              const Icon(
                Icons.edit_note,
                size: 18,
                color: AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              const Text(
                '练习任务',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── 症候名 chip ──
          if (widget.task.syndromeName != null &&
              widget.task.syndromeName!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.smx,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.l1,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                widget.task.syndromeName!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.l1Text,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── 任务描述 ──
          if (widget.task.taskDescription.isNotEmpty) ...[
            Text(
              '任务描述',
              style: AppTextStyles.subBody.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.task.taskDescription,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── 练习目标 ──
          if (widget.task.taskGoal.isNotEmpty) ...[
            Text(
              '练习目标',
              style: AppTextStyles.subBody.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.smx),
              decoration: BoxDecoration(
                color: AppColors.l1,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.emoji_events_outlined,
                    size: 16,
                    color: AppColors.l2Text,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.task.taskGoal,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: AppColors.l2Text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // ── 作答输入 ──
          TextField(
            controller: _answerController,
            enabled: !widget.submitting,
            maxLines: 4,
            minLines: 3,
            textAlignVertical: TextAlignVertical.top,
            decoration: InputDecoration(
              hintText: '在这里写下你的练习答案...',
              hintStyle: const TextStyle(color: AppColors.textTertiary),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.all(AppSpacing.md),
            ),
            style: const TextStyle(fontSize: 14, color: AppColors.textPrimary),
          ),
          _buildSelfAssessmentSection(),
          const SizedBox(height: 12),
          // ── 操作：跳过 | 提交 ──
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.submitting ? null : widget.onSkip,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text(
                  '跳过',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _handleSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.disabled,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.section,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: widget.submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.onPrimary,
                        ),
                      )
                    : const Text(
                        '提交作答',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
