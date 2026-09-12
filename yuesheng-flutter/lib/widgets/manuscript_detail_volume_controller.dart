// ─────────────────────────────────────────────────────────────
// manuscript_detail_volume_controller — 作品详情页卷动作控制器
//
// 从 manuscript_detail_volume.dart（原 part/extension）真分解而来：
//   createVolume / renameVolume / showVolumeActions / confirmDeleteVolume
//
// 依赖经 [ManuscriptDetailHost] 显式注入；导出委托 [ManuscriptDetailExporter]。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/volume_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chapter_providers.dart';
import '../providers/manuscript_providers.dart';
import 'manuscript_detail_exporter.dart';
import 'manuscript_detail_host.dart';
import 'yue_sheet.dart';

/// 作品详情页卷动作
class ManuscriptDetailVolumeController {
  final ManuscriptDetailHost host;
  final ManuscriptDetailExporter exporter;

  ManuscriptDetailVolumeController(this.host, this.exporter);

  /// 修复4：详情页新建卷（对齐章节树抽屉逻辑，留空自动"第一卷/第二卷…"）
  Future<void> createVolume() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: host.context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建卷'),
        content: TextField(
          key: const ValueKey('detail-new-volume-field'),
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
      final db = host.ref.read(appDatabaseProvider);
      final repo = VolumeRepository(db);
      // CR-21：先算自动标题再建卷——createVolume 后列表已含新卷，
      // nextVolumeTitle 按 MAX(sort_order)+1 推导会大一号。
      final title = trimmed.isNotEmpty
          ? trimmed
          : repo.nextVolumeTitle(await repo.listVolumes(host.manuscriptId));
      await repo.createVolume(host.manuscriptId, title: title);
      host.ref.invalidate(volumeListProvider(host.manuscriptId));
      if (!host.mounted) return;
      host.showSnack('已创建《$title》');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 新建卷失败: $e');
      if (!host.mounted) return;
      host.showSnack('新建卷失败，请稍后再试');
    }
  }

  /// 批次92-2：卷重命名（详情页卷头铅笔 + 长按菜单）
  Future<void> renameVolume(Volume volume) async {
    final controller = TextEditingController(text: volume.title);
    final input = await showDialog<String>(
      context: host.context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名卷'),
        content: TextField(
          key: const ValueKey('detail-rename-volume-field'),
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
      final repo = VolumeRepository(host.ref.read(appDatabaseProvider));
      await repo.updateVolumeTitle(volume.id, trimmed);
      host.ref.invalidate(volumeListProvider(host.manuscriptId));
      if (!host.mounted) return;
      host.showSnack(trimmed.isEmpty ? '已重命名为「未命名卷」' : '已重命名为《$trimmed》');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 重命名卷失败: $e');
      if (!host.mounted) return;
      host.showSnack('重命名失败，请稍后再试');
    }
  }

  /// 批次92-2：长按卷头 → 卷操作弹层（重命名 / 删除）
  Future<void> showVolumeActions(Volume volume) async {
    final action = await showYueModalBottomSheet<String>(
      context: host.context,
      builder: (_) => _VolumeActionsSheet(volume: volume),
    );
    if (!host.mounted || action == null) return;
    if (action == 'rename') {
      await renameVolume(volume);
    } else if (action == 'delete') {
      await confirmDeleteVolume(volume);
    } else if (action == 'export') {
      await exporter.exportVolume(volume);
    }
  }

  /// 批次92-2：删除卷二次确认（批次96-4：卷内章节一并软删进回收站，不再散落）
  Future<void> confirmDeleteVolume(Volume volume) async {
    final title = volume.title.trim().isEmpty ? '未命名卷' : volume.title.trim();
    final confirmed = await showDialog<bool>(
      context: host.context,
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
    if (confirmed != true || !host.mounted) return;
    try {
      final repo = VolumeRepository(host.ref.read(appDatabaseProvider));
      await repo.deleteVolume(volume.id);
      // 批次96-4：卷内章节已一并软删——详情页真源 + FutureProvider 双通道刷新
      await host.ref
          .read(chapterStoreProvider(host.manuscriptId).notifier)
          .loadChapters();
      host.ref.invalidate(volumeListProvider(host.manuscriptId));
      if (!host.mounted) return;
      host.showSnack('已删除《$title》');
    } catch (e) {
      debugPrint('[ManuscriptDetail] 删除卷失败: $e');
      if (!host.mounted) return;
      host.showSnack('删除卷失败，请稍后再试');
    }
  }
}

/// 卷操作弹层（导出本卷 / 重命名卷 / 删除卷）
class _VolumeActionsSheet extends StatelessWidget {
  final Volume volume;

  const _VolumeActionsSheet({required this.volume});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          const Divider(height: 1),
          ..._buildActionTiles(context),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 弹层标题（卷名 / 未命名卷）
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.lg,
        AppSpacing.section,
        AppSpacing.sm,
      ),
      child: Text(
        volume.title.trim().isEmpty ? '未命名卷' : volume.title.trim(),
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  /// 操作列表：导出本卷 / 重命名卷 / 删除卷
  List<Widget> _buildActionTiles(BuildContext context) {
    return [
      ListTile(
        leading: const Icon(
          Icons.ios_share_outlined,
          size: 18,
          color: AppColors.primary,
        ),
        title: const Text('导出本卷'),
        onTap: () => Navigator.pop(context, 'export'),
      ),
      ListTile(
        leading: const Icon(
          Icons.edit_outlined,
          size: 18,
          color: AppColors.primary,
        ),
        title: const Text('重命名卷'),
        onTap: () => Navigator.pop(context, 'rename'),
      ),
      ListTile(
        leading: const Icon(
          Icons.delete_outline,
          size: 18,
          color: AppColors.danger,
        ),
        title: const Text('删除卷', style: TextStyle(color: AppColors.danger)),
        subtitle: const Text('卷内章节将一并删除', style: TextStyle(fontSize: 12)),
        onTap: () => Navigator.pop(context, 'delete'),
      ),
    ];
  }
}
