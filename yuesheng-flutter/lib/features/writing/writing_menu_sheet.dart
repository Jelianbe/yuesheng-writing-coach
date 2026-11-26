// ─────────────────────────────────────────────────────────────
// WritingMenuSheet — 写作页 ⋮ 菜单入口 + 可拖拽容器（百灵极简：纯文字项，无图标）
//
// ★ P1 重裁（T-20261126-04 · R-027 批号「2026-11-26 四项全批 A」）
//   原形态：单列 14 可点项 + 3 组头 + 1 保存行，内容 741dp vs 容器 351.6dp
//   ⇒ 首屏可见率 47.4%、余量仅 0.6dp（全文搜索底 599.4 vs 视口底 600.0）。
//   改后：三 tab 分组，**组头不再渲染**（分组信息由 tab 栏承担，标签复用原
//   组头字面、零新增文案）：
//     ① 写作工具（默认）章节列表·大纲·角色·全文搜索·查找替换·回收板 = 6
//     ② 教学 当前文风·写作统计·打开教练面板·世界观·快捷短语         = 5
//     ③ 设置 排版设置·版本时光机                                    = 2
//   固定区（跨 tab 恒在）：保存状态行（上）+ 取消（下）。
//
// ★ 改后容量实测（G6，E1）：真机逻辑尺寸 393×851（1080×2340@2.75）容器
//   489.7dp ⇒ 6/6·5/5·2/2；窄屏 360×800 容器 461.6dp ⇒ 同样 6/6·5/5·2/2。
//   ⚠️ Flutter 默认视口 800×600 容器仅 351.6dp，扣拖拽条+保存行+tab 栏+
//   分隔线+取消约 188dp 后只剩 ≈3.4 项 ⇒ **该视口不是手机尺寸**，容量判据
//   以真机视口为准；它只用作阴性质检（回收板在此视口恒在首屏外）。
//
// ★ 既有契约（§4-569 约束 1）：`章节列表/大纲/角色/全文搜索` 四条直点路径
//   全在默认 tab 前 4 项 ⇒ 两处直点测试无需改为滚动。
//
// ★ 依赖方向（单向）：本文件 ──→ `writing_menu_body.dart`，**不反向**。
//   菜单内容渲染（三组构建 / MenuItem / SaveStatusRow / WritingMenuItems）
//   全在 body 文件；本文件只剩入口与可拖拽容器。此边界由门禁 3 守住 ——
//   本批首版曾把组构建留在本文件，实测报循环依赖一圈，已按此方向修正。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../widgets/yue_sheet.dart';
import 'writing_menu_body.dart';

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
    WritingMenuItems c,
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
            child: WritingMenuBody(scrollController: scrollController, c: c),
          ),
    );
  }
}
