// ─────────────────────────────────────────────────────────────
// writing_page 视图层：状态条与指示器
//
// 由 C92-6a 伪拆分清偿自 writing_page.dart / writing_page_status_builders.dart
// 提取为**独立 StatelessWidget**（R-019：独立类 / 显式接口，非 part 伪拆分）。
// 行为与原实现逐字等价：Key / 文案 / 令牌 / 布局参数均**零变化**。
//
// 覆盖：离线横幅、保存状态条、写作目标进度条、字数指示器、完成度徽标。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../config/app_theme.dart';

/// 千位分隔符格式化（如 3256 → "3,256"）
String _formatNum(int n) {
  return n.toString().replaceAllMapped(
    RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
    (Match m) => '${m[1]},',
  );
}

/// 字数格式化：>=10000 → "1.2万字"，否则 → "3,256字"（千位分隔符）
String _formatWordCount(int count) {
  if (count >= 10000) {
    return '${(count / 10000).toStringAsFixed(1)}万字';
  }
  return '${_formatNum(count)}字';
}

/// HH:mm 格式化（保存状态条用）
String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// 章节体量徽标：<3000 短章 / 3000-9999 中章 / ≥10000 长章
String _chapterScaleLabel(int wordCount) {
  if (wordCount >= 10000) return '长章';
  if (wordCount >= 3000) return '中章';
  return '短章';
}

/// 离线横幅：断网时提示内容自动保存为本地草稿
/// 对齐 RN chapter-editor.tsx offlineBar
class WritingOfflineBanner extends StatelessWidget {
  const WritingOfflineBanner({super.key, required this.isOffline});

  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    if (!isOffline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.warningBg,
      padding:
          // X-039-Batch1：16→lg / 10→smx
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.smx,
          ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: AppColors.warning),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '当前离线，内容自动保存为本地草稿，恢复网络后将同步',
              style: TextStyle(fontSize: 12, color: AppColors.warning),
            ),
          ),
        ],
      ),
    );
  }
}

/// 批次60：保存状态条——编辑器底部轻量指示「保存中… / 已保存 HH:MM / 保存失败」
/// 让用户直观确认内容已落库（数据安全感），失败时给出可见但温和的提示
/// 批次 X-037-P0-1 H2/C1：暗夜保存状态条联动走 AppColors.editorDark* 令牌
/// （消除硬编码；muted 用 editorDarkMuted 4.56:1 达 AA）
class WritingSaveStatusBar extends StatelessWidget {
  const WritingSaveStatusBar({
    super.key,
    required this.isSaving,
    required this.saveError,
    required this.autosavePaused,
    required this.lastSavedAt,
    required this.darkUi,
  });

  final bool isSaving;
  final String? saveError;
  final bool autosavePaused;
  final DateTime? lastSavedAt;
  final bool darkUi;

  @override
  Widget build(BuildContext context) {
    final muted = darkUi ? AppColors.editorDarkMuted : AppColors.textTertiary;
    final barBg = darkUi ? AppColors.editorDarkPanel : AppColors.background;
    final Widget content;
    if (isSaving) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: muted),
          ),
          const SizedBox(width: 6),
          Text('保存中…', style: TextStyle(fontSize: 11, color: muted)),
        ],
      );
    } else if (saveError != null) {
      // 入档批次：连续失败 >= 3 暂停自动保存时给持续可见提示
      content = Text(
        autosavePaused ? '自动保存已暂停，请手动保存' : '保存失败，请稍后重试',
        style: const TextStyle(fontSize: 11, color: AppColors.warning),
      );
    } else if (lastSavedAt != null) {
      content = Text(
        '已保存 ${_formatTime(lastSavedAt!)}',
        style: TextStyle(fontSize: 11, color: muted),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: barBg,
      // X-039-Batch1：16→lg / 2→xxs / 4→xs
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xxs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Align(alignment: Alignment.centerRight, child: content),
    );
  }
}

/// 批次82：AppBar 底部 2dp 写作目标进度条（未设目标时不占位）
class WritingGoalProgressBar extends StatelessWidget
    implements PreferredSizeWidget {
  const WritingGoalProgressBar({
    super.key,
    required this.goalWords,
    required this.wordCount,
    this.darkUi = false,
  });

  final int goalWords;
  final int wordCount;
  final bool darkUi;

  @override
  Size get preferredSize =>
      goalWords > 0 ? const Size.fromHeight(2) : Size.zero;

  @override
  Widget build(BuildContext context) {
    if (goalWords <= 0) return const SizedBox.shrink();
    final value = (wordCount / goalWords).clamp(0.0, 1.0).toDouble();
    return LinearProgressIndicator(
      value: value,
      minHeight: 2,
      // 批次 X-037-P0-1 H2：进度条暗夜底走 editorDarkDeepMuted 令牌（消除 0xFF3A3F45 硬编码）
      backgroundColor: darkUi
          ? AppColors.editorDarkDeepMuted
          : AppColors.placeholder,
      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
    );
  }
}

/// 批次82：AppBar 字数区——未设目标显示「12字」；已设目标显示「1,234/5,000」，
/// 点击弹出目标设置对话框；达标后字数高亮为竹青
/// 批次85-1：字数区右侧追加「完成度徽标」——设目标显示进度百分比（达标显示「已达成」），
/// 未设目标显示章节体量徽标（短章/中章/长章），让学员随时看到自己产出。
class WritingWordCountIndicator extends StatelessWidget {
  const WritingWordCountIndicator({
    super.key,
    required this.goalWords,
    required this.wordCount,
    required this.onTap,
    this.mutedColor,
  });

  final int goalWords;
  final int wordCount;
  final VoidCallback onTap;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final String text;
    final Color color;
    final secondary = mutedColor ?? AppColors.textSecondary;
    if (goalWords > 0) {
      text = '${_formatNum(wordCount)}/${_formatNum(goalWords)}';
      color = wordCount >= goalWords ? AppColors.primary : secondary;
    } else {
      text = _formatWordCount(wordCount);
      color = secondary;
    }
    return InkWell(
      onTap: onTap,
      // X-039-Batch1：4→xs
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Padding(
        // X-039-Batch1：8→sm / 8→sm
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, style: TextStyle(fontSize: 12, color: color)),
            const SizedBox(width: 6),
            WritingCompletionBadge(goalWords: goalWords, wordCount: wordCount),
          ],
        ),
      ),
    );
  }
}

/// 批次85-1：完成度徽标
class WritingCompletionBadge extends StatelessWidget {
  const WritingCompletionBadge({
    super.key,
    required this.goalWords,
    required this.wordCount,
  });

  final int goalWords;
  final int wordCount;

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color bg;
    final Color fg;
    if (goalWords > 0) {
      final done = wordCount >= goalWords;
      if (done) {
        label = '已达成';
        bg = AppColors.successBg;
        fg = AppColors.success;
      } else {
        final pct = (wordCount / goalWords * 100).round();
        label = '$pct%';
        bg = AppColors.primarySoft;
        fg = AppColors.primaryDeep;
      }
    } else {
      label = _chapterScaleLabel(wordCount);
      bg = AppColors.primarySoft;
      fg = AppColors.primaryDeep;
    }
    return Container(
      key: const Key('completionBadge'),
      // X-039-Batch1：6→xsm / 2→xxs
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xsm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        // X-039-Batch1：8→sm
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: fg)),
    );
  }
}
