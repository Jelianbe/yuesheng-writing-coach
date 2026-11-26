// ─────────────────────────────────────────────────────────────
// WritingMenuBody — ⋮ 菜单的三 tab 主体 + 菜单项呈现组件（P1 重裁，T-20261126-04）
//
// 从 `writing_menu_sheet.dart` 拆出（该文件原 339 行，超 R-019 文件级 300 行）。
// 本拆分是**真分解**：把「菜单内容渲染」这一整个职责搬到自有文件，
// 而非为过门禁割碎代码。`writing_menu_sheet.dart` 只留「入口 + 可拖拽容器」。
//
// ★ 依赖方向（单向，防循环依赖）：
//      writing_menu_sheet.dart  ──→  本文件
//   本文件**不得**反向 import `writing_menu_sheet.dart`——
//   门禁 3「循环依赖扫描」实测本批曾报
//   `writing_menu_body -> writing_menu_sheet -> writing_menu_body` 一圈，
//   根因是主体代码调用 sheet 的 static 组构建函数。修法 = 把组构建函数
//   搬进本文件（内容渲染本就在这里），sheet 不再被反向依赖。
//
// 形态：保存状态行（跨 tab 共享）+ 三 tab + 固定「取消」。
// tab 标签**复用原组头字面**（写作工具/教学/设置）⇒ 零新增用户可见文案。
//
// 为什么不用 `TabBarView`：它要求固定高度或 `Expanded`，而本 sheet 是
// `SingleChildScrollView` 驱动的可滚动体（`DraggableScrollableSheet` 靠这个
// controller 才可拖拽扩展）。改为「TabBar 管索引 + 直接渲染当前组」，
// 拖拽与滚动行为与改前完全一致。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../config/app_theme.dart';
import '../../config/app_palette.dart';
import '../../theme/app_typography.dart';

/// 写作菜单所需的所有回调与展示态（聚合为 record，避免逐方法透传 14 个参数）
typedef WritingMenuItems = ({
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

class WritingMenuBody extends StatefulWidget {
  final ScrollController scrollController;
  final WritingMenuItems c;

  const WritingMenuBody({
    super.key,
    required this.scrollController,
    required this.c,
  });

  @override
  State<WritingMenuBody> createState() => _WritingMenuBodyState();
}

class _WritingMenuBodyState extends State<WritingMenuBody>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(_syncIndex);
  }

  void _syncIndex() {
    if (_tab.index != _index) setState(() => _index = _tab.index);
  }

  @override
  void dispose() {
    _tab.removeListener(_syncIndex);
    _tab.dispose();
    super.dispose();
  }

  List<Widget> _itemsFor(BuildContext ctx) {
    switch (_index) {
      case 1:
        return buildTeachingGroup(ctx, widget.c);
      case 2:
        return buildSettingsGroup(ctx, widget.c);
      default:
        return buildWritingToolsGroup(ctx, widget.c);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: widget.scrollController,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SaveStatusRow(lastSavedAt: widget.c.lastSavedAt),
            TabBar(
              controller: _tab,
              labelColor: context.palette.textInk,
              unselectedLabelColor: context.palette.textSecondary,
              indicatorColor: context.palette.primary,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: context.palette.border,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: const [
                Tab(text: '写作工具'),
                Tab(text: '教学'),
                Tab(text: '设置'),
              ],
            ),
            ..._itemsFor(context),
            const Divider(height: 20),
            menuItem(
              context,
              '取消',
              textColor: context.palette.textSecondary,
              onAction: null,
            ),
          ],
        ),
      ),
    );
  }
}

// ── 菜单项工厂：点击关闭 sheet + 触发回调 ──
Widget menuItem(
  BuildContext ctx,
  String label, {
  Color? textColor,
  bool bold = false,
  required VoidCallback? onAction,
}) {
  return MenuItem(
    label: label,
    textColor: textColor,
    bold: bold,
    onTap: () {
      Navigator.pop(ctx);
      onAction?.call();
    },
  );
}

// ── 三组分组的构建（原在 sheet 内，为解循环依赖迁入本文件）──

/// P1 重裁：**组头不再渲染**——分组信息由顶部 tab 栏承担（tab 标签即原组头
/// 字面），省下的 3×23dp 是本次容量重裁的组成部分。
List<Widget> buildWritingToolsGroup(BuildContext ctx, WritingMenuItems c) {
  return [
    menuItem(ctx, '章节列表', onAction: c.onOpenChapterTree),
    menuItem(ctx, '大纲', onAction: c.onOpenOutline),
    // C78 批次3：角色档案（列表/详情/断言校正/合并）
    menuItem(ctx, '角色', onAction: c.onOpenCharacters),
    // 批次96-11：全文搜索（整本作品章节搜索，命中片段+高亮+跳转定位）
    menuItem(ctx, '全文搜索', onAction: c.onOpenFullTextSearch),
    menuItem(ctx, '查找替换', onAction: c.onOpenFindReplace),
    menuItem(ctx, '回收板', onAction: c.onOpenRecycleBin),
  ];
}

List<Widget> buildTeachingGroup(BuildContext ctx, WritingMenuItems c) {
  return [
    menuItem(ctx, '当前文风', onAction: c.onOpenStyleProfile),
    menuItem(ctx, '写作统计', onAction: c.onOpenWritingStats),
    menuItem(
      ctx,
      '打开教练面板',
      textColor: ctx.palette.primary,
      bold: true,
      onAction: c.onDiagnose,
    ),
    // W1 批次：世界观设定（列表/详情/追加/归档）
    menuItem(ctx, '世界观', onAction: c.onOpenWorlds),
    // 批次85-3：快捷短语（常用语管理 + 光标插入）
    menuItem(ctx, '快捷短语', onAction: c.onOpenQuickPhrases),
  ];
}

List<Widget> buildSettingsGroup(BuildContext ctx, WritingMenuItems c) {
  return [
    menuItem(ctx, '排版设置', onAction: c.onOpenSettings),
    menuItem(ctx, '版本时光机', onAction: c.onOpenVersions),
  ];
}

// ── 普通菜单项：48dp 高，左对齐文字，点击关闭 sheet + 触发回调 ──
class MenuItem extends StatelessWidget {
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

  const MenuItem({
    super.key,
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
              fontSize: 14,
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
class SaveStatusRow extends StatelessWidget {
  final DateTime? lastSavedAt;

  const SaveStatusRow({super.key, required this.lastSavedAt});

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
        child: Text(text, style: context.text.caption),
      ),
    );
  }
}
