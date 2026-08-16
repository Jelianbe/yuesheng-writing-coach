// ─────────────────────────────────────────────────────────────
// MaterialUploadSheet — 素材文件添加弹层
// 真源：yuesheng-android/src/components/modals/MaterialUploadSheet.tsx
//
// 流程对齐 RN：
//   - 选择文件：pickDocument → readFileContent → 预填文件名 → 表单
//   - 粘贴文本：粘贴 → 首行预填文件名 → 表单
//   - 保存：素材类型（常规/大纲/素材）+ 文件名 → createAttachedFile
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/reference_repository.dart';
import '../providers/app_providers.dart';
import '../services/file_parser.dart';

/// 素材类型（对齐 RN FileRole：general/outline/material）
const List<({String key, String label})> _fileRoles = [
  (key: 'general', label: '常规'),
  (key: 'outline', label: '大纲'),
  (key: 'material', label: '素材'),
];

class MaterialUploadSheet extends ConsumerStatefulWidget {
  final String bookId;
  final String bookTitle;

  /// 保存成功回调（RN onClose 前的 addFile 语义）
  final void Function(AttachedFileRow file)? onSaved;

  const MaterialUploadSheet({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.onSaved,
  });

  @override
  ConsumerState<MaterialUploadSheet> createState() =>
      _MaterialUploadSheetState();
}

class _MaterialUploadSheetState extends ConsumerState<MaterialUploadSheet> {
  late final TextEditingController _nameController;
  bool _uploading = false;
  String _progressText = '';
  String? _error;
  String _fileRole = 'general';
  String? _pendingContent;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // ── 选择文件 ──
  Future<void> _handlePickFile() async {
    setState(() {
      _error = null;
      _uploading = true;
      _progressText = '正在选择文件...';
    });
    try {
      final picked = await pickDocument();
      if (picked == null) {
        // 用户取消选择
        if (mounted) setState(() => _uploading = false);
        return;
      }
      final content = await readFileContent(picked.path);
      if (content.trim().isEmpty) {
        throw StateError('素材内容为空，无法保存');
      }
      // 预填文件名（去扩展名）
      final baseName = picked.name.replaceAll(RegExp(r'\.[^/.]+$'), '');
      if (!mounted) return;
      setState(() {
        _nameController.text = baseName;
        _pendingContent = content;
        _uploading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '文件读取失败';
        _uploading = false;
      });
    }
  }

  // ── 粘贴文本 ──
  Future<void> _showPasteDialog() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴文本'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: '在此输入或粘贴素材内容...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('确认'),
          ),
        ],
      ),
    );

    final trimmed = text?.trim() ?? '';
    if (trimmed.isEmpty) return;
    setState(() {
      // 首行（前 30 字）作为预填文件名
      final firstLine = trimmed.split(RegExp(r'\r?\n')).first;
      _nameController.text = firstLine.length > 30
          ? firstLine.substring(0, 30)
          : firstLine;
      _pendingContent = trimmed;
    });
  }

  // ── 保存 ──
  Future<void> _handleSave() async {
    final content = _pendingContent;
    if (content == null || content.trim().isEmpty) {
      setState(() => _error = '素材内容为空，无法保存');
      return;
    }
    setState(() {
      _error = null;
      _uploading = true;
      _progressText = '正在保存...';
    });
    try {
      final refRepo = ReferenceRepository(ref.read(appDatabaseProvider));
      final file = await refRepo.createAttachedFile(
        bookId: widget.bookId,
        fileName: _nameController.text.trim().isEmpty
            ? '未命名文件'
            : _nameController.text.trim(),
        fileRole: _fileRole,
        content: content,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call(file);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '保存失败，请稍后重试';
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部把手
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.borderSoft,
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.center,
            ),
            Text(
              '添加素材到《${widget.bookTitle}》',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            if (_uploading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _progressText,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // 选项
              _OptionCard(
                icon: Icons.attach_file,
                title: '选择文件',
                description: '从手机选择 .txt .md 素材文件',
                onTap: _handlePickFile,
              ),
              const SizedBox(height: 8),
              _OptionCard(
                icon: Icons.edit_note,
                title: '粘贴文本',
                description: '直接粘贴或输入素材内容',
                onTap: _showPasteDialog,
              ),

              // 表单（有内容后显示）
              if (_pendingContent != null) ...[
                const SizedBox(height: 16),
                const Text(
                  '素材类型：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final role in _fileRoles) ...[
                      _RoleChip(
                        label: role.label,
                        active: _fileRole == role.key,
                        onTap: () => setState(() => _fileRole = role.key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '素材名称：',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (_) {},
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: '请输入文件名',
                    isDense: true,
                    filled: true,
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.dangerBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      side: const BorderSide(color: AppColors.borderSoft),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '取消',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ),
                if (_pendingContent != null && !_uploading) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _handleSave,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '保存',
                        style: TextStyle(color: AppColors.onPrimary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 来源选项卡片（选择文件 / 粘贴文本）
class _OptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _OptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: AppColors.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.disabledText),
          ],
        ),
      ),
    );
  }
}

/// 素材类型选择 chip
class _RoleChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _RoleChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? AppColors.primary : AppColors.borderSoft,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? AppColors.primary : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
