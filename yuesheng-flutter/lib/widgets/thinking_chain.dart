// ─────────────────────────────────────────────────────────────
// ThinkingChain — 推理/依据步骤链（批次 C：外来 Editorial Ink
// Thinking Chain 组件竹青化）
//
// 参考结构（custom/components/thinking-chain.json + preview）：
//   - 变体：collapsed（折叠 header + 步骤数徽标）/ expanded / deep
//   - anatomy：summary-header / step-list / step-number / step-content /
//     depth-line / confidence-indicator
//   - doNotInvent：horizontal-chain（不横向排）/ animated-expand
//
// 竹青化适配（月笙令牌，不引入墨蓝/Sora/暖白/5px 间距）：
//   - 主色 AppColors.primary（#2D5A52 竹青），连接线 primary 30% 透明度
//   - 置信点 3 颗 4px 圆点：low=0.25 / mid=0.55 / high=1.0 透明度（沿用
//     Editorial Ink 层级语义，但色相用竹青）
//   - 间距/圆角/字号全部走 AppSpacing / AppRadius / AppTextStyles 令牌
//
// 数据诚实约束：ThinkingStep.confidence 可空——null 时不渲染置信点，
// 调用方不得用编造的每步置信（月笙诊断依据链全部为 null，置信只经
// ConfidenceBar 展示真实 payload.confidence）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 单个步骤
class ThinkingStep {
  final String label;
  final String? detail;

  /// 0-1 置信度；null = 不渲染置信点（避免伪造）
  final double? confidence;

  const ThinkingStep({required this.label, this.detail, this.confidence});
}

/// 步骤链展示（默认折叠）
class ThinkingChain extends StatefulWidget {
  final String title;
  final List<ThinkingStep> steps;
  final bool initiallyExpanded;

  const ThinkingChain({
    super.key,
    required this.title,
    required this.steps,
    this.initiallyExpanded = false,
  });

  @override
  State<ThinkingChain> createState() => _ThinkingChainState();
}

class _ThinkingChainState extends State<ThinkingChain> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          _buildHeader(),
          if (_expanded) ...[
            const Divider(height: 1, color: AppColors.border),
            _buildStepList(),
          ],
        ],
      ),
    );
  }

  /// header：图标 + 标题 + 步骤数徽标 + 展开箭头（R-019 拆出）
  Widget _buildHeader() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.smx,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.route_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _buildStepCountBadge(),
              const SizedBox(width: AppSpacing.sm),
              Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 步骤数徽标（primarySoft 底 + primary 字）
  Widget _buildStepCountBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.smx,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        '${widget.steps.length} 步',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }

  /// 步骤列表：垂直链 + 连接线（R-019 拆出）
  Widget _buildStepList() {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          for (var i = 0; i < widget.steps.length; i++) ...[
            _buildStepRow(i),
            if (i < widget.steps.length - 1) _buildConnector(),
          ],
        ],
      ),
    );
  }

  /// 相邻步骤间的连接竖线（primary 30% 透明度，对齐 Ink depth-line）
  Widget _buildConnector() {
    return Container(
      width: 1,
      height: AppSpacing.lg,
      margin: const EdgeInsets.only(left: AppSpacing.smx),
      color: AppColors.primary.withValues(alpha: 0.30),
    );
  }

  /// 单步：指示器列（圆点 + 置信点）+ 内容列
  Widget _buildStepRow(int index) {
    final step = widget.steps[index];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildIndicator(index, step.confidence),
        const SizedBox(width: AppSpacing.smx),
        Expanded(child: _buildStepContent(step)),
      ],
    );
  }

  /// 指示器列：编号圆点（实心）或空心圆点 + 置信点
  Widget _buildIndicator(int index, double? confidence) {
    return Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '${index + 1}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.onPrimary,
            ),
          ),
        ),
        if (confidence != null) ...[
          const SizedBox(height: AppSpacing.xs),
          _buildConfidenceDots(confidence),
        ],
      ],
    );
  }

  /// 置信点：3 颗 4px 圆点（low/mid/high 透明度层级）
  Widget _buildConfidenceDots(double confidence) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.only(left: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(
                alpha: _dotAlpha(i, confidence),
              ),
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }

  /// 置信点透明度：i < 达标点数为高亮，其余按 0.25/0.55/1.0 层级
  double _dotAlpha(int index, double confidence) {
    final filled = (confidence * 3).round().clamp(0, 3);
    if (index < filled) return 1.0;
    return switch (index) {
      0 => 0.25,
      1 => 0.55,
      _ => 1.0,
    };
  }

  /// 步骤内容：label + detail
  Widget _buildStepContent(ThinkingStep step) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          step.label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (step.detail != null) ...[
          const SizedBox(height: 2),
          Text(
            step.detail!,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ],
    );
  }
}
