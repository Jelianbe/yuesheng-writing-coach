// ─────────────────────────────────────────────────────────────
// bookshelf_manuscript_list — 书架作品列表
//
// 从 bookshelf_page.dart 宿主内嵌私有 `_ManuscriptList` 真分解提公而来。
// 批次93-2：接收排序后的列表；章节统计由父级一次性批量加载后传入。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../providers/manuscript_providers.dart';
import 'bookshelf_manuscript_card.dart';

/// 作品列表（批次93-2：接收排序后的列表；章节统计由父级一次性批量加载后传入）
class BookshelfManuscriptList extends StatelessWidget {
  final List<Manuscript> manuscripts;
  final Map<String, ManuscriptStats> statsMap;
  final void Function(Manuscript) onTap;
  final void Function(Manuscript) onLongPress;

  const BookshelfManuscriptList({
    super.key,
    required this.manuscripts,
    required this.statsMap,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      itemCount: manuscripts.length,
      itemBuilder: (context, index) {
        final ms = manuscripts[index];

        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.smx),
          child: BookshelfManuscriptCard(
            manuscript: ms,
            stats: statsMap[ms.id],
            onTap: () => onTap(ms),
            onLongPress: () => onLongPress(ms),
          ),
        );
      },
    );
  }
}
