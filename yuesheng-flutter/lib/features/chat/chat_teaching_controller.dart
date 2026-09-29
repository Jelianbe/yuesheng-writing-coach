// ─────────────────────────────────────────────────────────────
// chat_teaching_controller — 聊天页发送/训练动作控制器
//
// 从 chat_teaching.dart（原 part/extension）真分解而来：
//   handleSend / cancelGeneration / submitPractice
//   / buildEvaluationReportForLastMessage / handleTeachPrinciple
//
// 原 174 行 `_handleSend` 超限方法拆为 handleSend（薄编排）+ _buildCallbacks
//   + _buildOptions（@ 引用解析另拆 chat_mention_resolver.dart），满足 R-019。
//
// 依赖经 [ChatPageHost] 显式注入；取消令牌由本控制器私有持有。
// ─────────────────────────────────────────────────────────────

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/session_repository.dart';
import '../../data/repositories/student_model_repository.dart';
import '../../data/repositories/training_result_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/chat_store.dart';
import '../../providers/evaluation_providers.dart';
import '../../providers/practice_providers.dart';
import '../../providers/session_providers.dart';
import '../../services/chat_message_types.dart';
import '../../types/teaching_types.dart';
import '../onboarding/api_config_nudge.dart';
import 'chat_mention_resolver.dart';
import 'chat_page_host.dart';

/// 聊天页发送与训练动作
class ChatTeachingController {
  final ChatPageHost host;

  /// @ 引用解析（解析 / 落库 / 快照 / 反馈）
  late final ChatMentionResolver _mentions = ChatMentionResolver(host);

  /// 当前进行中的流式请求取消令牌；非 null 表示正在生成，可用于「停止生成」。
  CancelToken? _cancelToken;

  /// 流式「代际」号：每发起一次发送自增。A4 会话守卫只防「跨会话」旧流，
  /// 不防「同会话内」上一轮流的迟到 chunk/缓冲——暂停（Teacher 段被软取消）
  /// 后用户紧接着回答「原因」/提交反馈时，旧 run 的 onStream 仍会往共享的
  /// streamingContent 增量上拼，导致新旧输出混进同一个气泡。代际号让旧 run
  /// 的回调在新 run 开始后全部失效（与 A4 isCurrentSession 同模式，只是维度
  /// 从会话换成「这一轮生成」）。
  int _generation = 0;

  ChatTeachingController(this.host);

  /// 发送消息（含 @ 引用解析、流式回调装配、取消令牌生命周期）。
  Future<void> handleSend(
    String text, {
    TeachingSubphase? subphase,
    void Function(TrainingResult)? onTrainingResult,
    // 批次49：流式阶段标签（诊断/评估等场景 ThinkingIndicator 阶段化文案）
    String? stageLabel,
    // 批次98：诊断场景待诊断全文——对话历史只落库简洁消息，全文运行时注入
    String? chapterFullText,
  }) async {
    if (text.isEmpty) return;
    // C2：首次在对话里发起真实请求且未配 API → 弹一次性「配置 API」引导。
    await maybeShowApiConfigNudge(
      host.context,
      host.ref.read(appDatabaseProvider),
    );
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;

    final mention = await _mentions.resolve(text, bootstrap.sessionId);
    if (mention.text.trim().isEmpty) return;
    _mentions.showFeedback(mention);

    host.ref
        .read(chatStoreProvider.notifier)
        .setStreaming(true, stageLabel: stageLabel);
    // ADR-C84：发送即清空输入栏（消息已发出，输入栏立即可编辑下一条）
    if (host.mounted) host.setInputText('');

    final chatService = host.ref.read(chatServiceProvider);
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;
    // 代际号 +1：本轮的回调只认这个号；暂停/新发送都会让旧 run 回调失效。
    final gen = ++_generation;
    try {
      await chatService.sendMessage(
        bootstrap.sessionId,
        mention.text,
        _buildCallbacks(bootstrap.sessionId, onTrainingResult, gen),
        _buildOptions(cancelToken, chapterFullText, mention.referencesJson),
        subphase: subphase,
      );
    } catch (e) {
      host.ref.read(chatStoreProvider.notifier).setError(e.toString());
    } finally {
      // 无论完成/失败/取消，令牌都一次性作废，下次发送新建
      _cancelToken = null;
    }
  }

  /// 装配流式回调（落库上屏 / 流式增量 / 完成复位 / 取消 / Teacher 两段式）。
  SendMessageCallbacks _buildCallbacks(
    String sessionId,
    void Function(TrainingResult)? onTrainingResult,
    int gen,
  ) {
    // A4：闭包捕获的 sessionId 必须仍是当前激活会话，否则旧会话 chunk/完成/错误一律丢弃。
    bool isCurrentSession() =>
        host.ref.read(sessionBootstrapProvider).valueOrNull?.sessionId ==
        sessionId;
    // 代际守卫：同会话内上一轮（已暂停/已完结）run 的迟到回调一律丢弃（暂停混流修复）。
    bool isCurrentGeneration() => _generation == gen;
    return SendMessageCallbacks(
      // ADR-C84：用户消息落库即上屏（流式中断/失败也保证消息可见）
      onUserMessagePersisted: (message) {
        if (!isCurrentGeneration()) return;
        host.ref.read(chatStoreProvider.notifier).addMessage(message);
      },
      onStream: (delta) {
        if (!isCurrentSession() || !isCurrentGeneration()) return;
        host.ref.read(chatStoreProvider.notifier).appendStreamingContent(delta);
      },
      onComplete: (fullContent, messageId) => _onStreamComplete(sessionId, gen),
      onError: (error) {
        if (!isCurrentSession() || !isCurrentGeneration()) return;
        host.ref.read(chatStoreProvider.notifier).setError(error);
      },
      onCancelled: () {
        if (!isCurrentGeneration()) return;
        host.ref.read(chatStoreProvider.notifier).cancelStreaming();
      },
      onTeacherPhase: (teacherActive) {
        if (!isCurrentGeneration()) return;
        // 两段式流透明化：保留已显示的回复，仅切换阶段文案
        host.ref
            .read(chatStoreProvider.notifier)
            .updateStreamingStageLabel(teacherActive ? '正在生成教学建议…' : null);
      },
      onTeacherCancelled: _showTeacherCancelledSnack,
      onTrainingResult: onTrainingResult,
    );
  }

  /// 流式完成：回读消息列表展示已落库诊断卡；仅当代际仍是当前 run 时才复位
  /// 流式标志并触发态度检查，避免旧 onComplete 清掉新一轮气泡（见 Bug2 修复）。
  Future<void> _onStreamComplete(String sessionId, int gen) async {
    bool stillHere() =>
        host.ref.read(sessionBootstrapProvider).valueOrNull?.sessionId ==
        sessionId;
    if (!stillHere()) return;
    final isCurrentGen = _generation == gen;
    final sessionRepo = SessionRepository(host.ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(sessionId);
    if (!stillHere()) return;
    host.ref.read(chatStoreProvider.notifier).setMessages(messages);
    if (isCurrentGen) {
      host.ref.read(chatStoreProvider.notifier).setStreaming(false);
      host.scheduleAttitudeCheck();
    }
  }

  /// Teacher 建议被用户暂停：轻提示解释「暂停后仍出现症候卡」。
  void _showTeacherCancelledSnack() {
    if (!host.mounted) return;
    ScaffoldMessenger.of(
      host.context,
    ).showSnackBar(const SnackBar(content: Text('诊断已完成，教学建议已停止')));
  }

  /// 装配发送选项（阶段/态度/全文注入/心流信号/引用快照/取消令牌）。
  SendMessageOptions _buildOptions(
    CancelToken cancelToken,
    String? chapterFullText,
    String? referencesJson,
  ) {
    return SendMessageOptions(
      phase: TeachingPhase.p0Engage,
      attitude: host.attitude,
      teachingMode: host.teachingMode,
      // 批次98：诊断全文运行时注入（不落库）
      chapterFullText: chapterFullText,
      // 批次7 O1：心流判定叠加编辑器活跃维度
      lastEditorEditAtSec: host.ref.read(editorActivityProvider),
      // 批次71：@ 引用快照随消息落库
      referencesJson: referencesJson,
      // 取消令牌：让用户在生成中可主动中止
      cancelToken: cancelToken,
    );
  }

  /// 主动停止当前生成（「停止生成」按钮回调）。
  ///
  /// 除取消 HTTP 请求外，还要：
  /// 1. 代际号 +1 —— 让本轮（被暂停的 run）所有在途回调失效，迟到的
  ///    onStream 增量不会拼到用户接下来发的「原因/反馈」新一轮气泡里；
  /// 2. 立即清空待渲染的 streamingContent —— Teacher 段被软取消时
  ///    onTeacherCancelled 只弹提示、缓冲要等 onComplete 才清，这个窗口里
  ///    残留的旧诊断/教学建议文本必须当场清掉，不留给下一轮。
  void cancelGeneration() {
    _generation++;
    _cancelToken?.cancel('用户取消生成');
    host.ref.read(chatStoreProvider.notifier).cancelStreaming();
  }

  /// T3 训练系统：提交练习作答（复用 handleSend，强制 subphase=FEEDBACK）。
  Future<void> submitPractice(
    String content, [
    TrainingSelfAssessment? assessment,
  ]) async {
    final practiceStore = host.ref.read(practiceStoreProvider.notifier);
    practiceStore.setSubmitting(true);
    try {
      await handleSend(
        content,
        subphase: TeachingSubphase.feedback,
        // 批次49：训练评估打标
        stageLabel: '正在评估你的改写…',
        onTrainingResult: (result) {
          practiceStore.setTrainingResult(result);
          buildEvaluationReportForLastMessage();
          // P0-1 教学线：自评回写（异步，失败不阻断）
          if (assessment != null) {
            _persistSelfAssessment(assessment);
          }
        },
      );
    } finally {
      practiceStore.setSubmitting(false);
      practiceStore.submitPractice();
    }
  }

  /// P0-1 教学线：训练轮落库后回写自评。
  /// 时序保证：onTrainingResult 在 handleTrainingResult
  /// 的 _persistTrainingResult 之后触发，最新训练结果已落库。
  Future<void> _persistSelfAssessment(TrainingSelfAssessment assessment) async {
    try {
      final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
      if (bootstrap == null) return;
      final repo = TrainingResultRepository(host.ref.read(appDatabaseProvider));
      final latest = await repo.queryBySession(bootstrap.sessionId);
      if (latest.isEmpty) return;
      await repo.updateSelfAssessment(latest.first.id, assessment);
      // 批1·N2：回忆难度自评补进 teaching_history 的最近一条 training 记录
      // （供 message_injector 的 FSRS 复习调度消费）。无 rating 时跳过。
      if (assessment.userRating != null) {
        await StudentModelRepository(
          host.ref.read(appDatabaseProvider),
        ).updateLatestTrainingRating(
          bootstrap.sessionId,
          rating: assessment.userRating!,
          syndromeId: latest.first.syndromeId,
        );
      }
    } catch (e, s) {
      debugPrint('[SelfAssessment] 回写失败: $e $s');
    }
  }

  /// T4 评估报告：训练反馈落库后，为最后一条 assistant 消息构建评估报告。
  Future<void> buildEvaluationReportForLastMessage() async {
    final bootstrap = host.ref.read(sessionBootstrapProvider).valueOrNull;
    if (bootstrap == null) return;
    final sessionRepo = SessionRepository(host.ref.read(appDatabaseProvider));
    final messages = await sessionRepo.listMessages(bootstrap.sessionId);
    final lastAssistant = messages
        .where((m) => m.role == 'assistant')
        .lastOrNull;
    if (lastAssistant != null) {
      await host.ref
          .read(evaluationReportsProvider.notifier)
          .buildEvaluationReport(bootstrap.sessionId, lastAssistant.id);
    }
  }

  /// 批次61：Teacher 建议卡「教我原理」→ 发送原理讲解请求。
  void handleTeachPrinciple(String syndromeName) {
    if (host.ref.read(chatStoreProvider).isStreaming) return;
    host.setInputText('');
    handleSend(
      '我想了解「$syndromeName」的原理。请用简单的话给我讲清楚：'
      '它是什么、怎么判断、怎么避免。一次只讲一个点。',
    );
    host.scheduleAttitudeCheck();
  }
}
