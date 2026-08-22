// ─────────────────────────────────────────────────────────────
// PunctuationBar — 中文标点符号栏
// 悬浮于键盘上方的横滑标点条，复刻中文写作 App 标配功能
//
// 范围：
//   - 15 个常用中文标点 / 控制符（带 id，供批次86-2 自定义工具栏配置）
//   - 横向滚动（ListView.builder）
//   - 点击回调插入对应字符
//   - visibleIds：按配置的可见顺序渲染（null = 全部默认顺序）
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../config/app_theme.dart';

/// 标点项（id 供自定义工具栏配置标识；display 展示；insert 插入文本）
class PunctuationItem {
  final String id;
  final String display;
  final String insert;
  const PunctuationItem(this.id, this.display, this.insert);
}

/// 全部标点项（默认顺序 = 配置的初始值）
const List<PunctuationItem> punctuationItems = [
  PunctuationItem('comma', '，', '，'),
  PunctuationItem('period', '。', '。'),
  PunctuationItem('question', '？', '？'),
  PunctuationItem('exclaim', '！', '！'),
  PunctuationItem('colon', '：', '：'),
  PunctuationItem('quoteL', '「', '「'),
  PunctuationItem('quoteR', '」', '」'),
  PunctuationItem('ellipsis', '……', '……'),
  PunctuationItem('dash', '——', '——'),
  PunctuationItem('bookL', '《', '《'),
  PunctuationItem('bookR', '》', '》'),
  PunctuationItem('bracketL', '【', '【'),
  PunctuationItem('bracketR', '】', '】'),
  PunctuationItem('tab', '缩进', '\t'),
  PunctuationItem('newline', '换行', '\n'),
];

/// 默认标点 id 顺序（未配置时的完整列表）
List<String> get defaultPunctuationIds =>
    punctuationItems.map((e) => e.id).toList();

class PunctuationBar extends StatelessWidget {
  final void Function(String char) onTap;

  /// 按配置的可见标点 id 顺序渲染（null = 全部默认顺序）
  final List<String>? visibleIds;

  /// 批次88-5：用户自定义标点项（内置项之外，可增删）
  final List<PunctuationItem> customItems;

  /// 批次91-3：撤销/重做常驻操作项（标点栏最前两位；批次96-10 起为唯一入口——
  /// AppBar 已去撤销/重做。操作项不参与 visibleIds 配置，永不可被用户隐藏）
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;

  /// 批次94-4：暗夜编辑器背景联动取反——底色/标点文字/操作项图标可覆盖
  /// （null = 默认亮色令牌；写作页暗夜背景时传入取反色）
  final Color? backgroundColor;
  final Color? itemColor;
  final Color? actionColor;

  const PunctuationBar({
    super.key,
    required this.onTap,
    this.visibleIds,
    this.customItems = const [],
    this.onUndo,
    this.onRedo,
    this.backgroundColor,
    this.itemColor,
    this.actionColor,
  });

  /// 可见项（内置 + 自定义合并，按 visibleIds 过滤 + 排序；未知 id 忽略）
  List<PunctuationItem> get _visibleItems {
    final all = [...punctuationItems, ...customItems];
    if (visibleIds == null) return all;
    final byId = {for (final it in all) it.id: it};
    return [
      for (final id in visibleIds!)
        if (byId[id] != null) byId[id]!,
    ];
  }

  /// 批次91-3：常驻操作项（撤销/重做图标，点击走 onUndo/onRedo）
  Widget _buildActionItem(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        height: 36,
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 18,
          color: actionColor ?? AppColors.textTertiary,
        ),
      ),
    );
  }

  /// 单个标点项（点击插入对应字符）
  Widget _buildPunctItem(PunctuationItem item) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(item.insert),
      child: Container(
        constraints: const BoxConstraints(minWidth: 44),
        height: 36,
        alignment: Alignment.center,
        child: Text(
          item.display,
          style: TextStyle(fontSize: 16, color: itemColor ?? AppColors.textInk),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;
    return Container(
      height: 36,
      color: backgroundColor ?? AppColors.background,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          // 批次91-3：撤销/重做常驻最前两位（不随 visibleIds 隐藏；批次96-10 唯一入口）
          _buildActionItem(Icons.undo, onUndo),
          _buildActionItem(Icons.redo, onRedo),
          for (final item in items) _buildPunctItem(item),
        ],
      ),
    );
  }
}
