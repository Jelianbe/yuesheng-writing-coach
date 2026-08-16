// ─────────────────────────────────────────────────────────────
// DiagnosisPickerSheet — 诊断章节选择弹层（缺口清单第 7 项）
// 真源：yuesheng-android/src/components/diagnosis/DiagnosisPickerModal.tsx
//
// 成长页「写作诊断」入口：作品列表 → 展开章节 → 点击选章。
// 章节内容 <100 字时提示先编辑；空库引导去书架创建。
// 选择后由调用方跳转对话页触发自动诊断（startDiagnosis 语义）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../config/shared_constants.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/manuscript_repository.dart';
import '../providers/app_providers.dart';
import '../router/app_router.dart';

/// 章节选择回调（manuscriptId + 章节）
typedef DiagnosisChapterCallback =
    void Function(String manuscriptId, Chapter chapter);

class DiagnosisPickerSheet extends ConsumerStatefulWidget {
  final DiagnosisChapterCallback onSelect;

  const DiagnosisPickerSheet({super.key, required this.onSelect});

  @override
  ConsumerState<DiagnosisPickerSheet> createState() =>
      _DiagnosisPickerSheetState();
}

class _DiagnosisPickerSheetState extends ConsumerState<DiagnosisPickerSheet> {
  List<Manuscript> _manuscripts = [];
  String? _expandedMsId;
  Map<String, List<Chapter>> _chaptersMap = {};
  Map<String, int> _visibleCountMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final list = await ManuscriptRepository(db).listManuscripts();
      if (!mounted) return;
      setState(() {
        _manuscripts = list;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleExpand(String manuscriptId) async {
    if (_expandedMsId == manuscriptId) {
      setState(() => _expandedMsId = null);
      return;
    }
    setState(() => _expandedMsId = manuscriptId);
    if (!_chaptersMap.containsKey(manuscriptId)) {
      final db = ref.read(appDatabaseProvider);
      final chapters = await ChapterRepository(db).listChapters(manuscriptId);
      if (!mounted) return;
      setState(() {
        _chaptersMap = {..._chaptersMap, manuscriptId: chapters};
        _visibleCountMap = {
          ..._visibleCountMap,
          manuscriptId: UILimits.chapterListInitial,
        };
      });
    }
  }

  void _loadMore(String manuscriptId) {
    setState(() {
      _visibleCountMap = {
        ..._visibleCountMap,
        manuscriptId:
            (_visibleCountMap[manuscriptId] ?? UILimits.chapterListInitial) +
            UILimits.chapterListLoadMore,
      };
    });
  }

  void _handleSelect(String manuscriptId, Chapter chapter) {
    Navigator.of(context).pop();
    // 对齐 RN：内容过短先提示，不发诊断
    if (chapter.content.trim().length < UILimits.diagnosisWordThreshold) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('章节内容少于 100 字，请先编辑章节')));
      return;
    }
    widget.onSelect(manuscriptId, chapter);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部把手
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              '选择要诊断的章节',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '选择一个章节进行写作分析',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: _loading
                  ? const SizedBox(
                      height: 120,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : _manuscripts.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
            ),
            const SizedBox(height: 8),
            // 取消按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '取消',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 空库：引导去书架创建
  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '还没有作品',
            style: TextStyle(fontSize: 15, color: AppColors.textTertiary),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () {
              Navigator.of(context).pop();
              context.go(AppRoutes.bookshelf);
            },
            child: const Text(
              '去书架创建 →',
              style: TextStyle(fontSize: 14, color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  /// 作品 → 章节列表（列表区高度对齐 RN PICKER_LAYOUT.listMaxHeight=400）
  Widget _buildList() {
    return SizedBox(
      height: 400,
      child: ListView.builder(
        itemCount: _manuscripts.length,
        itemBuilder: (context, index) {
          final m = _manuscripts[index];
          final expanded = _expandedMsId == m.id;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: () => _toggleExpand(m.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          m.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        expanded ? '▼' : '▶',
                        style: TextStyle(
                          fontSize: 12,
                          color: expanded
                              ? AppColors.primary
                              : AppColors.disabledText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (expanded) _buildChapters(m.id),
              if (index < _manuscripts.length - 1)
                const Divider(height: 1, color: AppColors.borderSoft),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChapters(String manuscriptId) {
    final chapters = _chaptersMap[manuscriptId] ?? const <Chapter>[];
    if (chapters.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          '暂无章节',
          style: TextStyle(fontSize: 13, color: AppColors.disabledText),
        ),
      );
    }
    final visibleCount =
        (chapters.length <
            (_visibleCountMap[manuscriptId] ?? UILimits.chapterListInitial))
        ? chapters.length
        : (_visibleCountMap[manuscriptId] ?? UILimits.chapterListInitial);
    final visibleChapters = chapters.take(visibleCount).toList();
    final hasMore = visibleCount < chapters.length;

    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final ch in visibleChapters) ...[
            InkWell(
              onTap: () => _handleSelect(manuscriptId, ch),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ch.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${ch.wordCount} 字',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.disabledText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),
          ],
          if (hasMore)
            InkWell(
              onTap: () => _loadMore(manuscriptId),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  '加载更多（${chapters.length - visibleCount} 章未显示）',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
