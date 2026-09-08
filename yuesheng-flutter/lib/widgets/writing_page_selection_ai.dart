// ─────────────────────────────────────────────────────────────
// writing_page 的 part 文件：划词 AI 相关逻辑
// 覆盖批次82/95-1 的 B3 划词诊断（R-009：不代写，仅诊断）。
// 以私有 extension on _WritingPageState 形式提供划词 AI 方法，
// 直接访问宿主私有成员（_controller / _selectedText /
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
        _showSelectionMenu = false;
        _selectionMenuPos = null;
      });
      return;
    }
    final text = _controller.text.substring(selection.start, selection.end);
    setState(() {
      _selectedText = text;
      _showSelectionMenu = text.isNotEmpty;
      // 批次95-1：菜单跟随选区（RenderEditable 定位 + 屏幕外翻转）
      _selectionMenuPos = text.isNotEmpty
          ? _computeSelectionMenuPos(selection)
          : null;
    });
  }

  /// 批次95-1：划词菜单跟随选区——RenderEditable 取选区矩形 → Stack 局部坐标
  /// → 屏幕外翻转（下方放不下且上方有空间则翻到选区上方，纯纯/笔落跟随）
  /// 预估菜单尺寸用于翻转判断（1 项：诊断，宽松取值）
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
