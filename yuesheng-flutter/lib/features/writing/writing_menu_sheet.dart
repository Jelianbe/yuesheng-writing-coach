// ─────────────────────────────────────────────────────────────
// WritingMenuSheet — 写作页 ⋮ 菜单 BottomSheet
//
// 百灵极简风格：纯文字菜单项，无图标（按需才加 trailing）
// 用于写作页右上角"更多"按钮弹出的功能列表
//
// 批次96-9：菜单分组收敛——三个开关（行段聚焦/智能标点/对话按钮）
// 移入排版设置 EditorSettingsSheet（reactive SwitchListTile），菜单只留
// 跳转入口。菜单项分三组：写作工具 / 教学 / 设置。
//
// 菜单内容（N4-2 校正：**15 行 = 13 入口 + 取消 + 保存状态行**，
// 其中可点 `_MenuItem` **14 个** + 不可点保存状态行 1 个 + 组头 3 个）：
//   1. 保存状态行（不可点）
//   ─── 写作工具 ───（组头 1）
//   2. 章节列表（批次83：章节树抽屉入口）→ onOpenChapterTree
//   3. 大纲（批次83：大纲边写边看入口）→ onOpenOutline
//   4. 角色（C78 批次3：角色页独立路由）→ onOpenCharacters
//   5. 全文搜索（批次96-11：整本作品章节搜索）→ onOpenFullTextSearch
//   6. 查找替换（批次84-2：当前章查找替换）→ onOpenFindReplace
//   7. 回收板（批次86-1：删除/剪切长文本找回）→ onOpenRecycleBin
//   8. 快捷短语（批次85-3：常用语管理 + 光标插入）→ onOpenQuickPhrases
//   9. 世界观（W1：世界观设定独立路由 /worlds）→ onOpenWorlds
//   ─── 教学 ───（组头 2）
//   10. 当前文风（批次85-4：风格画像五维展示）→ onOpenStyleProfile
//   11. 写作统计（批次85-5：近 14 天写作曲线）→ onOpenWritingStats
//   12. 打开教练面板（竹青加粗）→ onDiagnose
//   ─── 设置 ───（组头 3）
//   13. 排版设置（批次82；含行段聚焦/智能标点/对话按钮开关）→ onOpenSettings
//   14. 版本时光机（批次82）→ onOpenVersions
//   15. 取消
//
// ★ 首屏容量实测（N4-2，测试视口 800×600、默认 initialHeight 0.55）：
//   sheet 351.6dp（top 248.4）· 项高 48 · 组头高 23 ·
//   「章节列表/大纲/角色/全文搜索」四行**恰好占满**可用高度
//   （全文搜索底 599.4 vs 视口底 600.0 ⇒ **余量 0.6dp**）。
//   ⇒ 在「全文搜索」之前**插入任何一行（项 48 / 组头 23）都会顶掉它**，
//     而 `writing_menu_sheet_test.dart:356` 与
//     `writing_page_test.dart:1947`（openFullTextSearch）都是**直点**该行。
//   ⇒ **改分组/加项前必须先解决容量**（见 `.ai/DECISIONS.md`）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../widgets/yue_sheet.dart';
import '../../theme/app_typography.dart';
import '../../config/app_palette.dart';

/// 写作菜单所需的所有回调与展示态（聚合为 record，避免逐方法透传 14 个参数）
typedef _WritingMenuCallbacks = ({
  DateTime? lastSavedAt,
  VoidCallback onDiagnose,
  VoidCallback? onOpenChapterTree,
  VoidCallback? onOpenOutline,
  VoidCallback? onOpenCharacters,
  VoidCallback? onOpenWorlds,
  VoidCallback? onOpenFullTextSearch,
  VoidCallback? onOpenFindReplace,
  VoidCallback? onOpenRecycleBin,
  VoidCallback? onOpenQuickPhrases,
  VoidCallback? onOpenStyleProfile,
  VoidCallback? onOpenWritingStats,
  VoidCallback? onOpenSettings,
  VoidCallback? onOpenVersions,
});

class WritingMenuSheet {
  const WritingMenuSheet._();

  static void show(
    BuildContext context, {
    required DateTime? lastSavedAt,
    required VoidCallback onDiagnose,
    double initialHeight = 0.55,
    ValueChanged<double>? onHeightChanged,
    VoidCallback? onOpenChapterTree,
    VoidCallback? onOpenOutline,
    VoidCallback? onOpenCharacters,
    VoidCallback? onOpenWorlds,
    VoidCallback? onOpenFullTextSearch,
    VoidCallback? onOpenFindReplace,
    VoidCallback? onOpenRecycleBin,
    VoidCallback? onOpenQuickPhrases,
    VoidCallback? onOpenStyleProfile,
    VoidCallback? onOpenWritingStats,
    VoidCallback? onOpenSettings,
    VoidCallback? onOpenVersions,
  }) {
    final initial = initialHeight.clamp(0.30, 0.85);
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _buildSheet(ctx, initial, onHeightChanged, (
        lastSavedAt: lastSavedAt,
        onDiagnose: onDiagnose,
        onOpenChapterTree: onOpenChapterTree,
        onOpenOutline: onOpenOutline,
        onOpenCharacters: onOpenCharacters,
        onOpenWorlds: onOpenWorlds,
        onOpenFullTextSearch: onOpenFullTextSearch,
        onOpenFindReplace: onOpenFindReplace,
        onOpenRecycleBin: onOpenRecycleBin,
        onOpenQuickPhrases: onOpenQuickPhrases,
        onOpenStyleProfile: onOpenStyleProfile,
        onOpenWritingStats: onOpenWritingStats,
        onOpenSettings: onOpenSettings,
        onOpenVersions: onOpenVersions,
      )),
    );
  }

  static Widget _buildSheet(
    BuildContext context,
    double initial,
    ValueChanged<double>? onHeightChanged,
    _WritingMenuCallbacks c,
  ) {
    // 拖拽/吸附动画会持续发出 notification——仅当 extent 变化超过阈值才上报，
    // 避免动画中间值反复落库（最后一次上报即最终吸附档位）
    var lastReported = initial;
    return DraggableScrollableSheet(
      initialChildSize: initial,
      minChildSize: 0.30,
      maxChildSize: 0.85,
      snap: true,
      snapSizes: const [0.30, 0.55, 0.85],
      expand: false,
      builder: (ctx, scrollController) =>
          NotificationListener<DraggableScrollableNotification>(
            onNotification: (n) {
              if ((n.extent - lastReported).abs() >= 0.005) {
                lastReported = n.extent;
                onHeightChanged?.call(n.extent);
              }
              return false;
            },
            child: _buildMenuBody(ctx, scrollController, c),
          ),
    );
  }

  static Widget _menuItem(
    BuildContext ctx,
    String label, {
    Color? textColor,
    bool bold = false,
    required VoidCallback? onAction,
  }) {
    return _MenuItem(
      label: label,
      textColor: textColor,
      bold: bold,
      onTap: () {
        Navigator.pop(ctx);
        onAction?.call();
      },
    );
  }

  static List<Widget> _buildWritingToolsGroup(
    BuildContext ctx,
    _WritingMenuCallbacks c,
  ) {
    return [
      const _SectionHeader(label: '写作工具'),
      _menuItem(ctx, '章节列表', onAction: c.onOpenChapterTree),
      _menuItem(ctx, '大纲', onAction: c.onOpenOutline),
      // C78 批次3：角色档案（列表/详情/断言校正/合并）
      _menuItem(ctx, '角色', onAction: c.onOpenCharacters),
      // 批次96-11：全文搜索（整本作品章节搜索，命中片段+高亮+跳转定位）
      _menuItem(ctx, '全文搜索', onAction: c.onOpenFullTextSearch),
      _menuItem(ctx, '查找替换', onAction: c.onOpenFindReplace),
      _menuItem(ctx, '回收板', onAction: c.onOpenRecycleBin),
      _menuItem(ctx, '快捷短语', onAction: c.onOpenQuickPhrases),
      // W1 批次：世界观设定（列表/详情/追加/归档）
      // 置于「写作工具」组末位：不挤占既有项位置，避免既有
      // 直点测试（全文搜索等）因下移出首屏而失效。
      _menuItem(ctx, '世界观', onAction: c.onOpenWorlds),
    ];
  }

  static List<Widget> _buildTeachingGroup(
    BuildContext ctx,
    _WritingMenuCallbacks c,
  ) {
    return [
      const _SectionHeader(label: '教学'),
      _menuItem(ctx, '当前文风', onAction: c.onOpenStyleProfile),
      _menuItem(ctx, '写作统计', onAction: c.onOpenWritingStats),
      _menuItem(
        ctx,
        '打开教练面板',
        textColor: ctx.palette.primary,
        bold: true,
        onAction: c.onDiagnose,
      ),
    ];
  }

  static List<Widget> _buildSettingsGroup(
    BuildContext ctx,
    _WritingMenuCallbacks c,
  ) {
    return [
      const _SectionHeader(label: '设置'),
      _menuItem(ctx, '排版设置', onAction: c.onOpenSettings),
      _menuItem(ctx, '版本时光机', onAction: c.onOpenVersions),
    ];
  }

  static Widget _buildMenuBody(
    BuildContext ctx,
    ScrollController scrollController,
    _WritingMenuCallbacks c,
  ) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.section),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SaveStatusRow(lastSavedAt: c.lastSavedAt),
            const Divider(height: 20),
            ..._buildWritingToolsGroup(ctx, c),
            ..._buildTeachingGroup(ctx, c),
            ..._buildSettingsGroup(ctx, c),
            const Divider(height: 20),
            _menuItem(
              ctx,
              '取消',
              textColor: ctx.palette.textSecondary,
              onAction: null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 分组标题：12sp 次要色，上下留白 ──
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.xs,
        bottom: AppSpacing.xxs,
      ),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          style: context.text.noteCaption.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── 普通菜单项：48dp 高，左对齐文字，点击关闭 sheet + 触发回调 ──
class _MenuItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  /// 可空：`null` 时在 `build` 里回退到 `context.palette.textInk`。
  ///
  /// ★ 2026-09-22（批次 M3）：原默认值直接写 `context.palette.textInk` ——
  ///   但 `const` 构造器的默认值**必须是编译期常量**，取不到 `BuildContext`
  ///   ⇒ `dart analyze` 报 `undefined_identifier`。
  ///   改法：默认值改 `null` + 在 `build`（有 context）里 `??` 回退。
  ///   **行为完全不变**（14 个调用点中 12 个不传 ⇒ 原默认值即 `textInk`；
  ///   另 2 个显式传 `primary` / `textSecondary` 不受影响）。
  final Color? textColor;
  final bool bold;

  const _MenuItem({
    required this.label,
    required this.onTap,
    this.textColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              color: textColor ?? context.palette.textInk,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

// ── 保存状态行：12sp 灰字，无点击 ──
class _SaveStatusRow extends StatelessWidget {
  final DateTime? lastSavedAt;

  const _SaveStatusRow({required this.lastSavedAt});

  String _formatTime(DateTime t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final text = lastSavedAt != null
        ? '✓ 已保存 ${_formatTime(lastSavedAt!)}'
        : '未保存';
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: context.text.noteCaption),
      ),
    );
  }
}
