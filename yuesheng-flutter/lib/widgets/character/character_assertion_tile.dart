// ─────────────────────────────────────────────────────────────
// CharacterAssertionTile — 断言条目（C78 批次3）
//
// 双灰显语义强制分离（验收红线，ADR-C78 §6）：
//   rejected → 删除线 + tertiary 灰 + 「已拒绝」红灰角标（可含拒绝理由）
//   stale    → 无删除线 + tertiary 灰 + 「章节已改写」警示角标
// 两者不得共用一种样式——前者是「用户裁决不要」，后者是「正文已变」。
//
// 查看原文（诚实降级，ADR-C78 §4.4 采信决策树由调用方实现并传入）：
//   解析失败必须显示「未定位到原文」，不得假装定位成功。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../types/character_types.dart';

/// 断言条目。纯展示 + 动作回调上抛，数据访问全部留在详情页。
class CharacterAssertionTile extends StatelessWidget {
  final CharacterAssertion assertion;

  /// 拒绝（详情页弹理由 chips 后落库）
  final VoidCallback? onReject;

  /// 修正（详情页弹表单后落库）
  final VoidCallback? onCorrect;

  /// 查看原文：返回 null = 未定位到（弹层如实显示）；返回文本 = 原文摘录
  final Future<String?> Function() resolveOriginalText;

  const CharacterAssertionTile({
    super.key,
    required this.assertion,
    required this.resolveOriginalText,
    this.onReject,
    this.onCorrect,
  });

  bool get _rejected => assertion.status == 'rejected';
  bool get _stale => assertion.stale && !_rejected;
  bool get _actionable => !_rejected && !_stale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xsm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SourceBadge(source: assertion.source),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _buildValueText()),
                    _buildStateBadge(),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                _buildMetaRow(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 值文本：rejected 加删除线；stale 仅变灰（无删除线，语义分离红线）
  Widget _buildValueText() {
    final gray = _rejected || _stale;
    return Text(
      assertion.value,
      style: AppTextStyles.body.copyWith(
        color: gray ? AppColors.textTertiary : AppColors.textInk,
        decoration: _rejected ? TextDecoration.lineThrough : null,
        fontSize: 15,
      ),
    );
  }

  Widget _buildStateBadge() {
    if (_rejected) return _badge('已拒绝', AppColors.dangerBg, AppColors.danger);
    if (_stale) return _badge('章节已改写', AppColors.warningBg, AppColors.warning);
    return const SizedBox.shrink();
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(text, style: AppTextStyles.microCaption.copyWith(color: fg)),
    );
  }

  Widget _buildMetaRow(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.xsm,
      runSpacing: AppSpacing.xxs,
      children: [
        Text(_chapterText(), style: AppTextStyles.microCaption),
        TextButton(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 28),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => _showOriginalText(context),
          child: const Text('查看原文', style: AppTextStyles.caption),
        ),
        if (_rejected && assertion.rejectReason != null)
          Text(
            '理由·${assertion.rejectReason}',
            style: AppTextStyles.microCaption,
          ),
        if (_actionable) ...[
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onReject,
            child: const Text('拒绝 ✗', style: AppTextStyles.caption),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: onCorrect,
            child: const Text('修正', style: AppTextStyles.caption),
          ),
        ],
      ],
    );
  }

  String _chapterText() {
    final ch = assertion.chapter;
    return ch == null ? '章节未知' : '第$ch章';
  }

  /// 查看原文弹层：null → 「未定位到原文」（诚实降级，验收红线 5）
  Future<void> _showOriginalText(BuildContext context) async {
    final text = await resolveOriginalText();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.section),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '原文摘录（第${assertion.chapter ?? '?'}章）',
                style: AppTextStyles.titleMd,
              ),
              const SizedBox(height: AppSpacing.md),
              if (text == null || text.isEmpty)
                const Text('未定位到原文', style: AppTextStyles.body)
              else
                SelectableText(text, style: AppTextStyles.body),
            ],
          ),
        ),
      ),
    );
  }
}

/// 来源标记（D-4）：[AI] = ai，[手] = user
class _SourceBadge extends StatelessWidget {
  final String source;
  const _SourceBadge({required this.source});

  @override
  Widget build(BuildContext context) {
    final isUser = source == 'user';
    return Container(
      width: 30,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isUser ? AppColors.primarySoft : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(
          color: isUser ? AppColors.primary : AppColors.border,
        ),
      ),
      child: Text(
        isUser ? '手' : 'AI',
        style: AppTextStyles.microCaption.copyWith(
          color: isUser ? AppColors.primary : AppColors.textTertiary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
