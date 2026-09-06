// ─────────────────────────────────────────────────────────────
// app_routes — 路由名称常量（独立叶子模块）
//
// 独立成文件的原因（R-020 循环依赖零容忍）：
//   路由常量被 router 与 widgets 双向消费。若常量留在 app_router.dart，
//   widget 为取常量被迫 import 整个 router，而 router 又必须 import
//   widget 页面类型 → 形成 app_router ↔ widgets/* 循环依赖。
//   提取到独立文件后，本模块不 import 任何业务模块，是纯叶子节点，
//   router 与 widgets 均只依赖常量文件，依赖图恢复 DAG。
// ─────────────────────────────────────────────────────────────

/// 路由名称常量
class AppRoutes {
  static const String bookshelf = '/bookshelf';
  static const String writing = '/';
  static const String growth = '/growth';
  static const String growthDetail = '/growth-detail';
  static const String chat = '/chat';
  static const String manuscriptDetail = '/manuscript-detail';
  static const String writingChapter = '/writing/:chapterId';
  static const String settings = '/settings';
  static const String appendChapters = '/append-chapters';
  static const String projectSettings = '/project-settings';
  static const String progressDetail = '/progress-detail';
  static const String chapterRecycleBin = '/chapter-recycle-bin';

  /// C78 批次3：角色页（FR-10 提示卡深链入口；写作页 ⋮ 菜单走 Navigator.push）
  static const String characters = '/characters';
}
