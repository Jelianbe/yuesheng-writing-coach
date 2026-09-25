// ─────────────────────────────────────────────────────────────
// OnboardingQuestionnaire — 写作偏好问卷 widget
// 复刻 yuesheng-android/src/components/profile/OnboardingQuestionnaire.tsx
//
// 波6 调整（对齐 onboarding_flow.dart）：
//   - Q1 用 4 级文本示例替代 3 级自评（N0→N3 递进）
//   - Q4（写作目标）移除（与 Q2 重叠）
//   - 3 题制：Q1 等级 / Q2 提升方向（多选）/ Q3 学习偏好
//
// 配色：月色竹青（#2D5A52 主色，#F7F8F6 背景）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:writingcoach/config/app_motion.dart';
import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/services/onboarding_flow.dart';
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/theme/app_typography.dart';
import 'package:writingcoach/config/app_palette.dart';

/// 写作偏好问卷
///
/// 用法：
/// ```dart
/// OnboardingQuestionnaire(
///   visible: true,
///   onComplete: (data) => onboardingService.submitOnboarding(sessionId, data),
///   onSkip: () => onboardingService.skipOnboarding(sessionId),
/// )
/// ```
class OnboardingQuestionnaire extends StatefulWidget {
  final bool visible;
  final void Function(OnboardingData data) onComplete;
  final void Function() onSkip;

  const OnboardingQuestionnaire({
    super.key,
    required this.visible,
    required this.onComplete,
    required this.onSkip,
  });

  @override
  State<OnboardingQuestionnaire> createState() =>
      _OnboardingQuestionnaireState();
}

class _OnboardingQuestionnaireState extends State<OnboardingQuestionnaire> {
  static const int _totalSteps = 1; // 简化：只留关注领域 1 题

  int _step = 0;
  final Set<String> _focusAreas = {};

  // 漏洞 4 修复：提交中标志，防止连点重复触发 onComplete
  // 设置后立即 setState 禁用按钮，回调返回前不可再次点击
  bool _isSubmitting = false;

  final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToStep(int index) {
    setState(() => _step = index);
    _pageController.animateToPage(
      index,
      // 批次6（6.1）：prefers-reduced-motion 时归零动画时长
      // 批次69：动效节奏统一——翻页时长/曲线收敛到 AppMotion 令牌
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.durationLong,
      curve: AppMotion.curvePage,
    );
  }

  bool _canProceed(int index) {
    if (_isSubmitting) return false;
    // 简化问卷：只有 1 题（关注领域，可选），总是可以提交
    return true;
  }

  void _handleComplete() {
    if (_isSubmitting) return;

    setState(() => _isSubmitting = true);

    // 简化问卷：只收集 focusAreas，其他默认 beginner/mixed
    // 后续根据诊断结果自动调整
    widget.onComplete(
      OnboardingData(
        proficiency: ProficiencyLevel.beginner,
        focusAreas: _focusAreas.toList(),
        cognitiveStyle: CognitiveStyle.mixed,
        writingGoal: '',
        completedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        skipped: false,
      ),
    );
  }

  void _toggleFocusArea(String area) {
    setState(() {
      if (_focusAreas.contains(area)) {
        _focusAreas.remove(area);
      } else {
        _focusAreas.add(area);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final isLastStep = _step == _totalSteps - 1;

    // P1-5 修复：拦截 Android 物理返回键 / iOS 左滑返回（用 PopScope + onPopInvokedWithResult，
    // 替代已废弃的 onPopInvoked）：
    //   - 提交中：不允许任何返回
    //   - step > 0：退回上一题（而不是直接退出整个 App）
    //   - step == 0：用户想在第一题退出 → 等价于"跳过问卷"（调用 onSkip）
    final body = PopScope(
      canPop: false, // 完全接管 pop 行为，都走 onPopInvokedWithResult
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return; // 已经被别的 handler 弹掉了
        if (_isSubmitting) return;
        if (_step > 0) {
          _goToStep(_step - 1);
          return;
        }
        // step == 0 时，把物理返回视作"跳过问卷"，交给 onSkip 统一处理
        widget.onSkip();
      },
      child: Scaffold(
        backgroundColor: context.palette.background, // 冷青灰白
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildProgress(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_buildQ2()], // 简化：只留关注领域
                ),
              ),
              _buildFooter(isLastStep),
            ],
          ),
        ),
      ),
    );
    return body;
  }

  // ════════════ Header ════════════

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (_step > 0)
            IconButton(
              icon: Icon(
                Icons.arrow_back,
                size: 22,
                color: context.palette.textPrimary,
              ),
              onPressed: () => _goToStep(_step - 1),
              tooltip: '上一题',
            )
          else
            const SizedBox(width: 48), // 占位保持右侧对齐
          Expanded(
            child: Center(
              child: Text(
                _step == 0 ? '写作偏好问卷' : '第 ${_step + 1}/$_totalSteps 题',
                style: context.text.titleLg,
              ),
            ),
          ),
          TextButton(
            // P1-5 修复：提交中禁用跳过，避免与 onComplete 的 submitOnboarding 并行写 DB 冲突
            onPressed: _isSubmitting ? null : widget.onSkip,
            child: Text(
              _isSubmitting ? '处理中…' : '跳过问卷',
              style: TextStyle(
                color: _isSubmitting
                    ? context.palette.disabledText
                    : context.palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════ Progress ════════════

  Widget _buildProgress() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_totalSteps, (i) {
          final isActive = i == _step;
          final isCompleted = i < _step;
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            width: isActive ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              color: isActive || isCompleted
                  ? AppColors
                        .primary // 月色竹青
                  : context.palette.placeholder,
            ),
          );
        }),
      ),
    );
  }

  // ════════════ Q2: 提升方向（多选） ════════════

  Widget _buildQ2() {
    return _QuestionPage(
      title: 'Q2. 你最想提升哪方面？',
      subtitle: '可多选，也可不选',
      child: Column(
        children: kFocusAreaOptions.map((area) {
          final selected = _focusAreas.contains(area);
          return _CheckCard(
            selected: selected,
            label: area,
            onTap: () => _toggleFocusArea(area),
          );
        }).toList(),
      ),
    );
  }

  // ════════════ Footer ════════════

  Widget _buildFooter(bool isLastStep) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.md,
        AppSpacing.section,
        AppSpacing.xl,
      ),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => _goToStep(_step - 1),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  side: BorderSide(color: context.palette.placeholder),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text('上一题'),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: _canProceed(_step)
                  ? (isLastStep ? _handleComplete : () => _goToStep(_step + 1))
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: context.palette.primary,
                foregroundColor: context.palette.onPrimary,
                disabledBackgroundColor: context.palette.disabled,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              child: Text(
                _isSubmitting ? '提交中…' : (isLastStep ? '开始写作之旅' : '下一题'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 内部组件
// ─────────────────────────────────────────────────────────────

class _QuestionPage extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _QuestionPage({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.sm,
        AppSpacing.section,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: context.text.titleLg),
          const SizedBox(height: 4),
          Text(subtitle, style: context.text.body),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _CheckCard extends StatelessWidget {
  final bool selected;
  final String label;
  final VoidCallback onTap;

  const _CheckCard({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: selected ? context.palette.l1 : context.palette.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? context.palette.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              // 多选方框
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(
                    color: selected
                        ? context.palette.primary
                        : context.palette.textTertiary,
                    width: 2,
                  ),
                  color: selected
                      ? context.palette.primary
                      : Colors.transparent,
                ),
                child: selected
                    ? Icon(
                        Icons.check,
                        size: 16,
                        color: context.palette.onPrimary,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? context.palette.primary
                        : context.palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
