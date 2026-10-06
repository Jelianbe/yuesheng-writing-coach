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

/// 阶段1 feature flag：true = 正文走分块只读渲染；false（默认）= 现网单
/// TextField(maxLines:null) 通路。编译期常量，两条路径各自出包对比帧率。
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
