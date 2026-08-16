// ─────────────────────────────────────────────────────────────
// ChapterRecycleBinPage — 章节回收站（批次94-2）
//
// 依据：墨者/纯纯废纸篓模型——章节「删除」改为软删进回收站，
// 可恢复或永久删除，防止误删丢失正文。
// 入口：作品详情页 ⋮ 更多菜单「回收站」（按作品维度过滤）。
// 操作：
//   恢复      → status='draft' 回章节列表（原文完整保留）
//   永久删除  → 物理删除（二次确认，诊断历史保留，会话冗余缓存清空）
// 每次操作后刷新 chapterStoreProvider（详情页真源，StateNotifier）+ invalidate
// chapterListProvider（FutureProvider，其它消费者）双通道同步。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chapter_providers.dart';
import '../providers/manuscript_providers.dart';

/// 章节回收站页
class ChapterRecycleBinPage extends ConsumerStatefulWidget {
  final String manuscriptId;
  final String manuscriptTitle;

  const ChapterRecycleBinPage({
    super.key,
    required this.manuscriptId,
    required this.manuscriptTitle,
  });

  @override
  ConsumerState<ChapterRecycleBinPage> createState() =>
      _ChapterRecycleBinPageState();
}

class _ChapterRecycleBinPageState extends ConsumerState<ChapterRecycleBinPage> {
  bool _loading = true;
  bool _error = false;
  List<Chapter> _items = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final repo = ChapterRepository(ref.read(appDatabaseProvider));
      final items = await repo.listArchivedChapters(widget.manuscriptId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = false;
      });
    } catch (e) {
      debugPrint('[RecycleBin] 加载失败: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 恢复章节 → 回章节列表
  Future<void> _restore(Chapter chapter) async {
    try {
      final repo = ChapterRepository(ref.read(appDatabaseProvider));
      await repo.restoreChapter(chapter.id);
      // 双通道同步：详情页真源（StateNotifier）+ FutureProvider 消费者
      ref.invalidate(chapterListProvider(widget.manuscriptId));
      await ref
          .read(chapterStoreProvider(widget.manuscriptId).notifier)
          .loadChapters();
      if (!mounted) return;
      setState(() => _items = _items.where((c) => c.id != chapter.id).toList());
      _snack('已恢复《${chapter.title}》');
    } catch (e) {
      debugPrint('[RecycleBin] 恢复失败: $e');
      if (mounted) _snack('恢复失败，请稍后再试');
    }
  }

  /// 永久删除（二次确认）
  Future<void> _purge(Chapter chapter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('永久删除'),
        content: Text(
          '永久删除《${chapter.title.isEmpty ? '未命名章节' : chapter.title}》吗？'
          '此操作不可恢复，诊断历史会保留。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final repo = ChapterRepository(ref.read(appDatabaseProvider));
      await repo.purgeChapter(chapter.id);
      // 双通道同步：详情页真源（StateNotifier）+ FutureProvider 消费者
      ref.invalidate(chapterListProvider(widget.manuscriptId));
      await ref
          .read(chapterStoreProvider(widget.manuscriptId).notifier)
          .loadChapters();
      if (!mounted) return;
      setState(() => _items = _items.where((c) => c.id != chapter.id).toList());
      _snack('已永久删除');
    } catch (e) {
      debugPrint('[RecycleBin] 永久删除失败: $e');
      if (mounted) _snack('删除失败，请稍后再试');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('章节回收站'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        toolbarHeight: 48,
        elevation: 0,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            const Text('加载失败，请稍后重试'),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.delete_sweep_outlined,
              size: 48,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: 12),
            const Text(
              '回收站是空的',
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '删除的章节会先进入这里，可恢复或永久删除',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const Divider(
        height: 1,
        color: AppColors.divider,
      ),
      itemBuilder: (context, index) {
        final c = _items[index];
        final title = c.title.trim().isEmpty ? '未命名章节' : c.title.trim();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${c.wordCount} 字 · ${_relativeTime(c.updatedAt)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.restore,
                  size: 20,
                  color: AppColors.primary,
                ),
                tooltip: '恢复',
                onPressed: () => _restore(c),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_forever_outlined,
                  size: 20,
                  color: AppColors.danger,
                ),
                tooltip: '永久删除',
                onPressed: () => _purge(c),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _relativeTime(int sec) {
    final diff = DateTime.now().toUtc().difference(
      DateTime.fromMillisecondsSinceEpoch(sec * 1000, isUtc: true),
    );
    if (diff.inMinutes < 1) return '刚刚删除';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
    return '${d.month}月${d.day}日';
  }
}
