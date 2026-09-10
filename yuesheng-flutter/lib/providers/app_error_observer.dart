// ─────────────────────────────────────────────────────────────
// app_error_observer — Riverpod provider 失败全局拦截（入档批次：
// AppError 业务错误基类 + ProviderObserver 全局拦截）
//
// 职责：ProviderObserver 监听 provider 抛错（providerDidFail），
// 结构化记录到全局 error_logs（复用 ErrorHandler.captureError）。
// 现有三路钩子（runZonedGuarded / FlutterError / PlatformDispatcher）
// 捕获的是「未被 AsyncValue 接住」的异步/框架错误；providerDidFail
// 补的是 Riverpod 层「AsyncNotifier/Provider 内抛错」的结构化入口，
// 两者互补不重复。
//
// 防递归：error_log 相关 provider 失败不再记日志（否则「记日志失败→
// 再记日志」无限循环，对齐 error_log_repository 内部不自记的约定）。
// 可测性：onError 回调可注入（默认走 ErrorHandler.instance.captureError）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_error.dart';
import '../services/error_handler.dart';

/// 全局 provider 失败观察者
class AppErrorObserver extends ProviderObserver {
  /// 记录失败的回调（默认走全局 error_logs，测试注入 spy）
  final void Function({
    required String level,
    required String category,
    required String message,
    String? stack,
    Map<String, dynamic>? context,
  })
  onError;

  /// 已知内部 provider 前缀：失败时不记日志（防递归）
  static const Set<String> _internalPrefixes = {'errorLog'};

  const AppErrorObserver({this.onError = _defaultCapture});

  static void _defaultCapture({
    required String level,
    required String category,
    required String message,
    String? stack,
    Map<String, dynamic>? context,
  }) {
    ErrorHandler.instance.captureError(
      level: level,
      category: category,
      message: message,
      stack: stack,
      context: context,
    );
  }

  @override
  void providerDidFail(
    ProviderBase<Object?> provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    final name = provider.name ?? provider.runtimeType.toString();
    if (_internalPrefixes.any(name.startsWith)) return;

    // AppError 提取 code 入 context，方便日志检索归因
    final appError = AppError.from(error);
    onError(
      level: 'error',
      category: 'general',
      message: '[$name] ${appError?.message ?? error.toString()}',
      stack: stackTrace.toString(),
      context: {if (appError != null) 'appErrorCode': appError.code.name},
    );
  }
}
