// ─────────────────────────────────────────────────────────────
// manuscript_detail_chapter_controller — 作品详情页章节动作控制器
//
// 从 manuscript_detail_chapter.dart（原 part/extension）真分解而来：
//   moveChapter / showMoveToVolumeSheet / renameChapter / quickCreateChapter
//   / openChapter / openChapterActions / confirmDeleteChapter
//
// 原 244 行 `_handleChapterLongPress` 超限方法拆为 openChapterActions（薄）
// + manuscript_detail_chapter_actions_sheet.dart（弹层 Widget），满足 R-019。
//
// 依赖经 [ManuscriptDetailHost] 显式注入；导出委托 [ManuscriptDetailExporter]。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/volume_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chapter_providers.dart';
import '../providers/manuscript_providers.dart';
import '../utils/chapter_title.dart';
import 'manuscript_detail_chapter_actions_sheet.dart';
import 'manuscript_detail_exporter.dart';
import 'manuscript_detail_host.dart';
import 'manuscript_detail_move_to_volume_sheet.dart';
import 'yue_sheet.dart';

/// 作品详情页章节动作
class ManuscriptDetailChapterController {
  final ManuscriptDetailHost host;
  final ManuscriptDetailExporter exporter;

  ManuscriptDetailChapterController(this.host, this.exporter);

  // ── 批次96-1：卷内上移/下移（同卷相邻章节交换 sort_order）──
  Future<void> moveChapter(Chapter chapter, int delta) async {
    final msId = host.manuscriptId;
    final chapters = host.ref.read(chapterStoreProvider(msId)).chapters;
    // 同卷章节（按 sort_order 排序）中找相邻目标
    final sameVolume =
        chapters.where((c) => c.volumeId == chapter.volumeId).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final idx = sameVolume.indexWhere((c) => c.id == chapter.id);
    final targetIdx = idx + delta;
    if (idx < 0 || targetIdx < 0 || targetIdx >= sameVolume.length) {
      host.showSnack(delta < 0 ? '已在最前' : '已在最后');
      return;
    }
    final target = sameVolume[targetIdx];
    try {
      final repo = ChapterRepository(host.ref.read(appDatabaseProvider));
      await repo.swapChapterSortOrder(chapter.id, target.id);
      // 双通道刷新：详情页真源 + FutureProvider 消费者（章节树/写作页）
      await host.ref.read(chapterStoreProvider(msId).notifier).loadChapters();
      if (!host.mounted) return;
      host.showSnack(delta < 0 ? '已上移' : '已下移');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 章节移动失败: $e');
      if (!host.mounted) return;
      host.showSnack('移动失败，请稍后再试');
    }
  }

  /// 批次96-1：移动到卷弹层（目标：全部卷 + 未分卷）
  Future<void> showMoveToVolumeSheet(Chapter chapter) async {
    final msId = host.manuscriptId;
    final volumes =
        host.ref.read(volumeListProvider(msId)).value ?? const <Volume>[];
    final selected = await showYueModalBottomSheet<String>(
      context: host.context,
      builder: (_) => MoveToVolumeSheet(chapter: chapter, volumes: volumes),
    );
    if (!host.mounted || selected == null) return;
    await _applyMoveToVolume(chapter, selected, msId);
  }

  /// 执行移动到卷（含未分卷）
  Future<void> _applyMoveToVolume(
    Chapter chapter,
    String selected,
    String msId,
  ) async {
    final target = selected == MoveToVolumeSheet.unassignedMarker
        ? null
        : selected;
    if (chapter.volumeId == target) return;
    try {
      final repo = VolumeRepository(host.ref.read(appDatabaseProvider));
      await repo.moveChapterToVolumeEnd(chapter.id, target);
      // 双通道刷新：详情页真源 + FutureProvider 消费者 + 卷列表
      await host.ref.read(chapterStoreProvider(msId).notifier).loadChapters();
      host.ref.invalidate(volumeListProvider(msId));
      if (!host.mounted) return;
      host.showSnack('已移动到${target == null ? '未分卷' : '目标卷'}');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 移动章节失败: $e');
      if (!host.mounted) return;
      host.showSnack('移动失败，请稍后再试');
    }
  }

  /// 修复3：重命名章节（铅笔图标 + 长按菜单均走这里）
  Future<void> renameChapter(Chapter chapter) async {
    final controller = TextEditingController(text: chapter.title);
    final input = await showDialog<String>(
      context: host.context,
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
      await host.ref
          .read(chapterStoreProvider(host.manuscriptId).notifier)
          .updateChapterTitle(chapter.id, trimmed);
      // 同步写作页 FutureProvider 缓存（下次打开章节树抽屉/写作页读到新标题）
      if (!host.mounted) return;
      host.showSnack(trimmed.isEmpty ? '已重命名为「未命名章节」' : '已重命名为《$trimmed》');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 重命名章节失败: $e');
      if (!host.mounted) return;
      host.showSnack('重命名失败，请稍后再试');
    }
  }

  /// 批次96-2：列表级「新建章节」快捷入口（卷内末尾/列表末尾）
  /// 就近归属：卷内入口 → 归属该卷；列表末尾 → 未分卷（散落）
  /// 自动命名「第X章」（复用 nextChapterTitle）
  /// 批次96-4：创建后不再跳写作页——只创建，列表即时可见（SnackBar 提示）
  Future<void> quickCreateChapter(String? volumeId) async {
    final msId = host.manuscriptId;
    final repo = ChapterRepository(host.ref.read(appDatabaseProvider));
    final chapters = await repo.listChapters(msId);
    final title = nextChapterTitle(chapters);
    final id = await host.ref
        .read(chapterStoreProvider(msId).notifier)
        .createChapter(title: title, volumeId: volumeId);
    if (id != null && host.mounted) {
      host.showSnack('已创建《$title》');
    } else if (host.mounted) {
      host.showSnack('创建失败，请稍后再试');
    }
  }

  /// 点击章节进入写作页
  void openChapter(Chapter chapter) {
    host.context
        .push(
          '/writing/${chapter.id}',
          extra: {
            'chapterTitle': chapter.title,
            'manuscriptId': chapter.manuscriptId,
          },
        )
        .then((_) {
          // 批次96-4：写作页返回后重载章节列表——标题/字数等编辑结果同步回列表
          if (host.mounted) {
            host.ref
                .read(chapterStoreProvider(chapter.manuscriptId).notifier)
                .loadChapters();
          }
        });
  }

  /// 批次 34：详情页长按章节 → 操作菜单（重命名 / 上移 / 下移 / 移动 / 导出 / 删除）
  void openChapterActions(Chapter chapter) {
    if (!host.mounted) return;
    showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      builder: (_) => ChapterActionsSheet(
        chapter: chapter,
        onRename: () => renameChapter(chapter),
        onMoveUp: () => moveChapter(chapter, -1),
        onMoveDown: () => moveChapter(chapter, 1),
        onMoveToVolume: () => showMoveToVolumeSheet(chapter),
        onExport: () => exporter.exportChapter(chapter),
        onDelete: () => confirmDeleteChapter(chapter),
      ),
    );
  }

  /// 批次94-2：删除章节 → 软删进回收站（可恢复，诊断历史保留）
  Future<void> confirmDeleteChapter(Chapter chapter) async {
    final confirmed = await showDialog<bool>(
      context: host.context,
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
    if (confirmed != true || !host.mounted) return;
    final ok = await host.ref
        .read(chapterStoreProvider(host.manuscriptId).notifier)
        .softDeleteChapter(chapter.id);
    if (host.context.mounted) {
      ScaffoldMessenger.of(
        host.context,
      ).showSnackBar(SnackBar(content: Text(ok ? '已移入回收站' : '删除失败，请稍后再试')));
    }
  }
}
