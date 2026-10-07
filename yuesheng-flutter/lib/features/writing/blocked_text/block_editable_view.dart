// ─────────────────────────────────────────────────────────────
// block_editable_view — 分页编辑器可编辑块（ADR-0002 阶段2/3）
//
// 每块一个 TextField，块级常驻 controller/focusNode：
//   - 视口懒构建（ListView.builder，块 build 计数可证）
//   - 智能标点 SmartPunctuationFormatter 逐块挂接（定制1，原样复用）
//   - 配色 style/hintStyle 逐块套用（定制6，_resolveColors 结果外传入）
//
// 阶段3 新增（ADR §6.3/§6.4/§6.5）：
//   - 回车拆块：块文本一旦出现 '\n'（软键盘/硬件键盘都走这条）→ 在该处切成
//     上下两块；按排版设置补首行缩进 '\u3000\u3000' / 段间空行（复用纯函数常量）
//   - 退格合并：光标在块首退格 → 拼回上一块末尾，焦点移上一块
//   - 组词区守卫（R-B5）：controller.value.composing 非空折叠态时，禁拆/禁合
//   - 跨块方向键：左右键到块边界移交焦点（原型已验证；上下键留 v2）
//   - FocusAware 淡化（定制3）：focusMode 下非当前块 alpha 0.32，当前块正常
//   - onValue 镜像：任一块文本/选区变化 → 整串 + 绝对选区 TextEditingValue
//     喂回宿主，供 flag-on 划词通路（selectionAi）原样消费
//
// 生命周期取舍（ADR §6.1）：controller/focusNode 对所有块常驻，不随滑出视口回收。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/paragraph_format.dart';
import '../smart_punctuation_formatter.dart';
import 'block_projection.dart';

/// 可编辑分块视图。初始文本只在 initState 读一次建块；之后块内 controller 是
/// 块真值，整串经 onChanged / onValue 回流宿主。
class BlockEditableView extends StatefulWidget {
  const BlockEditableView({
    super.key,
    required this.initialText,
    required this.style,
    required this.hintStyle,
    required this.smartPunctOn,
    required this.onChanged,
    this.focusMode = false,
    this.indentParagraph = false,
    this.blankLineBetween = false,
    this.onValue,
    this.onActiveBlockChanged,
    this.onBlockBuild,
  });

  final String initialText;
  final TextStyle style;
  final TextStyle hintStyle;
  final bool smartPunctOn;

  /// 任一块改动 → 拼回整串后的回调（接原 onContentChanged/autosave 通路）。
  final ValueChanged<String> onChanged;

  /// 行段聚焦（定制3）：true 时非当前块整体淡化。
  final bool focusMode;

  /// 段落格式钩子（定制2）：拆块后新块首补缩进。
  final bool indentParagraph;

  /// 段落格式钩子：拆块后段间插一个空行块。
  final bool blankLineBetween;

  /// 文本或选区变化 → 整串 + 绝对选区（flag-on 划词通路镜像）。
  final ValueChanged<TextEditingValue>? onValue;

  /// 当前块焦点变化回调（阶段3 划词定位）。
  final ValueChanged<int?>? onActiveBlockChanged;

  /// 每构建一个块回调一次（widget 测试计数）。
  final VoidCallback? onBlockBuild;

  @override
  State<BlockEditableView> createState() => BlockEditableViewState();
}

/// 暴露给宿主的操作句柄（locateCursor/revealCaret 用）。
class BlockEditableViewState extends State<BlockEditableView> {
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];
  int? _activeIndex;

  @override
  void initState() {
    super.initState();
    _resetBlocks(widget.initialText);
  }

  /// 用新整串重建全部块（外部回灌：undo/redo/快捷短语/标点/排版/时光机）。
  /// 旧 controller/focusNode 先 dispose；caretOffset 给定时经 locateCaret 恢复光标。
  void applyExternalText(String text, {int? caretOffset}) {
    setState(() {
      _resetBlocks(text);
      _activeIndex = null;
    });
    if (caretOffset != null) locateCaret(caretOffset);
    _emitValue();
  }

  /// 最近被触碰（文本或选区变化）的块序号 —— 即「选区的来源块」。
  ///
  /// ★ 2026-10-07 新增：旧实现没有这个概念，只认 `_activeIndex` + `hasFocus`，
  /// 于是在没有块聚焦时丢弃选区并发射 `TextSelection.collapsed(offset: -1)`
  /// （负偏移 = 无效选区），见 [_absoluteSelection] 的缺陷说明。
  int? _selectionBlockIndex;

  /// 建块控制器：先记来源块、再发射值（listener 按注册顺序调用）。
  TextEditingController _newBlockController(String text, int index) {
    final c = TextEditingController(text: text);
    c.addListener(() => _selectionBlockIndex = index);
    c.addListener(_emitValue);
    return c;
  }

  void _resetBlocks(String text) {
    for (final c in _controllers) {
      c.removeListener(_emitValue);
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
    final blocks = BlockProjection.fromText(text).blocks;
    for (var i = 0; i < blocks.length; i++) {
      _controllers.add(_newBlockController(blocks[i], i));
    }
    for (var i = 0; i < blocks.length; i++) {
      _focusNodes.add(
        FocusNode(onKeyEvent: _onKeyEvent)
          ..addListener(() => _onFocusChanged(i)),
      );
    }
  }

  void _onFocusChanged(int index) {
    if (!_focusNodes[index].hasFocus) return;
    if (_activeIndex == index) return;
    setState(() => _activeIndex = index);
    widget.onActiveBlockChanged?.call(index);
    _emitValue();
  }

  /// 绝对偏移 → 定位到对应块并聚焦（locateCursor/revealCaret）。
  void locateCaret(int absoluteOffset) {
    var off = 0;
    for (var i = 0; i < _controllers.length; i++) {
      final len = _controllers[i].text.length;
      if (absoluteOffset <= off + len) {
        _focusNodes[i].requestFocus();
        _controllers[i].selection = TextSelection.collapsed(
          offset: absoluteOffset - off,
        );
        return;
      }
      off += len + 1; // +1 = 块间 '\n'
    }
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final index = _focusNodes.indexOf(node);
    if (index < 0) return KeyEventResult.ignored;
    final ctrl = _controllers[index];
    final sel = ctrl.selection;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        sel.isCollapsed &&
        sel.baseOffset == 0 &&
        !_hasComposing(ctrl)) {
      if (index > 0) {
        _mergeWithPrevious(index);
        return KeyEventResult.handled;
      }
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        sel.isCollapsed &&
        sel.baseOffset == 0 &&
        index > 0) {
      _moveToBlock(index - 1, atEnd: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight &&
        sel.isCollapsed &&
        sel.baseOffset == ctrl.text.length &&
        index < _controllers.length - 1) {
      _moveToBlock(index + 1, atEnd: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveToBlock(int target, {required bool atEnd}) {
    _focusNodes[target].requestFocus();
    final len = _controllers[target].text.length;
    _controllers[target].selection = TextSelection.collapsed(
      offset: atEnd ? len : 0,
    );
  }

  bool _hasComposing(TextEditingController c) {
    final r = c.value.composing;
    return r.isValid && !r.isCollapsed;
  }

  void _mergeWithPrevious(int index) {
    final cur = _controllers[index];
    final prev = _controllers[index - 1];
    final caret = prev.text.length;
    prev.value = TextEditingValue(
      text: prev.text + cur.text,
      selection: TextSelection.collapsed(offset: caret),
    );
    cur.dispose();
    _focusNodes[index].dispose();
    setState(() {
      _controllers.removeAt(index);
      _focusNodes.removeAt(index);
    });
    _focusNodes[index - 1].requestFocus();
    prev.selection = TextSelection.collapsed(offset: caret);
    _emitValue();
  }

  /// 块文本变化：若含 '\n'（回车）→ 拆块；否则普通变更。
  void _onBlockTextChanged(int index) {
    final ctrl = _controllers[index];
    if (ctrl.text.contains('\n')) {
      if (_hasComposing(ctrl)) {
        _emitValue();
        return; // 组词态不拆块（R-B5）
      }
      _splitAtFirstNewline(index);
      return;
    }
    _emitValue();
  }

  void _splitAtFirstNewline(int index) {
    final ctrl = _controllers[index];
    final nl = ctrl.text.indexOf('\n');
    final left = ctrl.text.substring(0, nl);
    var right = ctrl.text.substring(nl + 1);
    if (widget.indentParagraph &&
        !right.startsWith('\u3000') &&
        !right.startsWith(' ')) {
      right = paragraphIndent + right;
    }
    ctrl.value = TextEditingValue(
      text: left,
      selection: TextSelection.collapsed(offset: left.length),
    );
    final insertAt = index + 1;
    final rightCtrl = _newBlockController(right, insertAt);
    final rightNode = FocusNode(onKeyEvent: _onKeyEvent);
    setState(() {
      _controllers.insert(insertAt, rightCtrl);
      _focusNodes.insert(insertAt, rightNode);
      if (widget.blankLineBetween) {
        _controllers.insert(insertAt, _newBlockController('', insertAt + 1));
        _focusNodes.insert(insertAt, FocusNode(onKeyEvent: _onKeyEvent));
      }
    });
    rightNode.requestFocus();
    rightCtrl.selection = TextSelection.collapsed(
      offset: widget.indentParagraph ? paragraphIndent.length : 0,
    );
    _emitValue();
  }

  /// 整串 + 当前块绝对选区 → 镜像给宿主。
  void _emitValue() {
    final buf = StringBuffer();
    for (var i = 0; i < _controllers.length; i++) {
      if (i > 0) buf.write('\n');
      buf.write(_controllers[i].text);
    }
    final text = buf.toString();
    widget.onValue?.call(
      TextEditingValue(text: text, selection: _absoluteSelection()),
    );
    widget.onChanged(text);
  }

  /// 来源块的局部选区 → 整篇绝对选区。
  ///
  /// ★ 2026-10-07 修正两处缺陷（收尾门禁门禁 2「选中态/浮动菜单」27 例红的根因）：
  ///  1) 旧实现以 `_focusNodes[_activeIndex].hasFocus` 为门槛。分块模式下**没有任何
  ///     TextField 持有整篇 controller**，选区只存在于各块 controller；一旦没有块
  ///     处于聚焦态（焦点被面板/弹窗夺走，或程序化写块后未聚焦），选区被**丢弃**。
  ///  2) 丢弃后写入 `TextSelection.collapsed(offset: -1)` —— **负偏移 = 无效选区**，
  ///     且被原样写进宿主 `contentController`（`writing_editor_view.dart:339`
  ///     `onValue: (v) => contentController.value = v`）⇒ 下游
  ///     `WritingPageSelectionAiController.onSelectionChanged` 只能走「隐藏菜单」分支。
  /// 改为「以最近被触碰的块为选区来源，不要求它聚焦」；无有效局部选区时回落为
  /// **合法**的折叠光标（offset 0），**绝不发射负偏移**。
  TextSelection _absoluteSelection() {
    final src = _selectionBlockIndex ?? _activeIndex;
    if (src != null && src >= 0 && src < _controllers.length) {
      final local = _controllers[src].selection;
      if (local.isValid) {
        return TextSelection(
          baseOffset: _absOffset(src, local.baseOffset),
          extentOffset: _absOffset(src, local.extentOffset),
        );
      }
    }
    return const TextSelection.collapsed(offset: 0);
  }

  int _absOffset(int block, int local) {
    var off = local;
    for (var i = 0; i < block; i++) {
      off += _controllers[i].text.length + 1;
    }
    return off;
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _focusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: _controllers.length,
      itemBuilder: (context, index) {
        widget.onBlockBuild?.call();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: _buildBlock(index),
        );
      },
    );
  }

  TextStyle _blockStyle(int index) {
    final dim = widget.focusMode && index != _activeIndex;
    if (!dim) return widget.style;
    return widget.style.copyWith(
      color: widget.style.color?.withValues(alpha: 0.32),
    );
  }

  Widget _buildBlock(int index) {
    final showHint = index == 0 && widget.initialText.isEmpty;
    final field = TextField(
      key: ValueKey('contentBlock_$index'),
      controller: _controllers[index],
      focusNode: _focusNodes[index],
      maxLines: null,
      style: _blockStyle(index),
      inputFormatters: [
        if (widget.smartPunctOn) const SmartPunctuationFormatter(),
      ],
      decoration: InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: showHint ? '请输入正文内容' : null,
        hintStyle: widget.hintStyle,
      ),
      onChanged: (_) => _onBlockTextChanged(index),
    );
    // Key 兼容（flag 开）：首块外层再挂现网 `chapterContentField`，与块自身的
    // `contentBlock_$index` 并存（KeyedSubtree）。find.byKey(chapterContentField)
    // 可解析到首块子树；块内输入/断言仍用稳定的 contentBlock_$index。
    if (index != 0) return field;
    return KeyedSubtree(key: const Key('chapterContentField'), child: field);
  }
}
