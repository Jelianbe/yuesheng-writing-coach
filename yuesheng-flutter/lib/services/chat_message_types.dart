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
import 'package:writingcoach/data/database/database.dart' show Message;
import 'package:writingcoach/services/llm_client.dart' show ChatContentBlock;
import 'package:writingcoach/types/teaching_types.dart'
    show AttitudeLevel, TeachingMode, TeachingPhase, TrainingResult;

/// 主回复流式结果（ADR-0010：`sawDone` = 本次是否见过 `[DONE]` 终态标记）。
typedef StreamOutcome = ({
  String fullContent,
  bool inDiagnosisBlock,
  bool sawDone,
});

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

  /// ADR-C84：用户消息已落库时触发（发送后立即上屏，不等 AI 回复）。
  /// 流式中断/失败也保证用户消息已上屏——修复「消息似乎没发出去」体感。
  final void Function(Message message)? onUserMessagePersisted;

  /// Teacher 建议阶段（诊断后的第二段流式）进入/离开通知。
  /// true = 已进入「生成教学建议」阶段；false = 该阶段结束（成功或失败）。
  /// UI 据此切换阶段文案，避免「回复显示完但界面仍在等待」被误判为卡住。
  final void Function(bool teacherActive)? onTeacherPhase;

  /// Teacher 建议阶段被用户主动取消时触发（区别于 onCancelled——
  /// 该阶段异常被 DiagnosisFlowHandler 吞掉不冒泡，需此回调显式通知 UI）。
  /// 语义：主回复与诊断已完成，仅教学建议被中止。
  final void Function()? onTeacherCancelled;

  /// 流已结束但未收到结束标记（内容可能不完整，ADR-0010）。
  /// 在 [onComplete] **之后**触发，携带该条 assistant 消息 id —— 供 UI 打标记，
  /// **不动**已落库内容（不走 onError：那条会清空已显示的字）。
  final void Function(String messageId)? onStreamTruncated;

  const SendMessageCallbacks({
    required this.onStream,
    required this.onComplete,
    required this.onError,
    this.onTrainingResult,
    this.onCancelled,
    this.onUserMessagePersisted,
    this.onTeacherPhase,
    this.onTeacherCancelled,
    this.onStreamTruncated,
  });
}

/// 发送消息选项
class SendMessageOptions {
  final TeachingPhase phase;
  final AttitudeLevel attitude;
  final TeachingMode teachingMode;
  final CancelToken? cancelToken;

  /// 批次64（B62g）：编辑器最近一次编辑时间（秒）。写作页传入，
  /// 心流判定叠加"编辑器活跃"；对话页不传（null）仅用消息频率判定。
  final int? lastEditorEditAtSec;

  /// 批次71：本消息携带的 @ 引用快照（JSON 数组字符串）。
  /// 随 user 消息落库，气泡底部展示引用徽章。
  final String? referencesJson;

  /// 批次98：诊断场景下待诊断全文（章节全文 / 选中文本）。
  /// 对话历史只落库简洁消息（「已发送章节《X》」），AI 收到全文——
  /// 全文在此字段随运行时装配注入 user 消息（不落库）。
  final String? chapterFullText;

  /// ADR-C137 批2：完整章模式（「这一章我自己写」）激活时为 true。
  /// 为 true 时对话层末尾追加一条「按需介入」system 块（存在感 + 求助即答 +
  /// R-009 边界重申）。默认 false——对话页 / 非完整章路径注入链逐字节不变
  /// （message_sequence 锚点零漂移的依据）。
  final bool wholeChapterModeActive;

  /// C147：本消息附带的图片等多模态内容块（图片直读链）。
  /// null/空 = 纯文本，用户消息序列化与既有锚点逐字节一致；非空时挂到用户消息
  /// 的 contentBlocks（text 块 + image_url 块）。R-009：不夹带任何看图评判指令。
  final List<ChatContentBlock>? attachmentBlocks;

  /// W-45 窄改①（2026-10-20 舰长批准，触 R-027）：被诊断章节在全书中的**位次
  /// （1 基）与总章数**，供位置敏感症候按**真实位置**而非字数猜测筛选。
  ///
  /// **两者皆 null ⇒ system prompt 逐字节不变**（锚点零漂移的依据）。
  /// 写入侧已归一化（DB 的 `Chapters.sortOrder` 是 0 基且 0/1 混用，不可直传）。
  /// 本字段**不落库**：与 [chapterFullText] 同属运行时注入，不进消息历史。
  final int? chapterOrder;
  final int? totalChapters;

  const SendMessageOptions({
    required this.phase,
    required this.attitude,
    this.teachingMode = TeachingMode.socratic,
    this.cancelToken,
    this.lastEditorEditAtSec,
    this.referencesJson,
    this.chapterFullText,
    this.wholeChapterModeActive = false,
    this.attachmentBlocks,
    this.chapterOrder,
    this.totalChapters,
  });
}
