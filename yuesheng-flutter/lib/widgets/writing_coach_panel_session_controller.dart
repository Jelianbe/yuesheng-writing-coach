// ─────────────────────────────────────────────────────────────
// writing_coach_panel 的会话动作控制器（独立类，依赖注入，无 part）
//
// R-019 真分解：从 _WritingCoachPanelState 的 extension 抽出的
// **独立类** WritingCoachSessionController —— 覆盖部分认同 / 教原理 /
// 快速观察 / 长按删除，并把发送/练习提交委托给 WritingCoachChatRunner。
// 所需能力经 WritingCoachPanelHost 注入，不隐式依赖 State 私有成员，
// 也不使用 part / extension。
//
// ⚠️ 本文件**刻意不含** UILimits 字数门槛常量——门槛文案（诊断两档 + 快速观察）
//    保留在 writing_coach_panel_teaching.dart（门禁测试锚定该路径）。
//    快速观察的字数校验经 [_observeGate] 回调委托给教学控制器完成。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/database.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/session_providers.dart';
import '../types/teaching_types.dart';
import 'writing_coach_panel_store.dart' show writingCoachStoreProvider;
import 'writing_coach_panel_chat_runner.dart';
import 'writing_coach_panel_delete_dialog.dart';
import 'writing_coach_panel_host.dart';
import 'writing_coach_panel_interactions.dart';

/// 会话动作控制器（部分认同 / 教原理 / 快速观察 / 长按删除 + 发送委托）。
class WritingCoachSessionController {
  final WritingCoachPanelHost _host;

  /// 快速观察前置校验（会话懒创建 + 字数门槛）。
  ///
  /// 门槛常量在 teaching 文件（受 ADR-C66 门禁锚定），此处仅注入调用。
  final Future<({String sid, String content})?> Function() _observeGate;

  /// 发送 / 练习提交执行器。
  late final WritingCoachChatRunner _chat = WritingCoachChatRunner(_host);

  WritingCoachSessionController(this._host, this._observeGate);

  /// 便捷读取宿主 ref
  WidgetRef get _ref => _host.ref;

  /// 便捷读取章节 id
  String get _chapterId => _host.chapterId;

  /// 对外暴露发送（练习卡 / 输入栏 / 三卡共用）。
  Future<void> handleSend({
    TeachingSubphase? subphase,
    void Function(TrainingResult)? onTrainingResult,
  }) =>
      _chat.handleSend(subphase: subphase, onTrainingResult: onTrainingResult);

  /// ADR-C87：主动停止当前生成（「停止生成」按钮回调）。
  void cancelGeneration() => _chat.cancelGeneration();

  /// 提交练习作答（T3：练习任务闭环）。
  Future<void> submitPractice(String content) => _chat.submitPractice(content);

  // ───────────────────────── 输入栏聚焦 / 部分认同 / 教原理 ─────────────────────────

  /// 批次81：聚焦输入栏（三卡「返回对话/继续对话/补充内容」复用）
  void focusInput() => _host.focusInput();

  /// 批次81 H3：部分认同提交反馈 / 快速选项 → 填入输入栏并发送（复用发送链路）
  Future<void> handlePartialAgreementSubmit(
    String feedback,
    String? quickOption,
  ) async {
    if (_ref.read(writingCoachStoreProvider(_chapterId)).isStreaming) return;
    if (quickOption == null && feedback.trim().isEmpty) return;
    _host.inputController.text = buildPartialAgreementMessage(
      feedback,
      quickOption,
    );
    await _chat.handleSend();
  }

  /// 批次81 H3：部分认同跳过此症候 → 填入输入栏并发送（请求重新诊断）
  Future<void> handlePartialAgreementSkip() async {
    if (_ref.read(writingCoachStoreProvider(_chapterId)).isStreaming) return;
    _host.inputController.text = buildPartialAgreementSkipMessage();
    await _chat.handleSend();
  }

  /// 批次61：Teacher 建议卡「教我原理」→ 填入输入框并发送（复用 _handleSend 链路）
  Future<void> handleTeachPrinciple(String syndromeName) async {
    _host.inputController.text = buildTeachPrincipleMessage(syndromeName);
    await _chat.handleSend();
  }

  // ───────────────────────── 长按删除 ─────────────────────────

  /// 批次74：长按删除教练面板消息（对齐对话页长按删除心智）
  Future<void> confirmDeleteMessage(Message msg) async {
    final confirmed = await WritingCoachDeleteDialog.show(
      context: _host.context,
    );
    if (confirmed != true || !_host.isMounted) return;
    await _host.awaitInit();
    final sid = _host.sessionId;
    if (sid == null) return;
    final sessionRepo = SessionRepository(_ref.read(appDatabaseProvider));
    await sessionRepo.deleteMessage(sid, msg.id);
    final messages = await sessionRepo.listMessages(sid);
    if (!_host.isMounted) return;
    _ref
        .read(writingCoachStoreProvider(_chapterId).notifier)
        .setMessages(messages);
  }

  // ───────────────────────── 快速观察 ─────────────────────────

  /// 快速观察（批次69 A7 双通道·实时通道 UI 入口）。
  Future<void> handleRealtimeObserve() async {
    // ADR-C66：门槛校验委托给教学控制器（门槛常量留在 teaching 文件）
    final prepared = await _observeGate();
    if (prepared == null) return;
    final sid = prepared.sid;
    final content = prepared.content;

    // 批次49：快速观察阶段标签
    if (_host.isMounted) _host.streamStageLabel = '正在快速观察…';
    final store = _ref.read(writingCoachStoreProvider(_chapterId).notifier);
    store.setStreaming(true);
    // ADR-C87：本次观察的取消令牌（「停止生成」按钮可中止）
    final cancelToken = CancelToken();
    _host.cancelToken = cancelToken;

    try {
      await _runObserve(
        sid: sid,
        content: content,
        store: store,
        cancelToken: cancelToken,
      );
    } catch (e) {
      if (_host.isMounted) _host.streamStageLabel = null;
      // ADR-C88：取消优雅复位，不标记失败不弹红错
      if (e is DioException && e.type == DioExceptionType.cancel) {
        store.cancelStreaming();
        return;
      }
      store.setError(e.toString());
    } finally {
      _host.cancelToken = null;
    }
  }

  /// RealtimeObservationService.observe 调用 + 刷新消息（R-019 清偿拆出）。
  Future<void> _runObserve({
    required String sid,
    required String content,
    required ChatStore store,
    required CancelToken cancelToken,
  }) async {
    await _ref
        .read(realtimeObservationServiceProvider)
        .observe(
          sessionId: sid,
          text: content,
          targetRefType: 'chapter',
          targetRefId: _chapterId,
          onStream: store.appendStreamingContent,
          cancelToken: cancelToken,
        );

    // observe 内部已写入 assistant 消息 → 刷新消息列表
    final messages = await SessionRepository(
      _ref.read(appDatabaseProvider),
    ).listMessages(sid);
    store.setMessages(messages);
    store.setStreaming(false);
    // 批次49：复位阶段标签，避免残留到下一次流式
    if (_host.isMounted) _host.streamStageLabel = null;
  }
}
