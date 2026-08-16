// ignore_for_file: invalid_use_of_protected_member
part of 'bookshelf_page.dart';

extension _BookshelfCreate on _BookshelfPageState {
    void _openCreateModal() {
      // P0-2 修复：改用 showDialog 标准屏障遮罩：
      //   - barrier 黑色半透明，背景变暗，不会穿透
      //   - barrierDismissible = true：点外部自动关闭
      //   - 弹窗卸载时自动触发 WillPopScope → 清理控制器
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: AppColors.overlay,
        builder: (ctx) {
          return _CreateManuscriptModal(
            titleController: _titleController,
            descController: _descController,
            genreController: _genreController,
            onCancel: _closeCreateModal,
            onCreate: _handleCreate,
            // 批次 35：新建弹窗内「文本导入」入口
            onImportTap: _openImportSheet,
          );
        },
      ).then((_) {
        // 无论是 barrier dismiss 还是取消/创建成功，最终都清理一次
        if (_titleController.text.isNotEmpty ||
            _descController.text.isNotEmpty ||
            _genreController.text.isNotEmpty) {
          _titleController.clear();
          _descController.clear();
          _genreController.clear();
        }
      });
    }
    void _closeCreateModal() {
      _titleController.clear();
      _descController.clear();
      _genreController.clear();
      // showDialog 默认 useRootNavigator: true，弹窗在 root navigator 上；
      // 必须用 rootNavigator: true 弹出（对齐批次 27 创建成功路径的修复），
      // 否则会误 pop go_router 嵌套导航栈（bookshelf 是栈底）→ 空栈断言崩溃。
      if (mounted) {
        try {
          Navigator.of(context, rootNavigator: true).pop();
        } catch (_) {}
      }
    }
    /// 批次 35：新建弹窗「文本导入」→ 关闭表单弹窗 + 打开导入弹层
    void _openImportSheet() {
      _closeCreateModal();
      if (!mounted) return;
      showYueModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => BookImportSheet(onImported: _handleImported),
      );
    }
    /// 批次 35：导入成功 → 刷新书架 + 提示
    void _handleImported(WorkImportResult result) {
      if (!mounted) return;
      _refreshBookshelf();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已导入《${result.title}》（${result.chapterCount}章）')),
      );
    }
    Future<void> _handleCreate() async {
      final title = _titleController.text.trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请输入作品标题')));
        return;
      }

      final id = await ref
          .read(manuscriptStoreProvider.notifier)
          .createManuscript(
            title: title,
            description: _descController.text.trim(),
            genre: _genreController.text.trim(),
          );

      if (id != null && mounted) {
        // 创建作品成功：关闭创建弹窗。
        // showDialog 默认 useRootNavigator: true，弹窗在 root navigator 上；
        // 必须用 rootNavigator: true 弹出，否则会误 pop go_router 嵌套导航栈
        // （bookshelf 是栈底唯一页面 → 空栈断言崩溃）。
        Navigator.of(context, rootNavigator: true).pop();
        // 批次93-4：新建书后立即跳详情页（阅文「去写作」模型，不再是留在书架 + SnackBar）
        context.push(
          '/manuscript-detail',
          extra: {'manuscriptId': id, 'title': title},
        );
      } else if (mounted) {
        // P2-5：创建失败时给用户明确反馈
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('创建失败，请稍后再试')));
      }
    }
}
