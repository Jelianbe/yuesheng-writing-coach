// ─────────────────────────────────────────────────────────────
// manuscript_detail_move_to_volume_sheet — 移动到卷弹层
//
// 从 manuscript_detail_chapter.dart（原 part/extension _showMoveToVolumeSheet）
// 真分解而来（R-019：根除 74 行超限方法 + part 形态）。
//   - MoveToVolumeSheet 移动到卷弹层（目标：全部卷 + 未分卷）
//
// 无状态纯渲染：选择经 Navigator.pop 返回卷 id（或未分卷哨兵值）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../config/app_palette.dart';

/// 移动到卷弹层（目标：全部卷 + 未分卷）
class MoveToVolumeSheet extends StatelessWidget {
  final Chapter chapter;
  final List<Volume> volumes;

  const MoveToVolumeSheet({
    super.key,
    required this.chapter,
    required this.volumes,
  });

  /// 选择「未分卷」的哨兵值
  static const String unassignedMarker = '__unassigned__';

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(context),
        const Divider(height: 1),
        ..._buildVolumeTiles(context),
        _buildUnassignedTile(context),
        const SizedBox(height: 8),
      ],
    );
  }

  /// 弹层标题（章节名 + 「到」）
  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.section,
        AppSpacing.lg,
        AppSpacing.section,
        AppSpacing.sm,
      ),
      child: Text(
        '移动《${chapter.title.isEmpty ? '未命名章节' : chapter.title}》到',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: context.palette.textPrimary,
        ),
      ),
    );
  }

  /// 可选目标卷列表（当前所在卷打勾）
  List<Widget> _buildVolumeTiles(BuildContext context) {
    return [
      for (final v in volumes)
        ListTile(
          leading: Icon(
            Icons.collections_bookmark_outlined,
            size: 18,
            color: context.palette.primary,
          ),
          title: Text(v.title.trim().isEmpty ? '未命名卷' : v.title.trim()),
          trailing: chapter.volumeId == v.id
              ? Icon(Icons.check, size: 18, color: context.palette.primary)
              : null,
          onTap: () => Navigator.pop(context, v.id),
        ),
    ];
  }

  /// 「未分卷」目标（当前未分卷时打勾）
  Widget _buildUnassignedTile(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.notes_outlined,
        size: 18,
        color: context.palette.textTertiary,
      ),
      title: const Text('未分卷'),
      trailing: chapter.volumeId == null
          ? Icon(Icons.check, size: 18, color: context.palette.primary)
          : null,
      onTap: () => Navigator.pop(context, unassignedMarker),
    );
  }
}
