// ─────────────────────────────────────────────────────────────
// writing_page 菜单动作（C92-6b）
//
// 来源：原宿主 `writing_page.dart` 的 ⋮ 菜单与各弹层入口
// （C92-6b 首版曾为「菜单控制器」，因它天然需要同时调用文档/导航/FAB/查找
//  多个控制器，会引入控制器间循环依赖，改置于**组装层**的顶层函数）。
//
// 说明：本文件属组装层（与 scaffold 同层），可自由访问宿主与全部控制器，
// 不构成控制器之间的依赖环。每个函数均受 R-019「≤50 行」约束。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/app_state_repository.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/manuscript_providers.dart';
import '../../../providers/writing_providers.dart';
import '../../character/character_page.dart';
import '../../editor_settings_sheet.dart';
import '../../quick_phrase_sheet.dart';
import '../../recycle_bin_sheet.dart';
import '../../style_profile_sheet.dart';
import '../../version_time_machine_sheet.dart';
import '../../writing_menu_sheet.dart';
import '../../writing_stats_sheet.dart';
import '../controllers/writing_page_controllers.dart';
import '../writing_page_host.dart';

/// 返回上一页（批次93-3：返回前发书架刷新信号）
void handleWritingBack(WritingPageHost host) {
  host.ref.read(bookshelfRefreshSignalProvider.notifier).state++;
  final onBack = host.onBackCallback;
  if (onBack != null) {
    onBack();
  } else {
    Navigator.of(host.context).maybePop();
  }
}

/// 批次85-3：打开快捷短语弹层（常用语管理 + 光标插入）
void openQuickPhrases(WritingPageHost host, WritingPageControllers c) {
  QuickPhraseSheet.show(host.context, onInsert: c.document.insertQuickPhrase);
}

/// 批次86-1：打开回收板弹层（删除/剪切的长文本找回）
void openRecycleBin(WritingPageHost host, WritingPageControllers c) {
  RecycleBinSheet.show(host.context, onRestore: c.document.insertQuickPhrase);
}

/// 批次85-4：打开当前文风弹层（教学特色：风格画像五维展示）
void openStyleProfile(WritingPageHost host) {
  StyleProfileSheet.show(host.context);
}

/// 批次85-5：打开写作统计弹层（近 14 天写作曲线）
void openWritingStats(WritingPageHost host) {
  WritingStatsSheet.show(host.context);
}

/// C78 批次3：打开角色页（ADR-C78 §3.0：MaterialPageRoute 独立路由页，
/// 不用 Sheet / 不复用面板槽位——isAiPanelOpen / toggleAiPanel 语义
/// 已被 writing_providers_test.dart:85,173-200 锁死，本入口零接触）
void openCharacters(WritingPageHost host) {
  final manuscriptId = host.resolvedManuscriptId;
  if (manuscriptId == null || manuscriptId.isEmpty) {
    ScaffoldMessenger.of(host.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('章节加载中，请稍后再试')));
    return;
  }
  Navigator.push(
    host.context,
    MaterialPageRoute<void>(
      builder: (_) => CharacterPage(manuscriptId: manuscriptId),
    ),
  );
}

/// ⋮ 菜单：读取用户记忆的篇幅占比 → 打开 WritingMenuSheet（各入口回调分发）
Future<void> showWritingMenu(
  WritingPageHost host,
  WidgetRef ref,
  WritingPageControllers c,
  WritingState state,
) async {
  // E3：移除「开发中」占位菜单项，菜单只保留真实功能（保存状态 + 打开教练面板）
  // 批次79 B：「诊断本章」改名「打开教练面板」——原行为仅展开面板不诊断
  // 批次96-7：拖拽调整篇幅——打开前读取用户记忆的高度占比，松手后落库
  final menuRepo = AppStateRepository(ref.read(appDatabaseProvider));
  final menuHeight = await menuRepo.getEditorMenuHeight();
  if (!host.context.mounted) return;
  WritingMenuSheet.show(
    host.context,
    lastSavedAt: state.lastSavedAt,
    initialHeight: menuHeight,
    onHeightChanged: (h) => menuRepo.setEditorMenuHeight(h),
    onDiagnose: c.fab.toggleAiPanel,
    // 批次83：章节树抽屉入口（卷-章列表 + 快速跳转 + 新建章）
    onOpenChapterTree: c.chapterNav.handleOpenChapterTree,
    // 批次83：大纲边写边看入口（右侧抽屉）
    onOpenOutline: c.chapterNav.handleOpenOutline,
    // C78 批次3：角色页入口（独立路由页）
    onOpenCharacters: () => openCharacters(host),
    // 批次96-11：全文搜索入口（整本作品章节搜索 + 跳转定位）
    onOpenFullTextSearch: c.findReplace.openFullTextSearch,
    // 批次84-2：全文查找替换入口
    onOpenFindReplace: c.findReplace.openFindReplace,
    // 批次86-1：回收板入口（删除/剪切长文本找回）
    onOpenRecycleBin: () => openRecycleBin(host, c),
    // 批次85-3：快捷短语入口（常用语管理 + 光标插入）
    onOpenQuickPhrases: () => openQuickPhrases(host, c),
    // 批次85-4：当前文风展示入口（风格画像五维）
    onOpenStyleProfile: () => openStyleProfile(host),
    // 批次85-5：写作统计入口（近 14 天写作曲线）
    onOpenWritingStats: () => openWritingStats(host),
    // 批次96-9：三个开关（行段聚焦/智能标点/对话按钮）已移入排版设置
    onOpenSettings: () => showEditorSettings(host, c),
    onOpenVersions: () => showVersionTimeMachine(host, c),
  );
}

/// 批次82：排版设置入口（字号/行距/背景 + 三开关，用户级持久化）
void showEditorSettings(WritingPageHost host, WritingPageControllers c) {
  EditorSettingsSheet.show(
    host.context,
    chapterId: host.chapterId,
    // 批次88-2：对话按钮位置恢复入口
    onResetFabPosition: c.fab.resetFabPosition,
    // 批次88-4：段落格式批量应用（按开关状态）
    onApplyParagraphFormat: c.document.applyParagraphFormat,
  );
}

/// 批次82：版本时光机入口（每 200 字快照，查看/恢复）
/// 批次84-3：传入当前内容 → 详情差异对比基准
void showVersionTimeMachine(WritingPageHost host, WritingPageControllers c) {
  VersionTimeMachineSheet.show(
    host.context,
    chapterId: host.chapterId,
    currentContent: host.editorController.text,
    onRestore: c.document.restoreVersion,
  );
}
