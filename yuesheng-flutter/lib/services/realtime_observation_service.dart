// ─────────────────────────────────────────────────────────────
// RealtimeObservationService — A7 双通道·实时通道服务（批次68 B62j）
//
// 双通道分工（V2.0 §4.1 模型策略）：
//   · 实时通道（本服务，轻 prompt）：写作过程中的轻量编辑观察，
//     低延迟反馈，只跑 Editor 观察，不接 Reviewer/Teacher/全量诊断。
//   · 复盘通道（重）：章末「诊断本章」全量 ChatService（既有，不动）。
//
// 设计：
//   · 复用 callEditorStream（editor-observation skill）做轻 prompt 调用，
//     附加轻量约束 system 消息（表达密度：一次一个点 / 最小示范 / 不代改正文）。
//   · R1 原则：观察结果总是入库（即使 teacher 未触发），便于审计阈值校准。
//   · 失败兜底不抛出：API/解析失败 → observation=null，displayContent 兜底。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/services/editor_service.dart';
import 'package:writingcoach/services/editor_validator.dart';
import 'package:writingcoach/services/llm_client.dart';

/// 实时通道轻量观察约束（批次68 A7，对齐表达密度规则 + A1 措辞约束）
const String kRealtimeObservationConstraint = '''
# 轻量观察约束（实时通道）

本次是写作过程中的轻量观察，追求低延迟、不打断创作流。请遵守：
1. 一次只观察一个最值得提的点，不一次性展开所有问题；
2. 示范只给最小可感知的一例（不超过 2 句）；
3. 只定位问题与位置，不代改正文；
4. 语气温和，用提问式表达。''';

/// 实时观察结果
class RealtimeObservationResult {
  /// 展示给用户的自然语言内容（去 [YS_EDITOR] 标记）
  final String displayContent;

  /// 结构化编辑观察（解析失败 / 校验失败为 null）
  final EditorResult? observation;

  /// 已入库的 assistant 消息 id（observation 入库的关联键）
  final String? messageId;

  const RealtimeObservationResult({
    required this.displayContent,
    this.observation,
    this.messageId,
  });
}

/// 实时通道观察服务（轻 prompt，只跑 Editor 观察）
class RealtimeObservationService {
  final LlmClient _llmClient;
  final SessionRepository _sessionRepo;
  final EditorObservationRepository _editorObservationRepo;

  RealtimeObservationService({
    required LlmClient llmClient,
    required SessionRepository sessionRepo,
    required EditorObservationRepository editorObservationRepo,
  }) : // 私有字段无法用 initializing formal：this._xxx 为私有名，
       // 跨 library 的调用方（session_providers / 测试）无法以私有名传参。
       // ignore: prefer_initializing_formals
       _llmClient = llmClient,
       // ignore: prefer_initializing_formals
       _sessionRepo = sessionRepo,
       // ignore: prefer_initializing_formals
       _editorObservationRepo = editorObservationRepo;

  /// 对文本做一次轻量编辑观察（实时通道）。
  ///
  /// 流程：轻 prompt 调用（editor-observation skill + 轻量约束）→
  /// displayContent 写为 assistant 消息 → observation 入库（R1）→ 返回结果。
  /// 任何失败均不抛出：observation=null + 兜底文案（对齐 callEditorStream 语义）。
  Future<RealtimeObservationResult> observe({
    required String sessionId,
    required String text,
    String? targetRefType,
    String? targetRefId,
    void Function(String delta)? onStream,
    CancelToken? cancelToken,
  }) async {
    final editorResult = await callEditorStream(
      _llmClient,
      text,
      onStream ?? (_) {},
      cancelToken: cancelToken,
      extraSystemMessages: [
        ChatMessage(role: 'system', content: kRealtimeObservationConstraint),
      ],
    );

    // displayContent 写为 assistant 消息（observation 入库需 messageId 关联）
    final messageId = await _writeAssistantMessage(sessionId, editorResult);

    // R1：observation 总是入库（解析/校验成功才入；失败不入）
    if (editorResult.observation != null && messageId != null) {
      await _persistObservation(
        sessionId: sessionId,
        messageId: messageId,
        editorResult: editorResult.observation!,
        targetRefType: targetRefType,
        targetRefId: targetRefId,
      );
    }

    return RealtimeObservationResult(
      displayContent: editorResult.displayContent,
      observation: editorResult.observation,
      messageId: messageId,
    );
  }

  /// displayContent 写为 assistant 消息，返回消息 id。
  ///
  /// 兜底文案（LLM 失败）也走此路径，保证用户可见；displayContent
  /// 为空白时不写消息、返回 null（observation 入库需要非空关联键）。
  Future<String?> _writeAssistantMessage(
    String sessionId,
    EditorStreamResult editorResult,
  ) async {
    if (editorResult.displayContent.trim().isNotEmpty) {
      return _sessionRepo.addMessage(
        sessionId,
        'assistant',
        editorResult.displayContent,
      );
    }
    return null;
  }

  /// observation 入库（R1：观察结果总是入库，便于审计阈值校准）。
  ///
  /// 入库失败被吞掉：不影响已写入的展示内容（失败兜底不抛出语义）。
  Future<void> _persistObservation({
    required String sessionId,
    required String messageId,
    required EditorResult editorResult,
    String? targetRefType,
    String? targetRefId,
  }) async {
    final observations = editorResult.observations;
    try {
      await _editorObservationRepo.insertEditorObservation(
        InsertEditorObservationParams(
          sessionId: sessionId,
          messageId: messageId,
          editorResult: editorResult,
          teacherTriggered: false,
          pronouncedCount: observations
              .where((o) => o.observationVisibility == 'pronounced')
              .length,
          againstCount: observations
              .where((o) => o.intentAlignment == 'against')
              .length,
          targetRefType: targetRefType,
          targetRefId: targetRefId,
        ),
      );
    } catch (_) {
      // 入库失败不影响展示内容
    }
  }
}
