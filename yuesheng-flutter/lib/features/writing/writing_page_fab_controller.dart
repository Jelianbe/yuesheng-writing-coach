// ─────────────────────────────────────────────────────────────
// WritingPageFabController — 对话按钮浮层控制器（C92-6b）
//
// 来源：宿主 `writing_page.dart` 外迁（批次88-2 可拖动 FAB：位置加载/复位/
// 拖拽换位/持久化，以及 AI 面板开合）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

import '../../data/repositories/app_state_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/writing_providers.dart';
import 'writing_page_host.dart';

class WritingPageFabController {
  WritingPageFabController(this._host);

  final WritingPageHost _host;

  /// 批次88-2：对话按钮尺寸（Material FAB 默认）
  static const double _fabSize = 56;

  /// 批次88-2：FAB 与屏幕右边距（Material 悬浮按钮规范边距）
  static const double _fabMargin = 16;

  /// 底部标点栏固定高度（见 PunctuationBar `height: 36`）。
  /// FAB 默认位需悬浮在它上方，否则会压住标点栏右侧按钮。
  static const double _punctuationBarHeight = 36;

  /// 批次88-2：拖动起点时 FAB 的位置（body 内局部坐标，配合全局位移计算）
  Offset _dragStart = Offset.zero;

  /// 批次88-2：拖动起点手势的全局位置（用于差值计算，避免 FAB 移动导致坐标系漂移）
  Offset _dragStartGlobal = Offset.zero;

  double get fabSize => _fabSize;

  /// 默认右下角位（FAB 左上角，body 内局部坐标）。
  ///
  /// 写作页 Scaffold body **未包 SafeArea**（对比作品详情页 body 包了 SafeArea），
  /// body 一直延伸到屏幕最底部的系统手势导航区。旧逻辑底边只留 16dp，导致竖屏下
  /// FAB 下半被手势导航条切掉、且压住底部标点栏。这里统一从 body 底部向上预留：
  /// 系统手势 inset（viewPadding.bottom，键盘弹起时不受 viewInsets 影响）
  /// + 标点栏高度 + 呼吸边距，使按钮完整可见、不贴边、不压标点栏/系统栏。
  Offset defaultFabOffset(Size area) {
    final bottomInset = MediaQuery.viewPaddingOf(_host.context).bottom;
    final bottomReserve = bottomInset + _punctuationBarHeight + _fabMargin;
    return Offset(
      area.width - _fabSize - _fabMargin,
      area.height - _fabSize - bottomReserve,
    );
  }

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
    // 未持久化位置时，长按拖动的起点基准与 build 默认位保持一致（同为
    // defaultFabOffset），避免手指一按 FAB 就跳到旧的低位。
    _dragStart = _host.fabOffset ?? defaultFabOffset(area);
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
