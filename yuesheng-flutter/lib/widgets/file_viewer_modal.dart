// ─────────────────────────────────────────────────────────────
// FileViewerModal — 素材文件内容查看页
// 真源：yuesheng-android/src/components/manuscript/FileViewerModal.tsx
//
// 能力：
//   - 全屏查看素材文件内容（selectable）
//   - 头部：文件名 + 角色徽章 + 大小
//   - 底部操作：更改角色（轮换 general→outline→material）/ 删除文件（确认）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/reference_repository.dart';
import '../providers/capability_providers.dart';

const Map<String, String> _roleLabels = {
  'outline': '大纲',
  'material': '素材',
  'general': '常规',
};

const List<String> _roleCycle = ['outline', 'material', 'general'];

class FileViewerModal extends ConsumerStatefulWidget {
  final String fileId;

  /// 删除成功后回调（FileSection 刷新列表用）
  final VoidCallback? onDeleted;

  const FileViewerModal({super.key, required this.fileId, this.onDeleted});

  @override
  ConsumerState<FileViewerModal> createState() => _FileViewerModalState();
}

class _FileViewerModalState extends ConsumerState<FileViewerModal> {
  AttachedFileRow? _file;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final refRepo = ref.read(referenceCapabilityProvider);
    final file = await refRepo.getAttachedFile(widget.fileId);
    if (mounted) {
      setState(() {
        _file = file;
        _loading = false;
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  // ── 更改角色：轮换 general→outline→material（对齐 RN）──
  Future<void> _handleChangeRole() async {
    final file = _file;
    if (file == null) return;
    final currentIdx = _roleCycle.indexOf(file.fileRole);
    final nextRole = _roleCycle[(currentIdx + 1) % _roleCycle.length];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('更改角色'),
        content: Text('将「${file.fileName}」的角色改为「${_roleLabels[nextRole]}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final refRepo = ref.read(referenceCapabilityProvider);
      await refRepo.updateAttachedFile(file.id, fileRole: nextRole);
      setState(
        () => _file = AttachedFileRow(
          id: file.id,
          bookId: file.bookId,
          fileName: file.fileName,
          fileRole: nextRole,
          mimeType: file.mimeType,
          content: file.content,
          byteSize: file.byteSize,
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('更新失败，请稍后重试')));
      }
    }
  }

  // ── 删除 ──
  Future<void> _handleDelete() async {
    final file = _file;
    if (file == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除「${file.fileName}」吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final refRepo = ref.read(referenceCapabilityProvider);
      await refRepo.deleteAttachedFile(file.id);
      widget.onDeleted?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: '关闭',
        ),
        title: Text(
          _file?.fileName ?? '素材内容',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _file == null
          ? const Center(
              child: Text(
                '文件不存在或已被删除',
                style: TextStyle(color: AppColors.textTertiary),
              ),
            )
          : Column(
              children: [
                // 头部
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.smx,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                        child: Text(
                          _roleLabels[_file!.fileRole] ?? _file!.fileRole,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _formatSize(_file!.byteSize),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 内容
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: SelectableText(
                      _file!.content,
                      style: const TextStyle(
                        fontSize: 15,
                        height: 1.6,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                // 底部操作
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _handleChangeRole,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            side: const BorderSide(color: AppColors.borderSoft),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: const Text(
                            '更改角色',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _handleDelete,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            backgroundColor: AppColors.dangerBg,
                            foregroundColor: AppColors.danger,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: const Text('删除文件'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
