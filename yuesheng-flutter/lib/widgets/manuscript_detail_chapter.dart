// ignore_for_file: invalid_use_of_protected_member
part of 'manuscript_detail_page.dart';

extension _ManuscriptDetailChapter on _ManuscriptDetailPageState {
  // ── 批次96-1：卷内上移/下移（同卷相邻章节交换 sort_order）──
  Future<void> _handleChapterMove(Chapter chapter, int delta) async {
    final msId = widget.args.manuscriptId;
    final chapters = ref.read(chapterStoreProvider(msId)).chapters;
    // 同卷章节（按 sort_order 排序）中找相邻目标
    final sameVolume =
        chapters.where((c) => c.volumeId == chapter.volumeId).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final idx = sameVolume.indexWhere((c) => c.id == chapter.id);
    final targetIdx = idx + delta;
    if (idx < 0 || targetIdx < 0 || targetIdx >= sameVolume.length) {
      _snack(delta < 0 ? '已在最前' : '已在最后');
      return;
    }
    final target = sameVolume[targetIdx];
    try {
      final repo = ChapterRepository(ref.read(appDatabaseProvider));
      await repo.swapChapterSortOrder(chapter.id, target.id);
      // 双通道刷新：详情页真源 + FutureProvider 消费者（章节树/写作页）
      await ref.read(chapterStoreProvider(msId).notifier).loadChapters();
      ref.invalidate(chapterListProvider(msId));
      if (!mounted) return;
      _snack(delta < 0 ? '已上移' : '已下移');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 章节移动失败: $e');
      if (!mounted) return;
      _snack('移动失败，请稍后再试');
    }
  }

  Future<void> _showMoveToVolumeSheet(Chapter chapter) async {
    final msId = widget.args.manuscriptId;
    final volumes =
        ref.read(volumeListProvider(msId)).value ?? const <Volume>[];
    const unassignedMarker = '__unassigned__';
    final selected = await showYueModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Column(
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
              '移动《${chapter.title.isEmpty ? '未命名章节' : chapter.title}》到',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const Divider(height: 1),
          for (final v in volumes)
            ListTile(
              leading: const Icon(
                Icons.collections_bookmark_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              title: Text(v.title.trim().isEmpty ? '未命名卷' : v.title.trim()),
              trailing: chapter.volumeId == v.id
                  ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                  : null,
              onTap: () => Navigator.pop(ctx, v.id),
            ),
          ListTile(
            leading: const Icon(
              Icons.notes_outlined,
              size: 18,
              color: AppColors.textTertiary,
            ),
            title: const Text('未分卷'),
            trailing: chapter.volumeId == null
                ? const Icon(Icons.check, size: 18, color: AppColors.primary)
                : null,
            onTap: () => Navigator.pop(ctx, unassignedMarker),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
    if (!mounted || selected == null) return;
    final target = selected == unassignedMarker ? null : selected;
    if (chapter.volumeId == target) return;
    try {
      final repo = VolumeRepository(ref.read(appDatabaseProvider));
      await repo.moveChapterToVolumeEnd(chapter.id, target);
      // 双通道刷新：详情页真源 + FutureProvider 消费者 + 卷列表
      await ref.read(chapterStoreProvider(msId).notifier).loadChapters();
      ref.invalidate(chapterListProvider(msId));
      ref.invalidate(volumeListProvider(msId));
      if (!mounted) return;
      _snack('已移动到${target == null ? '未分卷' : '目标卷'}');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 移动章节失败: $e');
      if (!mounted) return;
      _snack('移动失败，请稍后再试');
    }
  }

  Future<void> _handleRenameChapter(Chapter chapter) async {
    final controller = TextEditingController(text: chapter.title);
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名章节'),
        content: TextField(
          key: ValueKey('rename-chapter-${chapter.id}'),
          controller: controller,
          autofocus: true,
          maxLength: 30,
          decoration: const InputDecoration(hintText: '输入章节标题'),
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
      await ref
          .read(chapterStoreProvider(widget.args.manuscriptId).notifier)
          .updateChapterTitle(chapter.id, trimmed);
      // 同步写作页 FutureProvider 缓存（下次打开章节树抽屉/写作页读到新标题）
      ref.invalidate(chapterListProvider(widget.args.manuscriptId));
      if (!mounted) return;
      _snack(trimmed.isEmpty ? '已重命名为「未命名章节」' : '已重命名为《$trimmed》');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 重命名章节失败: $e');
      if (!mounted) return;
      _snack('重命名失败，请稍后再试');
    }
  }

  Future<void> _handleQuickCreateChapter(String? volumeId) async {
    final msId = widget.args.manuscriptId;
    final repo = ChapterRepository(ref.read(appDatabaseProvider));
    final chapters = await repo.listChapters(msId);
    final title = nextChapterTitle(chapters);
    final id = await ref
        .read(chapterStoreProvider(msId).notifier)
        .createChapter(title: title, volumeId: volumeId);
    if (id != null && mounted) {
      ref.invalidate(chapterListProvider(msId));
      _snack('已创建《$title》');
    } else if (mounted) {
      _snack('创建失败，请稍后再试');
    }
  }

  void _handleChapterTap(Chapter chapter) {
    context
        .push(
          '/writing/${chapter.id}',
          extra: {
            'chapterTitle': chapter.title,
            'manuscriptId': chapter.manuscriptId,
          },
        )
        .then((_) {
          // 批次96-4：写作页返回后重载章节列表——标题/字数等编辑结果同步回列表
          if (mounted) {
            ref
                .read(chapterStoreProvider(chapter.manuscriptId).notifier)
                .loadChapters();
          }
        });
  }

  void _handleChapterLongPress(Chapter chapter) {
    if (!mounted) return;
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            12,
            AppSpacing.lg,
            24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部把手
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
              // 修复3：重命名章节（铅笔图标入口之外的第二入口）
              InkWell(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handleRenameChapter(chapter);
                },
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '重命名《${chapter.title.isEmpty ? '未命名章节' : chapter.title}》',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              // 批次96-1：卷内上移（同卷前一章交换 sort_order）
              InkWell(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handleChapterMove(chapter, -1);
                },
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_upward_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '上移',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              // 批次96-1：卷内下移（同卷后一章交换 sort_order）
              InkWell(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handleChapterMove(chapter, 1);
                },
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.arrow_downward_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '下移',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              // 批次96-1：移动到卷（跨卷归属调整，对齐章节树抽屉入口）
              InkWell(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showMoveToVolumeSheet(chapter);
                },
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.drive_file_move_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '移动到卷',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              // 批次94-1：导出本章（重命名与删除之间）
              InkWell(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _exportChapter(chapter);
                },
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.ios_share_outlined,
                        size: 20,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '导出《${chapter.title.isEmpty ? '未命名章节' : chapter.title}》',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1, color: AppColors.divider),
              InkWell(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDeleteChapter(chapter);
                },
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.delete_outline,
                        size: 20,
                        color: AppColors.danger,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '删除《${chapter.title.isEmpty ? '未命名章节' : chapter.title}》',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textSecondary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteChapter(Chapter chapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除章节'),
        content: Text(
          '确定删除《${chapter.title.isEmpty ? '未命名章节' : chapter.title}》吗？'
          '该章节将移入回收站，可随时恢复，诊断历史会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await ref
        .read(chapterStoreProvider(widget.args.manuscriptId).notifier)
        .softDeleteChapter(chapter.id);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ok ? '已移入回收站' : '删除失败，请稍后再试')));
    }
  }
}
