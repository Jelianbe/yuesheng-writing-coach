// ignore_for_file: invalid_use_of_protected_member
part of 'bookshelf_page.dart';

extension _BookshelfActions on _BookshelfPageState {
  /// 批次93-7：长按菜单「继续写作」→ 最新章节写作页（无章节 → 详情页）
  Future<void> _handleContinueWriting(Manuscript ms) async {
    try {
      final chapters = await ChapterRepository(
        ref.read(appDatabaseProvider),
      ).listChapters(ms.id);
      if (!mounted) return;
      if (chapters.isEmpty) {
        context.push(
          '/manuscript-detail',
          extra: {'manuscriptId': ms.id, 'title': ms.title},
        );
        return;
      }
      final last = chapters.last; // listChapters 按 sort_order 升序
      context.push(
        '/writing/${last.id}',
        extra: {'manuscriptId': ms.id, 'chapterTitle': last.title},
      );
    } catch (_) {
      // 读取失败静默（书架加载正常时不会发生）
    }
  }

  /// 批次93-7：长按菜单「编辑信息」→ 弹编辑弹窗 → updateManuscript
  Future<void> _handleEditInfo(Manuscript ms) async {
    final titleC = TextEditingController(text: ms.title);
    final descC = TextEditingController(text: ms.description);
    final genreC = TextEditingController(text: ms.genre);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑作品信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('edit-title-field'),
              controller: titleC,
              maxLength: 30,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '输入作品标题',
              ),
            ),
            TextField(
              controller: descC,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: '简介',
                hintText: '一句话介绍你的作品',
              ),
            ),
            TextField(
              controller: genreC,
              decoration: const InputDecoration(
                labelText: '类型',
                hintText: '如：奇幻、都市',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != true || !mounted) return;
    final title = titleC.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('标题不能为空')));
      return;
    }
    await ref
        .read(manuscriptStoreProvider.notifier)
        .updateManuscript(
          ms.id,
          title: title,
          description: descC.text.trim(),
          genre: genreC.text.trim(),
        );
  }

  /// 批次93-7：长按菜单「置顶」→ sort_order 置为当前最小 - 1
  Future<void> _handlePin(Manuscript ms) async {
    try {
      final repo = ManuscriptRepository(ref.read(appDatabaseProvider));
      final minOrder = ref
          .read(manuscriptStoreProvider)
          .manuscripts
          .fold<int>(0, (min, m) => m.sortOrder < min ? m.sortOrder : min);
      await repo.updateSortOrder(ms.id, minOrder - 1);
      ref.read(manuscriptStoreProvider.notifier).loadManuscripts();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已置顶《${ms.title.isEmpty ? '未命名作品' : ms.title}》'),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e) {
      debugPrint('[Bookshelf] 置顶失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('置顶失败，请稍后再试')));
    }
  }

  void _handleManuscriptTap(Manuscript ms) {
    context.push(
      '/manuscript-detail',
      extra: {'manuscriptId': ms.id, 'title': ms.title},
    );
  }

  /// 批次93-7：书架长按作品 → 操作菜单（继续写作/编辑信息/置顶/删除）
  /// 笔落长按菜单模型；「导出」由批次94 落地（避免 WIP 死菜单项）
  void _handleManuscriptLongPress(Manuscript ms) {
    if (!mounted) return;
    final title = ms.title.isEmpty ? '未命名作品' : ms.title;
    showYueModalBottomSheet<String>(
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
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Divider(height: 1),
              _LongPressAction(
                icon: Icons.edit_note_outlined,
                label: '继续写作',
                iconColor: AppColors.primary,
                labelColor: AppColors.primary,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handleContinueWriting(ms);
                },
              ),
              const Divider(height: 1),
              _LongPressAction(
                icon: Icons.edit_outlined,
                label: '编辑信息',
                iconColor: AppColors.textPrimary,
                labelColor: AppColors.textPrimary,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handleEditInfo(ms);
                },
              ),
              const Divider(height: 1),
              _LongPressAction(
                icon: Icons.push_pin_outlined,
                label: '置顶',
                iconColor: AppColors.textPrimary,
                labelColor: AppColors.textPrimary,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _handlePin(ms);
                },
              ),
              const Divider(height: 1),
              _LongPressAction(
                icon: Icons.delete_outline,
                label: '删除',
                iconColor: AppColors.danger,
                labelColor: AppColors.danger,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _confirmDeleteManuscript(ms);
                },
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

  /// 批次 34：删除作品二次确认（软删 archived，章节/诊断数据保留，对齐 RN deleteManuscript）
  Future<void> _confirmDeleteManuscript(Manuscript ms) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除作品'),
        content: Text(
          '确定删除《${ms.title.isEmpty ? '未命名作品' : ms.title}》吗？删除后将不再显示，章节和诊断记录会保留。',
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
    await ref.read(manuscriptStoreProvider.notifier).deleteManuscript(ms.id);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已删除')));
    }
  }
}
