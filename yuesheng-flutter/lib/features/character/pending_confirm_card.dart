// ─────────────────────────────────────────────────────────────
// PendingConfirmCard — AI 抽取断言「待用户裁决」确认卡（设定资料库第一批 UI）
//
// 闭环：AI 抽取 → pending 落库（diagnosis_committer._asAiPending）→
//       本卡展示 → 用户确认（confirmed）/ 拒绝（rejected + 可选理由）→
//       列表刷新。拒绝即拒绝记忆本体：AI 不得再次提议同值
//       （_injectFactProtocol 源头抑制 + merge 客户端过滤双保险）。
//
// 无 Scaffold：作为角色列表上方的内嵌挂件使用。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../providers/app_providers.dart';
import '../../services/setting_library_service.dart';
import '../../types/character_types.dart';
import '../../theme/app_typography.dart';
import '../../config/app_palette.dart';

/// C78 D-7 拒绝理由 chips（与角色详情页拒绝理由同一枚举，见 character_dialogs）
const List<String> _kRejectReasons = ['抽取错误', '章节已改写', '重复', '其他'];

/// AI 抽取断言待用户裁决的确认卡。
///
/// [items]：`(人物, 断言)` 列表（repository.listPendingAssertions 产出）。
/// [onChanged]：任一操作完成后回调（父级负责重新加载 pending 列表）。
class PendingConfirmCard extends ConsumerWidget {
  final String manuscriptId;
  final List<(CharacterFact, CharacterAssertion)> items;
  final VoidCallback onChanged;

  const PendingConfirmCard({
    super.key,
    required this.manuscriptId,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return const SizedBox.shrink();
    final service = ref.read(settingLibraryServiceProvider);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.palette.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          // 条目区限高可滚：确认卡位于列表上方（Expanded 之外），
          // 不做限高会在 pending 较多时把列表挤出屏幕。
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final (row, assertion) in items)
                    _buildItem(context, ref, service, row, assertion),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.fact_check_outlined,
          size: 18,
          color: context.palette.l1Text,
        ),
        const SizedBox(width: AppSpacing.xsm),
        Text(
          'AI 抽取待确认 · ${items.length} 条',
          style: context.text.caption.copyWith(color: context.palette.l1Text),
        ),
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    WidgetRef ref,
    SettingLibraryService service,
    CharacterFact row,
    CharacterAssertion a,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _buildItemText(context, row, a)),
          const SizedBox(width: AppSpacing.sm),
          _VerdictButtons(
            onConfirm: () async {
              await service.confirmCharacter(
                manuscriptId: manuscriptId,
                name: row.name,
                attribute: a.attribute,
                value: a.value,
              );
              onChanged();
            },
            onReject: () async {
              final reason = await _askRejectReason(context);
              await service.rejectCharacter(
                manuscriptId: manuscriptId,
                name: row.name,
                attribute: a.attribute,
                value: a.value,
                reason: reason,
              );
              onChanged();
            },
          ),
        ],
      ),
    );
  }

  /// 条目文本列：人物 · 属性 · 值 + 证据摘录（可选）
  Widget _buildItemText(
    BuildContext context,
    CharacterFact row,
    CharacterAssertion a,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${row.name} · ${a.attribute} · ${a.value}',
          style: context.text.body,
        ),
        if (a.evidence != null && a.evidence!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xxs),
            child: Text(
              a.evidence!,
              style: context.text.noteCaption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
    );
  }

  /// 拒绝前询问理由（可跳过）。返回 null 表示不填理由。
  Future<String?> _askRejectReason(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text('拒绝理由（可选）', style: context.text.titleMd),
            ),
            for (final r in _kRejectReasons)
              ListTile(
                title: Text(r, style: context.text.body),
                onTap: () => Navigator.pop(ctx, r),
              ),
            const Divider(height: 1),
            ListTile(
              title: Text('不填理由，直接拒绝', style: context.text.body),
              onTap: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    return picked;
  }
}

/// 确认 / 拒绝两个紧凑按钮。
class _VerdictButtons extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onReject;

  const _VerdictButtons({required this.onConfirm, required this.onReject});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _VerdictButton(
          icon: Icons.check,
          label: '确认',
          filled: true,
          onPressed: onConfirm,
        ),
        const SizedBox(width: AppSpacing.xsm),
        _VerdictButton(
          icon: Icons.close,
          label: '拒绝',
          filled: false,
          onPressed: onReject,
        ),
      ],
    );
  }
}

class _VerdictButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onPressed;

  const _VerdictButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14),
        const SizedBox(width: 2),
        Text(label, style: context.text.microCaption),
      ],
    );
    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xxs,
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: child,
          );
  }
}
