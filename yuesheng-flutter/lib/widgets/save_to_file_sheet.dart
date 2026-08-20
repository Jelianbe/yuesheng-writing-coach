// ─────────────────────────────────────────────────────────────
// SaveToFileSheet — 保存到文件弹层（缺口清单 C 类）
// 真源：yuesheng-android/src/components/modals/SaveToFileSheet.tsx
//
// 入口：AI 消息气泡「保存到文件」→ 选角色（常规/大纲/素材）+
// 文件名 → createAttachedFile 写入当前主引用作品。
// 文件名预填：指定 > 内容首行截取 40 字 > 「AI 回复 - 日期」。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/reference_repository.dart';
import '../providers/capability_providers.dart';

/// 文件角色（对齐 RN FileRole：general/outline/material）
const List<({String key, String label})> _fileRoles = [
  (key: 'general', label: '常规'),
  (key: 'outline', label: '大纲'),
  (key: 'material', label: '素材'),
];

class SaveToFileSheet extends ConsumerStatefulWidget {
  /// 要保存的内容（AI 回复全文）
  final String content;

  /// 保存目标作品 ID（当前主引用作品）
  final String bookId;

  /// 保存目标作品标题（仅展示，对齐 RN bookTitle）
  final String bookTitle;

  /// 建议角色（对齐 RN suggestedRole，未传默认 general）
  final String? suggestedRole;

  /// 建议文件名（对齐 RN suggestedFileName，优先于内容首行预填）
  final String? suggestedFileName;

  /// 保存成功回调（对齐 RN addFile 后的语义，可由调用方刷新列表）
  final void Function(AttachedFileRow file)? onSaved;

  const SaveToFileSheet({
    super.key,
    required this.content,
    required this.bookId,
    required this.bookTitle,
    this.suggestedRole,
    this.suggestedFileName,
    this.onSaved,
  });

  @override
  ConsumerState<SaveToFileSheet> createState() => _SaveToFileSheetState();
}

class _SaveToFileSheetState extends ConsumerState<SaveToFileSheet> {
  late String _fileRole;
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fileRole = widget.suggestedRole ?? 'general';
    _nameController = TextEditingController(text: _defaultFileName());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  /// 文件名预填：用户指定 > 内容首行截取 40 字 > 日期默认（对齐 RN L52-58）
  String _defaultFileName() {
    if (widget.suggestedFileName != null) return widget.suggestedFileName!;
    final firstLine = widget.content.trim().split(RegExp(r'\r?\n')).first;
    if (firstLine.isNotEmpty) {
      return firstLine.length > 40 ? firstLine.substring(0, 40) : firstLine;
    }
    final now = DateTime.now();
    return 'AI 回复 - ${now.year}/${now.month}/${now.day}';
  }

  Future<void> _handleSave() async {
    if (widget.content.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('内容为空，无法保存')));
      return;
    }
    setState(() => _saving = true);
    try {
      final refRepo = ref.read(referenceCapabilityProvider);
      final file = await refRepo.createAttachedFile(
        bookId: widget.bookId,
        fileName: _nameController.text.trim().isEmpty
            ? '未命名'
            : _nameController.text.trim(),
        fileRole: _fileRole,
        content: widget.content,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      widget.onSaved?.call(file);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
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
            const Text(
              '保存到文件',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '保存到《${widget.bookTitle}》',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
            ),
            const SizedBox(height: 16),

            // 文件角色
            const Text(
              '文件角色',
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

            // 文件名
            const Text(
              '文件名',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
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
            const SizedBox(height: 16),

            // 操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
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
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _handleSave,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _saving ? '保存中...' : '保存',
                      style: const TextStyle(color: AppColors.onPrimary),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 文件角色选择 chip（与 MaterialUploadSheet 同风格）
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
