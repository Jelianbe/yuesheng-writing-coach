// ─────────────────────────────────────────────────────────────
// WritingPageScaffold — 写作页组装层（C92-6b）
//
// 来源：宿主 `writing_page.dart` 外迁的组装逻辑（Scaffold 骨架 / body 三态 /
// 编辑器与教练面板并排或底部抽屉 / 拖动 FAB / AppBar / 面板）。
// 说明：控制器（controllers/）负责行为，本层只负责「把状态与回调装配成 Widget 树」，
// 宿主 State 只保留字段、生命周期与 `build` 入口。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_theme.dart';
import '../../../config/editor_background_presets.dart';
import '../../../providers/writing_providers.dart';
import '../../../services/suggestion_adoption_service.dart';
import '../../writing_coach_panel.dart';
import '../controllers/writing_page_controllers.dart';
import '../writing_page_host.dart';
import 'writing_editor_view.dart';
import 'writing_page_app_bar.dart';
import 'writing_page_breadcrumb.dart';
import 'writing_page_chrome.dart';
import 'writing_page_menu_actions.dart';
import 'writing_status_views.dart';

class WritingPageScaffold extends ConsumerWidget {
  const WritingPageScaffold({
    super.key,
    required this.host,
    required this.controllers,
    required this.state,
  });

  final WritingPageHost host;
  final WritingPageControllers controllers;
  final WritingState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      key: host.scaffoldKey,
      // 批次 X-037-P0-1 H4/C1：正文壳与当前预设配平，暗夜用 editorDarkSurface 令牌（WCAG AA 可达）
      backgroundColor: isDarkEditorPreset(state.editorBackground)
          ? AppColors.editorDarkSurface
          : AppColors.background,
      // 批次83：章节树抽屉（每次打开以新 key 重建 → 列表/标题保持最新）
      drawer: controllers.chapterNav.buildChapterTreeDrawer(),
      onDrawerChanged: controllers.chapterNav.handleDrawerChanged,
      // 批次83：大纲边写边看（右侧抽屉；每次打开重建 + 失效缓存）
      endDrawer: controllers.chapterNav.buildOutlineDrawer(),
      onEndDrawerChanged: controllers.chapterNav.handleEndDrawerChanged,
      appBar: _buildAppBar(ref),
      // 批次88-2：对话按钮从 Scaffold FAB 改为 body Stack 内可拖动浮层
      // （长按拖动换位 + 松手持久化；⋮ 菜单可隐藏/显示，隐藏后菜单找回）
      body: _buildBody(context),
    );
  }

  /// 正文区（三态：加载中 / 失败 / 编辑器+面板），对话按钮浮层叠加其上
  Widget _buildBody(BuildContext context) {
    final showFab =
        !state.isLoading &&
        state.error == null &&
        !state.isAiPanelOpen &&
        state.fabVisible;
    return LayoutBuilder(
      builder: (context, constraints) {
        final area = constraints.biggest;
        return Stack(
          children: [
            Positioned.fill(child: _buildMainContent(context)),
            if (showFab) _buildDraggableFab(area),
          ],
        );
      },
    );
  }

  Widget _buildMainContent(BuildContext context) {
    if (state.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    if (state.error != null) {
      return WritingErrorView(
        message: state.error!,
        onRetry: () {
          host.ref
              .read(writingStoreProvider(host.chapterId).notifier)
              .loadChapter();
        },
      );
    }
    // 批次82 P0-④：面板不再以 bottomSheet 半屏覆盖正文；
    // 改为右侧可收起侧栏（Row 并排），正文永远可见可编辑
    return _buildEditorWithPanel(context);
  }

  /// 批次88-2：对话按钮浮层（长按拖动 + 点击开合面板）
  Widget _buildDraggableFab(Size area) {
    final size = controllers.fab.fabSize;
    return WritingDraggableFab(
      left: host.fabOffset?.dx ?? (area.width - size - 16),
      top: host.fabOffset?.dy ?? (area.height - size - 16),
      isPanelOpen: state.isAiPanelOpen,
      onDragStart: (globalPosition) =>
          controllers.fab.handleFabDragStart(globalPosition, area),
      onDragUpdate: (globalPosition) =>
          controllers.fab.handleFabDragUpdate(globalPosition, area),
      onDragEnd: controllers.fab.handleFabDragEnd,
      onPressed: controllers.fab.toggleAiPanel,
    );
  }

  /// 批次82 P0-④：正文 + 右侧可收起教练侧栏（并排，正文不被覆盖）
  /// 批次95-2：窄屏（<600dp）改为底部抽屉式覆盖（纯纯侧栏划开非常驻），
  /// 避免 280px 侧栏在手机窄屏挤压正文；宽屏维持 Row 并排
  Widget _buildEditorWithPanel(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    if (!isNarrow) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildEditor()),
          if (state.isAiPanelOpen)
            SizedBox(
              width: _panelWidth(context),
              child: _buildAiPanel(context),
            ),
        ],
      );
    }
    return Stack(
      children: [
        Positioned.fill(child: _buildEditor()),
        if (state.isAiPanelOpen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.sizeOf(context).height * 0.75,
            child: Material(
              color: AppColors.background,
              elevation: 8,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildAiPanel(context),
            ),
          ),
      ],
    );
  }

  /// 侧栏宽度：屏宽 55%，下限 280（手机窄屏仍可容纳对话），上限 480（平板）
  double _panelWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return (w * 0.55).clamp(280.0, 480.0).toDouble();
  }

  /// 编辑器主体（视图层独立类：离线横幅 / 标题 / 正文 / 划词菜单 / 保存状态条 / 标点栏）
  Widget _buildEditor() {
    return WritingEditorView(
      state: state,
      titleController: host.titleController,
      contentController: host.editorController,
      focusNode: host.focusNode,
      editorStackKey: host.editorStackKey,
      punctBarIds: host.punctBarIds,
      punctCustomItems: host.punctCustomItems,
      showSelectionMenu: host.showSelectionMenu,
      selectionMenuPos: host.selectionMenuPos,
      onTitleChanged: controllers.document.onTitleChanged,
      onContentChanged: controllers.document.onContentChanged,
      onDiagnoseSelection: controllers.selectionAi.handleDiagnoseSelection,
      onUndo: controllers.document.undo,
      onRedo: controllers.document.redo,
      onPunctuationTap: controllers.document.handlePunctuationTap,
    );
  }

  /// AppBar（视图层独立类：返回 / 面包屑 / 字数指示 / 一键排版 / ⋮ 菜单）
  PreferredSizeWidget _buildAppBar(WidgetRef ref) {
    // 批次 X-037-P0-1 C1：暗夜色走 AppColors.editorDark* 令牌
    final darkUi = isDarkEditorPreset(state.editorBackground);
    final fg = darkUi ? AppColors.editorDarkText : AppColors.textPrimary;
    final muted = darkUi ? AppColors.editorDarkMuted : AppColors.textSecondary;
    return WritingPageAppBar(
      darkUi: darkUi,
      foregroundColor: fg,
      goalWords: state.goalWords,
      breadcrumb: WritingPageBreadcrumb(
        title: state.chapter?.title ?? host.widgetChapterTitle,
        volumeId: state.chapter?.volumeId,
        manuscriptId: host.resolvedManuscriptId,
        color: fg,
      ),
      progressBar: WritingGoalProgressBar(
        goalWords: state.goalWords,
        wordCount: state.wordCount,
        darkUi: darkUi,
      ),
      wordCount: WritingWordCountIndicator(
        goalWords: state.goalWords,
        wordCount: state.wordCount,
        mutedColor: muted,
        onTap: controllers.status.showGoalDialog,
      ),
      onBack: () => handleWritingBack(host),
      onFormatChapter: controllers.document.handleFormatChapter,
      onOpenMenu: () => showWritingMenu(host, ref, controllers, state),
    );
  }

  Widget _buildAiPanel(BuildContext context) {
    final st = host.ref.read(writingStoreProvider(host.chapterId));
    // 批次6（6.9 C2）：挂 ValueKey(chapterId) 强制章节切换时重建 Panel State，
    // 防滚动位置/选区/草稿跨章节泄漏
    return WritingCoachPanel(
      key: ValueKey(host.chapterId),
      chapterId: host.chapterId,
      manuscriptId: host.widgetManuscriptId ?? '',
      chapterTitle: st.chapter?.title ?? host.widgetChapterTitle ?? '',
      // B3 划词诊断：注入选中文本（面板打开后自动触发选段诊断）
      pendingDiagnoseText: host.pendingDiagnoseText,
      onClose: controllers.fab.toggleAiPanel,
      onAdopt: (suggestion) {
        // 批次5（5.1）：采纳动作收敛单一 service（suggestion_adoption_service）
        adoptSuggestionToChapter(
          context,
          chapterId: host.chapterId,
          suggestion: suggestion,
          onAdopted: () async {
            // 采纳/撤销后刷新 store + 同步编辑器
            await host.ref
                .read(writingStoreProvider(host.chapterId).notifier)
                .loadChapter();
            if (!host.mounted) return;
            final newContent = host.ref
                .read(writingStoreProvider(host.chapterId))
                .localContent;
            if (host.editorController.text != newContent) {
              controllers.document.syncEditorText(newContent);
            }
            host.dirty = false;
          },
        );
      },
    );
  }
}
