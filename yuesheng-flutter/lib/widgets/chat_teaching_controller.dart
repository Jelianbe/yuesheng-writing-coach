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

import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/practice_providers.dart';
import '../providers/session_providers.dart';
import '../services/chat_message_types.dart';
import '../types/teaching_types.dart';
import 'chat_mention_resolver.dart';
import 'chat_page_host.dart';

/// 聊天页发送与训练动作
class ChatTeachingController {
  final ChatPageHost host;

  /// @ 引用解析（解析 / 落库 / 快照 / 反馈）
  late final ChatMentionResolver _mentions = ChatMentionResolver(host);

  /// 当前进行中的流式请求取消令牌；非 null 表示正在生成，可用于「停止生成」。
  CancelToken? _cancelToken;

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
    try {
      await chatService.sendMessage(
        bootstrap.sessionId,
        mention.text,
        _buildCallbacks(bootstrap.sessionId, onTrainingResult),
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
  ) {
    return SendMessageCallbacks(
      // ADR-C84：用户消息落库即上屏（流式中断/失败也保证消息可见）
      onUserMessagePersisted: (message) {
        host.ref.read(chatStoreProvider.notifier).addMessage(message);
      },
      onStream: (delta) {
        host.ref.read(chatStoreProvider.notifier).appendStreamingContent(delta);
      },
      onComplete: (fullContent, messageId) async {
        final sessionRepo = SessionRepository(
          host.ref.read(appDatabaseProvider),
        );
        final messages = await sessionRepo.listMessages(sessionId);
        host.ref.read(chatStoreProvider.notifier).setMessages(messages);
        host.ref.read(chatStoreProvider.notifier).setStreaming(false);
        // 批次 12：发送完成后延迟检查态度建议（对齐 RN）
        host.scheduleAttitudeCheck();
      },
      onError: (error) {
        host.ref.read(chatStoreProvider.notifier).setError(error);
      },
      onCancelled: () {
        // 用户主动取消：优雅复位（不标记失败、不弹红错）
        host.ref.read(chatStoreProvider.notifier).cancelStreaming();
      },
      onTeacherPhase: (teacherActive) {
        // 两段式流透明化：保留已显示的回复，仅切换阶段文案
        host.ref
            .read(chatStoreProvider.notifier)
            .updateStreamingStageLabel(teacherActive ? '正在生成教学建议…' : null);
      },
      onTeacherCancelled: _showTeacherCancelledSnack,
      onTrainingResult: onTrainingResult,
    );
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
  void cancelGeneration() {
    _cancelToken?.cancel('用户取消生成');
  }

  /// T3 训练系统：提交练习作答（复用 handleSend，强制 subphase=FEEDBACK）。
  Future<void> submitPractice(String content) async {
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
        },
      );
    } finally {
      practiceStore.setSubmitting(false);
      practiceStore.submitPractice();
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
