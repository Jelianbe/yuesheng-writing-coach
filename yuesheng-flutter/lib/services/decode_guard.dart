// ─────────────────────────────────────────────────────────────
// decode_guard — 数据解析失败的可观测降级守卫
// ─────────────────────────────────────────────────────────────
// 背景（2026-08-29 应用体检 P0）：
//   全仓多处空 catch 用于 JSON 解析降级——DB 中存放的
//   teachingHistory / styleProfile / styleFingerprint / onboardingData
//   等字段，可能因旧版本格式、写入截断或迁移残留而损坏。
//
//   降级行为本身是对的（不该因一条脏数据让页面崩溃），但**静默**是错的：
//   用户侧表现为「学习记录凭空消失」「文笔画像没了」，而日志中无任何
//   痕迹，事后无法追溯原因。
//
// 本守卫做的事只有一件：**保留原有降级行为，补上可观测性**。
// 因此行为零变更——降级结果、返回类型、控制流全部与改造前一致。
//
// 用法：
//   } catch (e, st) {
//     logDecodeFailure(field: 'teachingHistory', error: e, stack: st);
//   }
//   return [];                     // 降级值由调用方原样保持
//
// 不适用于：error_log_repository 内部的解析。该处若走 ErrorHandler
// 会形成「记日志失败 → 再记日志」的递归，应改用 debugPrint 直写。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import 'error_handler.dart';

/// 记录一次数据解析失败（降级已由调用方处理）。
///
/// [field]  失败的字段名，用于定位（如 'teachingHistory'）。
/// [error] / [stack] 原始异常与堆栈。
/// [category] error_logs.category，须为白名单值（见 error_handler.dart）；
///   默认 'database'（绝大多数场景是 DB 中 JSON 字段损坏）。
///   非数据层场景（如路由弹栈）应显式传入对应类别，如 'render'。
void logDecodeFailure({
  required String field,
  required Object error,
  StackTrace? stack,
  String category = 'database',
}) {
  debugPrint('[decode] $field 解析失败，按默认值降级: $error');
  ErrorHandler.instance.captureError(
    // 降级成功 = 功能未中断，但数据异常需被观测 → warn 而非 error，
    // 避免淹没真正的 error 级故障。
    level: 'warn',
    category: category,
    message: '$field 解析失败，已按默认值降级',
    context: {'field': field, 'error': '$error'},
    stack: stack?.toString(),
  );
}
