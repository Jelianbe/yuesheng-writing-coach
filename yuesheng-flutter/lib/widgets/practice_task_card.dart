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
//       + 5.6 回忆难度自评（批1·N2，可选）：again/hard/good/easy 四档
//         （FSRS 间隔调度输入——与上面三维证据语义不同，见 spaced_repetition.dart）
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
import '../services/spaced_repetition.dart';
import '../types/teaching_types.dart';
import '../theme/app_typography.dart';
import '../config/app_palette.dart';

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
  FsrsRating? _userRating; // 批1·N2：回忆难度自评（null = 未填）

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
        _userRating != null ||
        explanation.isNotEmpty ||
        transfer.isNotEmpty;
    widget.onSubmit(
      trimmed,
      hasAny
          ? TrainingSelfAssessment(
              confidenceRating: _confidenceRating,
              explanationText: explanation.isEmpty ? null : explanation,
              transferText: transfer.isEmpty ? null : transfer,
              // 批1·N2：枚举 → 落库字符串（与 DB TEXT 列同形）
              userRating: _userRating?.value,
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
          style: context.text.subBody.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Text(
          '填得越完整，掌握判定越准',
          style: TextStyle(fontSize: 12, color: context.palette.textTertiary),
        ),
        const SizedBox(height: 8),
        Text(
          '你觉得这次改得怎么样？',
          style: TextStyle(fontSize: 13, color: context.palette.textPrimary),
        ),
        const SizedBox(height: 6),
        _buildConfidenceChips(),
        const SizedBox(height: 10),
        // ── 5.6 回忆难度自评（批1·N2，可跳过）──
        Text(
          '这次练习对你来说有多难？',
          style: TextStyle(fontSize: 13, color: context.palette.textPrimary),
        ),
        const SizedBox(height: 6),
        _buildRecallRatingChips(),
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

  /// 回忆难度自评 4 档（批1·N2，可跳过 = null）。
  ///
  /// 形态照抄 `_buildConfidenceChips`（ChoiceChip 单选）；用 `Wrap` 而非 `Row`：
  /// 4 个**中文**标签在窄屏 / 大字体下比 5 个数字更易超出，Wrap 放不下时自动换行，
  /// 不牺牲可用性（一行放得下时与 Row 视觉一致）。
  Widget _buildRecallRatingChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in FsrsRating.values)
          ChoiceChip(
            label: Text(_recallRatingLabel(r)),
            selected: _userRating == r,
            onSelected: (_) => setState(() => _userRating = r),
          ),
      ],
    );
  }

  /// 四档界面文案（**非落库值**；落库值见 `FsrsRating.value`）。
  String _recallRatingLabel(FsrsRating rating) => switch (rating) {
    FsrsRating.again => '再来一次',
    FsrsRating.hard => '有点难',
    FsrsRating.good => '还行',
    FsrsRating.easy => '很轻松',
  };

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
        hintStyle: TextStyle(color: context.palette.textTertiary),
        filled: true,
        fillColor: context.palette.surface,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: context.palette.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      style: TextStyle(fontSize: 13, color: context.palette.textPrimary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: context.palette.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.palette.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          ..._buildSyndromeChip(),
          ..._buildTaskDescription(),
          ..._buildTaskGoal(),
          _buildAnswerField(),
          _buildSelfAssessmentSection(),
          const SizedBox(height: 12),
          _buildActions(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.edit_note, size: 18, color: context.palette.textPrimary),
        const SizedBox(width: 8),
        Text(
          '练习任务',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: context.palette.textPrimary,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSyndromeChip() {
    if (widget.task.syndromeName == null || widget.task.syndromeName!.isEmpty) {
      return [];
    }
    return [
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.smx,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: context.palette.l1,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          widget.task.syndromeName!,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.palette.l1Text,
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _buildTaskDescription() {
    if (widget.task.taskDescription.isEmpty) {
      return [];
    }
    return [
      Text(
        '任务描述',
        style: context.text.subBody.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        widget.task.taskDescription,
        style: TextStyle(
          fontSize: 14,
          height: 1.5,
          color: context.palette.textPrimary,
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  List<Widget> _buildTaskGoal() {
    if (widget.task.taskGoal.isEmpty) {
      return [];
    }
    return [
      Text(
        '练习目标',
        style: context.text.subBody.copyWith(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.smx),
        decoration: BoxDecoration(
          color: context.palette.l1,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 16,
              color: context.palette.l2Text,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.task.taskGoal,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: context.palette.l2Text,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _buildAnswerField() {
    return TextField(
      controller: _answerController,
      enabled: !widget.submitting,
      maxLines: 4,
      minLines: 3,
      textAlignVertical: TextAlignVertical.top,
      decoration: InputDecoration(
        hintText: '在这里写下你的练习答案...',
        hintStyle: TextStyle(color: context.palette.textTertiary),
        filled: true,
        fillColor: context.palette.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: context.palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: context.palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: context.palette.primary),
        ),
        contentPadding: const EdgeInsets.all(AppSpacing.md),
      ),
      style: TextStyle(fontSize: 14, color: context.palette.textPrimary),
    );
  }

  Widget _buildActions() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _buildSkipButton(),
        const SizedBox(width: 12),
        _buildSubmitButton(),
      ],
    );
  }

  Widget _buildSkipButton() {
    return TextButton(
      onPressed: widget.submitting ? null : widget.onSkip,
      style: TextButton.styleFrom(
        backgroundColor: context.palette.surface,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 9,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      child: Text(
        '跳过',
        style: TextStyle(
          fontSize: 14,
          color: context.palette.textTertiary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return FilledButton(
      onPressed: _handleSubmit,
      style: FilledButton.styleFrom(
        backgroundColor: context.palette.primary,
        disabledBackgroundColor: context.palette.disabled,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.section,
          vertical: 9,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      child: widget.submitting
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.palette.onPrimary,
              ),
            )
          : Text(
              '提交作答',
              style: TextStyle(
                fontSize: 14,
                color: context.palette.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}
