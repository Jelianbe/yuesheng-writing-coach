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

import '../config/app_motion.dart';
import '../config/app_theme.dart';
import '../services/onboarding_flow.dart';
import '../types/teaching_types.dart';

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
  static const int _totalSteps = kOnboardingQuestionCount; // 3

  int _step = 0;
  ProficiencyLevel? _proficiency;
  final Set<String> _focusAreas = {};
  CognitiveStyle? _cognitiveStyle;

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
    // 漏洞 4 修复：提交中禁用所有前进按钮
    if (_isSubmitting) return false;
    switch (index) {
      case 0:
        return _proficiency != null;
      case 1:
        return true; // 多选可空
      case 2:
        return _cognitiveStyle != null;
      default:
        return false;
    }
  }

  void _handleComplete() {
    // 漏洞 4 修复：提交中直接返回，避免连点重复触发回调
    if (_isSubmitting) return;
    if (_proficiency == null || _cognitiveStyle == null) return;

    // 立即标记 + setState 禁用按钮，防止回调执行期间再次点击
    setState(() => _isSubmitting = true);

    widget.onComplete(
      OnboardingData(
        proficiency: _proficiency!,
        focusAreas: _focusAreas.toList(),
        cognitiveStyle: _cognitiveStyle!,
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
        backgroundColor: AppColors.background, // 冷青灰白
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildProgress(),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_buildQ1(), _buildQ2(), _buildQ3()],
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          if (_step > 0)
            IconButton(
              icon: const Icon(
                Icons.arrow_back,
                size: 22,
                color: AppColors.textPrimary,
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
                style: AppTextStyles.titleLg,
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
                    ? AppColors.disabledText
                    : AppColors.textSecondary,
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
                  : AppColors.placeholder,
            ),
          );
        }),
      ),
    );
  }

  // ════════════ Q1: 4 级文本示例 ════════════

  Widget _buildQ1() {
    return _QuestionPage(
      title: 'Q1. 哪段文字最接近你的写作水平？',
      subtitle: '选一段最像你平时写的',
      child: Column(
        children: kProficiencyExamples.map((ex) {
          final selected = _proficiency == ex.proficiency;
          return _RadioCard(
            selected: selected,
            label: ex.label,
            sample: ex.sample,
            onTap: () => setState(() => _proficiency = ex.proficiency),
          );
        }).toList(),
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

  // ════════════ Q3: 学习偏好 ════════════

  Widget _buildQ3() {
    return _QuestionPage(
      title: 'Q3. 你的学习偏好？',
      subtitle: '选最适合你的方式',
      child: Column(
        children: kCognitiveStyleOptions.map((opt) {
          final selected = _cognitiveStyle == opt.value;
          return _RadioCard(
            selected: selected,
            label: opt.label,
            sample: null,
            onTap: () => setState(() => _cognitiveStyle = opt.value),
          );
        }).toList(),
      ),
    );
  }

  // ════════════ Footer ════════════

  Widget _buildFooter(bool isLastStep) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.section, AppSpacing.md, AppSpacing.section, AppSpacing.xl),
      child: Row(
        children: [
          if (_step > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: () => _goToStep(_step - 1),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  side: const BorderSide(color: AppColors.placeholder),
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
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                disabledBackgroundColor: AppColors.disabled,
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
      padding: const EdgeInsets.fromLTRB(AppSpacing.section, AppSpacing.sm, AppSpacing.section, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.titleLg,
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: AppTextStyles.body,
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _RadioCard extends StatelessWidget {
  final bool selected;
  final String label;
  final String? sample;
  final VoidCallback onTap;

  const _RadioCard({
    required this.selected,
    required this.label,
    required this.sample,
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
            color: selected
                ? AppColors
                      .l1 // 竹青浅
                : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 单选圆圈
              Container(
                width: 22,
                height: 22,
                margin: const EdgeInsets.only(top: AppSpacing.xxs),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textTertiary,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ),
                    ),
                    if (sample != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        sample!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.hintText,
                          height: 1.5,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
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
            color: selected ? AppColors.l1 : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
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
                        ? AppColors.primary
                        : AppColors.textTertiary,
                    width: 2,
                  ),
                  color: selected ? AppColors.primary : Colors.transparent,
                ),
                child: selected
                    ? const Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.onPrimary,
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
                    color: selected ? AppColors.primary : AppColors.textPrimary,
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
