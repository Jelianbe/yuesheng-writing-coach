// ─────────────────────────────────────────────────────────────
// OnboardingFlow — 首启功能引导（横滑多页）
// 真源：yuesheng-android/src/components/onboarding/OnboardingFlow.tsx
//
// 结构（对齐 RN）：
//   - 右上「跳过」（等价 onComplete）
//   - 横滑页（`_pages`，当前 5 页，按标题依次为：我是月笙 / 我能帮你做什么 /
//     开始使用 / 怎么开始 / 配置 API）—— 页数为数据驱动，增删页只改 `_pages`
//   - 进度指示点（当前页高亮变宽）
//   - 底部：非末页「下一步」→ 下一页；末页「开始使用」→ onComplete
//
// 显示条件（批次63）：AppStateRepository.getOnboardingCompleted() == false 时
// 全屏显示；完成后 setOnboardingCompleted(true) 进主壳（启动门在 main.dart）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'package:writingcoach/config/app_motion.dart';
import 'package:writingcoach/config/app_theme.dart';
import 'package:writingcoach/config/app_palette.dart';

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
  _OnboardingPage(
    icon: Icons.explore,
    title: '怎么开始',
    subtitle: '三步用起来',
    features: [
      (text: '选中文字', desc: '划词即可诊断', icon: Icons.gesture),
      (text: '导入作品', desc: '带来你的初稿', icon: Icons.upload_file),
      (text: '问月笙', desc: '随时聊写作', icon: Icons.chat_bubble_outline),
    ],
  ),
  _OnboardingPage(
    icon: Icons.vpn_key,
    title: '配置 API',
    subtitle: '解锁完整功能',
    description:
        '本应用需接入你自己的 AI 服务商 API 才能做真实诊断与教学；'
        '未配置时可用免费测试模式（离线示例）体验。怎么获取：去服务商官网注册'
        '（DeepSeek 为 platform.deepseek.com）→ 在「设置 → API」填入 '
        'Key / Base URL / 模型。费用按用量计入你的服务商账户。',
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
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildSkipButton(),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) => _buildPage(_pages[index]),
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

  Widget _buildPage(_OnboardingPage page) {
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
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: context.palette.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            page.subtitle,
            style: TextStyle(
              fontSize: 15,
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
          onPressed: widget.onComplete,
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
      children: List.generate(_pages.length, (i) {
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
              fontSize: 15,
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
