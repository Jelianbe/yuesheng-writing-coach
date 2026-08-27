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

class PracticeTaskCard extends StatefulWidget {
  final PracticeTask task;
  final bool submitting;

  /// 提交作答（内容已 trim 非空）
  final void Function(String content) onSubmit;

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

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final trimmed = _answerController.text.trim();
    if (trimmed.isEmpty || widget.submitting) return;
    widget.onSubmit(trimmed);
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
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.smx, vertical: AppSpacing.xs),
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
