// ─────────────────────────────────────────────────────────────
// manuscript_detail_navigator — 作品详情页导航动作（独立类）
//
// 从 manuscript_detail_nav.dart（原 part/extension）真分解而来。
//   - handleOpenRelatedSession  相关对话 → 切写作页会话
//   - openAppendChapters        导入 → 追加章节页
//   - openMoreMenu              更多菜单（项目设置 / 导出整书 / 回收站 / 删除）
//   - confirmDeleteManuscript   删除作品二次确认 → 软删 → 回书架
//
// 依赖经 [ManuscriptDetailHost] 显式注入；导出委托给 [ManuscriptDetailExporter]。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../providers/chat_store.dart';
import '../providers/manuscript_providers.dart';
import '../router/app_routes.dart';
import 'manuscript_detail_exporter.dart';
import 'manuscript_detail_host.dart';
import 'manuscript_detail_menu.dart';
import 'yue_sheet.dart';

/// 作品详情页导航动作
class ManuscriptDetailNavigator {
  final ManuscriptDetailHost host;
  final ManuscriptDetailExporter exporter;

  ManuscriptDetailNavigator(this.host, this.exporter);

  /// 批次 30：相关对话点击 → 交接待打开会话并切到对话 Tab
  /// ChatPage 监听 pendingOpenSessionProvider 非空时 switchTo 目标会话
  void handleOpenRelatedSession(String sessionId) {
    host.ref.read(pendingOpenSessionProvider.notifier).state = sessionId;
    host.context.go(AppRoutes.writing);
  }

  /// 章节列表「导入」→ 追加章节页
  void openAppendChapters() {
    final ms = host.manuscript;
    host.context.push(
      '/append-chapters',
      extra: <String, dynamic>{
        'manuscriptId': host.manuscriptId,
        'title': ms?.title ?? host.manuscriptTitle ?? '',
      },
    );
  }

  /// 更多菜单（批次 20，对齐 RN MoreMenuSheet）
  void openMoreMenu() {
    final ms = host.manuscript;
    showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      builder: (sheetContext) => MoreMenuSheet(
        onOpenSettings: () {
          Navigator.of(sheetContext).pop();
          host.context.push(
            '/project-settings',
            extra: <String, dynamic>{
              'manuscriptId': host.manuscriptId,
              'title': ms?.title ?? host.manuscriptTitle ?? '',
            },
          );
        },
        onExport: () {
          Navigator.of(sheetContext).pop();
          exporter.exportManuscript();
        },
        onRecycleBin: () {
          Navigator.of(sheetContext).pop();
          host.context.push(
            AppRoutes.chapterRecycleBin,
            extra: <String, dynamic>{
              'manuscriptId': host.manuscriptId,
              'title': ms?.title ?? host.manuscriptTitle ?? '',
            },
          );
        },
        onDelete: () {
          Navigator.of(sheetContext).pop();
          confirmDeleteManuscript();
        },
      ),
    );
  }

  /// 删除项目：二次确认 → 软删除 → 回书架
  /// （批次59：确认文案对齐真实软删语义——archived 数据保留，与书架删除作品一致）
  Future<void> confirmDeleteManuscript() async {
    final title = (host.manuscriptTitle?.trim().isNotEmpty ?? false)
        ? host.manuscriptTitle!
        : '未命名作品';
    final confirmed = await showDialog<bool>(
      context: host.context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除作品'),
        content: Text('确定删除《$title》吗？删除后将不再显示，章节和诊断记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !host.mounted) return;
    try {
      await host.ref
          .read(manuscriptStoreProvider.notifier)
          .deleteManuscript(host.manuscriptId);
      if (host.context.mounted) host.context.go('/bookshelf');
    } catch (_) {
      if (host.context.mounted) {
        ScaffoldMessenger.of(
          host.context,
        ).showSnackBar(const SnackBar(content: Text('删除失败，请稍后重试')));
      }
    }
  }
}
