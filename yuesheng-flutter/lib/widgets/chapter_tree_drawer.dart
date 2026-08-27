// ─────────────────────────────────────────────────────────────
// ChapterTreeDrawer — 章节树侧栏（批次83 章节树侧栏 / 批次89-2 卷分组）
// 写作页左侧抽屉：作品全部章节 + 当前章高亮 + 快速跳转 + 新建章节。
//
// 设计说明：
//   - 批次83 第一版为扁平章列表；批次89-2 起按卷分组折叠展示：
//     卷按 sort_order 展示，未分卷章节归入末尾「未分卷」组；卷头可
//     点击折叠/展开（折叠态为组件内本地状态，随抽屉重建重置）。
//   - 无卷的作品（volumes 为空）保持扁平列表，行为与批次83 一致。
//   - 抽屉每次打开由 WritingPage 以新 ValueKey 重建 + 失效
//     chapterListProvider / volumeListProvider，保证列表数据与标题最新
//   - 跳转/新建动作通过回调交给 WritingPage 执行（本组件保持纯 UI）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/volume_repository.dart';
import '../data/repositories/chapter_repository.dart';
import '../providers/app_providers.dart';
import '../providers/manuscript_providers.dart';
import '../utils/volume_group.dart';
import 'yue_sheet.dart';

/// 章节状态 → 中文标签 + 矿物色配色（对齐稿件详情页章节卡）
class _StatusConfig {
  final String label;
  final Color bgColor;
  final Color textColor;
  const _StatusConfig(this.label, this.bgColor, this.textColor);
}

const Map<String, _StatusConfig> _statusConfig = {
  'draft': _StatusConfig('草稿', AppColors.border, AppColors.textDeep),
  'revising': _StatusConfig('修改中', AppColors.warningBg, AppColors.warning),
  'complete': _StatusConfig('完成', AppColors.l1, AppColors.primary),
};

class ChapterTreeDrawer extends ConsumerStatefulWidget {
  final String currentChapterId;

  /// 所属作品 ID（null/空 = 无法加载列表，走空态）
  final String? manuscriptId;

  /// 点击某章 → 快速跳转（由 WritingPage 执行）
  final void Function(String chapterId, String title) onJumpToChapter;

  /// 点击「新建章节」（由 WritingPage 执行）
  final VoidCallback onCreateChapter;

  const ChapterTreeDrawer({
    super.key,
    required this.currentChapterId,
    required this.manuscriptId,
    required this.onJumpToChapter,
    required this.onCreateChapter,
  });

  @override
  ConsumerState<ChapterTreeDrawer> createState() => _ChapterTreeDrawerState();
}

class _ChapterTreeDrawerState extends ConsumerState<ChapterTreeDrawer> {
  /// 已折叠的卷 id
  final Set<String> _collapsed = {};

  @override
  Widget build(BuildContext context) {
    final msId = widget.manuscriptId ?? '';
    final chaptersAsync = msId.isEmpty
        ? null
        : ref.watch(chapterListProvider(msId));
    final volumesAsync = msId.isEmpty
        ? null
        : ref.watch(volumeListProvider(msId));
    final chapters = chaptersAsync?.value ?? const <Chapter>[];
    final volumes = volumesAsync?.value ?? const <Volume>[];
    final loading =
        (chaptersAsync?.isLoading ?? false) ||
        (volumesAsync?.isLoading ?? false);

    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 头部：标题 + 章节数 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
              child: Row(
                children: [
                  const Icon(
                    Icons.menu_book_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '章节列表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textInk,
                    ),
                  ),
                  const Spacer(),
                  // 批次89-3：新建卷入口（始终可用，卷可在任何时候追加）
                  IconButton(
                    key: const ValueKey('create-volume-btn'),
                    onPressed: msId.isNotEmpty ? _handleCreateVolume : null,
                    visualDensity: VisualDensity.compact,
                    tooltip: '新建卷',
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    '${chapters.length} 章',
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── 章节列表 / 加载中 / 空态 ──
            Expanded(child: _buildBody(chapters, volumes, loading)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    List<Chapter> chapters,
    List<Volume> volumes,
    bool loading,
  ) {
    if (loading && chapters.isEmpty && volumes.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      );
    }

    final children = <Widget>[];
    if (chapters.isEmpty && volumes.isEmpty) {
      // 空态：引导提示 + 末尾「新建章节」行（底部无独立按钮）
      children.add(
        const Padding(
          padding: EdgeInsets.only(top: AppSpacing.xxl + AppSpacing.xl, bottom: AppSpacing.sm),
          child: _EmptyChapters(),
        ),
      );
    } else if (volumes.isEmpty) {
      // 无卷 → 扁平章节列表（批次83 原行为，兼容既有测试）
      for (final ch in chapters) {
        children.add(_buildChapterItem(ch));
      }
    } else {
      // 有卷 → 按全局序渲染段（批次96-4：散落章节平铺无组头，卷组自然穿插）
      final sections = buildChapterSections(volumes, chapters);
      for (final sec in sections) {
        final loose = sec.looseChapter;
        if (loose != null) {
          children.add(_buildChapterItem(loose));
          continue;
        }
        final volume = sec.volume!;
        final key = volume.id;
        final collapsed = _collapsed.contains(key);
        children.add(
          _VolumeHeader(
            volume: volume,
            count: sec.chapters.length,
            collapsed: collapsed,
            onToggle: () => setState(() {
              if (!_collapsed.add(key)) _collapsed.remove(key);
            }),
            onLongPress: () => _showVolumeActions(volume),
            onRename: () => _handleRenameVolume(volume),
          ),
        );
        if (collapsed) continue;
        if (sec.chapters.isEmpty) {
          children.add(const _EmptyVolumeHint());
          continue;
        }
        for (final ch in sec.chapters) {
          children.add(_buildChapterItem(ch));
        }
      }
    }
    // 批次89-4：列表末尾「新建章节」行（新建卷唯一入口 = 头部「＋」图标）
    children.add(_NewChapterRow(onTap: widget.onCreateChapter));
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      children: children,
    );
  }

  Widget _buildChapterItem(Chapter ch) {
    final isCurrent = ch.id == widget.currentChapterId;
    return _ChapterTreeItem(
      // 当前章唯一标记（测试高亮断言用）
      key: isCurrent ? ValueKey('tree-current-${ch.id}') : null,
      chapter: ch,
      isCurrent: isCurrent,
      onTap: () => widget.onJumpToChapter(ch.id, ch.title),
      // 批次89-3：长按章节 → 操作弹层（先重命名再移卷）
      onLongPress: () => _showChapterActionsSheet(ch),
      // 修复3：行尾铅笔图标 → 直接重命名
      onRename: () => _handleRenameChapter(ch),
    );
  }

  // ── 批次89-3：卷管理交互（新建卷 / 删卷 / 章节移到卷）──
  // ── 修复3：章节管理交互（重命名 + 移卷）──

  String get _msId => widget.manuscriptId ?? '';

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  /// 修复3：重命名章节（铅笔图标 + 操作弹层均走这里）
  Future<void> _handleRenameChapter(Chapter chapter) async {
    final controller = TextEditingController(text: chapter.title);
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名章节'),
        content: TextField(
          key: ValueKey('tree-rename-${chapter.id}'),
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
      final db = ref.read(appDatabaseProvider);
      final repo = ChapterRepository(db);
      await repo.updateChapterTitle(chapter.id, trimmed);
      ref.invalidate(chapterListProvider(_msId));
      if (!mounted) return;
      _snack(trimmed.isEmpty ? '已重命名为「未命名章节」' : '已重命名为《$trimmed》');
    } catch (e) {
      debugPrint('[ChapterTreeDrawer] 重命名章节失败: $e');
      if (!mounted) return;
      _snack('重命名失败，请稍后再试');
    }
  }

  /// 修复3：长按章节 → 先弹操作菜单（重命名 / 移动到卷），选移卷再进卷列表
  Future<void> _showChapterActionsSheet(Chapter chapter) async {
    final action = await showYueModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.section, AppSpacing.lg, AppSpacing.section, AppSpacing.sm),
              child: Text(
                chapter.title.trim().isEmpty ? '未命名章节' : chapter.title.trim(),
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
                Icons.edit_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              title: const Text('重命名章节'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(
                Icons.drive_file_move_outlined,
                size: 18,
                color: AppColors.textPrimary,
              ),
              title: const Text('移动到卷'),
              onTap: () => Navigator.pop(ctx, 'move'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'rename') {
      await _handleRenameChapter(chapter);
    } else if (action == 'move') {
      await _showMoveToVolumeSheet(chapter);
    }
  }

  /// 新建卷：弹输入框（空 → 自动命名「第X卷」）
  Future<void> _handleCreateVolume() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建卷'),
        content: TextField(
          key: const ValueKey('new-volume-field'),
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
      await repo.createVolume(_msId, title: trimmed);
      final title = trimmed.isNotEmpty
          ? trimmed
          : repo.nextVolumeTitle(await repo.listVolumes(_msId));
      ref.invalidate(volumeListProvider(_msId));
      ref.invalidate(chapterListProvider(_msId));
      if (!mounted) return;
      _snack('已创建《$title》');
    } catch (e) {
      debugPrint('[ChapterTreeDrawer] 新建卷失败: $e');
      if (!mounted) return;
      _snack('新建卷失败，请稍后再试');
    }
  }

  /// 长按卷头 → 卷操作弹层（重命名卷 / 删除卷）
  /// 批次92-2：新增「重命名卷」项（鱼写作长按驱动模型：长按 → 重命名/删除）
  Future<void> _showVolumeActions(Volume volume) async {
    final action = await showYueModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.section, AppSpacing.lg, AppSpacing.section, AppSpacing.sm),
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
    if (action == 'rename' && mounted) {
      await _handleRenameVolume(volume);
    } else if (action == 'delete' && mounted) {
      await _confirmDeleteVolume(volume);
    }
  }

  /// 批次92-2：重命名卷（长按菜单 + 铅笔图标均走这里）
  Future<void> _handleRenameVolume(Volume volume) async {
    final controller = TextEditingController(text: volume.title);
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名卷'),
        content: TextField(
          key: const ValueKey('tree-rename-volume-field'),
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
      ref.invalidate(volumeListProvider(_msId));
      if (!mounted) return;
      _snack(trimmed.isEmpty ? '已重命名为「未命名卷」' : '已重命名为《$trimmed》');
    } catch (e) {
      debugPrint('[ChapterTreeDrawer] 重命名卷失败: $e');
      if (!mounted) return;
      _snack('重命名失败，请稍后再试');
    }
  }

  /// 删除卷二次确认（批次96-4：卷内章节一并软删进回收站，不再散落）
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
      ref.invalidate(volumeListProvider(_msId));
      ref.invalidate(chapterListProvider(_msId));
      if (!mounted) return;
      _snack('已删除《$title》');
    } catch (e) {
      debugPrint('[ChapterTreeDrawer] 删除卷失败: $e');
      if (!mounted) return;
      _snack('删除卷失败，请稍后再试');
    }
  }

  /// 长按章节 → 移动到卷弹层（目标：全部卷 + 未分卷）
  Future<void> _showMoveToVolumeSheet(Chapter chapter) async {
    final volumes = await ref.read(volumeListProvider(_msId).future);
    if (!mounted) return;
    final db = ref.read(appDatabaseProvider);
    final repo = VolumeRepository(db);
    // 「未分卷」用固定标记区分于遮罩关闭（都返回可空 String）
    const unassignedMarker = '__unassigned__';
    final selected = await showYueModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.section, AppSpacing.lg, AppSpacing.section, AppSpacing.sm),
            child: const Text(
              '移动到卷',
              style: TextStyle(
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
    if (!mounted || selected == null) return; // 遮罩关闭：不执行
    final target = selected == unassignedMarker ? null : selected;
    if (chapter.volumeId == target) return;
    try {
      // 批次96-1：统一走「落到目标卷末位」语义（与详情页移卷一致，
      // 避免原 sort_order 保留导致章节插入目标卷任意位置）
      await repo.moveChapterToVolumeEnd(chapter.id, target);
      ref.invalidate(volumeListProvider(_msId));
      ref.invalidate(chapterListProvider(_msId));
    } catch (e) {
      debugPrint('[ChapterTreeDrawer] 移动章节失败: $e');
      if (!mounted) return;
      _snack('移动失败，请稍后再试');
    }
  }
}

/// 卷头：图标 + 卷名 + 章节数 + 折叠箭头（点击折叠/展开，长按卷操作）
/// 批次92-2：行尾新增铅笔小图标 → 直接重命名
class _VolumeHeader extends StatelessWidget {
  final Volume? volume;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onLongPress;
  final VoidCallback? onRename;

  const _VolumeHeader({
    required this.volume,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    this.onLongPress,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    final isUnassigned = volume == null;
    final title = volume == null
        ? '未分卷'
        : (volume!.title.trim().isEmpty ? '未命名卷' : volume!.title.trim());
    return InkWell(
      onTap: onToggle,
      onLongPress: onLongPress,
      child: Container(
        color: AppColors.background,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.smx),
        child: Row(
          children: [
            Icon(
              collapsed ? Icons.chevron_right : Icons.expand_more,
              size: 18,
              color: AppColors.textTertiary,
            ),
            const SizedBox(width: 4),
            Icon(
              isUnassigned
                  ? Icons.notes_outlined
                  : Icons.collections_bookmark_outlined,
              size: 16,
              color: isUnassigned ? AppColors.textTertiary : AppColors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMd,
              ),
            ),
            if (onRename != null)
              InkWell(
                onTap: onRename,
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            Text(
              '$count 章',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 空卷占位提示
class _EmptyVolumeHint extends StatelessWidget {
  const _EmptyVolumeHint();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.xxl + AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.sm),
      child: Text('暂无章节', style: AppTextStyles.caption),
    );
  }
}

/// 单章行：纯文字（标题 + 字数 + 状态标签）；当前章高亮竹青；
/// 修复3：行尾追加铅笔小图标 → 直接重命名
class _ChapterTreeItem extends StatelessWidget {
  final Chapter chapter;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onRename;

  const _ChapterTreeItem({
    super.key,
    required this.chapter,
    required this.isCurrent,
    required this.onTap,
    this.onLongPress,
    required this.onRename,
  });

  /// 千位分隔符格式化（如 3256 → "3,256"）
  String _formatNum(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = _statusConfig[chapter.status];
    final title = chapter.title.trim().isEmpty ? '未命名章节' : chapter.title;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: isCurrent ? AppColors.primarySoft : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.smx),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: isCurrent ? AppColors.primary : AppColors.textInk,
                  fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            // 修复3：铅笔小图标（点击直接重命名，不占过多空间）
            InkWell(
              onTap: onRename,
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.xxs),
                child: Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            if (chapter.wordCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xs),
                child: Text(
                  '${_formatNum(chapter.wordCount)}字',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
            if (status != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xsm, vertical: AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: status.bgColor,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(fontSize: 10, color: status.textColor),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 空态：作品还没有章节时引导新建
class _EmptyChapters extends StatelessWidget {
  const _EmptyChapters();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(
            Icons.menu_book_outlined,
            size: 40,
            color: AppColors.placeholder,
          ),
          SizedBox(height: 12),
          Text('还没有章节', style: AppTextStyles.body),
          SizedBox(height: 4),
          Text(
            '点下面的「新建章节」开个头吧',
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

/// 列表末尾「新建章节」行（批次89-4：新建章节入口挂在章节列表末尾，
/// 与章节同级；新建卷唯一入口 = 头部「＋」图标）
class _NewChapterRow extends StatelessWidget {
  final VoidCallback onTap;

  const _NewChapterRow({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            const Icon(
              Icons.add_circle_outline,
              size: 18,
              color: AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              '新建章节',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
