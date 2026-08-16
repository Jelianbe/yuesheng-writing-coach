// ─────────────────────────────────────────────────────────────
// AdoptSuggestionSheet — 采纳建议弹窗
//
// 三种动作：
//   1. 局部合并（默认）：将建议追加到章节末尾，原文保留不动。
//      旧内容备份到 previous_content，可通过「撤销上次采纳」恢复。
//   2. 替换全部：用建议完全替换章节原有内容。需二次确认。
//      原文同样备份到 previous_content。
//   3. 撤销上次采纳：仅在 previous_content 存在时显示。
//      将 previous_content 恢复为 content，并清空 previous_content。
//
// 所有写入操作均走 ChapterRepository：
//   - adoptContentToChapter（备份 + 替换）
//   - undoLastAdoption（恢复 + 清空备份）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../data/repositories/chapter_repository.dart';
import '../providers/app_providers.dart';

/// 二次确认对话框文案（与项目铁律一致，勿改）
const String _kReplaceAllConfirmText = '此操作将用AI改写完全替换章节原有内容，原文可通过撤销上次采纳恢复';

class AdoptSuggestionSheet extends ConsumerStatefulWidget {
  final String chapterId;
  final String suggestion;
  final VoidCallback onAdopted;

  const AdoptSuggestionSheet({
    super.key,
    required this.chapterId,
    required this.suggestion,
    required this.onAdopted,
  });

  /// 弹出采纳建议弹窗
  static void show(
    BuildContext context, {
    required String chapterId,
    required String suggestion,
    required VoidCallback onAdopted,
  }) {
    showYueModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AdoptSuggestionSheet(
        chapterId: chapterId,
        suggestion: suggestion,
        onAdopted: onAdopted,
      ),
    );
  }

  @override
  ConsumerState<AdoptSuggestionSheet> createState() =>
      _AdoptSuggestionSheetState();
}

class _AdoptSuggestionSheetState extends ConsumerState<AdoptSuggestionSheet> {
  /// 是否存在 previous_content（控制「撤销上次采纳」按钮显隐）
  bool _hasPreviousContent = false;

  /// P2-4：是否已完成 previous_content 查询（未完成时先预留高度避免布局跳动）
  bool _hasPreviousLoaded = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadHasPreviousContent();
  }

  Future<void> _loadHasPreviousContent() async {
    final repo = ChapterRepository(ref.read(appDatabaseProvider));
    final ch = await repo.getChapter(widget.chapterId);
    if (mounted) {
      setState(() {
        _hasPreviousContent = ch?.previousContent != null;
        _hasPreviousLoaded = true;
      });
    }
  }

  ChapterRepository _repo() => ChapterRepository(ref.read(appDatabaseProvider));

  /// 局部合并：追加建议到章节末尾，原文保留。
  Future<void> _adoptLocalMerge() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final repo = _repo();
      final ch = await repo.getChapter(widget.chapterId);
      if (ch == null) return;
      final newContent = ch.content.isEmpty
          ? widget.suggestion
          : '${ch.content}\n\n${widget.suggestion}';
      await repo.adoptContentToChapter(widget.chapterId, newContent);
      if (mounted) {
        widget.onAdopted();
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 替换全部：弹出二次确认 → 确认后用建议完全替换章节内容。
  Future<void> _adoptReplaceAll() async {
    if (_isProcessing) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认替换全部'),
        content: const Text(_kReplaceAllConfirmText),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认替换'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isProcessing = true);
    try {
      final repo = _repo();
      await repo.adoptContentToChapter(widget.chapterId, widget.suggestion);
      if (mounted) {
        widget.onAdopted();
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 撤销上次采纳：恢复 previous_content 为 content，清空 previous_content。
  Future<void> _undoLastAdoption() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await _repo().undoLastAdoption(widget.chapterId);
      if (mounted) {
        widget.onAdopted();
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部拖拽指示条
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // 标题
            const Text(
              '采纳建议',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textInk,
              ),
            ),
            const SizedBox(height: 12),
            // 建议内容预览
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                child: Text(
                  widget.suggestion,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: AppColors.textInk,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // 局部合并（默认）
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isProcessing ? null : _adoptLocalMerge,
                icon: const Icon(Icons.merge_type, size: 18),
                label: const Text('局部合并'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 替换全部（需二次确认）
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isProcessing ? null : _adoptReplaceAll,
                icon: const Icon(Icons.find_replace, size: 18),
                label: const Text('替换全部'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            // 撤销上次采纳（仅 previous_content 存在时显示）
            // P2-4：查询未完成时预留固定高度，避免按钮延迟出现导致布局跳动
            if (!_hasPreviousLoaded)
              const SizedBox(height: 44) // 预留高度≈按钮+间距
            else if (_hasPreviousContent) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: _isProcessing ? null : _undoLastAdoption,
                  icon: const Icon(Icons.undo, size: 18),
                  label: const Text('撤销上次采纳'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
