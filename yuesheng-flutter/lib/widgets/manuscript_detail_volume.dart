// ignore_for_file: invalid_use_of_protected_member
part of 'manuscript_detail_page.dart';

extension _ManuscriptDetailVolume on _ManuscriptDetailPageState {
  // ── 修复4：详情页新建卷（对齐章节树抽屉逻辑，留空自动"第一卷/第二卷…"）──
  Future<void> _handleCreateVolume() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建卷'),
        content: TextField(
          key: const ValueKey('detail-new-volume-field'),
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '留空自动命名「第一卷/第二卷…」'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
    if (input == null) return;
    final trimmed = input.trim();
    try {
      final db = ref.read(appDatabaseProvider);
      final repo = VolumeRepository(db);
      await repo.createVolume(widget.args.manuscriptId, title: trimmed);
      final title = trimmed.isNotEmpty
          ? trimmed
          : repo.nextVolumeTitle(
              await repo.listVolumes(widget.args.manuscriptId),
            );
      ref.invalidate(volumeListProvider(widget.args.manuscriptId));
      if (!mounted) return;
      _snack('已创建《$title》');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 新建卷失败: $e');
      if (!mounted) return;
      _snack('新建卷失败，请稍后再试');
    }
  }

  Future<void> _handleRenameVolume(Volume volume) async {
    final controller = TextEditingController(text: volume.title);
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名卷'),
        content: TextField(
          key: const ValueKey('detail-rename-volume-field'),
          controller: controller,
          autofocus: true,
          maxLength: 12,
          decoration: const InputDecoration(hintText: '输入卷名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (input == null) return;
    final trimmed = input.trim();
    try {
      final repo = VolumeRepository(ref.read(appDatabaseProvider));
      await repo.updateVolumeTitle(volume.id, trimmed);
      ref.invalidate(volumeListProvider(widget.args.manuscriptId));
      if (!mounted) return;
      _snack(trimmed.isEmpty ? '已重命名为「未命名卷」' : '已重命名为《$trimmed》');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 重命名卷失败: $e');
      if (!mounted) return;
      _snack('重命名失败，请稍后再试');
    }
  }

  Future<void> _showVolumeActions(Volume volume) async {
    final action = await showYueModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.section,
                AppSpacing.lg,
                AppSpacing.section,
                AppSpacing.sm,
              ),
              child: Text(
                volume.title.trim().isEmpty ? '未命名卷' : volume.title.trim(),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.ios_share_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              title: const Text('导出本卷'),
              onTap: () => Navigator.pop(ctx, 'export'),
            ),
            ListTile(
              leading: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              title: const Text('重命名卷'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.danger,
              ),
              title: const Text(
                '删除卷',
                style: TextStyle(color: AppColors.danger),
              ),
              subtitle: const Text('卷内章节将一并删除', style: TextStyle(fontSize: 12)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      await _handleRenameVolume(volume);
    } else if (action == 'delete') {
      await _confirmDeleteVolume(volume);
    } else if (action == 'export') {
      await _exportVolume(volume);
    }
  }

  Future<void> _confirmDeleteVolume(Volume volume) async {
    final title = volume.title.trim().isEmpty ? '未命名卷' : volume.title.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除《$title》？'),
        content: const Text('删除后，卷内所有章节将一并删除（可在回收站恢复），不再散落。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repo = VolumeRepository(ref.read(appDatabaseProvider));
      await repo.deleteVolume(volume.id);
      // 批次96-4：卷内章节已一并软删——详情页真源 + FutureProvider 双通道刷新
      await ref
          .read(chapterStoreProvider(widget.args.manuscriptId).notifier)
          .loadChapters();
      ref.invalidate(volumeListProvider(widget.args.manuscriptId));
      ref.invalidate(chapterListProvider(widget.args.manuscriptId));
      if (!mounted) return;
      _snack('已删除《$title》');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 删除卷失败: $e');
      if (!mounted) return;
      _snack('删除卷失败，请稍后再试');
    }
  }
}
