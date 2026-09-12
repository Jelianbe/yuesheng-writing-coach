// ─────────────────────────────────────────────────────────────
// WritingPageSelectionAiController — 划词 AI 控制器（C92-6b）
//
// 来源：原 `writing_page_selection_ai.dart`（part + extension 伪拆分）。
// 覆盖批次82/95-1 的 B3 划词诊断（R-009：不代写，仅诊断）。
//
// ⚠️ 搬迁约束：本文件必须保持**选段门槛常量的两处引用同处一个文件**
//   （`diagnosis_word_threshold_test.dart` 按「门槛文件数守恒」断言，
//   拆散到多个文件会误报；引用名称见下方代码）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderBox, RenderEditable;

import '../../../config/shared_constants.dart';
import '../../../providers/writing_providers.dart';
import '../writing_page_host.dart';

class WritingPageSelectionAiController {
  WritingPageSelectionAiController(this._host);

  final WritingPageHost _host;

  /// 预估菜单尺寸用于翻转判断（1 项：诊断，宽松取值）
  static const Size _selectionMenuSize = Size(150, 176);

  /// B3 划词诊断：捕获选中文本 → 显示浮动菜单（对齐 RN onSelectionChange）
  /// 由 controller listener 触发（Flutter 3.44 TextField 无公共 onSelectionChanged）
  void onSelectionChanged() {
    // 批次84-2：查找替换定位是程序化选区，不算用户划词 → 不弹菜单
    if (_host.suppressSelectionMenu) return;
    final selection = _host.editorController.selection;
    if (!selection.isValid || selection.start == selection.end) {
      _host.hostSetState(() {
        _host.selectedText = '';
        _host.showSelectionMenu = false;
        _host.selectionMenuPos = null;
      });
      return;
    }
    final text = _host.editorController.text.substring(
      selection.start,
      selection.end,
    );
    _host.hostSetState(() {
      _host.selectedText = text;
      _host.showSelectionMenu = text.isNotEmpty;
      // 批次95-1：菜单跟随选区（RenderEditable 定位 + 屏幕外翻转）
      _host.selectionMenuPos = text.isNotEmpty
          ? _computeSelectionMenuPos(selection)
          : null;
    });
  }

  /// 批次95-1：划词菜单跟随选区——RenderEditable 取选区矩形 → Stack 局部坐标
  /// → 屏幕外翻转（下方放不下且上方有空间则翻到选区上方，纯纯/笔落跟随）
  Offset? _computeSelectionMenuPos(TextSelection selection) {
    try {
      final stackCtx = _host.editorStackKey.currentContext;
      if (stackCtx == null) return null;
      final stackBox = stackCtx.findRenderObject();
      if (stackBox is! RenderBox || !stackBox.hasSize) return null;
      final editable = _findRenderEditable(stackCtx);
      if (editable == null) return null;
      final offset = selection.baseOffset.clamp(
        0,
        _host.editorController.text.length,
      );
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
  void handleDiagnoseSelection() {
    final text = _host.selectedText.trim();
    if (text.isEmpty) {
      _host.hostSetState(() => _host.showSelectionMenu = false);
      return;
    }
    // ADR-C66：选段下限统一取自 UILimits（与写作面板的选段诊断同源）
    if (text.length < UILimits.diagnosisSelectionWordThreshold) {
      ScaffoldMessenger.of(_host.context).showSnackBar(
        const SnackBar(
          content: Text(
            '请至少选择 ${UILimits.diagnosisSelectionWordThreshold} 字以上的文本进行诊断',
          ),
        ),
      );
      _host.hostSetState(() => _host.showSelectionMenu = false);
      return;
    }
    _injectToPanel(text);
  }

  /// B3 划词诊断：注入面板（诊断文本）并打开面板
  /// 一次性消费：下一帧面板已捕获后立即清空，防止关闭再打开时重复触发
  void _injectToPanel(String diagnoseText) {
    _host.hostSetState(() {
      _host.showSelectionMenu = false;
      _host.pendingDiagnoseText = diagnoseText;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_host.mounted && _host.pendingDiagnoseText != null) {
        _host.hostSetState(() => _host.pendingDiagnoseText = null);
      }
    });
    // 打开 AI 面板（已打开则仅注入，由面板 didUpdateWidget 触发）
    final isOpen = _host.ref
        .read(writingStoreProvider(_host.chapterId))
        .isAiPanelOpen;
    if (!isOpen) {
      _host.ref
          .read(writingStoreProvider(_host.chapterId).notifier)
          .toggleAiPanel();
    }
  }
}
