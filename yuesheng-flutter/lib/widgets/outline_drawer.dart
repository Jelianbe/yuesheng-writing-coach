// ─────────────────────────────────────────────────────────────
// OutlineDrawer — 大纲边写边看（批次83 大纲边写边看）
// 写作页右侧抽屉（endDrawer）：**外壳**（Drawer + SafeArea + 头部标题栏）。
//
// ★ 批次 N12「大纲 Drawer 解绑」（2026-09-18）
//   本文件原为一个 530 行的整体：内容直接挂在 `Drawer` 之下（`return Drawer(`）
//   ⇒ 类根节点即抽屉外壳，内容无法在抽屉之外复用。该「强绑」由
//   `docs/designs/2026-09-13-detail-tab-refactor-architecture.md`
//   §1.3 / §8 A4 记录并裁定**独立立项**处理。
//   ⇒ 现拆为：
//     · **内容体** → `OutlineContentView`（无 Drawer / 无 SafeArea / 无头部）
//     · **本文件** → 薄壳：`Drawer > SafeArea > [头部, Divider, 内容体]`
//
//   **公开构造器签名原样保留**（`manuscriptId` / `onClose`）⇒ 消费者
//   （`writing_page_chapter_nav_controller.buildOutlineDrawer` →
//   `writing_page_scaffold` 的 `endDrawer:`）与既有测试**零改动**。
//   手法同构先例：`CharacterPage → CharacterListView`（薄壳保留类名 + 签名）。
//
//   表现零变更：头部标题「大纲」、关闭按钮、背景色、分隔线、内容全同。
//   头部单独成类（`_DrawerHeader`）—— 否则薄壳 `build` 会落在 52 行、
//   **仍超 R-019 的 50 行硬限**（拆分后实测 16 + 28 行，两者均合规）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';
import 'outline_content_view.dart';

/// 大纲抽屉外壳（写作页 endDrawer）。
///
/// 只负责**抽屉外壳**：背景、SafeArea、头部标题与关闭按钮。
/// 内容（实体分组 / 印象行 / 快速确认）见 [OutlineContentView]。
class OutlineDrawer extends StatelessWidget {
  /// 所属作品 ID（null/空 = 无法加载，走空态）
  final String? manuscriptId;

  /// 右上角关闭按钮（由 WritingPage 关闭 endDrawer）
  final VoidCallback onClose;

  /// N4-3：空态「打开教练面板」回调（null = 不渲染该按钮）。
  ///
  /// **可选参数** ⇒ N12 记录的「公开构造器签名原样保留（manuscriptId / onClose）」
  /// 仍然成立：既有消费者与既有测试**零改动**。
  final VoidCallback? onOpenCoach;

  const OutlineDrawer({
    super.key,
    required this.manuscriptId,
    required this.onClose,
    this.onOpenCoach,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(onClose: onClose),
            const Divider(height: 1),
            Expanded(
              child: OutlineContentView(
                manuscriptId: manuscriptId,
                onOpenCoach: onOpenCoach,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 头部：标题「大纲」+ 右上角关闭按钮
class _DrawerHeader extends StatelessWidget {
  /// 右上角关闭按钮（由 WritingPage 关闭 endDrawer）
  final VoidCallback onClose;

  const _DrawerHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.article_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          const Text(
            '大纲',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textInk,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(
              Icons.close,
              size: 20,
              color: AppColors.textTertiary,
            ),
            tooltip: '关闭大纲',
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}
