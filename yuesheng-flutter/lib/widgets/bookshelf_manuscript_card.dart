// ─────────────────────────────────────────────────────────────
// bookshelf_manuscript_card — 书架作品卡片
//
// 从 bookshelf_page.dart 宿主内嵌私有 `_ManuscriptCard` 真分解提公而来。
// 原 `build` 129 行（R-019 债务）在此**真拆**为卡片骨架 + 封面 + 信息列 +
// 信息行四个 ≤50 行的组装方法，不是挪文件。
//
// 批次93-1 信息加厚：首字封面 + 章节数 + 总字数 + 相对时间 + 简介预览。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../providers/manuscript_providers.dart';

/// 作品卡片（批次93-1 信息加厚：首字封面 + 章节数 + 总字数 + 相对时间 + 简介预览）
class BookshelfManuscriptCard extends StatelessWidget {
  final Manuscript manuscript;
  final ManuscriptStats? stats;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const BookshelfManuscriptCard({
    super.key,
    required this.manuscript,
    this.stats,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // 批次93-1（B27）：章节统计由父级批量加载后传入，避免逐卡片 N+1 查询
    final chapterCount = stats?.chapterCount ?? 0;
    final totalWords = stats?.totalWords ?? 0;
    final title = manuscript.title.isEmpty ? '未命名作品' : manuscript.title;
    // 首字封面（取书名首汉字；空标题用「未」）
    final firstChar = manuscript.title.isEmpty ? '未' : manuscript.title[0];
    final genre = manuscript.genre.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: _cardBody(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cover(firstChar, genre),
                const SizedBox(width: 12),
                Expanded(
                  child: _infoColumn(title, genre, chapterCount, totalWords),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 卡片外壳：圆角容器 + 左侧 4dp 竹青色条（月色竹青主色锚点）+ 内边距
  Widget _cardBody(Widget child) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧 4dp 竹青色条（月色竹青主色锚点）
            Container(width: 4, color: AppColors.primary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 首字封面（体裁色 + 圆角 + 书名首汉字，48px）
  Widget _cover(String firstChar, String genre) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: _genreColor(genre),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: Text(
        firstChar,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.onPrimary,
        ),
      ),
    );
  }

  /// 标题 + 简介预览 + 信息行
  Widget _infoColumn(
    String title,
    String genre,
    int chapterCount,
    int totalWords,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        if (manuscript.description.isNotEmpty) ...[
          const SizedBox(height: 4),
          // 简介预览两行
          Text(
            manuscript.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.noteCaption.copyWith(height: 1.4),
          ),
        ],
        const SizedBox(height: 6),
        _metaRow(genre, chapterCount, totalWords),
      ],
    );
  }

  /// 信息行：体裁 · 章节数 · 总字数 + 相对时间
  Widget _metaRow(String genre, int chapterCount, int totalWords) {
    return Row(
      children: [
        if (genre.isNotEmpty) ...[
          Text(
            genre,
            style: const TextStyle(fontSize: 11, color: AppColors.textDeep),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          '$chapterCount 章 · ${_formatWords(totalWords)}',
          style: AppTextStyles.microCaption,
        ),
        const Spacer(),
        Text(
          _relativeTime(manuscript.updatedAt),
          style: AppTextStyles.microCaption,
        ),
      ],
    );
  }
}

/// 字数格式化（万字 / 千字 / 字）
String _formatWords(int n) {
  if (n >= 10000) {
    return '${(n / 10000).toStringAsFixed(1)}万字';
  } else if (n >= 1000) {
    return '${(n / 1000).toStringAsFixed(1)}千字';
  }
  return '$n字';
}

/// 批次93-1：体裁 → 首字封面底色（全部收敛到月色竹青既有令牌）
Color _genreColor(String genre) {
  switch (genre.trim()) {
    case '奇幻':
      return AppColors.primary;
    case '都市':
      return AppColors.textDeep;
    case '言情':
      return AppColors.warning;
    case '科幻':
      return AppColors.success;
    case '武侠':
      return AppColors.l2Text;
    case '悬疑':
      return AppColors.l3Text;
    case '历史':
      return AppColors.primaryDeep;
    default:
      return AppColors.textTertiary;
  }
}

/// 批次93-1：相对时间（刚刚/N分钟前/N小时前/N天前/N周前/MM/dd）
String _relativeTime(int ts) {
  final now = DateTime.now();
  final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
  if (diff.inDays < 1) return '${diff.inHours}小时前';
  if (diff.inDays < 7) return '${diff.inDays}天前';
  if (diff.inDays < 30) return '${diff.inDays ~/ 7}周前';
  return '${dt.month}/${dt.day}';
}
