// ─────────────────────────────────────────────────────────────
// WritingPageControllers — 控制器聚合（C92-6b）
//
// 组装层（view/writing_page_scaffold.dart、view/writing_page_menu_actions.dart）
// 通过本聚合拿到全部控制器实例；控制器之间**不互相 import 宿主以外的库**，
// 需要协同时由本聚合在构造处显式注入（依赖图为无环 DAG，见各控制器文件头）。
//
// 依赖顺序（构造序即注入序）：
//   selectionAi / document / fab / chapterNav  ← 只依赖 host
//   findReplace ← chapterNav
//   status      ← document
//   storeSync   ← document + status
// ─────────────────────────────────────────────────────────────

import '../writing_page_host.dart';
import 'writing_page_chapter_nav_controller.dart';
import 'writing_page_document_controller.dart';
import 'writing_page_fab_controller.dart';
import 'writing_page_find_replace_controller.dart';
import 'writing_page_selection_ai_controller.dart';
import 'writing_page_status_controller.dart';
import 'writing_page_store_sync_controller.dart';

class WritingPageControllers {
  WritingPageControllers(WritingPageHost host) {
    selectionAi = WritingPageSelectionAiController(host);
    document = WritingPageDocumentController(host);
    fab = WritingPageFabController(host);
    chapterNav = WritingPageChapterNavController(host);
    findReplace = WritingPageFindReplaceController(host, chapterNav);
    status = WritingPageStatusController(host, document);
    storeSync = WritingPageStoreSyncController(host, document, status);
  }

  late final WritingPageSelectionAiController selectionAi;
  late final WritingPageDocumentController document;
  late final WritingPageFabController fab;
  late final WritingPageChapterNavController chapterNav;
  late final WritingPageFindReplaceController findReplace;
  late final WritingPageStatusController status;
  late final WritingPageStoreSyncController storeSync;
}
