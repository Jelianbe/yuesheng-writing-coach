// ─────────────────────────────────────────────────────────────
// WritingPageHost — 写作页宿主能力接口（C92-6b 伪拆分清偿）
//
// 背景：`writing_page.dart` 曾以 4 条 `part` + `extension on _WritingPageState`
// 的形态把逻辑物理拆到外部文件，属**伪拆分**（R-019 禁 part/extension）。
// C92-6b 将其真分解为 7 个独立控制器：控制器只依赖本接口访问宿主 State 的
// 能力与共享状态，宿主不再以 extension 暴露实现。
//
// ⚠️ 依赖方向（门禁 3「循环依赖扫描」硬约束）：
//   本文件**只暴露宿主能力与共享状态，绝不 import / 暴露任何控制器**。
//   控制器之间需要协同时：① 由宿主在构造函数里显式注入对方实例（无回边时）；
//   ② 或经本接口的抽象方法（如 [locateCursor] / [onContentChanged]）转发。
//   组装层（view/writing_page_scaffold.dart + view/writing_page_menu_actions.dart）
//   通过 `WritingPageControllers` 聚合拿到全部控制器实例。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/writing_providers.dart';
import '../editing/focus_aware_editing_controller.dart';
import '../punctuation_bar.dart';

/// 写作页宿主能力（由 `_WritingPageState` 实现）。
///
/// 命名约定：字段型「可变状态」用同名 getter + setter。
abstract interface class WritingPageHost {
  // ── 基础能力 ────────────────────────────────────────────────
  BuildContext get context;
  bool get mounted;
  WidgetRef get ref;

  /// 转发 [State.setState]（控制器无法直接调用 protected 成员）。
  void hostSetState(VoidCallback fn);

  // ── widget 入参 ─────────────────────────────────────────────
  String get chapterId;
  String? get widgetManuscriptId;
  String? get widgetChapterTitle;
  int? get initialCursorOffset;
  void Function(String chapterId, String chapterTitle)?
  get onJumpToChapterCallback;

  /// 宿主可选的返回回调（null = 走 `Navigator.maybePop`）。
  VoidCallback? get onBackCallback;

  /// 所属作品 ID（优先路由参数，其次已加载章节反查）。
  String? get resolvedManuscriptId;

  // ── 生命周期资源 ────────────────────────────────────────────
  /// 正文编辑控制器（`FocusAwareEditingController`：带行段聚焦淡化开关）。
  FocusAwareEditingController get editorController;
  TextEditingController get titleController;
  FocusNode get focusNode;
  GlobalKey get editorStackKey;
  GlobalKey<ScaffoldState> get scaffoldKey;
  WritingStore? get store;
  void setStore(WritingStore store);

  // ── 共享可变状态 ────────────────────────────────────────────
  bool get dirty;
  set dirty(bool value);

  bool get suppressSelectionMenu;
  set suppressSelectionMenu(bool value);

  String get selectedText;
  set selectedText(String value);

  bool get showSelectionMenu;
  set showSelectionMenu(bool value);

  Offset? get selectionMenuPos;
  set selectionMenuPos(Offset? value);

  String? get pendingDiagnoseText;
  set pendingDiagnoseText(String? value);

  String? get lastEditorText;
  set lastEditorText(String? value);

  bool get goalCelebrated;
  set goalCelebrated(bool value);

  Offset? get fabOffset;
  set fabOffset(Offset? value);

  int get treeOpenCount;
  set treeOpenCount(int value);

  int get outlineOpenCount;
  set outlineOpenCount(int value);

  bool get searchCursorLocated;
  set searchCursorLocated(bool value);

  bool get draftDialogShown;
  set draftDialogShown(bool value);

  bool get saveErrorShown;
  set saveErrorShown(bool value);

  List<String>? get punctBarIds;
  List<PunctuationItem> get punctCustomItems;

  /// 标点栏配置加载完成 → 一次性写入（原 `setState` 内的成对赋值）。
  void setPunctuationConfig({
    required List<String>? ids,
    required List<PunctuationItem> items,
  });

  // ── 跨控制器共享的编辑器操作（由宿主统一实现，避免控制器互相 import）──
  /// 批次96-11：跨章全文搜索定位 → 光标折叠定位到命中处（程序化选区不弹划词菜单）。
  void locateCursor(int offset);

  /// 编辑器内容变更（由文档控制器实现，供查找替换等复用）。
  void onContentChanged(String content);
}
