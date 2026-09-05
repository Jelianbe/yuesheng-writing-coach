// ─────────────────────────────────────────────────────────────
// ChatMessageTypes — ChatService / DiagnosisFlowHandler 共享类型
//
// ADR-C74 K-9 抽取产物：sendMessage / parseAndPersist / handleTrainingResult
// 三方共享 SendMessageCallbacks / SendMessageOptions 类型。原位于
// chat_service.dart，K-9 拆出后由 diagnosis_flow_handler.dart 也需消费，
// 避免循环导入。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:writingcoach/types/teaching_types.dart'
    show AttitudeLevel, TeachingPhase, TrainingResult;

/// 流式回调
class SendMessageCallbacks {
  final void Function(String delta) onStream;
  final FutureOr<void> Function(String fullContent, String messageId)
  onComplete;
  final void Function(String error) onError;

  /// 训练结果回调（subphase==FEEDBACK 且 parseTrainingResult 命中时触发）
  final void Function(TrainingResult result)? onTrainingResult;

  /// 用户主动取消时触发（区别于 onError：取消是预期行为，不应标记消息失败）
  final void Function()? onCancelled;

  const SendMessageCallbacks({
    required this.onStream,
    required this.onComplete,
    required this.onError,
    this.onTrainingResult,
    this.onCancelled,
  });
}

/// 发送消息选项
class SendMessageOptions {
  final TeachingPhase phase;
  final AttitudeLevel attitude;
  final CancelToken? cancelToken;

  /// 批次64（B62g）：编辑器最近一次编辑时间（秒）。写作页传入，
  /// 心流判定叠加"编辑器活跃"；对话页不传（null）仅用消息频率判定。
  final int? lastEditorEditAtSec;

  /// 批次71：本消息携带的 @ 引用快照（JSON 数组字符串）。
  /// 随 user 消息落库，气泡底部展示引用徽章。
  final String? referencesJson;

  const SendMessageOptions({
    required this.phase,
    required this.attitude,
    this.cancelToken,
    this.lastEditorEditAtSec,
    this.referencesJson,
  });
}
