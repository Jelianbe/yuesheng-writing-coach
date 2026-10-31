// ─────────────────────────────────────────────────────────────
// WritingCoachDiagnosisRunner — 诊断链路执行器（独立类，无 part）
//
// R-019 真分解：从写作教练诊断流程中抽出的**独立类**，负责分块/单次诊断
// 链路编排、流式回调、取消/错误优雅复位。所需能力经 WritingCoachPanelHost
// 注入，不隐式依赖 State 私有成员，也不使用 part / extension。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/diagnosis_temperature.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/diagnosis_repository.dart';
import '../../data/repositories/edit_diff_event_repository.dart';
import '../../data/repositories/event_fact_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../data/repositories/training_result_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/chat_store.dart';
import '../../providers/session_providers.dart';
import '../../services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import '../../services/chat_service.dart';
import '../../services/chapter_completion_querier.dart';
import '../../services/chapter_position.dart';
import '../../services/progressive_diagnosis.dart';
import '../../services/session_harvest_assembler.dart';
import '../../services/story_structure_profile.dart';
import '../../types/teaching_types.dart';
import 'diagnosis_complete_snack.dart';
import 'writing_coach_panel_store.dart' show writingCoachStoreProvider;
import 'writing_coach_panel_host.dart';

/// 诊断链路执行器（分块 + 单次 + 流式回调 + 取消/错误复位）。
class WritingCoachDiagnosisRunner {
  final WritingCoachPanelHost _host;

  WritingCoachDiagnosisRunner(this._host);

  WidgetRef get _ref => _host.ref;

  String get _chapterId => _host.chapterId;

  /// ADR-0006 + T-20261025-06 件2：一次读取同时产出结构画像与真实位次
  /// （失败/降级 ⇒ null ⇒ 调用方按空串 / 无位次处理）。
  Future<({String? profile, ({int order, int total})? position})?>
  _buildProfileFacts() async {
    final db = _ref.read(appDatabaseProvider);
    final chapterRepo = ChapterRepository(db);
    final chapter = await chapterRepo.getChapter(_chapterId);
    if (chapter == null) return null;
    return (
      profile: await buildStoryStructureProfileText(
        eventFactRepo: EventFactRepository(db),
        chapterRepo: chapterRepo,
        diagnosisRepo: DiagnosisRepository(db),
        manuscriptId: chapter.manuscriptId,
      ),
      position: await resolveChapterPosition(chapterRepo, chapter),
    );
  }

  /// 诊断链路编排：共用取消令牌 + 分块/单次路由 + 取消/错误处理。
  Future<void> runChain({
    required String sid,
    required String content,
    required String title,
    required String diagPrompt,
    required bool isSelection,
  }) async {
    // ADR-C87 延伸：诊断全链路（分块+单次）共用取消令牌
    final cancelToken = CancelToken();
    _host.cancelToken = cancelToken;
    try {
      await _runProgressiveOrSend(
        sid: sid,
        content: content,
        title: title,
        diagPrompt: diagPrompt,
        cancelToken: cancelToken,
      );
    } on ProgressiveMergeOverBudget catch (e) {
      // W-15-B B1：merge 预算拒发——显式提示（设计稿 §3.1「UI 显式报」），
      // 不落入下方通用 catch（「超限静默继续发送」是本批要消灭的形态）。
      handleError(e.userMessage);
    } on ProgressiveDiagnosisCancelled {
      // 用户主动停止分块诊断：优雅复位（不标记失败、不弹红错）
      handleCancelled();
    } catch (e) {
      handleError(e.toString());
    } finally {
      _host.cancelToken = null;
    }
  }

  /// 长度路由执行：先分块链路（长文本），null（≤THRESHOLD）则单次 sendMessage。

  /// W-18 用户温度档（merge 段；灵活档 ⇒ null ⇒ 请求体逐字节不变）。
  Future<double?> _mergeTemperature() async => mergeTemperatureFor(
    await AppStateRepository(
      _ref.read(appDatabaseProvider),
    ).getDiagnosisTemperature(),
  );

  /// 分块/单次链路共用的写入目标（store + chatService + 症候启用集下传）。
  ({ChatStore store, ChatService chatService}) _prepareTargets(
    DiagnosisPrefs? diagPrefs,
  ) {
    final store = _ref.read(writingCoachStoreProvider(_chapterId).notifier);
    final chatService = _ref.read(chatServiceProvider)
      ..disabledSyndromeIds = diagPrefs?.effectiveDisabledIds ?? const {};
    return (store: store, chatService: chatService);
  }

  Future<void> _runProgressiveOrSend({
    required String sid,
    required String content,
    required String title,
    required String diagPrompt,
    required CancelToken cancelToken,
  }) async {
    // D2：长度路由 — 先尝试分块链路（长文本）
    final diagPrefs = await AppStateRepository(
      _ref.read(appDatabaseProvider),
    ).getDiagnosisPrefs();
    // ADR-0006：结构画像 + 件2 位次同一次读取（拿不到 ⇒ 空串 / 不过滤）。
    final facts = await _buildProfileFacts();
    final progressive = await runProgressiveDiagnosis(
      content: content,
      title: title,
      llmClient: _ref.read(llmClientProvider),
      sessionId: sid,
      teachingMode: _host.teachingMode,
      structureProfile: facts?.profile ?? '',
      disabledSyndromeIds: diagPrefs?.effectiveDisabledIds ?? const {},
      chapterOrder: facts?.position?.order,
      totalChapters: facts?.position?.total,
      mergeTemperature: await _mergeTemperature(),
      onContent: (delta) => _ref
          .read(writingCoachStoreProvider(_chapterId).notifier)
          .appendStreamingContent(delta),
      // ADR-C87 延伸：分块诊断中途可取消（每块前/合并前检查）
      cancelToken: cancelToken,
    );

    final targets = _prepareTargets(diagPrefs);
    if (progressive != null) {
      // D4-A：分块链路完成 → 解析+持久化+卡片插入
      await _commitProgressive(sid, progressive, content, targets.chatService);
      await handleComplete(sid);
      return;
    }

    // 分块链路返回 null（内容 <= THRESHOLD）→ 走单次 sendMessage 链路
    await _runSingleSend(
      sid: sid,
      diagPrompt: diagPrompt,
      fullText: content,
      store: targets.store,
      chatService: targets.chatService,
      cancelToken: cancelToken,
    );
  }

  /// 分块链路结果落库（解析 + 持久化 + 卡片插入）。
  Future<void> _commitProgressive(
    String sid,
    ProgressiveResult progressive,
    String content,
    ChatService chatService,
  ) async {
    await chatService.commitDiagnosisFromContent(
      sessionId: sid,
      fullContent: progressive.fullContent,
      chapterContent: content,
    );
  }

  /// 单次诊断 sendMessage（D1 链路）。
  Future<void> _runSingleSend({
    required String sid,
    required String diagPrompt,
    required String fullText,
    required ChatStore store,
    required dynamic chatService,
    required CancelToken cancelToken,
  }) async {
    await chatService.sendMessage(
      sid,
      diagPrompt,
      SendMessageCallbacks(
        onStream: store.appendStreamingContent,
        onComplete: (_, _) => handleComplete(sid),
        onError: handleError,
        onCancelled: handleCancelled,
      ),
      SendMessageOptions(
        phase: TeachingPhase.p1World,
        attitude: _host.attitude,
        teachingMode: _host.teachingMode,
        // 批次64（B62g）：透传编辑器活动时间戳，心流判定叠加编辑活跃
        lastEditorEditAtSec: _ref.read(editorActivityProvider),
        // ADR-C87：取消令牌——诊断中可主动中止
        cancelToken: cancelToken,
        // 批次98：诊断全文运行时注入（不落库，对话历史只展示简洁消息）
        chapterFullText: fullText,
      ),
    );
  }

  /// 诊断完成：刷新消息 + 复位流式/诊断中 + 完成反馈 + 会话收口卡（T-20261018-02）。
  Future<void> handleComplete(String sid) async {
    final sessionRepo = SessionRepository(_ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(sid);
    final store = _ref.read(writingCoachStoreProvider(_chapterId).notifier);
    store.setMessages(messages);
    store.setStreaming(false);
    // D5-A：复位诊断中标志 + 完成反馈（短时 SnackBar，不遮挡后续操作）
    if (_host.isMounted) {
      _host.isDiagnosing = false;
      _host.streamStageLabel = null;
      // 已由 _host.isMounted 守护（mounted 时 context 仍有效）。
      // ignore: use_build_context_synchronously
      showDiagnosisCompleteSnack(_host.context);
    }
    // T-20261018-02（A 议题）：会话收口卡——触发判定 + 装配在 assembler 内
    // （三条件全不满足不出卡；失败静默不阻断主流程）。插入后刷新一次消息，
    // 使收口卡即时出现在消息流（重开会话亦经消息持久化恢复）。
    await _emitSessionHarvest(sid);
    if (_host.isMounted) {
      final refreshed = await sessionRepo.listMessages(sid);
      _ref
          .read(writingCoachStoreProvider(_chapterId).notifier)
          .setMessages(refreshed);
    }
  }

  /// 装配并插入会话收口卡（T-20261018-02）。
  ///
  /// 本次诊断症候集与焦点从落库行直读（history[0] = 本次），避免依赖
  /// 诊断链中间态；assembler 内部自判触发条件。
  Future<void> _emitSessionHarvest(String sid) async {
    try {
      final db = _ref.read(appDatabaseProvider);
      final diagRepo = DiagnosisRepository(db);
      final latest = await diagRepo.getLatestDiagnosis(sid);
      if (latest == null) return;
      final trainingRepo = TrainingResultRepository(db);
      final chapterRepo = ChapterRepository(db);
      final appStateRepo = AppStateRepository(db);
      final editDiffRepo = EditDiffEventRepository(db);
      final sessionRepo = SessionRepository(db);
      final assembler = SessionHarvestAssembler(
        diagRepo: diagRepo,
        trainingRepo: trainingRepo,
        completionQuerier: ChapterCompletionQuerier(
          editDiffRepo,
          appStateRepo,
          chapterRepo,
        ),
        sessionRepo: sessionRepo,
      );
      final syndromes = _syndromePairsOf(latest.syndromes);
      await assembler.assembleAndInsert(
        sessionId: sid,
        currentSyndromes: syndromes,
        nextFocusId: latest.currentTeachingFocusId,
      );
    } catch (e) {
      // 收口卡失败不阻断诊断完成主流程（对齐候选区失败静默先例）。
      debugPrint('[DiagnosisRunner] 收口卡装配失败(不阻断): $e');
    }
  }

  /// 诊断行 syndromes JSON → (id, severity) 轻量对（损坏降级空表）。
  List<({String id, String severity})> _syndromePairsOf(String raw) {
    try {
      final list = raw.isEmpty ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) => e is Map<String, dynamic>
                ? (
                    id: e['syndrome_id'] as String? ?? '',
                    severity: e['severity'] as String? ?? '',
                  )
                : null,
          )
          .whereType<({String id, String severity})>()
          .where((s) => s.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// 诊断错误：复位诊断中标志 + 写入 store 错误。
  void handleError(String error) {
    if (_host.isMounted) {
      _host.isDiagnosing = false;
      _host.streamStageLabel = null;
    }
    _ref.read(writingCoachStoreProvider(_chapterId).notifier).setError(error);
  }

  /// 用户主动停止诊断：优雅复位（不标记失败、不弹红错）。
  void handleCancelled() {
    _ref.read(writingCoachStoreProvider(_chapterId).notifier).cancelStreaming();
    if (_host.isMounted) {
      _host.isDiagnosing = false;
      _host.streamStageLabel = null;
    }
  }
}
