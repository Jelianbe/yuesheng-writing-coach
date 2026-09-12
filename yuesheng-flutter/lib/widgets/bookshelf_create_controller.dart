// ─────────────────────────────────────────────────────────────
// bookshelf_create_controller — 书架页新建 / 导入动作控制器
//
// 从 bookshelf_create.dart（原 part/extension）真分解而来：
//   openCreateModal / closeCreateModal / openImportSheet /
//   handleImported / handleCreate
//
// 表单控制器与刷新能力经 [BookshelfPageHost] 显式注入；
// 新建弹窗 UI 已提为公有 [BookshelfCreateModal]。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../providers/manuscript_providers.dart';
import '../router/app_routes.dart';
import '../services/decode_guard.dart';
import '../services/work_import_service.dart';
import 'book_import_sheet.dart';
import 'bookshelf_create_modal.dart';
import 'bookshelf_page_host.dart';
import 'yue_sheet.dart';

/// 书架页新建作品 / 文本导入动作
class BookshelfCreateController {
  final BookshelfPageHost host;

  BookshelfCreateController(this.host);

  void openCreateModal() {
    // P0-2 修复：改用 showDialog 标准屏障遮罩：
    //   - barrier 黑色半透明，背景变暗，不会穿透
    //   - barrierDismissible = true：点外部自动关闭
    //   - 弹窗卸载时自动触发 WillPopScope → 清理控制器
    showDialog<void>(
      context: host.context,
      barrierDismissible: true,
      barrierColor: AppColors.overlay,
      builder: (ctx) {
        return BookshelfCreateModal(
          titleController: host.titleController,
          descController: host.descController,
          genreController: host.genreController,
          onCancel: closeCreateModal,
          onCreate: handleCreate,
          // 批次 35：新建弹窗内「文本导入」入口
          onImportTap: openImportSheet,
        );
      },
    ).then((_) {
      // 无论是 barrier dismiss 还是取消/创建成功，最终都清理一次
      if (host.titleController.text.isNotEmpty ||
          host.descController.text.isNotEmpty ||
          host.genreController.text.isNotEmpty) {
        host.titleController.clear();
        host.descController.clear();
        host.genreController.clear();
      }
    });
  }

  void closeCreateModal() {
    host.titleController.clear();
    host.descController.clear();
    host.genreController.clear();
    // showDialog 默认 useRootNavigator: true，弹窗在 root navigator 上；
    // 必须用 rootNavigator: true 弹出（对齐批次 27 创建成功路径的修复），
    // 否则会误 pop go_router 嵌套导航栈（bookshelf 是栈底）→ 空栈断言崩溃。
    if (host.mounted) {
      try {
        Navigator.of(host.context, rootNavigator: true).pop();
      } catch (e, st) {
        // 弹栈失败 → 保持当前页面（原行为保留）。此前静默，无法追溯。
        logDecodeFailure(
          field: 'bookshelf.create_modal.pop',
          error: e,
          stack: st,
          category: 'render',
        );
      }
    }
  }

  /// 批次 35：新建弹窗「文本导入」→ 关闭表单弹窗 + 打开导入弹层
  void openImportSheet() {
    closeCreateModal();
    if (!host.mounted) return;
    showYueModalBottomSheet<void>(
      context: host.context,
      isScrollControlled: true,
      builder: (_) => BookImportSheet(onImported: handleImported),
    );
  }

  /// 批次 35：导入成功 → 刷新书架 + 提示
  void handleImported(WorkImportResult result) {
    if (!host.mounted) return;
    host.refreshBookshelf();
    ScaffoldMessenger.of(host.context).showSnackBar(
      SnackBar(content: Text('已导入《${result.title}》（${result.chapterCount}章）')),
    );
  }

  Future<void> handleCreate() async {
    final title = host.titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        host.context,
      ).showSnackBar(const SnackBar(content: Text('请输入作品标题')));
      return;
    }

    final id = await host.ref
        .read(manuscriptStoreProvider.notifier)
        .createManuscript(
          title: title,
          description: host.descController.text.trim(),
          genre: host.genreController.text.trim(),
        );

    if (id != null && host.context.mounted) {
      // 创建作品成功：关闭创建弹窗。
      // showDialog 默认 useRootNavigator: true，弹窗在 root navigator 上；
      // 必须用 rootNavigator: true 弹出，否则会误 pop go_router 嵌套导航栈
      // （bookshelf 是栈底唯一页面 → 空栈断言崩溃）。
      Navigator.of(host.context, rootNavigator: true).pop();
      // 批次93-4：新建书后立即跳详情页（阅文「去写作」模型，不再是留在书架 + SnackBar）
      host.context.push(
        AppRoutes.manuscriptDetail,
        extra: {'manuscriptId': id, 'title': title},
      );
    } else if (host.context.mounted) {
      // P2-5：创建失败时给用户明确反馈
      ScaffoldMessenger.of(
        host.context,
      ).showSnackBar(const SnackBar(content: Text('创建失败，请稍后再试')));
    }
  }
}
