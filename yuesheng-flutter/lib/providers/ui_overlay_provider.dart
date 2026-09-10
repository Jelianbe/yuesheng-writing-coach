// ─────────────────────────────────────────────────────────────
// ui_overlay_provider — 全局 Toast / Confirm 覆盖层队列（入档批次）
//
// 对齐外来《状态管理详细设计.md》§4.1 useAppStore（dialogStack/toasts
// 数组 + showConfirmDialog 返回 Promise），适配 Riverpod 形态：
//
// - showToast：入队 + 超时自动 dismiss（默认 2s），队列按序展示
// - confirm：Promise 化（返回 Future<bool>），挂起期间阻塞队列后续
//   dialog（confirm 是模态），resolve 后继续
// - 纯增量能力：存量 33 处 showSnackBar / 27 处 showDialog 保持不动，
//   新代码（含后续批次）经此统一出口；UI 视觉完全走竹青现有组件
//   （toast/confirm 的样式由 UiOverlayHost 用现有令牌渲染）
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Toast 种类（仅影响语义色，与竹青令牌对应）
enum UiToastKind { info, success, warning, error }

class UiToast {
  final String id;
  final String message;
  final UiToastKind kind;
  final DateTime createdAt;
  final Duration autoDismiss;

  const UiToast({
    required this.id,
    required this.message,
    this.kind = UiToastKind.info,
    required this.createdAt,
    this.autoDismiss = const Duration(seconds: 2),
  });
}

/// 挂起的确认框（Promise 化）
class UiConfirmRequest {
  final String title;
  final String message;
  final String confirmText;
  final String cancelText;
  final Completer<bool> completer;

  UiConfirmRequest({
    required this.title,
    required this.message,
    this.confirmText = '确认',
    this.cancelText = '取消',
  }) : completer = Completer<bool>();

  bool get isResolved => completer.isCompleted;
}

/// 覆盖层状态（toast 队列 + 至多一个挂起 confirm）
class UiOverlayState {
  final List<UiToast> toasts;
  final UiConfirmRequest? confirm;

  const UiOverlayState({this.toasts = const [], this.confirm});

  UiOverlayState copyWith({
    List<UiToast>? toasts,
    UiConfirmRequest? confirm,
    bool clearConfirm = false,
  }) {
    return UiOverlayState(
      toasts: toasts ?? this.toasts,
      confirm: clearConfirm ? null : (confirm ?? this.confirm),
    );
  }
}

/// 全局覆盖层 Provider：toast 队列 + Promise 化 confirm。
///
/// 用法：
///   ref.read(uiOverlayProvider.notifier).showToast('已保存');
///   final ok = await ref.read(uiOverlayProvider.notifier).confirm(
///     title: '删除章节？',
///     message: '删除后可从回收站恢复。',
///   );
class UiOverlayNotifier extends StateNotifier<UiOverlayState> {
  UiOverlayNotifier() : super(const UiOverlayState());

  int _seq = 0;
  final List<Timer> _timers = [];

  /// 入队一条 toast，[autoDismiss] 后自动移除（防队列永久堆积）
  void showToast(
    String message, {
    UiToastKind kind = UiToastKind.info,
    Duration? autoDismiss,
  }) {
    final toast = UiToast(
      id: 'toast_${++_seq}',
      message: message,
      kind: kind,
      createdAt: DateTime.now(),
      autoDismiss: autoDismiss ?? const Duration(seconds: 2),
    );
    state = state.copyWith(toasts: [...state.toasts, toast]);
    _timers.add(Timer(toast.autoDismiss, () => dismissToast(toast.id)));
  }

  void dismissToast(String id) {
    final remaining = state.toasts.where((t) => t.id != id).toList();
    if (remaining.length != state.toasts.length) {
      state = state.copyWith(toasts: remaining);
    }
  }

  /// Promise 化确认：返回 `Future<bool>`（true=确认）。
  /// confirm 是模态：挂起期间新的 confirm 请求排队语义由调用方保证
  /// （同一时刻至多一个挂起请求，重复调用覆盖前者并完成其 Future=false）。
  Future<bool> confirm({
    required String title,
    required String message,
    String confirmText = '确认',
    String cancelText = '取消',
  }) {
    final previous = state.confirm;
    if (previous != null && !previous.isResolved) {
      previous.completer.complete(false);
    }
    final request = UiConfirmRequest(
      title: title,
      message: message,
      confirmText: confirmText,
      cancelText: cancelText,
    );
    state = state.copyWith(confirm: request);
    return request.completer.future;
  }

  void resolveConfirm(bool result) {
    final request = state.confirm;
    if (request == null || request.isResolved) return;
    request.completer.complete(result);
    state = state.copyWith(clearConfirm: true);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    final request = state.confirm;
    if (request != null && !request.isResolved) {
      request.completer.complete(false);
    }
    super.dispose();
  }
}

/// 全局覆盖层 provider（不销毁——app 生命周期级）
final uiOverlayProvider =
    StateNotifierProvider<UiOverlayNotifier, UiOverlayState>(
      (ref) => UiOverlayNotifier(),
    );
