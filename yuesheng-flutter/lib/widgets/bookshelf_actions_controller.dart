// ─────────────────────────────────────────────────────────────
// bookshelf_actions_controller — 书架页作品动作控制器
//
// 从 bookshelf_actions.dart（原 part/extension）真分解而来：
//   handleContinueWriting / handleEditInfo / handlePin /
//   handleManuscriptTap / handleManuscriptLongPress /
//   confirmDeleteManuscript
//
// 依赖经 [BookshelfPageHost] 显式注入。原 `_handleManuscriptLongPress`
// （111 行）与 `_handleEditInfo`（68 行）在此**真拆**：菜单 / 弹窗 UI 分别
// 提为 BookshelfLongPressSheet / BookshelfEditManuscriptDialog，控制器只留
// 「组装回调 / 校验 / 落库」编排，全部 ≤50 行。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../providers/app_providers.dart';
import '../providers/manuscript_providers.dart';
import 'bookshelf_edit_manuscript_dialog.dart';
import 'bookshelf_long_press_sheet.dart';
import 'bookshelf_page_host.dart';
import 'yue_sheet.dart';

/// 书架页作品卡片动作（点按 / 长按菜单 / 置顶 / 删除 / 编辑）
class BookshelfActionsController {
  final BookshelfPageHost host;

  BookshelfActionsController(this.host);

  /// 批次93-7：长按菜单「继续写作」→ 最新章节写作页（无章节 → 详情页）
  Future<void> handleContinueWriting(Manuscript ms) async {
    try {
      final chapters = await ChapterRepository(
        host.ref.read(appDatabaseProvider),
      ).listChapters(ms.id);
      if (!host.context.mounted) return;
      if (chapters.isEmpty) {
        host.context.push(
          '/manuscript-detail',
          extra: {'manuscriptId': ms.id, 'title': ms.title},
        );
        return;
      }
      final last = chapters.last; // listChapters 按 sort_order 升序
      host.context.push(
        '/writing/${last.id}',
        extra: {'manuscriptId': ms.id, 'chapterTitle': last.title},
      );
    } catch (_) {
      // 读取失败静默（书架加载正常时不会发生）
    }
  }

  /// 批次93-7：长按菜单「编辑信息」→ 弹编辑弹窗 → updateManuscript
  Future<void> handleEditInfo(Manuscript ms) async {
    final input = await showDialog<ManuscriptEditInput>(
      context: host.context,
      builder: (_) => BookshelfEditManuscriptDialog(manuscript: ms),
    );
    if (input == null || !host.context.mounted) return;
    if (input.title.isEmpty) {
      ScaffoldMessenger.of(
        host.context,
      ).showSnackBar(const SnackBar(content: Text('标题不能为空')));
      return;
    }
    await host.ref
        .read(manuscriptStoreProvider.notifier)
        .updateManuscript(
          ms.id,
          title: input.title,
          description: input.description,
          genre: input.genre,
        );
  }

  /// 批次93-7：长按菜单「置顶」→ sort_order 置为当前最小 - 1
  Future<void> handlePin(Manuscript ms) async {
    try {
      final repo = ManuscriptRepository(host.ref.read(appDatabaseProvider));
      final minOrder = host.ref
          .read(manuscriptStoreProvider)
          .manuscripts
          .fold<int>(0, (min, m) => m.sortOrder < min ? m.sortOrder : min);
      await repo.updateSortOrder(ms.id, minOrder - 1);
      host.ref.read(manuscriptStoreProvider.notifier).loadManuscripts();
      if (!host.context.mounted) return;
      ScaffoldMessenger.of(host.context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('已置顶《${ms.title.isEmpty ? '未命名作品' : ms.title}》'),
            duration: const Duration(seconds: 2),
          ),
        );
    } catch (e) {
      debugPrint('[Bookshelf] 置顶失败: $e');
      if (!host.context.mounted) return;
      ScaffoldMessenger.of(host.context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('置顶失败，请稍后再试')));
    }
  }

  void handleManuscriptTap(Manuscript ms) {
    host.context.push(
      '/manuscript-detail',
      extra: {'manuscriptId': ms.id, 'title': ms.title},
    );
  }

  /// 批次93-7：书架长按作品 → 操作菜单（继续写作/编辑信息/置顶/删除）
  /// 笔落长按菜单模型；「导出」由批次94 落地（避免 WIP 死菜单项）
  void handleManuscriptLongPress(Manuscript ms) {
    if (!host.mounted) return;
    showYueModalBottomSheet<String>(
      context: host.context,
      isScrollControlled: true,
      builder: (_) => BookshelfLongPressSheet(
        title: ms.title.isEmpty ? '未命名作品' : ms.title,
        onContinueWriting: () => handleContinueWriting(ms),
        onEditInfo: () => handleEditInfo(ms),
        onPin: () => handlePin(ms),
        onDelete: () => confirmDeleteManuscript(ms),
      ),
    );
  }

  /// 批次 34：删除作品二次确认（软删 archived，章节/诊断数据保留，对齐 RN deleteManuscript）
  Future<void> confirmDeleteManuscript(Manuscript ms) async {
    final confirmed = await showDialog<bool>(
      context: host.context,
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
    if (confirmed != true || !host.context.mounted) return;
    await host.ref
        .read(manuscriptStoreProvider.notifier)
        .deleteManuscript(ms.id);
    if (host.context.mounted) {
      ScaffoldMessenger.of(
        host.context,
      ).showSnackBar(const SnackBar(content: Text('已删除')));
    }
  }
}
