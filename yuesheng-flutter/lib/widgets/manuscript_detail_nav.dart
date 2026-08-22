// ignore_for_file: invalid_use_of_protected_member
part of 'manuscript_detail_page.dart';

extension _ManuscriptDetailNav on _ManuscriptDetailPageState {
  /// 批次 30：相关对话点击 → 交接待打开会话并切到对话 Tab
  /// ChatPage 监听 pendingOpenSessionProvider 非空时 switchTo 目标会话
  void _handleOpenRelatedSession(String sessionId) {
    ref.read(pendingOpenSessionProvider.notifier).state = sessionId;
    context.go(AppRoutes.writing);
  }

  void _openAppendChapters() {
    final ms = _manuscript;
    context.push(
      '/append-chapters',
      extra: <String, dynamic>{
        'manuscriptId': widget.args.manuscriptId,
        'title': ms?.title ?? widget.args.title ?? '',
      },
    );
  }

  void _openMoreMenu() {
    final ms = _manuscript;
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _MoreMenuSheet(
        onOpenSettings: () {
          Navigator.of(sheetContext).pop();
          context.push(
            '/project-settings',
            extra: <String, dynamic>{
              'manuscriptId': widget.args.manuscriptId,
              'title': ms?.title ?? widget.args.title ?? '',
            },
          );
        },
        onExport: () {
          Navigator.of(sheetContext).pop();
          _exportManuscript();
        },
        onRecycleBin: () {
          Navigator.of(sheetContext).pop();
          context.push(
            AppRoutes.chapterRecycleBin,
            extra: <String, dynamic>{
              'manuscriptId': widget.args.manuscriptId,
              'title': ms?.title ?? widget.args.title ?? '',
            },
          );
        },
        onDelete: () {
          Navigator.of(sheetContext).pop();
          _confirmDeleteManuscript();
        },
      ),
    );
  }

  Future<void> _confirmDeleteManuscript() async {
    final title = (widget.args.title?.trim().isNotEmpty ?? false)
        ? widget.args.title!
        : '未命名作品';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除作品'),
        content: Text('确定删除《$title》吗？删除后将不再显示，章节和诊断记录会保留。'),
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
    try {
      await ref
          .read(manuscriptStoreProvider.notifier)
          .deleteManuscript(widget.args.manuscriptId);
      if (mounted) context.go('/bookshelf');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    }
  }
}
