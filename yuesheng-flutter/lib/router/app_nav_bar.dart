// ─────────────────────────────────────────────────────────────
// app_nav_bar.dart — 全局壳底部导航（三 Tab）
//
// 【为什么从 `app_router.dart` 搬出来】
//   `app_router.dart` 是**路由表**，不该持有 Widget 实现；它已在 R-019
//   文件级基线登记值上（容差 0）⇒ 任何改动都会被判「变胖」。
//   搬出后：路由文件只剩「装哪个栏」的判定，栏本身自成一体（≈40 行）。
//
// 【是否渲染由谁决定】
//   `nav_gate.dart` 的 [shouldRenderBottomNav]（web 首发隐藏，NAV-1）。
//   本文件**不做**平台判断 —— 判定点只有一个，避免两处漂移。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_palette.dart';

/// 全局壳的三 Tab 底栏：书架 / 对话 / 成长。
///
/// 行为与搬迁前**逐行等价**：`goBranch` 的 `initialLocation` 取
/// 「点的就是当前 Tab」⇒ 再点当前 Tab 回到该分支初始位置（既定交互）。
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({super.key, required this.shell});

  /// `go_router` 的分支导航壳；底栏的选中态与切分支都读它。
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: shell.currentIndex,
      onDestinationSelected: (index) {
        shell.goBranch(index, initialLocation: index == shell.currentIndex);
      },
      backgroundColor: context.palette.background,
      indicatorColor: context.palette.primarySoft,
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
    );
  }
}
