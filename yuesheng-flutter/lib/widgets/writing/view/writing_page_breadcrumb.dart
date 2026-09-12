// ─────────────────────────────────────────────────────────────
// writing_page 视图层：写作页面包屑（AppBar title）
//
// 由 C92-6a 伪拆分清偿自 writing_page.dart 提取为独立 ConsumerWidget。
// 行为与原实现逐字等价：文案（「卷名 · 章名」/「未命名章节」）、字号、
// 溢出策略、卷名解析（volumeListProvider）均**零变化**。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/manuscript_providers.dart';

/// 批次95-4：写作页面包屑（「卷名 · 章名」；未分卷/加载中/无卷时仅章名）
class WritingPageBreadcrumb extends ConsumerWidget {
  const WritingPageBreadcrumb({
    super.key,
    required this.title,
    required this.volumeId,
    required this.manuscriptId,
    required this.color,
  });

  /// 章节标题候选（优先已加载章节标题，其次路由携带标题）
  final String? title;

  /// 所属卷 ID（null = 未分卷 → 仅显示章名）
  final String? volumeId;

  /// 所属作品 ID（null = 深链未带 → 仅显示章名）
  final String? manuscriptId;

  /// 文本色（暗夜背景时取反；未分卷分支沿用默认色，与原实现一致）
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chapterTitle = (title ?? '').trim();
    final fallback = chapterTitle.isEmpty ? '未命名章节' : chapterTitle;
    final volId = volumeId;
    final msId = manuscriptId;
    if (volId == null || msId == null) {
      // 未分卷/深链未带作品 ID：仅章名，且沿用默认文本色（与原实现一致）
      return _buildLine(fallback, null);
    }
    final volumes = ref.watch(volumeListProvider(msId));
    return volumes.when(
      data: (list) {
        String? volName;
        for (final v in list) {
          if (v.id == volId) {
            volName = v.title;
            break;
          }
        }
        final text = (volName?.trim().isNotEmpty == true)
            ? '$volName · $fallback'
            : fallback;
        return _buildLine(text, color);
      },
      loading: () => _buildLine(fallback, color),
      error: (_, _) => _buildLine(fallback, color),
    );
  }

  /// 面包屑单行文本（`color == null` = 不指定颜色，即原未分卷分支的行为）
  Widget _buildLine(String text, Color? color) {
    return Text(
      text,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
      overflow: TextOverflow.ellipsis,
    );
  }
}
