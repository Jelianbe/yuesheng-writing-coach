// ─────────────────────────────────────────────────────────────
// WritingPageStatusController — 状态对话框控制器（C92-6b）
//
// 来源：原 `writing_page_status_builders.dart`（part + extension 伪拆分）。
// C92-6a 已把状态条/指示器/进度条/徽标/离线横幅提为独立视图类
// （view/writing_status_views.dart）；本控制器只承接两个对话框逻辑。
// 依赖：宿主 + 文档控制器（草稿恢复后同步编辑器正文）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';
import '../../../providers/writing_providers.dart';
import '../goal_dialog.dart';
import '../writing_page_host.dart';
import 'writing_page_document_controller.dart';

class WritingPageStatusController {
  WritingPageStatusController(this._host, this._document);

  final WritingPageHost _host;
  final WritingPageDocumentController _document;

  /// 草稿恢复弹窗：检测到上次未保存的草稿时询问恢复/放弃
  /// 对齐 RN chapter-editor.tsx Alert「发现未保存草稿」
  void showDraftRestoreDialog(WritingState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_host.mounted) return;
      showDialog<void>(
        context: _host.context,
        barrierDismissible: false,
        builder: (ctx) {
          final store = _host.ref.read(
            writingStoreProvider(_host.chapterId).notifier,
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
                  _document.syncEditorText(store.currentContent);
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
  Future<void> showGoalDialog() async {
    final current = _host.ref
        .read(writingStoreProvider(_host.chapterId))
        .goalWords;
    final result = await showDialog<int>(
      context: _host.context,
      builder: (_) => GoalDialog(current: current),
    );
    if (result != null && _host.mounted) {
      await _host.ref
          .read(writingStoreProvider(_host.chapterId).notifier)
          .setGoalWords(result);
    }
  }
}
