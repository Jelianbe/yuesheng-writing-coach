// ─────────────────────────────────────────────────────────────
// writing_page 的 part 文件：状态/指示器 builders + 草稿恢复对话框
// 覆盖批次60/82/85-1/94-4 的保存状态条、离线横幅、写作目标（对话框+
// 进度条+字数指示器+完成度徽章）与批次草稿恢复弹窗。
// 以私有 extension on _WritingPageState 形式提供，直接访问宿主私有
// 成员（ref / context / widget / _syncEditorText 等），行为与原内联
// 实现完全一致，仅做物理拆分。
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

  /// 离线横幅：断网时提示内容自动保存为本地草稿
  /// 对齐 RN chapter-editor.tsx offlineBar
  Widget _buildOfflineBanner(WritingState state) {
    if (!state.isOffline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.warningBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前离线，内容自动保存为本地草稿，恢复网络后将同步',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }

  /// 批次60：保存状态条——编辑器底部轻量指示「保存中… / 已保存 HH:MM / 保存失败」
  /// 让用户直观确认内容已落库（数据安全感），失败时给出可见但温和的提示
  /// 批次 X-037-P0-1 H2/C1：暗夜保存状态条联动走 AppColors.editorDark* 令牌（消除硬编码；muted 用 editorDarkMuted 4.56:1 达 AA）
  Widget _buildSaveStatusBar(WritingState state) {
    final darkUi = isDarkEditorPreset(state.editorBackground);
    final muted = darkUi ? AppColors.editorDarkMuted : AppColors.textTertiary;
    final barBg = darkUi ? AppColors.editorDarkPanel : AppColors.background;
    final Widget content;
    if (state.isSaving) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: muted),
          ),
          const SizedBox(width: 6),
          Text('保存中…', style: TextStyle(fontSize: 11, color: muted)),
        ],
      );
    } else if (state.saveError != null) {
      content = const Text(
        '保存失败，请稍后重试',
        style: TextStyle(fontSize: 11, color: AppColors.warning),
      );
    } else if (state.lastSavedAt != null) {
      content = Text(
        '已保存 ${_formatTime(state.lastSavedAt!)}',
        style: TextStyle(fontSize: 11, color: muted),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: barBg,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Align(alignment: Alignment.centerRight, child: content),
    );
  }

  /// HH:mm 格式化（保存状态条用）
  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
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

  /// 批次82：AppBar 底部 2dp 写作目标进度条（未设目标时不占位）
  PreferredSizeWidget _buildGoalProgressBar(
    WritingState state, {
    bool darkUi = false,
  }) {
    final goal = state.goalWords;
    if (goal <= 0) {
      return const PreferredSize(
        preferredSize: Size.zero,
        child: SizedBox.shrink(),
      );
    }
    final value = (state.wordCount / goal).clamp(0.0, 1.0).toDouble();
    return PreferredSize(
      preferredSize: const Size.fromHeight(2),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 2,
        backgroundColor: darkUi
            ? const Color(0xFF3A3F45)
            : AppColors.placeholder,
        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
      ),
    );
  }

  /// 批次82：AppBar 字数区——未设目标显示「12字」；已设目标显示「1,234/5,000」，
  /// 点击弹出目标设置对话框；达标后字数高亮为竹青
  /// 批次85-1：字数区右侧追加「完成度徽标」——设目标显示进度百分比（达标显示「已达成」），
  /// 未设目标显示章节体量徽标（短章/中章/长章），让学员随时看到自己产出。
  Widget _buildWordCountIndicator(WritingState state, {Color? mutedColor}) {
    final goal = state.goalWords;
    final String text;
    final Color color;
    final secondary = mutedColor ?? AppColors.textSecondary;
    if (goal > 0) {
      text = '${_formatNum(state.wordCount)}/${_formatNum(goal)}';
      color = state.wordCount >= goal ? AppColors.primary : secondary;
    } else {
      text = _formatWordCount(state.wordCount);
      color = secondary;
    }
    return InkWell(
      onTap: _showGoalDialog,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(width: 6),
            _buildCompletionBadge(state),
          ],
        ),
      ),
    );
  }

  /// 批次85-1：完成度徽标
  Widget _buildCompletionBadge(WritingState state) {
    final goal = state.goalWords;
    final String label;
    final Color bg;
    final Color fg;
    if (goal > 0) {
      final done = state.wordCount >= goal;
      if (done) {
        label = '已达成';
        bg = AppColors.successBg;
        fg = AppColors.success;
      } else {
        final pct = (state.wordCount / goal * 100).round();
        label = '$pct%';
        bg = AppColors.primarySoft;
        fg = AppColors.primaryDeep;
      }
    } else {
      label = _chapterScaleLabel(state.wordCount);
      bg = AppColors.primarySoft;
      fg = AppColors.primaryDeep;
    }
    return Container(
      key: const Key('completionBadge'),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: fg)),
    );
  }

  /// 章节体量徽标：<3000 短章 / 3000-9999 中章 / ≥10000 长章
  String _chapterScaleLabel(int wordCount) {
    if (wordCount >= 10000) return '长章';
    if (wordCount >= 3000) return '中章';
    return '短章';
  }
}
