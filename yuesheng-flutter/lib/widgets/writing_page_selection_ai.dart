// ─────────────────────────────────────────────────────────────
// writing_page 的 part 文件：划词 AI 相关逻辑
// 覆盖批次82/83/95-1 的 B3 划词诊断 + 改写/续写/扩写择选弹层。
// 以私有 extension on _WritingPageState 形式提供划词 AI 方法，
// 直接访问宿主私有成员（_controller / _selectedText / _selection /
// _selectionMenuPos / _editorStackKey / _pendingDiagnoseText 等），
// 行为与原内联实现完全一致，仅做物理拆分。
// ─────────────────────────────────────────────────────────────
// ignore_for_file: invalid_use_of_protected_member
part of 'writing_page.dart';

extension _WritingPageSelectionAi on _WritingPageState {
  /// B3 划词诊断：捕获选中文本 → 显示浮动菜单（对齐 RN onSelectionChange）
  /// 由 controller listener 触发（Flutter 3.44 TextField 无公共 onSelectionChanged）
  void _onControllerSelectionChanged() {
    // 批次84-2：查找替换定位是程序化选区，不算用户划词 → 不弹菜单
    if (_suppressSelectionMenu) return;
    final selection = _controller.selection;
    if (!selection.isValid || selection.start == selection.end) {
      setState(() {
        _selectedText = '';
        _selection = null;
        _showSelectionMenu = false;
        _selectionMenuPos = null;
      });
      return;
    }
    final text = _controller.text.substring(selection.start, selection.end);
    setState(() {
      _selectedText = text;
      _selection = selection;
      _showSelectionMenu = text.isNotEmpty;
      // 批次95-1：菜单跟随选区（RenderEditable 定位 + 屏幕外翻转）
      _selectionMenuPos = text.isNotEmpty
          ? _computeSelectionMenuPos(selection)
          : null;
    });
  }

  /// 批次95-1：划词菜单跟随选区——RenderEditable 取选区矩形 → Stack 局部坐标
  /// → 屏幕外翻转（下方放不下且上方有空间则翻到选区上方，纯纯/笔落跟随）
  /// 预估菜单尺寸用于翻转判断（4 项 + 分隔线，宽松取值）
  static const Size _selectionMenuSize = Size(150, 176);
  Offset? _computeSelectionMenuPos(TextSelection selection) {
    try {
      final stackCtx = _editorStackKey.currentContext;
      if (stackCtx == null) return null;
      final stackBox = stackCtx.findRenderObject();
      if (stackBox is! RenderBox || !stackBox.hasSize) return null;
      final editable = _findRenderEditable(stackCtx);
      if (editable == null) return null;
      final offset = selection.baseOffset.clamp(0, _controller.text.length);
      final rect = editable.getLocalRectForCaret(TextPosition(offset: offset));
      if (rect.size.isEmpty) return null;
      final local = stackBox.globalToLocal(
        editable.localToGlobal(rect.topLeft),
      );
      final maxLeft = (stackBox.size.width - _selectionMenuSize.width).clamp(
        0.0,
        stackBox.size.width,
      );
      final left = (local.dx - 8).clamp(0.0, maxLeft);
      const belowGap = 24.0;
      final below = local.dy + belowGap;
      final flipUp =
          below + _selectionMenuSize.height > stackBox.size.height &&
          local.dy > _selectionMenuSize.height;
      final top = flipUp ? local.dy - _selectionMenuSize.height - 8 : below;
      return Offset(left, top);
    } catch (_) {
      // 定位失败保守降级：不弹菜单（不抛错）
      return null;
    }
  }

  /// 在元素树中查找正文 EditableText 的 RenderEditable（取选区矩形用）
  RenderEditable? _findRenderEditable(BuildContext context) {
    if (context is StatefulElement && context.state is EditableTextState) {
      return (context.state as EditableTextState).renderEditable;
    }
    RenderEditable? result;
    context.visitChildElements((e) {
      result ??= _findRenderEditable(e);
    });
    return result;
  }

  /// B3 划词诊断：校验选中文本（≥20 字）→ 打开 AI 面板并注入选段诊断
  /// 对齐 RN handleDiagnoseSelection（选段下限 20 字）
  void _handleDiagnoseSelection() {
    final text = _selectedText.trim();
    if (text.isEmpty) {
      setState(() => _showSelectionMenu = false);
      return;
    }
    // ADR-C66：选段下限统一取自 UILimits（与写作面板的选段诊断同源）
    if (text.length < UILimits.diagnosisSelectionWordThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '请至少选择 ${UILimits.diagnosisSelectionWordThreshold} 字以上的文本进行诊断',
          ),
        ),
      );
      setState(() => _showSelectionMenu = false);
      return;
    }
    _injectToPanel(text);
  }

  /// 批次83：划词「改写这段」→ 择选弹层（生成 3 个版本可择选 + 换一换）
  void _handleRewriteSelection() {
    _openSelectionAi(SelectionAiMode.rewrite);
  }

  /// 批次83：划词「续写这段」→ 择选弹层（续写走向可择选）
  void _handleContinueSelection() {
    _openSelectionAi(SelectionAiMode.continueWrite);
  }

  /// 批次83：划词「扩写这段」→ 择选弹层（扩写版本可择选）
  void _handleExpandSelection() {
    _openSelectionAi(SelectionAiMode.expand);
  }

  /// 批次83：打开择选弹层（≥10 字拦截；改写/续写/扩写共用）
  void _openSelectionAi(SelectionAiMode mode) {
    final text = _selectedText.trim();
    if (text.isEmpty) {
      setState(() => _showSelectionMenu = false);
      return;
    }
    // ADR-C66：门槛取自 UILimits
    if (text.length < UILimits.selectionAiWordThreshold) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请至少选择 ${UILimits.selectionAiWordThreshold} 字以上的文本'),
        ),
      );
      setState(() => _showSelectionMenu = false);
      return;
    }
    setState(() => _showSelectionMenu = false);
    SelectionAiSheet.show(
      context,
      mode: mode,
      selectedText: text,
      onAdopt: (chosen) => _adoptAiVersion(mode, chosen),
    );
  }

  /// 批次83：择选「用这个」→ 按模式落稿（替换选区 / 插入选区后）+ 保存
  void _adoptAiVersion(SelectionAiMode mode, String chosen) {
    final selection = _selection;
    if (selection == null ||
        !selection.isValid ||
        selection.end > _controller.text.length) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('选中的内容好像变了，重新选一下试试')));
      }
      return;
    }
    final current = _controller.text;
    final int start = selection.start;
    final int end = selection.end;
    final String newText;
    final int cursor;
    if (mode == SelectionAiMode.continueWrite) {
      // 续写：插到选中文本之后
      newText = current.replaceRange(end, end, chosen);
      cursor = end + chosen.length;
    } else {
      // 改写/扩写：替换选中文本
      newText = current.replaceRange(start, end, chosen);
      cursor = start + chosen.length;
    }
    _controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _onContentChanged(newText);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            mode == SelectionAiMode.continueWrite ? '已续写这段' : '已更新这段文字',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  /// B3 划词诊断：注入面板（诊断文本）并打开面板
  /// 一次性消费：下一帧面板已捕获后立即清空，防止关闭再打开时重复触发
  void _injectToPanel(String diagnoseText) {
    setState(() {
      _showSelectionMenu = false;
      _pendingDiagnoseText = diagnoseText;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingDiagnoseText != null) {
        setState(() => _pendingDiagnoseText = null);
      }
    });
    // 打开 AI 面板（已打开则仅注入，由面板 didUpdateWidget 触发）
    final isOpen = ref
        .read(writingStoreProvider(widget.chapterId))
        .isAiPanelOpen;
    if (!isOpen) {
      ref.read(writingStoreProvider(widget.chapterId).notifier).toggleAiPanel();
    }
  }
}
