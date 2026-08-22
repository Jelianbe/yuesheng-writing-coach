// ─────────────────────────────────────────────────────────────
// FileSection — 作品详情页素材文件区
// 真源：yuesheng-android/src/components/manuscript/FileSection.tsx
//
// 范围：
//   - 素材文件列表（role 徽章 + 文件名 + 大小）
//   - 「添加素材」按钮 → MaterialUploadSheet
//   - 长按删除（确认对话框）
// 内容查看器（FileViewerModal）留后续批次
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../data/repositories/reference_repository.dart';
import '../providers/capability_providers.dart';
import 'file_viewer_modal.dart';
import 'material_upload_sheet.dart';

const Map<String, String> _roleLabels = {
  'outline': '大纲',
  'material': '素材',
  'general': '常规',
};

class FileSection extends ConsumerStatefulWidget {
  final String manuscriptId;
  final String manuscriptTitle;

  const FileSection({
    super.key,
    required this.manuscriptId,
    required this.manuscriptTitle,
  });

  @override
  ConsumerState<FileSection> createState() => _FileSectionState();
}

class _FileSectionState extends ConsumerState<FileSection> {
  List<AttachedFileRow> _files = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final refRepo = ref.read(referenceCapabilityProvider);
    final files = await refRepo.listAttachedFiles(widget.manuscriptId);
    if (mounted) setState(() => _files = files);
  }

  void _openUpload() {
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => MaterialUploadSheet(
        bookId: widget.manuscriptId,
        bookTitle: widget.manuscriptTitle,
        onSaved: (_) => _load(),
      ),
    );
  }

  Future<void> _delete(AttachedFileRow file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除「${file.fileName}」吗？'),
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
    if (confirmed != true) return;

    try {
      final refRepo = ref.read(referenceCapabilityProvider);
      await refRepo.deleteAttachedFile(file.id);
      _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    }
  }

  void _openViewer(AttachedFileRow file) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => FileViewerModal(fileId: file.id, onDeleted: _load),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '素材文件',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            InkWell(
              onTap: _openUpload,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surfaceWhite,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.attach_file, size: 14, color: AppColors.primary),
                    SizedBox(width: 4),
                    Text(
                      '添加素材',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        if (_files.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.folder_open,
                  size: 36,
                  color: AppColors.disabledText,
                ),
                const SizedBox(height: 8),
                const Text(
                  '还没有素材文件',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '上传大纲、人物表、世界观等参考文档\n在对话中引用后 AI 可以读取这些内容',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppColors.textTertiary,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _openUpload,
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('上传素材'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          for (final file in _files)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => _openViewer(file),
                onLongPress: () => _delete(file),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.borderSoft),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.description_outlined,
                        size: 26,
                        color: AppColors.textTertiary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    file.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primarySoft,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.sm,
                                    ),
                                  ),
                                  child: Text(
                                    _roleLabels[file.fileRole] ?? file.fileRole,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatSize(file.byteSize),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 批次75：删除按钮可见化——行尾提供删除入口（长按仍可用）
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.danger,
                        ),
                        tooltip: '删除文件',
                        onPressed: () => _delete(file),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.disabledText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}
