// ─────────────────────────────────────────────────────────────
// WorkImportSheet — 作品导入弹层（+ 按钮）
// 真源：yuesheng-android/src/components/reference/WorkImportModal.tsx
//
// 流程对齐 RN handlePickFile → handleCreateWork：
//   - 选择文件：pickDocument → readFileContent → parseDocument → 事务入库
//   - 粘贴文本：parseDocument → 事务入库
// 入库复用 WorkImportService（批次2），事务内建稿件+章节+主引用
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../providers/work_import_providers.dart';
import '../services/work_import_service.dart';

class WorkImportSheet extends ConsumerStatefulWidget {
  final String sessionId;

  /// 导入成功回调（RN onUploadComplete 对齐）
  final void Function(WorkImportResult result)? onUploadComplete;

  const WorkImportSheet({
    super.key,
    required this.sessionId,
    this.onUploadComplete,
  });

  @override
  ConsumerState<WorkImportSheet> createState() => _WorkImportSheetState();
}

class _WorkImportSheetState extends ConsumerState<WorkImportSheet> {
  bool _uploading = false;
  String _progressText = '';
  String? _error;

  // ── 选择文件 ──
  Future<void> _handlePickFile() async {
    setState(() {
      _error = null;
      _uploading = true;
      _progressText = '正在选择文件...';
    });
    try {
      final result = await ref
          .read(workImportServiceProvider)
          .importFromFile(sessionId: widget.sessionId);
      if (result == null) {
        // 用户取消选择：复位，不报错
        if (mounted) setState(() => _uploading = false);
        return;
      }
      _finish(result);
    } catch (e) {
      _handleError(e);
    }
  }

  // ── 粘贴文本确认 ──
  Future<void> _confirmPaste(String content) async {
    setState(() {
      _error = null;
      _uploading = true;
      _progressText = '正在解析章节...';
    });
    try {
      final result = await ref
          .read(workImportServiceProvider)
          .importFromText(sessionId: widget.sessionId, text: content);
      _finish(result);
    } catch (e) {
      _handleError(e);
    }
  }

  void _finish(WorkImportResult result) {
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onUploadComplete?.call(result);
  }

  void _handleError(Object e) {
    if (!mounted) return;
    setState(() {
      _error = _friendlyError(e);
      _uploading = false;
    });
  }

  /// release 静默：仅展示可读中文文案，不暴露技术细节
  String _friendlyError(Object e) {
    if (e is StateError) return e.message;
    return '导入失败，请稍后重试';
  }

  Future<void> _showPasteDialog() async {
    final controller = TextEditingController();
    final content = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴文本'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 8,
          minLines: 5,
          decoration: const InputDecoration(
            hintText: '在此输入或粘贴小说文本...',
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
            child: const Text('确认导入'),
          ),
        ],
      ),
    );

    final trimmed = content?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await _confirmPaste(trimmed);
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
              '导入作品',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '从文件导入小说，自动按章节拆分',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
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
              _OptionCard(
                icon: Icons.description_outlined,
                title: '选择文件',
                description: '支持 .txt .md 格式，自动识别章节',
                onTap: _handlePickFile,
              ),
              const SizedBox(height: 8),
              _OptionCard(
                icon: Icons.content_paste,
                title: '粘贴文本',
                description: '直接粘贴小说内容',
                onTap: _showPasteDialog,
              ),
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
            OutlinedButton(
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
          ],
        ),
      ),
    );
  }
}

/// 导入方式选项卡片（对齐 RN optionButton）
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
