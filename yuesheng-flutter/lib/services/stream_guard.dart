// ─────────────────────────────────────────────────────────────
// stream_guard — 流式「两段式空闲超时」守卫
//
// 抽为独立模块，便于单元测试（模拟静默断流，验证守卫会按时抛错，
// 而非让 `await for` 永久阻塞导致 UI 卡死）。
//
// 两段计时：
//   - 首字符到达前：connectTimeout（连接/首字超时），覆盖模型冷启动慢；
//   - 首字符之后：idleTimeout（流式中段空闲超时），相邻 chunk 超阈值视为断流。
// 触发后抛 TimeoutException，由 streamChat 调用方转 onError → UI 复位。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import '../config/shared_constants.dart';

/// 对流式解码后的字符串流套一层空闲超时守卫。
///
/// [connectTimeout] / [idleTimeout] 可覆盖（测试时传短值加速验证）；
/// 缺省取 [LlmConfig.streamConnectTimeoutMs] / [LlmConfig.streamIdleTimeoutMs]。
Stream<String> guardStream(
  Stream<String> source, {
  Duration? connectTimeout,
  Duration? idleTimeout,
}) {
  final connect =
      connectTimeout ??
      Duration(milliseconds: LlmConfig.streamConnectTimeoutMs);
  final idle =
      idleTimeout ?? Duration(milliseconds: LlmConfig.streamIdleTimeoutMs);

  final controller = StreamController<String>();
  Timer? timer;
  var firstReceived = false;

  void arm() {
    timer?.cancel();
    timer = Timer(firstReceived ? idle : connect, () {
      timer = null;
      controller.addError(
        TimeoutException(
          firstReceived
              ? '模型响应中断（超过 ${idle.inSeconds} 秒未收到新内容）'
              : '模型响应超时（超过 ${connect.inSeconds} 秒未返回首个字符）',
        ),
      );
    });
  }

  final sub = source.listen(
    (text) {
      if (!firstReceived) firstReceived = true;
      // 收到数据即重置空闲计时；首字后切换为更短的 idle 阈值
      arm();
      controller.add(text);
    },
    onError: (e, st) {
      timer?.cancel();
      controller.addError(e, st);
    },
    onDone: () {
      timer?.cancel();
      controller.close();
    },
    cancelOnError: false,
  );

  // 启动连接阶段计时（首字到达前）
  arm();

  // 无论何种方式退出都清理底层订阅与计时器，避免连接泄漏
  controller.onCancel = () {
    timer?.cancel();
    sub.cancel();
  };

  return controller.stream;
}
