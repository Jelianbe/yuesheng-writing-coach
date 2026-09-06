// ─────────────────────────────────────────────────────────────
// app_router — go_router 路由配置
// 复刻 yuesheng-android/src/app/_layout.tsx + (tabs)/_layout.tsx
//
//   结构：
//   StatefulShellRoute.indexedStack (3 Tab 分支)
//   ├── Branch A 书架 /bookshelf（默认 Tab）
//   ├── Branch B 对话 / (ChatPage，C2 改造)
//   └── Branch C 成长 /growth
//   顶层：/chat（重定向到 Tab2，保留深链入口）
//
// C2 改造后：
//   - 默认 Tab 改为书架（initialLocation = /bookshelf）
//   - Tab2 从"写作"占位页改为"对话"（ChatPage）
//   - /chat 顶层路由重定向到 Tab2
//   - 写作入口走 书架→作品详情→/writing/:chapterId
//   - 成长 Tab 仍用占位页
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_motion.dart';
import '../config/app_theme.dart';
import '../widgets/bookshelf_page.dart';
import '../widgets/chat_page.dart';
import '../widgets/append_chapters_page.dart';
import '../widgets/character/character_page.dart';
import '../widgets/chapter_recycle_bin_page.dart';
import '../widgets/growth_detail_page.dart';
import '../widgets/growth_page.dart';
import '../widgets/manuscript_detail_page.dart';
import '../widgets/placeholder_page.dart';
import '../widgets/progress_detail_page.dart';
import '../widgets/project_settings_page.dart';
import '../widgets/settings_page.dart';
import '../widgets/writing_page.dart';
import 'app_routes.dart';

/// go_router 配置
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoutes.bookshelf,
  errorBuilder: (context, state) => Scaffold(
    appBar: AppBar(title: const Text('页面未找到')),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
          const SizedBox(height: 16),
          Text('路径 ${state.uri.path} 不存在'),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.go(AppRoutes.writing),
            child: const Text('返回首页'),
          ),
        ],
      ),
    ),
  ),
  routes: [
    // ── 顶层路由：/chat（重定向到 Tab2，保留深链入口）──
    // C2 改造：/chat 不再独立渲染，重定向到 Tab2（路径 /）
    // 通知/外部链接点击 /chat 时仍能落到对话页
    GoRoute(
      path: AppRoutes.chat,
      redirect: (context, state) => AppRoutes.writing,
    ),

    // ── 顶层路由：/manuscript-detail（批次 B 实现）──
    GoRoute(
      path: AppRoutes.manuscriptDetail,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final manuscriptId =
            extra['manuscriptId'] as String? ??
            state.uri.queryParameters['id'] ??
            '';
        final title = extra['title'] as String?;
        if (manuscriptId.isEmpty) {
          return const PlaceholderPage(title: '作品详情', subtitle: '未提供作品 ID');
        }
        return ManuscriptDetailPage(
          args: ManuscriptDetailArgs(manuscriptId: manuscriptId, title: title),
        );
      },
    ),

    // ── 顶层路由：/writing/:chapterId（章节写作页）──
    GoRoute(
      path: AppRoutes.writingChapter,
      builder: (context, state) {
        final chapterId = state.pathParameters['chapterId'] ?? '';
        final extra = state.extra as Map<String, dynamic>?;
        final manuscriptId = extra?['manuscriptId'] as String? ?? '';
        final chapterTitle = extra?['chapterTitle'] as String?;
        // 批次96-11：全文搜索跨章跳转携带的光标定位偏移（章节加载后定位命中处）
        final cursorOffset = extra?['cursorOffset'] as int?;
        // 批次83：同路由切章（章节树跳转）时以 ValueKey(chapterId) 强制
        // 重建 State，否则 widget 复用旧 State、新章节不会 loadChapter
        return WritingPage(
          key: ValueKey(chapterId),
          chapterId: chapterId,
          chapterTitle: chapterTitle,
          manuscriptId: manuscriptId,
          initialCursorOffset: cursorOffset,
          onBack: () {
            // P0-1 修复：返回作品详情时必须带回 manuscriptId extra，
            // 否则 ManuscriptDetail 路由拿不到 manuscriptId，进入"未提供作品ID"占位页
            context.go(
              AppRoutes.manuscriptDetail,
              extra: <String, dynamic>{
                'manuscriptId': manuscriptId,
                'title': chapterTitle,
              },
            );
          },
        );
      },
    ),

    // ── 顶层路由：/growth-detail（成长详情页，C4 接入）──
    GoRoute(
      path: AppRoutes.growthDetail,
      builder: (context, state) => const GrowthDetailPage(),
    ),

    // ── 顶层路由：/settings（设置页，批次 11）──
    GoRoute(
      path: AppRoutes.settings,
      builder: (context, state) => const SettingsPage(),
    ),

    // ── 顶层路由：/append-chapters（追加章节导入页，批次 20）──
    // 真源：RN /import-confirm（稿件详情 ChapterSection「导入」入口）
    GoRoute(
      path: AppRoutes.appendChapters,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final manuscriptId = extra['manuscriptId'] as String? ?? '';
        final title = extra['title'] as String? ?? '';
        if (manuscriptId.isEmpty) {
          return const PlaceholderPage(title: '追加章节', subtitle: '未提供作品 ID');
        }
        return AppendChaptersPage(
          manuscriptId: manuscriptId,
          manuscriptTitle: title,
        );
      },
    ),

    // ── 顶层路由：/project-settings（项目设置页，批次 20）──
    // 真源：RN /project-settings（稿件详情更多菜单「项目设置」入口）
    GoRoute(
      path: AppRoutes.projectSettings,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final manuscriptId = extra['manuscriptId'] as String? ?? '';
        final title = extra['title'] as String?;
        if (manuscriptId.isEmpty) {
          return const PlaceholderPage(title: '项目设置', subtitle: '未提供作品 ID');
        }
        return ProjectSettingsPage(
          manuscriptId: manuscriptId,
          initialTitle: title,
        );
      },
    ),

    // ── 顶层路由：/progress-detail（学习进度详情页，批次 21）──
    // 真源：RN /progress-detail（书架 ProgressCard「学习进度」入口，sessionId 维度）
    GoRoute(
      path: AppRoutes.progressDetail,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final sessionId = extra['sessionId'] as String? ?? '';
        if (sessionId.isEmpty) {
          return const PlaceholderPage(title: '学习进度', subtitle: '未提供会话 ID');
        }
        return ProgressDetailPage(sessionId: sessionId);
      },
    ),

    // ── 顶层路由：/chapter-recycle-bin（章节回收站，批次94-2）──
    // 入口：作品详情页 ⋮ 更多菜单「回收站」；按作品维度过滤软删章节
    GoRoute(
      path: AppRoutes.chapterRecycleBin,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final manuscriptId = extra['manuscriptId'] as String? ?? '';
        final title = extra['title'] as String? ?? '';
        if (manuscriptId.isEmpty) {
          return const PlaceholderPage(title: '章节回收站', subtitle: '未提供作品 ID');
        }
        return ChapterRecycleBinPage(
          manuscriptId: manuscriptId,
          manuscriptTitle: title,
        );
      },
    ),

    // ── 顶层路由：/characters（C78 批次3 角色页）──
    // 入口①：写作页 ⋮ 菜单（Navigator.push，ADR-C78 §3.0）
    // 入口②：对话页 FR-10 批次提示卡（go_router 深链，可携带最近批次过滤）
    GoRoute(
      path: AppRoutes.characters,
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        final manuscriptId = extra['manuscriptId'] as String? ?? '';
        if (manuscriptId.isEmpty) {
          return const PlaceholderPage(title: '角色', subtitle: '未提供作品 ID');
        }
        return CharacterPage(
          manuscriptId: manuscriptId,
          manuscriptTitle: extra['title'] as String?,
          sinceTimestamp: extra['since'] as int?,
        );
      },
    ),

    // ── Tab 布局：StatefulShellRoute.indexedStack ──
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return _AppShell(navigationShell: navigationShell);
      },
      branches: [
        // Branch A: 书架
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.bookshelf,
              builder: (context, state) => const BookshelfPage(),
            ),
          ],
        ),
        // Branch B: 对话（C2 改造：从写作占位页改为 ChatPage）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.writing,
              builder: (context, state) => const ChatPage(),
            ),
          ],
        ),
        // Branch C: 成长（C4 接入：GrowthPage + 跳转详情页）
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: AppRoutes.growth,
              builder: (context, state) => GrowthPage(
                onOpenDetail: () => context.go(AppRoutes.growthDetail),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// 应用 Shell — 底部 Tab 导航容器
class _AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const _AppShell({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 批次68：Tab 切换轻淡入——indexedStack 硬切保留（保活+即时），
      // 切换瞬间新 Tab 内容 150ms 淡入，消除生硬感（reduced-motion 归零）
      body: TweenAnimationBuilder<double>(
        key: ValueKey('tab-fade-${navigationShell.currentIndex}'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : AppMotion.durationFast,
        curve: AppMotion.curveStandard,
        builder: (context, value, child) =>
            Opacity(opacity: value, child: child),
        child: navigationShell,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) {
          navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          );
        },
        backgroundColor: AppColors.background,
        indicatorColor: AppColors.primarySoft,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: '书架',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_outlined),
            selectedIcon: Icon(Icons.chat),
            label: '对话',
          ),
          NavigationDestination(
            icon: Icon(Icons.trending_up_outlined),
            selectedIcon: Icon(Icons.trending_up),
            label: '成长',
          ),
        ],
      ),
    );
  }
}
