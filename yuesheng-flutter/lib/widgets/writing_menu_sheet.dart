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
// 菜单内容（13 项 = 10 入口 + 教练面板 + 取消 + 保存状态行）：
//   1. 保存状态行（不可点）
//   ─── 写作工具 ───
//   2. 章节列表（批次83：章节树抽屉入口）→ onOpenChapterTree
//   3. 大纲（批次83：大纲边写边看入口）→ onOpenOutline
//   4. 全文搜索（批次96-11：整本作品章节标题+正文搜索，命中片段+高亮+跳转定位）→ onOpenFullTextSearch
//   5. 查找替换（批次84-2：当前章查找替换入口）→ onOpenFindReplace
//   6. 回收板（批次86-1：删除/剪切长文本找回）→ onOpenRecycleBin
//   7. 快捷短语（批次85-3：常用语管理 + 光标插入）→ onOpenQuickPhrases
//   ─── 教学 ───
//   8. 当前文风（批次85-4：风格画像五维展示）→ onOpenStyleProfile
//   9. 写作统计（批次85-5：近 14 天写作曲线）→ onOpenWritingStats
//   10. 打开教练面板（竹青加粗）→ onDiagnose
//   ─── 设置 ───
//   11. 排版设置（批次82；含行段聚焦/智能标点/对话按钮开关）→ onOpenSettings
//   12. 版本时光机（批次82）→ onOpenVersions
//   13. 取消
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';

class WritingMenuSheet {
  const WritingMenuSheet._();

  static void show(
    BuildContext context, {
    required DateTime? lastSavedAt,
    required VoidCallback onDiagnose,
    // 批次96-7：拖拽调整篇幅——初始高度占比（默认 0.55）+ 松手后高度回调
    // （用户级持久化由调用方负责，见 AppStateRepository.get/setEditorMenuHeight）
    double initialHeight = 0.55,
    ValueChanged<double>? onHeightChanged,
    // 批次83：章节树抽屉入口
    VoidCallback? onOpenChapterTree,
    // 批次83：大纲边写边看入口
    VoidCallback? onOpenOutline,
    // 批次96-11：全文搜索入口（整本作品章节搜索，命中片段+高亮+跳转定位）
    VoidCallback? onOpenFullTextSearch,
    // 批次84-2：全文查找替换入口
    VoidCallback? onOpenFindReplace,
    // 批次86-1：回收板入口（删除/剪切长文本找回）
    VoidCallback? onOpenRecycleBin,
    // 批次85-3：快捷短语入口（常用语管理 + 光标插入）
    VoidCallback? onOpenQuickPhrases,
    // 批次85-4：当前文风展示入口（风格画像五维）
    VoidCallback? onOpenStyleProfile,
    // 批次85-5：写作统计入口（近 14 天写作曲线）
    VoidCallback? onOpenWritingStats,
    // 批次82：排版设置入口（P0 四件套之①；批次96-9：兼管三开关）
    VoidCallback? onOpenSettings,
    // 批次82：版本时光机入口（P0 四件套之③）
    VoidCallback? onOpenVersions,
  }) {
    // 批次96-6→96-7：菜单改非全屏抽屉 + DraggableScrollableSheet 拖拽调整篇幅——
    // 三档吸附（30%/55%/85%），min 0.30 保证菜单项可读，max 0.85 顶部始终露出编辑器区域；
    // initialChildSize 由调用方传入（用户级记忆）；松手后经 onHeightChanged 落库
    final initial = initialHeight.clamp(0.30, 0.85);
    // 拖拽/吸附动画会持续发出 notification——仅当 extent 变化超过阈值才上报，
    // 避免动画中间值反复落库（最后一次上报即最终吸附档位）
    var lastReported = initial;
    showYueModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: initial,
        minChildSize: 0.30,
        maxChildSize: 0.85,
        snap: true,
        snapSizes: const [0.30, 0.55, 0.85],
        expand: false,
        builder: (ctx, scrollController) =>
            NotificationListener<DraggableScrollableNotification>(
          onNotification: (n) {
            // 松手/吸附到位后上报当前高度占比，由调用方持久化
            if ((n.extent - lastReported).abs() >= 0.005) {
              lastReported = n.extent;
              onHeightChanged?.call(n.extent);
            }
            return false;
          },
          child: SingleChildScrollView(
            controller: scrollController,
            child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            _SaveStatusRow(lastSavedAt: lastSavedAt),
            const Divider(height: 20),
            // ─── 写作工具 ───
            const _SectionHeader(label: '写作工具'),
            _MenuItem(
              label: '章节列表',
              onTap: () {
                Navigator.pop(ctx);
                onOpenChapterTree?.call();
              },
            ),
            _MenuItem(
              label: '大纲',
              onTap: () {
                Navigator.pop(ctx);
                onOpenOutline?.call();
              },
            ),
            // 批次96-11：全文搜索（整本作品章节搜索，命中片段+高亮+跳转定位）
            _MenuItem(
              label: '全文搜索',
              onTap: () {
                Navigator.pop(ctx);
                onOpenFullTextSearch?.call();
              },
            ),
            _MenuItem(
              label: '查找替换',
              onTap: () {
                Navigator.pop(ctx);
                onOpenFindReplace?.call();
              },
            ),
            _MenuItem(
              label: '回收板',
              onTap: () {
                Navigator.pop(ctx);
                onOpenRecycleBin?.call();
              },
            ),
            _MenuItem(
              label: '快捷短语',
              onTap: () {
                Navigator.pop(ctx);
                onOpenQuickPhrases?.call();
              },
            ),
            // ─── 教学 ───
            const _SectionHeader(label: '教学'),
            _MenuItem(
              label: '当前文风',
              onTap: () {
                Navigator.pop(ctx);
                onOpenStyleProfile?.call();
              },
            ),
            _MenuItem(
              label: '写作统计',
              onTap: () {
                Navigator.pop(ctx);
                onOpenWritingStats?.call();
              },
            ),
            _MenuItem(
              label: '打开教练面板',
              textColor: AppColors.primary,
              bold: true,
              onTap: () {
                Navigator.pop(ctx);
                onDiagnose();
              },
            ),
            // ─── 设置 ───
            const _SectionHeader(label: '设置'),
            _MenuItem(
              label: '排版设置',
              onTap: () {
                Navigator.pop(ctx);
                onOpenSettings?.call();
              },
            ),
            _MenuItem(
              label: '版本时光机',
              onTap: () {
                Navigator.pop(ctx);
                onOpenVersions?.call();
              },
            ),
            // 批次96-5：菜单末尾「取消」——菜单近全屏时遮罩仅剩顶部窄条，
            // 仅靠点遮罩/下滑关闭不直观，需显式关闭入口（对齐详情页更多菜单）
            const Divider(height: 20),
            _MenuItem(
              label: '取消',
              textColor: AppColors.textSecondary,
              onTap: () => Navigator.pop(ctx),
            ),
            ],
          ),
        ),
        ),
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
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

// ── 普通菜单项：48dp 高，左对齐文字，点击关闭 sheet + 触发回调 ──
class _MenuItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color textColor;
  final bool bold;

  const _MenuItem({
    required this.label,
    required this.onTap,
    this.textColor = AppColors.textInk,
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
              color: textColor,
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
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}
