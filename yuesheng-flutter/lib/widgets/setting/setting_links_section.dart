// ─────────────────────────────────────────────────────────────
// SettingLinksSection — 详情页「关联设定」区块（Codex 式互链第一批，v36）
//
// 展示涉及本实体的全部互链（出链 + 入链）：类型徽标 + 名称 + 可选关系名。
// - 可跳转目标（角色/世界观）→ 点击进入对应详情页
// - 其他/大纲/已删除条目 → 普通标签（无详情页或目标已不存在）
// - 「＋ 添加关联」→ 弹窗选类型 + 条目 + 可选关系名
// - 删除：列表项尾部删除图标 + 确认
//
// 角色/世界观详情页同构复用（kind 区分）。本批不参与诊断注入。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../data/repositories/setting_link_repository.dart';
import '../../providers/app_providers.dart';
import 'setting_link_dialog.dart';

/// 详情页「关联设定」区块。
class SettingLinksSection extends ConsumerStatefulWidget {
  final String manuscriptId;
  final SettingEntityKind kind;
  final String entityId;

  /// 跳转委托（宿主注入，避免区块与详情页互相 import 成环）。
  final void Function(SettingEntityKind kind, String id)? onJump;

  const SettingLinksSection({
    super.key,
    required this.manuscriptId,
    required this.kind,
    required this.entityId,
    this.onJump,
  });

  @override
  ConsumerState<SettingLinksSection> createState() =>
      _SettingLinksSectionState();
}

class _SettingLinksSectionState extends ConsumerState<SettingLinksSection> {
  bool _loading = true;
  List<SettingLinkView> _links = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final links = await SettingLinkRepository(
      ref.read(appDatabaseProvider),
    ).listForEntity(widget.manuscriptId, widget.kind, widget.entityId);
    if (!mounted) return;
    setState(() {
      _links = links;
      _loading = false;
    });
  }

  Future<void> _addLink() async {
    final result = await showSettingLinkDialog(
      context,
      manuscriptId: widget.manuscriptId,
      selfKind: widget.kind,
      selfId: widget.entityId,
    );
    if (result == null || !mounted) return;
    await SettingLinkRepository(ref.read(appDatabaseProvider)).createLink(
      manuscriptId: widget.manuscriptId,
      sourceKind: widget.kind,
      sourceId: widget.entityId,
      targetKind: result.kind,
      targetId: result.id,
      label: result.label,
    );
    if (!mounted) return;
    _load();
  }

  Future<void> _removeLink(SettingLinkView view) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除关联'),
        content: Text('移除与「${view.otherName}」的关联？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await SettingLinkRepository(
      ref.read(appDatabaseProvider),
    ).deleteLink(view.link.id);
    if (!mounted) return;
    _load();
  }

  void _jump(SettingLinkView view) {
    if (!view.isJumpable) return;
    widget.onJump?.call(view.otherKind, view.otherId);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('关联设定', style: AppTextStyles.titleMd),
            const Spacer(),
            TextButton.icon(
              onPressed: _addLink,
              icon: const Icon(Icons.add_link, size: 16),
              label: const Text('添加关联'),
            ),
          ],
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.sm),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_links.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              '还没有关联的设定条目',
              style: AppTextStyles.subBody.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          )
        else
          ..._links.map(_buildTile),
      ],
    );
  }

  Widget _buildTile(SettingLinkView view) {
    final jumpable = view.isJumpable;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ListTile(
        dense: true,
        leading: Icon(
          switch (view.otherKind) {
            SettingEntityKind.character => Icons.person_outline,
            SettingEntityKind.world => Icons.public,
            SettingEntityKind.outline => Icons.account_tree_outlined,
            SettingEntityKind.setting => Icons.label_outline,
          },
          size: 18,
          color: AppColors.primary,
        ),
        title: Text(
          view.link.label.isEmpty
              ? view.otherName
              : '${view.otherName} · ${view.link.label}',
          style: AppTextStyles.body,
        ),
        subtitle: Text(
          '${view.otherKind.label}'
          '${jumpable ? '' : ' · 不可跳转'}',
          style: AppTextStyles.microCaption,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.link_off, size: 18),
          onPressed: () => _removeLink(view),
          tooltip: '移除关联',
        ),
        onTap: jumpable ? () => _jump(view) : null,
      ),
    );
  }
}
