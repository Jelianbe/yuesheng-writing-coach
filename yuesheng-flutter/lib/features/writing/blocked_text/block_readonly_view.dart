// ─────────────────────────────────────────────────────────────
// block_readonly_view — 分页编辑器只读渲染（ADR-0002 阶段1）
//
// 整章文本（contentController.text）经 BlockProjection 切块后，
// ListView.builder 只构建视口内块 —— 验证「长章节滚动不再整章布局/光栅」。
// 阶段1 不接编辑（无 controller/focusNode/inputFormatter），编辑能力在阶段2+。
// 回退：kBlockEditorEnabled = false 时 _buildContentField 走原单 TextField。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import 'block_projection.dart';

/// feature flag（ADR-0002）：true = 正文走**分块可编辑**渲染（阶段 2+，
/// `BlockEditableView`，每块独立 TextField + 逐块智能标点）；
/// false = 回退单 `TextField(maxLines:null)` 通路。编译期常量，两条路径各自出包对比帧率。
///
/// ⚠️ **2026-10-07 订正**：本常量自 `7d245a75`（0.5.1 发版）起即为 **true**，
/// 原文「阶段1 只读渲染 / false（默认）」描述的是 2026-08 的旧世界，已失效。
/// 回退通路**仍在** `writing_editor_view.dart::_buildContentField` 的 else 分支，未删除。
/// ⚠️ 改本常量前必读 `reports/2026-10-07-分块编辑器缺陷专项审查.md`：
/// 上一次翻值时提交自述「同步测试契约」但漏了 `writing_page_test.dart`，
/// 一次改动使收尾门禁门禁 2 红 54 例。
const bool kBlockEditorEnabled = true;

/// 分块只读渲染视图：BlockProjection 投影 → ListView.builder 懒加载。
class BlockReadonlyView extends StatelessWidget {
  const BlockReadonlyView({
    super.key,
    required this.text,
    required this.style,
    this.onBlockBuild,
  });

  /// 整章扁平文本（唯一真源，同现网 controller.text）。
  final String text;

  /// 逐块套用的文字样式（与现网正文 TextStyle 同参数）。
  final TextStyle style;

  /// 每构建一个块回调一次（widget 测试计数用：证明视口外块不构建）。
  final VoidCallback? onBlockBuild;

  @override
  Widget build(BuildContext context) {
    final projection = BlockProjection.fromText(text);
    return ListView.builder(
      itemCount: projection.blocks.length,
      itemBuilder: (context, index) {
        onBlockBuild?.call();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(projection.blocks[index], style: style),
        );
      },
    );
  }
}
