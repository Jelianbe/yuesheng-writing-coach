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

import '../../config/shared_constants.dart';
import '../../data/repositories/record_entry_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/writing_providers.dart';
import '../manuscript/remember_entry_sheet.dart';
import 'writing_page_host.dart';

class WritingPageSelectionAiController {
  WritingPageSelectionAiController(this._host);

  final WritingPageHost _host;

  /// B3 划词诊断：捕获选中文本（供系统选择菜单的「引用诊断/存入设定库」消费）。
  /// 菜单本身自 2026-11-22 起由 TextField.contextMenuBuilder 接管，见
  /// `writing_selection_context_menu.dart`。
  /// 由 controller listener 触发（Flutter 3.44 TextField 无公共 onSelectionChanged）
  void onSelectionChanged() {
    // 2026-11-22：选择菜单统一改由 TextField.contextMenuBuilder 接管
    // （系统 toolbar 自动锚定 + 键盘避让）。本 listener 只保留 selectedText
    // 记录——系统菜单里「引用诊断 / 存入设定库」按钮消费的就是这份文本。
    // 旧 overlay 的 showSelectionMenu / selectionMenuPos 计算已移除：
    //   · 不再手写 RenderEditable 定位（避免键盘弹起位置陈旧导致遮挡）；
    //   · 不再与系统 cut/copy/share 菜单并存（消除多选弹窗）。
    final selection = _host.editorController.selection;
    if (!selection.isValid || selection.start == selection.end) {
      if (_host.selectedText.isNotEmpty) {
        _host.hostSetState(() => _host.selectedText = '');
      }
      return;
    }
    final text = _host.editorController.text.substring(
      selection.start,
      selection.end,
    );
    if (text != _host.selectedText) {
      _host.hostSetState(() => _host.selectedText = text);
    }
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

  /// C147：划词菜单「存入设定库」→ 确认卡（选段整段可编辑 + 作者自选归入位置）
  /// → proposePending 落 record_entry.pending（与聊天「记一下」同一两级裁决链）。
  /// R-009：选段原样搬运进可编辑框，位置作者自选；AI 不替作者定性。
  Future<void> handleSaveSelectionToLibrary() async {
    final text = _host.selectedText.trim();
    final manuscriptId = _host.resolvedManuscriptId;
    _host.hostSetState(() => _host.showSelectionMenu = false);
    if (text.isEmpty) return;
    if (manuscriptId == null || manuscriptId.isEmpty) {
      ScaffoldMessenger.of(
        _host.context,
      ).showSnackBar(const SnackBar(content: Text('未关联作品，无法存入设定库')));
      return;
    }
    final result = await showRememberEntrySheet(
      _host.context,
      initialExcerpt: text,
    );
    if (result == null) return;
    await RecordEntryRepository(
      _host.ref.read(appDatabaseProvider),
    ).proposePending(
      manuscriptId: manuscriptId,
      excerpt: result.excerpt,
      targetSection: result.targetSection,
    );
    if (!_host.mounted) return;
    ScaffoldMessenger.of(
      _host.context,
    ).showSnackBar(const SnackBar(content: Text('已存入设定库待整理')));
  }
}
