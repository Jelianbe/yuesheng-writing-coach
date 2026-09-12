// ─────────────────────────────────────────────────────────────
// WritingPageFabController — 对话按钮浮层控制器（C92-6b）
//
// 来源：宿主 `writing_page.dart` 外迁（批次88-2 可拖动 FAB：位置加载/复位/
// 拖拽换位/持久化，以及 AI 面板开合）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../../data/repositories/app_state_repository.dart';
import '../../../providers/app_providers.dart';
import '../../../providers/writing_providers.dart';
import '../writing_page_host.dart';

class WritingPageFabController {
  WritingPageFabController(this._host);

  final WritingPageHost _host;

  /// 批次88-2：对话按钮尺寸（Material FAB 默认）
  static const double _fabSize = 56;

  /// 批次88-2：拖动起点时 FAB 的位置（body 内局部坐标，配合全局位移计算）
  Offset _dragStart = Offset.zero;

  /// 批次88-2：拖动起点手势的全局位置（用于差值计算，避免 FAB 移动导致坐标系漂移）
  Offset _dragStartGlobal = Offset.zero;

  double get fabSize => _fabSize;

  /// 批次88-2：加载对话按钮位置（用户级持久化；可见性开关已随排版设置移入 store）
  Future<void> loadFabPosition() async {
    final repo = AppStateRepository(_host.ref.read(appDatabaseProvider));
    final pos = await repo.getFabPosition();
    if (!_host.mounted) return;
    _host.hostSetState(() => _host.fabOffset = pos);
  }

  /// 批次88-2：恢复对话按钮到右下角默认位置（排版设置入口）
  Future<void> resetFabPosition() async {
    _host.hostSetState(() => _host.fabOffset = null);
    await AppStateRepository(
      _host.ref.read(appDatabaseProvider),
    ).clearFabPosition();
    if (!_host.context.mounted) return;
    ScaffoldMessenger.of(_host.context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('对话按钮已回到右下角'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  void handleFabDragStart(Offset globalPosition, Size area) {
    _dragStart =
        _host.fabOffset ??
        Offset(area.width - _fabSize - 16, area.height - _fabSize - 16);
    _dragStartGlobal = globalPosition;
  }

  void handleFabDragUpdate(Offset globalPosition, Size area) {
    // 用全局位移差值：FAB 移动会带动 GestureDetector，
    // 局部坐标会漂移，全局坐标稳定
    _host.hostSetState(() {
      _host.fabOffset = Offset(
        (_dragStart.dx + globalPosition.dx - _dragStartGlobal.dx).clamp(
          0.0,
          area.width - _fabSize,
        ),
        (_dragStart.dy + globalPosition.dy - _dragStartGlobal.dy).clamp(
          0.0,
          area.height - _fabSize,
        ),
      );
    });
  }

  void handleFabDragEnd() {
    final pos = _host.fabOffset;
    if (pos != null) {
      AppStateRepository(
        _host.ref.read(appDatabaseProvider),
      ).setFabPosition(pos);
    }
  }

  void toggleAiPanel() {
    _host.ref
        .read(writingStoreProvider(_host.chapterId).notifier)
        .toggleAiPanel();
  }
}
