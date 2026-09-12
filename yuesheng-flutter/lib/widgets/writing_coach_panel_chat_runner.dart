// ─────────────────────────────────────────────────────────────
// WritingCoachChatRunner — 发送 / 练习提交 执行器（独立类，无 part）
//
// R-019 真分解：从会话动作控制器中抽出的**独立类**，负责会话懒创建、
// ChatService 流式发送、练习提交、评估报告构建。所需能力经
// WritingCoachPanelHost 注入，不隐式依赖 State 私有成员，也不使用 part。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/practice_providers.dart';
import '../providers/session_providers.dart';
import '../services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import '../types/teaching_types.dart';
import 'writing_coach_panel_store.dart' show writingCoachStoreProvider;
import 'writing_coach_panel_host.dart';

/// 发送 / 练习提交 执行器。
class WritingCoachChatRunner {
  final WritingCoachPanelHost _host;

  WritingCoachChatRunner(this._host);

  WidgetRef get _ref => _host.ref;

  String get _chapterId => _host.chapterId;

  /// 确保章节会话存在（ADR-C81 懒创建的创建点，幂等）。
  Future<String?> ensureSession() async {
    final existing = _host.sessionId;
    if (existing != null) return existing;
    final sessionId = await SessionRepository(
      _ref.read(appDatabaseProvider),
    ).getOrCreateSessionForChapter(_host.manuscriptId, _chapterId);
    _host.sessionId = sessionId;
    await _host.loadAttitude(sessionId);
    _ref
        .read(writingCoachStoreProvider(_chapterId).notifier)
        .setSessionId(sessionId);
    await _ref
        .read(evaluationReportsProvider.notifier)
        .restoreForSession(sessionId);
    return sessionId;
  }

  /// 发送消息（P1-2 修复：接入 ChatService 流式回复）
  ///
  /// [subphase] 非空时强制指定子阶段（练习提交 → FEEDBACK）；
  /// [onTrainingResult] 训练结果回调。
  Future<void> handleSend({
    TeachingSubphase? subphase,
    void Function(TrainingResult)? onTrainingResult,
  }) async {
    final text = _host.inputController.text.trim();
    if (text.isEmpty) return;

    // ADR-C81 懒创建：发送是「产生内容」入口，此处才真正创建会话
    final sid = await ensureSession();
    if (sid == null) return;

    // ADR-C86：发送即清空输入栏（会话确保成功后才清空，避免失败丢输入）
    _host.inputController.clear();

    final store = _ref.read(writingCoachStoreProvider(_chapterId).notifier);
    store.setStreaming(true);
    // ADR-C87：本次发送的取消令牌（供「停止生成」按钮在流式中段中止）
    final cancelToken = CancelToken();
    _host.cancelToken = cancelToken;
    try {
      await _runSendMessage(
        sid: sid,
        text: text,
        store: store,
        subphase: subphase,
        onTrainingResult: onTrainingResult,
        cancelToken: cancelToken,
      );
    } catch (e) {
      if (_host.isMounted) _host.streamStageLabel = null;
      // ADR-C88：取消（DioExceptionType.cancel）优雅复位，不标记失败不弹红错
      if (e is DioException && e.type == DioExceptionType.cancel) {
        store.cancelStreaming();
        return;
      }
      store.setError(e.toString());
    } finally {
      _host.cancelToken = null;
    }
  }

  /// ChatService.sendMessage 调用 + 流式回调。
  Future<void> _runSendMessage({
    required String sid,
    required String text,
    required ChatStore store,
    TeachingSubphase? subphase,
    void Function(TrainingResult)? onTrainingResult,
    required CancelToken cancelToken,
  }) async {
    final chatService = _ref.read(chatServiceProvider);
    await chatService.sendMessage(
      sid,
      text,
      SendMessageCallbacks(
        onUserMessagePersisted: store.addMessage,
        onStream: store.appendStreamingContent,
        onComplete: (fullContent, messageId) async {
          final sessionRepo = SessionRepository(_ref.read(appDatabaseProvider));
          final messages = await sessionRepo.listMessages(sid);
          store.setMessages(messages);
          store.setStreaming(false);
          // 批次49：复位阶段标签
          if (_host.isMounted) _host.streamStageLabel = null;
        },
        onError: store.setError,
        onCancelled: store.cancelStreaming,
        onTrainingResult: onTrainingResult,
      ),
      SendMessageOptions(
        phase: TeachingPhase.p0Engage,
        attitude: _host.attitude,
        // 批次64（B62g）：透传编辑器活动时间戳，心流判定叠加编辑活跃
        lastEditorEditAtSec: _ref.read(editorActivityProvider),
        // ADR-C87：取消令牌——流式中可主动中止
        cancelToken: cancelToken,
      ),
      subphase: subphase,
    );
  }

  /// ADR-C87：主动停止当前生成（「停止生成」按钮回调）。
  void cancelGeneration() {
    _host.cancelToken?.cancel('用户取消生成');
  }

  /// 提交练习作答（T3：练习任务闭环）
  ///
  /// 复用 handleSend 链路，强制 subphase=FEEDBACK，使 chat_service 步骤 11 的
  /// parseTrainingResult + teaching_history 落库生效，并把结果回写到 practiceStore。
  Future<void> submitPractice(String content) async {
    final practiceStore = _ref.read(practiceStoreProvider.notifier);
    practiceStore.setSubmitting(true);
    _host.inputController.text = content;
    // 批次49：训练评估阶段标签
    if (_host.isMounted) _host.streamStageLabel = '正在评估你的改写…';
    await handleSend(
      subphase: TeachingSubphase.feedback,
      onTrainingResult: (result) {
        practiceStore.setTrainingResult(result);
        buildEvaluationReportForLastMessage();
      },
    );
    practiceStore.setSubmitting(false);
    practiceStore.submitPractice();
  }

  /// T4 评估报告：训练反馈落库后，为最后一条 assistant 消息构建评估报告。
  Future<void> buildEvaluationReportForLastMessage() async {
    final sid = _host.sessionId;
    if (sid == null) return;
    final sessionRepo = SessionRepository(_ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(sid);
    final lastAssistant = messages
        .where((m) => m.role == 'assistant')
        .lastOrNull;
    if (lastAssistant != null) {
      await _ref
          .read(evaluationReportsProvider.notifier)
          .buildEvaluationReport(sid, lastAssistant.id);
    }
  }
}
