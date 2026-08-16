// ─────────────────────────────────────────────────────────────
// ErrorHandler — 全局错误捕获 + error_logs 落库（批次2 2.1 接线）
//
// 三路钩子统一入口：
//   - runZonedGuarded（未捕获异步异常）
//   - FlutterError.onError（框架层错误）
//   - PlatformDispatcher.instance.onError（平台/引擎层错误）
//
// 时序：DB 未 ready 前错误入内存队列（防丢），appDatabaseProvider 首读时
// attachRepository 并 flush；kDebugMode 只记不显（不向用户暴露 stack）。
// 落库失败静默降级，不阻断主流程（防御性，来自真实断点事故）。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/repositories/error_log_repository.dart';

/// 待写入的错误条目（DB ready 前的内存队列）
class _PendingError {
  final String level;
  final String category;
  final String message;
  final String? stack;
  final Map<String, dynamic>? context;

  const _PendingError({
    required this.level,
    required this.category,
    required this.message,
    this.stack,
    this.context,
  });
}

/// 全局错误处理器（单例）
class ErrorHandler {
  ErrorHandler._();

  static final ErrorHandler instance = ErrorHandler._();

  /// 内存队列上限（防极端场景无限膨胀）
  static const int _maxQueueLength = 200;

  /// error_logs.category 的 CHECK 约束白名单（tables.dart ErrorLogs.category）
  static const Set<String> _kAllowedCategories = {
    'general',
    'api',
    'database',
    'render',
    'network',
    'skill',
    'validation',
  };

  /// error_logs.level 的 CHECK 约束白名单（tables.dart ErrorLogs.level）
  static const Set<String> _kAllowedLevels = {
    'debug',
    'info',
    'warn',
    'error',
    'fatal',
  };

  ErrorLogRepository? _repo;
  final List<_PendingError> _queue = [];
  void Function(FlutterErrorDetails)? _previousFlutterErrorHandler;
  bool Function(Object error, StackTrace stack)? _previousPlatformErrorHandler;

  /// 注册三路错误钩子（main() 最早调用，幂等）
  void installErrorHandlers() {
    // FlutterError.onError：先记录，再透传原处理器（debug 红屏/测试上报不受影响）
    if (_previousFlutterErrorHandler == null) {
      _previousFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        captureError(
          level: 'error',
          category: 'render',
          message: details.exceptionAsString(),
          stack: details.stack?.toString(),
          context: {
            if (details.library != null) 'library': details.library,
            if (details.context != null) 'context': details.context.toString(),
          },
        );
        _previousFlutterErrorHandler?.call(details);
      };
    }
    // PlatformDispatcher.onError：平台/引擎层未捕获错误
    if (_previousPlatformErrorHandler == null) {
      _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (error, stack) {
        captureError(
          level: 'error',
          category: 'general',
          message: error.toString(),
          stack: stack.toString(),
        );
        return _previousPlatformErrorHandler?.call(error, stack) ?? true;
      };
    }
  }

  /// 绑定 DB 仓库并 flush 队列（幂等；由 appDatabaseProvider 首读时调用）
  void attachRepository(ErrorLogRepository repo) {
    _repo = repo;
    unawaited(_flushQueue());
  }

  Future<void> _flushQueue() async {
    final repo = _repo;
    if (repo == null) return;
    final pending = List<_PendingError>.of(_queue);
    _queue.clear();
    for (final e in pending) {
      try {
        await repo.insertErrorLog(
          level: e.level,
          category: e.category,
          message: e.message,
          stack: e.stack,
          context: e.context,
        );
      } catch (_) {
        // 落库失败不重试（避免 DB 故障时死循环），静默降级
      }
    }
  }

  /// 捕获一条错误：DB ready → 直接写；否则入队（超上限丢弃最旧，内存有界）
  void captureError({
    required String level,
    required String category,
    required String message,
    String? stack,
    Map<String, dynamic>? context,
  }) {
    // 归一化到 error_logs 的 CHECK 白名单（category/level），防非法值被 DB 约束吞掉
    final normalized = _kAllowedCategories.contains(category)
        ? category
        : 'general';
    final normalizedLevel = _kAllowedLevels.contains(level) ? level : 'error';
    final repo = _repo;
    if (repo != null) {
      unawaited(
        _persist(repo, level: normalizedLevel, category: normalized,
            message: message, stack: stack, context: context),
      );
      return;
    }
    if (_queue.length >= _maxQueueLength) {
      _queue.removeAt(0); // 队列溢出：丢弃最旧
    }
    _queue.add(
      _PendingError(
        level: normalizedLevel,
        category: normalized,
        message: message,
        stack: stack,
        context: context,
      ),
    );
  }

  Future<void> _persist(
    ErrorLogRepository repo, {
    required String level,
    required String category,
    required String message,
    String? stack,
    Map<String, dynamic>? context,
  }) async {
    try {
      await repo.insertErrorLog(
        level: level,
        category: category,
        message: message,
        stack: stack,
        context: context,
      );
    } catch (_) {
      // 落库失败静默降级，不阻断主流程
    }
  }

  /// 测试专用：重置单例状态（仓库 + 队列）
  @visibleForTesting
  void resetForTesting() {
    _repo = null;
    _queue.clear();
    _previousFlutterErrorHandler = null;
    _previousPlatformErrorHandler = null;
  }
}
