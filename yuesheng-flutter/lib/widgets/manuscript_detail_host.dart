// ─────────────────────────────────────────────────────────────
// manuscript_detail_host — 作品详情页宿主能力接口
//
// 从 manuscript_detail_page.dart 家族真分解而来（R-019：原 part/extension
// 硬挂 State 的动作方法，改为独立类 + 显式接口注入）。
//
// 原 `extension _ManuscriptDetailChapter/Volume/Export/Nav on
// _ManuscriptDetailPageState` 隐式寄生在 State 上；提取后各控制器只依赖
// 本接口暴露的最小能力集，不再回指宿主文件（避免循环依赖）。
//
// 由 `_ManuscriptDetailPageState implements ManuscriptDetailHost` 提供实现。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';

/// 作品详情页宿主对动作控制器暴露的能力（最小集）
abstract class ManuscriptDetailHost {
  /// Riverpod 容器（读 provider / 调 notifier）
  WidgetRef get ref;

  /// 构建上下文（弹层 / 导航）
  BuildContext get context;

  /// 是否仍挂载（异步间隙保护）
  bool get mounted;

  /// 当前作品（可能为 null：加载中/不存在）
  Manuscript? get manuscript;

  /// 作品 id
  String get manuscriptId;

  /// 路由传入的作品标题（可能为 null）
  String? get manuscriptTitle;

  /// SnackBar 轻提示
  void showSnack(String message);
}
