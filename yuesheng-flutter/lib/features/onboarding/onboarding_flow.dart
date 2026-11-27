// ─────────────────────────────────────────────────────────────
// OnboardingFlow — 首启功能引导（横滑多页）
// 真源：yuesheng-android/src/components/onboarding/OnboardingFlow.tsx
//
// 结构（对齐 RN）：
//   - 右上「跳过」→ onSkip（未传则 onComplete）
//   - 横滑页（`onboardingPages`，见 `onboarding_pages.dart`，当前 5 页）——
//     页数为数据驱动，增删页只改那个文件的清单
//   - 进度指示点（当前页高亮变宽）
//   - 底部：非末页「下一步」→ 下一页；末页「开始使用」→ onComplete
//
// 显示条件（批次63）：getOnboardingCompleted()==false 时全屏显示，完成后进主壳。
//
// ⚠️ 数据层（`OnboardingPage` / `onboardingPages`）已切至
//    `onboarding_pages.dart`（`T-20261126-08`：本文件撞 300 行硬上限、容差 0）。
//    那 61 行是**数据清单**，与 `skill_registry` 同型拆法，非伪拆分。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:writingcoach/config/app_motion.dart';
import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/config/app_palette.dart';
import 'package:writingcoach/features/onboarding/onboarding_pages.dart';

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onSkip; // P3：跳过写 api_config_hint_seen；未传回落 onComplete
  const OnboardingFlow({super.key, required this.onComplete, this.onSkip});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    _controller.animateToPage(
      index,
      // 批次69：动效节奏统一——翻页时长收敛到 AppMotion 令牌
      duration: AppMotion.durationLong,
      curve: AppMotion.curvePage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == onboardingPages.length - 1;
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSkipButton(),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: onboardingPages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) =>
                    _buildPage(onboardingPages[index]),
              ),
            ),
            _buildProgressDots(),
            const SizedBox(height: AppSpacing.xl),
            _buildBottomButton(isLast),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildPageIcon(page.icon),
          const SizedBox(height: AppSpacing.xl),
          Text(
            page.title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            page.subtitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.palette.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (page.features != null)
            Column(
              children: [for (final f in page.features!) _buildFeatureCard(f)],
            )
          else
            Text(
              page.description!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: context.palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSkipButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, AppSpacing.md, AppSpacing.lg, 0),
        child: TextButton(
          onPressed: widget.onSkip ?? widget.onComplete,
          child: Text(
            '跳过',
            style: TextStyle(fontSize: 14, color: context.palette.textTertiary),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(onboardingPages.length, (i) {
        final active = i == _page;
        return AnimatedContainer(
          duration: AppMotion.durationStandard,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? context.palette.primary : context.palette.border,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        );
      }),
    );
  }

  Widget _buildBottomButton(bool isLast) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: isLast ? widget.onComplete : () => _goToPage(_page + 1),
          style: FilledButton.styleFrom(
            backgroundColor: context.palette.primary,
            foregroundColor: context.palette.onPrimary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isLast ? '开始使用' : '下一步',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (!isLast) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.arrow_forward,
                  size: 18,
                  color: context.palette.onPrimary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageIcon(IconData icon) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        color: context.palette.l1,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 44, color: context.palette.primary),
    );
  }

  Widget _buildFeatureCard(({String text, String desc, IconData icon}) f) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: context.palette.surfaceWhite,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(f.icon, size: 18, color: context.palette.primary),
          const SizedBox(width: AppSpacing.sm),
          Text(
            f.text,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              f.desc,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 14,
                color: context.palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
