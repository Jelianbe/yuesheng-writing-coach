// ─────────────────────────────────────────────────────────────
// manuscript_detail_chapter_card — 作品详情页章节卡片
//
// 从 manuscript_detail_page.dart 真分解而来（R-019：根除宿主塞满私有 Widget）。
//   - ChapterStatusConfig   章节状态 → 中文标签 + 矿物色配色
//   - chapterStatusConfig   状态配置表（draft/revising/complete）
//       ★ V-5 起为**全库单一真源**：章节树抽屉（chapter_tree_drawer.dart）
//       原自持逐字相同的私有表且兜底分叉，已改引用本表；表外状态统一
//       「不渲染徽标」（不编造状态）。回归网：test/widgets/chapter_status_badge_test.dart
//   - ChapterCard           章节卡片（修复1：纯文字无序号色块；修复3：行尾编辑图标）
//
// 无状态纯渲染，仅经构造注入数据与回调。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../data/database/database.dart';
import '../../config/app_palette.dart';

/// 章节状态 → 中文标签 + 矿物色配色
class ChapterStatusConfig {
  final String label;
  final Color bgColor;
  final Color textColor;
  const ChapterStatusConfig(this.label, this.bgColor, this.textColor);
}

/// 章节状态配置表
/// ⚠️ P1-6 改造：const Map 装不进运行期 palette ⇒ 改 **palette 驱动函数**（恰 3 键、
/// 表外状态返回 null——V-5 裁定「不编造」语义不变；`AppPalette.light` 恒等 AppColors，
/// V-5 值域锁测试传 light 逐项对账）。
ChapterStatusConfig? chapterStatusConfigFor(AppPalette p, String status) {
  switch (status) {
    case 'draft':
      return ChapterStatusConfig('草稿', p.border, p.textDeep);
    case 'revising':
      return ChapterStatusConfig('修改中', p.warningBg, p.warning);
    case 'complete':
      return ChapterStatusConfig('完成', p.l1, p.primary);
  }
  return null;
}

/// 章节卡片（修复1：移除序号色块，改为纯文字；修复3：行尾增加编辑图标用于重命名）
class ChapterCard extends StatelessWidget {
  final Chapter chapter;
  final int index;
  final VoidCallback onTap;

  /// 长按 → 操作菜单（删除 / 重命名）
  final VoidCallback onLongPress;

  /// 行尾可见删除入口（对齐 file_section 批次75，复用长按删除流程）
  final VoidCallback onDelete;

  /// 修复3：行尾铅笔图标 → 直接重命名
  final VoidCallback onRename;

  const ChapterCard({
    super.key,
    required this.chapter,
    required this.index,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
    required this.onRename,
  });

  String _formatWords(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万字';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}千字';
    }
    return '$count字';
  }

  @override
  Widget build(BuildContext context) {
    // V-5：兜底与章节树抽屉统一 —— **表外状态不渲染徽标、不编造状态**
    //（原 `?? chapterStatusConfig['draft']!` 会把未知状态显示成「草稿」）。
    // 实测 chapters.status 带 CHECK 约束（tables.dart，v24 重建即带），
    // 表外值 DB 层进不来 ⇒ 本次统一不动任何线上呈现，消的是两表分叉。
    final statusCfg = chapterStatusConfigFor(context.palette, chapter.status);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: context.palette.surfaceWhite,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: context.palette.divider),
          ),
          child: Row(
            children: [
              // 章节信息（修复1：移除左侧序号色块，纯文字展示）
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTitleRow(context, statusCfg),
                    const SizedBox(height: 6),
                    _buildMetaRow(context),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _buildTrailingActions(context),
            ],
          ),
        ),
      ),
    );
  }

  /// 标题行：章节名 + 状态标签（R-019 清偿拆出）。
  /// V-5：`statusCfg == null`（表外状态）时不渲染徽标 —— 与章节树抽屉
  /// 的 `if (status != null)` 同一判据、同一张表（单一真源）。
  Widget _buildTitleRow(BuildContext context, ChapterStatusConfig? statusCfg) {
    return Row(
      children: [
        Expanded(
          child: Text(
            chapter.title.isEmpty ? '未命名章节' : chapter.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.palette.textPrimary,
            ),
          ),
        ),
        // 状态标签
        if (statusCfg != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xxs,
            ),
            decoration: BoxDecoration(
              color: statusCfg.bgColor,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              statusCfg.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: statusCfg.textColor,
              ),
            ),
          ),
      ],
    );
  }

  /// 元信息行：字数 + 已诊断（R-019 清偿拆出）。
  Widget _buildMetaRow(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.sticky_note_2_outlined,
          size: 12,
          color: context.palette.textTertiary,
        ),
        const SizedBox(width: 4),
        Text(
          _formatWords(chapter.wordCount),
          style: TextStyle(fontSize: 12, color: context.palette.textTertiary),
        ),
        if (chapter.lastDiagnosedAt != null) ...[
          const SizedBox(width: 12),
          Icon(
            Icons.check_circle_outline,
            size: 12,
            color: context.palette.textDeep,
          ),
          const SizedBox(width: 4),
          Text(
            '已诊断',
            style: TextStyle(fontSize: 12, color: context.palette.textDeep),
          ),
        ],
      ],
    );
  }

  /// 行尾操作：重命名 + 删除 + 跳转箭头（R-019 清偿拆出）。
  Widget _buildTrailingActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 修复3：行尾铅笔图标（直接重命名章节名）
        IconButton(
          onPressed: onRename,
          icon: Icon(
            Icons.edit_outlined,
            size: 18,
            color: context.palette.textSecondary,
          ),
          tooltip: '重命名章节',
          visualDensity: VisualDensity.compact,
        ),
        // 批次79 C：行尾可见删除入口
        IconButton(
          onPressed: onDelete,
          icon: Icon(
            Icons.delete_outline,
            size: 18,
            color: context.palette.danger,
          ),
          tooltip: '删除章节',
          visualDensity: VisualDensity.compact,
        ),
        Icon(
          Icons.chevron_right,
          size: 20,
          color: context.palette.textTertiary,
        ),
      ],
    );
  }
}
