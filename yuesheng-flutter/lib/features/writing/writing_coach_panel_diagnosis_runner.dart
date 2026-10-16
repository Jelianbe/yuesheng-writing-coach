// ─────────────────────────────────────────────────────────────
// WritingCoachDiagnosisRunner — 诊断链路执行器（独立类，无 part）
//
// R-019 真分解：从写作教练诊断流程中抽出的**独立类**，负责分块/单次诊断
// 链路编排、流式回调、取消/错误优雅复位。所需能力经 WritingCoachPanelHost
// 注入，不隐式依赖 State 私有成员，也不使用 part / extension。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/diagnosis_temperature.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/chapter_repository.dart';
import '../../data/repositories/diagnosis_repository.dart';
import '../../data/repositories/event_fact_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/chat_store.dart';
import '../../providers/session_providers.dart';
import '../../services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import '../../services/chat_service.dart';
import '../../services/progressive_diagnosis.dart';
import '../../services/story_structure_profile.dart';
import '../../types/teaching_types.dart';
import 'writing_coach_panel_store.dart' show writingCoachStoreProvider;
import 'writing_coach_panel_host.dart';

/// 诊断完成提示（短时 floating SnackBar，不遮挡后续操作）。
void showDiagnosisCompleteSnack(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('诊断完成'),
      duration: Duration(milliseconds: 1200),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 诊断链路执行器（分块 + 单次 + 流式回调 + 取消/错误复位）。
class WritingCoachDiagnosisRunner {
  final WritingCoachPanelHost _host;

  WritingCoachDiagnosisRunner(this._host);

  WidgetRef get _ref => _host.ref;

  String get _chapterId => _host.chapterId;

  /// ADR-0006：构建结构画像文本（失败/降级 ⇒ null ⇒ 调用方按空串处理）。
  Future<String?> _buildProfileText() async {
    final db = _ref.read(appDatabaseProvider);
    final chapter = await ChapterRepository(db).getChapter(_chapterId);
    if (chapter == null) return null;
    return buildStoryStructureProfileText(
      eventFactRepo: EventFactRepository(db),
      chapterRepo: ChapterRepository(db),
      diagnosisRepo: DiagnosisRepository(db),
      manuscriptId: chapter.manuscriptId,
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
  /// ADR-0006：结构画像文本（失败/降级 ⇒ 空串）。
  Future<String> _profileText() async => (await _buildProfileText()) ?? '';

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
    // ADR-0006：结构画像（覆盖度不足/事件表空 ⇒ 空串，零行为变更）。
    final profileText = await _profileText();
    final progressive = await runProgressiveDiagnosis(
      content: content,
      title: title,
      llmClient: _ref.read(llmClientProvider),
      sessionId: sid,
      teachingMode: _host.teachingMode,
      structureProfile: profileText,
      disabledSyndromeIds: diagPrefs?.effectiveDisabledIds ?? const {},
      mergeTemperature: await _mergeTemperature(),
      onContent: (delta) {
        _ref
            .read(writingCoachStoreProvider(_chapterId).notifier)
            .appendStreamingContent(delta);
      },
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

  /// 诊断完成：刷新消息 + 复位流式/诊断中 + 完成反馈。
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
