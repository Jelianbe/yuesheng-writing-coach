// ─────────────────────────────────────────────────────────────
// writing_page 视图层：写作页面包屑（AppBar title）
//
// 由 C92-6a 伪拆分清偿自 writing_page.dart 提取为独立 ConsumerWidget。
// 行为与原实现逐字等价：文案（「卷名 · 章名」/「未命名章节」）、字号、
// 溢出策略、卷名解析（volumeListProvider）均**零变化**。
//
// N4-1：提级为「章节切换」一级入口 —— 传入 [onTap] 时整行成为可点区。
// **缺省（onTap == null）行为与改造前逐字等价**（仍是纯 Text，无 InkWell），
// 故既有调用方与被钉住的测试零破坏。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_theme.dart';
import '../../../providers/manuscript_providers.dart';

/// 批次95-4：写作页面包屑（「卷名 · 章名」；未分卷/加载中/无卷时仅章名）
/// N4-1：可选 [onTap] → 可点区（打开既有章节树抽屉 = 章节切换一级入口）
class WritingPageBreadcrumb extends ConsumerWidget {
  const WritingPageBreadcrumb({
    super.key,
    required this.title,
    required this.volumeId,
    required this.manuscriptId,
    required this.color,
    this.onTap,
  });

  /// N4-1：可点区 Key（测试定位命中区；`onTap == null` 时**不挂**此 Key）
  static const Key tapTargetKey = Key('writing-breadcrumb-tap-target');

  /// 章节标题候选（优先已加载章节标题，其次路由携带标题）
  final String? title;

  /// 所属卷 ID（null = 未分卷 → 仅显示章名）
  final String? volumeId;

  /// 所属作品 ID（null = 深链未带 → 仅显示章名）
  final String? manuscriptId;

  /// 文本色（暗夜背景时取反；未分卷分支沿用默认色，与原实现一致）
  final Color color;

  /// N4-1：点击回调（null = 不可点 ⇒ 与原实现逐字等价）
  final VoidCallback? onTap;

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
  ///
  /// N4-1：`onTap != null` 时外包一层命中区 ≥48dp 的 [InkWell]。
  /// 与 `leading` 返回键**天然不重叠**：AppBar `title` 由 NavigationToolbar
  /// 布局在 `leading` 之后（`kLeadingWidth` = 56 > 48），本层再留 4dp 内边距成缝。
  Widget _buildLine(String text, Color? color) {
    final label = Text(
      text,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color),
      overflow: TextOverflow.ellipsis,
    );
    final onTap = this.onTap;
    if (onTap == null) return label;
    return InkWell(
      key: tapTargetKey,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        // 命中区 ≥48dp：AppBar `toolbarHeight` = 48，等高即满高，不会撑破
        constraints: const BoxConstraints(minHeight: 48),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: label,
      ),
    );
  }
}
