// ─────────────────────────────────────────────────────────────
// writing_page 的 part 文件：状态对话框（草稿恢复 / 写作目标设置）
//
// C92-6a（2026-09-12）伪拆分清偿：原文件内的「状态条 / 指示器 / 目标进度条 /
// 完成度徽标 / 离线横幅」已提取为**独立视图类**（view/writing_status_views.dart，
// 非 part）；本文件现仅保留两个对话框逻辑（弹窗需要宿主 store 与 context，
// 属 State 职责，6b 将转入独立控制器）。
// ─────────────────────────────────────────────────────────────
// ignore_for_file: invalid_use_of_protected_member
part of 'writing_page.dart';

extension _WritingPageStatusBuilders on _WritingPageState {
  /// 草稿恢复弹窗：检测到上次未保存的草稿时询问恢复/放弃
  /// 对齐 RN chapter-editor.tsx Alert「发现未保存草稿」
  void _showDraftRestoreDialog(WritingState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final store = ref.read(
            writingStoreProvider(widget.chapterId).notifier,
          );
          return AlertDialog(
            title: const Text('发现未保存草稿'),
            content: const Text('检测到上次未保存的草稿，是否恢复？'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  store.discardDraft();
                },
                child: const Text('放弃草稿'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  store.restoreDraft();
                  // 恢复后同步 controller（localContent 可能因 restoreDraft 变化，
                  // 而 controller 已有章节原文，不会触发「空则同步」分支）
                  _syncEditorText(store.currentContent);
                },
                child: const Text('恢复草稿'),
              ),
            ],
          );
        },
      );
    });
  }

  /// 批次82：写作目标设置对话框（AppBar 字数区点击弹出）
  /// 输入目标字数（0 或留空 = 不设目标；已有目标时可一键清除）
  Future<void> _showGoalDialog() async {
    final current = ref.read(writingStoreProvider(widget.chapterId)).goalWords;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => GoalDialog(current: current),
    );
    if (result != null && mounted) {
      await ref
          .read(writingStoreProvider(widget.chapterId).notifier)
          .setGoalWords(result);
    }
  }
}
