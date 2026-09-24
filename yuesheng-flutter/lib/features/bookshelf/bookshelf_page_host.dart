// ─────────────────────────────────────────────────────────────
// bookshelf_page_host — 书架页宿主能力接口
//
// 从 bookshelf_page.dart 家族真分解而来（R-019：原 `part` + `extension
// _BookshelfX on _BookshelfPageState` 硬挂 State 的动作方法，改为独立
// 控制器 + 显式接口注入）。
//
// 原 3 个 extension 隐式寄生在 `_BookshelfPageState` 上，直接读写 State
// 私有字段 / setState / ref；提取后各控制器只依赖本接口暴露的最小能力集，
// 不再回指宿主文件（避免循环依赖，无需 part）。
//
// 由 `_BookshelfPageState implements BookshelfPageHost` 提供实现。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bookshelf_sort_mode.dart';

/// 书架页宿主对动作控制器暴露的能力（最小集）。
///
/// 说明：本页跨控制器共享的可变 UI 状态（搜索关键字 / 排序模式 / 三个
/// 表单控制器）仍物理保存在 [State] 中，经本接口以「getter 读 + 写方法
/// 内部 setState」暴露，保证重建时机与拆分前完全一致。
abstract class BookshelfPageHost {
  /// Riverpod 容器（读 provider / 调 notifier）
  WidgetRef get ref;

  /// 构建上下文（弹层 / 导航 / SnackBar）
  BuildContext get context;

  /// 是否仍挂载（异步间隙保护）
  bool get mounted;

  /// 新建弹窗标题输入控制器
  TextEditingController get titleController;

  /// 新建弹窗简介输入控制器
  TextEditingController get descController;

  /// 新建弹窗体裁输入控制器
  TextEditingController get genreController;

  /// 当前搜索关键字（标题模糊匹配）
  String get query;

  /// 当前排序模式
  BookshelfSortMode get sortMode;

  /// 更新搜索关键字（内部 setState）
  void setQuery(String value);

  /// 书架统一刷新：失效章节统计缓存 + 重载作品列表
  void refreshBookshelf();
}
