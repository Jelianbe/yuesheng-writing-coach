// ─────────────────────────────────────────────────────────────
// OnboardingFlow — 首启功能引导（3 页横滑）
// 真源：yuesheng-android/src/components/onboarding/OnboardingFlow.tsx
//
// 结构（对齐 RN）：
//   - 右上「跳过」（等价 onComplete）
//   - 3 页横滑：我是月笙 / 三大核心能力 / 开始使用
//   - 进度指示点（当前页高亮变宽）
//   - 底部：非末页「下一步」→ 下一页；末页「开始使用」→ onComplete
//
// 显示条件（批次63）：AppStateRepository.getOnboardingCompleted() == false 时
// 全屏显示；完成后 setOnboardingCompleted(true) 进主壳（启动门在 main.dart）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_motion.dart';
import '../config/app_theme.dart';

/// 引导页数据（对齐 RN PAGES）
class _OnboardingPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? description;
  final List<({String text, String desc, IconData icon})>? features;

  const _OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.description,
    this.features,
  });
}

const List<_OnboardingPage> _pages = [
  _OnboardingPage(
    icon: Icons.person,
    title: '我是月笙',
    subtitle: '你的专属写作教练',
    description: '陪你一起发现写作问题，拆解练习，持续成长',
  ),
  _OnboardingPage(
    icon: Icons.auto_awesome,
    title: '我能帮你做什么',
    subtitle: '三大核心能力',
    features: [
      (text: '智能诊断', desc: '发现写作中的问题', icon: Icons.search),
      (text: '拆解练习', desc: '针对性提升技能', icon: Icons.build),
      (text: '追踪成长', desc: '记录进步轨迹', icon: Icons.trending_up),
    ],
  ),
  _OnboardingPage(
    icon: Icons.rocket_launch,
    title: '开始使用',
    subtitle: '开启写作之旅',
    description: '导入你的作品，让我来帮你诊断和提升',
  ),
];

class OnboardingFlow extends StatefulWidget {
  final VoidCallback onComplete;
  const OnboardingFlow({super.key, required this.onComplete});

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
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // 右上「跳过」（对齐 RN skipBtn）
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, AppSpacing.lg, 0),
                child: TextButton(
                  onPressed: widget.onComplete,
                  child: const Text(
                    '跳过',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
            // 3 页横滑
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) =>
                    _buildPage(_pages[index]),
              ),
            ),
            // 进度指示点
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  // 批次69：动效节奏统一——进度点时长收敛到 AppMotion 令牌
                  duration: AppMotion.durationStandard,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? AppColors.primary : AppColors.border,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                );
              }),
            ),
            const SizedBox(height: AppSpacing.xl),
            // 底部按钮：非末页「下一步」/ 末页「开始使用」
            Padding(
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
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.onPrimary,
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
                        const Icon(Icons.arrow_forward,
                            size: 18, color: AppColors.onPrimary),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(_OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.l1,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(page.icon, size: 44, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            page.subtitle,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (page.features != null)
            Column(
              children: [
                for (final f in page.features!)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceWhite,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(f.icon, size: 18, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          f.text,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            f.desc,
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            )
          else
            Text(
              page.description!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}
