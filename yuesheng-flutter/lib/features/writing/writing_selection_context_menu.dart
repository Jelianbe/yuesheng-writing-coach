// ─────────────────────────────────────────────────────────────
// writing_selection_context_menu — 写作页统一的文本选择工具栏（2026-11-22）
//
// 背景（用户反馈）：旧实现里系统 cut/copy/share 菜单与自定义「诊断这段文字」
// overlay 并存（多选弹窗），且 overlay 位置在选区变化时算一次、键盘弹起不重算
// → 被软键盘遮挡。
//
// 新方案：用 Flutter 官方 `TextField.contextMenuBuilder` 完全接管选择菜单——
//   · 系统动作（复制/粘贴/全选/剪切）用 `state.contextMenuButtonItems`（官方实现，
//     零行为风险，跨 Android/iOS 自适应）；
//   · 追加两个自定义项「引用诊断」「存入设定库」，回调读宿主已就绪的
//     `selectedText`（由 selectionAi controller listener 在选区变化时更新）；
//   · toolbar 由 `AdaptiveTextSelectionToolbar` 用 `state.contextMenuAnchors`
//     自动锚定在选区附近并随键盘避让 ⇒ 遮挡问题由框架层解决，不再手写定位。
//
// 纯函数模块：两条 TextField 路径（分块编辑器 flag 开 / 单字段回退）共用同一
// builder，行为一致；不依赖任何 provider / 平台通道，可直接单测。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// 菜单项标签（供测试与代码共同引用，避免字串漂移）。
const String kSelectionMenuDiagnoseLabel = '引用诊断';
const String kSelectionMenuSaveToLibraryLabel = '存入设定库';

/// 构造选择菜单的按钮项列表（纯函数，可直接单测）。
///
/// [systemItems] 来自 `EditableTextState.contextMenuButtonItems`（官方的
/// 复制/粘贴/全选/剪切），原样保留；[onDiagnose] 为「引用诊断」回调；
/// [onSaveToLibrary] 为「存入设定库」回调，null 时不渲染该项。
List<ContextMenuButtonItem> buildSelectionMenuItems({
  required Iterable<ContextMenuButtonItem> systemItems,
  required VoidCallback onDiagnose,
  VoidCallback? onSaveToLibrary,
}) {
  return <ContextMenuButtonItem>[
    ...systemItems,
    ContextMenuButtonItem(
      type: ContextMenuButtonType.custom,
      label: kSelectionMenuDiagnoseLabel,
      onPressed: onDiagnose,
    ),
    if (onSaveToLibrary != null)
      ContextMenuButtonItem(
        type: ContextMenuButtonType.custom,
        label: kSelectionMenuSaveToLibraryLabel,
        onPressed: onSaveToLibrary,
      ),
  ];
}

/// 构建写作页统一选择菜单 builder。
///
/// [onDiagnose] 点击「引用诊断」时回调（宿主读 selectedText 注入诊断面板）。
/// [onSaveToLibrary] 点击「存入设定库」时回调；null 时不渲染该项。
EditableTextContextMenuBuilder buildWritingContextMenu({
  required VoidCallback onDiagnose,
  VoidCallback? onSaveToLibrary,
}) {
  return (BuildContext context, EditableTextState editableTextState) {
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: editableTextState.contextMenuAnchors,
      buttonItems: buildSelectionMenuItems(
        systemItems: editableTextState.contextMenuButtonItems,
        onDiagnose: onDiagnose,
        onSaveToLibrary: onSaveToLibrary,
      ),
    );
  };
}
