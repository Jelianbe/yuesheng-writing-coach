// ─────────────────────────────────────────────────────────────
// BookImportSheet — 书架「文本导入」弹层（批次 35）
// 真源：RN WorkImportModal 的选文件分支（书架无会话上下文 → 不建引用）
//
// 流程：选择文件（pickDocument）→ readFileContent → parseDocument
//   → importBookFromFile（事务建稿件+章节，无主引用）→ onImported
// 测试可注入：override workImportServiceProvider 提供 fake（file_picker 不可测）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../providers/work_import_providers.dart';
import '../services/work_import_service.dart';

class BookImportSheet extends ConsumerStatefulWidget {
  /// 导入成功回调（返回 WorkImportResult）
  final void Function(WorkImportResult result)? onImported;

  const BookImportSheet({super.key, this.onImported});

  @override
  ConsumerState<BookImportSheet> createState() => _BookImportSheetState();
}

class _BookImportSheetState extends ConsumerState<BookImportSheet> {
  bool _uploading = false;
  String? _error;

  Future<void> _handlePickFile() async {
    setState(() {
      _error = null;
      _uploading = true;
    });
    try {
      final result = await ref
          .read(workImportServiceProvider)
          .importBookFromFile();
      if (result == null) {
        // 用户取消选择：复位，不报错
        if (mounted) setState(() => _uploading = false);
        return;
      }
      _finish(result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
        _uploading = false;
      });
    }
  }

  void _finish(WorkImportResult result) {
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onImported?.call(result);
  }

  /// release 静默：仅展示可读中文文案，不暴露技术细节
  String _friendlyError(Object e) {
    if (e is StateError) return e.message;
    return '导入失败，请稍后重试';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部把手
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.borderSoft,
                borderRadius: BorderRadius.circular(AppRadius.xs),
              ),
              alignment: Alignment.center,
            ),
            const Text(
              '导入书籍',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '从 TXT 文件导入小说，自动按章节拆分',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 16),

            if (_uploading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              )
            else
              _OptionCard(
                icon: Icons.description_outlined,
                title: '选择文件',
                description: '支持 .txt .md 格式，自动识别章节',
                onTap: _handlePickFile,
              ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.dangerBg,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: AppColors.danger),
                ),
              ),
            ],

            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _uploading ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: const BorderSide(color: AppColors.borderSoft),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
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

/// 导入方式选项卡片（对齐 WorkImportSheet _OptionCard）
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
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
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
