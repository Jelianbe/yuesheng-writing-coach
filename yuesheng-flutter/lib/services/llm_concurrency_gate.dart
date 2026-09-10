import 'package:flutter/foundation.dart' show visibleForTesting;

// ─────────────────────────────────────────────────────────────
// llm_concurrency_gate — 在途请求并发闸门（入档批次）
//
// 对齐外来《交互设计规范》低成本补强思路：防止重复/并发在途请求。
// 月笙 LLM 客户端（LlmClient）此前无任何并发控制——UI 层虽有
// isStreaming 单流，但跨会话/多入口并发（诊断 + 教师 + 编辑观察
// 同时触发）没有兜底，B14 历史泄漏即源于此。
//
// 形态：全局互斥闸门（同一时刻至多一个 LLM 请求在途），第二请求
// 快速失败抛 [LlmInFlightException]（不进网络、不排队、不重试），
// 调用方（chat/editor service）已有错误处理路径会把它转成
// 「已有请求处理中」的温和提示。
//
// 安全：LlmClient 用 try/finally 保证异常/取消路径也释放闸门，
// 不会因一次崩溃卡死后续所有请求。
// ─────────────────────────────────────────────────────────────

/// 在途冲突异常：已有 LLM 请求未结束
class LlmInFlightException implements Exception {
  const LlmInFlightException();
  @override
  String toString() => 'LlmInFlightException: 已有请求在途';
}

/// 全局互斥闸门（默认共享单例，测试可注入独立实例）
class LlmConcurrencyGate {
  int _inFlight = 0;

  /// 是否有请求在途
  bool get isBusy => _inFlight > 0;

  /// 进入闸门：已有在途请求则抛 [LlmInFlightException]，
  /// 否则占用（调用方必须在 finally 中调用 [exit] 释放）
  void enter() {
    if (_inFlight > 0) {
      throw const LlmInFlightException();
    }
    _inFlight++;
  }

  /// 释放闸门（幂等：已释放/未占用时静默）
  void exit() {
    if (_inFlight > 0) _inFlight--;
  }

  /// 重置（测试/极端恢复用）
  @visibleForTesting
  void reset() => _inFlight = 0;
}

/// 应用级共享闸门（LlmClient 默认使用）
final LlmConcurrencyGate kSharedLlmGate = LlmConcurrencyGate();
