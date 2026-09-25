// ─────────────────────────────────────────────────────────────
// writing_page 视图层：AppBar 骨架
//
// 由 C92-6a 伪拆分清偿自 writing_page.dart 提取为独立 StatelessWidget
// （R-019：独立类 / 显式接口，非 part 伪拆分）。
// 行为与原实现逐字等价：`toolbarHeight: 48` + `bottom` 进度条 → 高度
// 48(+2) 与原 AppBar 自算的 preferredSize 一致；leading/title/actions 的
// 结构、图标、tooltip、文案零变化。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_palette.dart';

/// 写作页 AppBar（返回 / 面包屑 / 字数指示 / 一键排版 / ⋮ 菜单）
class WritingPageAppBar extends StatelessWidget implements PreferredSizeWidget {
  const WritingPageAppBar({
    super.key,
    required this.darkUi,
    required this.editorPalette,
    required this.foregroundColor,
    required this.goalWords,
    required this.breadcrumb,
    required this.progressBar,
    required this.wordCount,
    required this.onBack,
    required this.onFormatChapter,
    required this.onOpenMenu,
  });

  /// 是否暗夜编辑器背景（决定底色取本 palette 的暗色支还是常规支）
  final bool darkUi;

  /// ★ 2026-09-22（批次 M1）：编辑器 presets 轴所选 palette（**由宿主下发**）。
  ///
  /// 此前本组件自带 `darkUi` 布尔 + 直读静态 `AppColors.editorDarkSurface` /
  /// `AppColors.background`，使编辑器轴无法接入主题体系。现改为接收
  /// `editorPaletteFor(state.editorBackground)` 的结果 —— 与宿主、与编辑器正文
  /// **取同一套 palette**，取消「布尔 + 两处静态常量」的双真源形态。
  final AppPalette editorPalette;

  /// 前景色（由宿主统一计算并下发，避免与宿主各算一次而重复）
  final Color foregroundColor;

  /// 写作目标字数（>0 时底部进度条占 2dp，决定 preferredSize）
  final int goalWords;

  final Widget breadcrumb;
  final PreferredSizeWidget progressBar;
  final Widget wordCount;
  final VoidCallback onBack;
  final VoidCallback onFormatChapter;
  final VoidCallback onOpenMenu;

  @override
  Size get preferredSize => Size.fromHeight(48 + (goalWords > 0 ? 2 : 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: darkUi
          ? editorPalette.editorDarkSurface
          : editorPalette.background,
      elevation: 0,
      toolbarHeight: 48,
      leading: IconButton(
        icon: Icon(Icons.arrow_back, color: foregroundColor),
        onPressed: onBack,
      ),
      // 批次95-4：写作页面包屑（卷名·章名）
      title: breadcrumb,
      // 批次88-1：标题移出 AppBar，改为正文上方独立大号标题行（WritingEditorView）
      bottom: progressBar,
      actions: [
        // 批次96-10：撤销/重做入口收敛——AppBar 不再放撤销/重做
        // 批次82：字数显示 + 写作目标（点击设置目标）
        wordCount,
        // 批次96-8：一键排版（原「记灵感」位置；按排版开关批量应用段落格式）
        IconButton(
          icon: Icon(Icons.format_align_left, size: 20, color: foregroundColor),
          tooltip: '一键排版',
          onPressed: onFormatChapter,
        ),
        IconButton(
          icon: Icon(Icons.more_vert, color: foregroundColor),
          onPressed: onOpenMenu,
        ),
      ],
    );
  }
}
