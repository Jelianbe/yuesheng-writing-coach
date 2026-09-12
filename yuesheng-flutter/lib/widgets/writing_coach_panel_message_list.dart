// ─────────────────────────────────────────────────────────────
// WritingCoachMessageList — 教练面板消息列表（独立 Widget）
//
// R-019 真分解：从 _WritingCoachPanelState 的 _buildMessageList（原 188 行）
// 抽出的**独立 ConsumerWidget**。所需状态（isInitLoading / sessionId /
// streamStageLabel / isDiagnosing / scrollController）与回调（onAdopt /
// onTeachPrinciple / onPartialAgreementSubmit / onPartialAgreementSkip /
// onFocusInput / onDeleteMessage / onPracticeSubmit）**全部通过构造参数
// 显式传入**；practiceStoreProvider / evaluationReportsProvider 由本 Widget
// 自行 watch（Riverpod 提供），不再隐式依赖 State 私有成员。
//
// 行为与原实现完全一致（纯结构搬运）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../data/database/database.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/practice_providers.dart';
import '../router/app_routes.dart';
import 'message_bubble.dart';
import 'message_card_dispatcher.dart';
import 'practice_result_indicator.dart';
import 'practice_task_card.dart';
import 'writing/thinking_placeholder.dart';

class WritingCoachMessageList extends ConsumerWidget {
  final ChatState chatState;

  /// P2-3：初始化是否完成（未完成显示 loading，避免闪空状态）
  final bool isInitLoading;

  /// 当前会话 id（流式气泡的 sessionId 归属）
  final String? sessionId;

  /// 批次49：流式阶段标签（决定占位文案 + 是否加阶段角标）
  final String? streamStageLabel;

  /// D5-A：是否诊断中（驱动占位文案）
  final bool isDiagnosing;

  /// 消息列表滚动控制器（自动滚动到底部由宿主负责驱动）
  final ScrollController scrollController;

  /// 采纳建议回调（null 表示不建议采纳按钮）
  final void Function(String suggestion)? onAdopt;

  /// Teacher 建议卡「教我原理」
  final void Function(String syndromeName) onTeachPrinciple;

  /// 部分认同：提交反馈
  final void Function(String feedback, String? quickOption)
  onPartialAgreementSubmit;

  /// 部分认同：跳过此症候
  final VoidCallback onPartialAgreementSkip;

  /// 三卡「返回对话 / 补充内容 / 继续对话」→ 聚焦输入栏
  final VoidCallback onFocusInput;

  /// 长按消息 → 删除
  final void Function(Message message) onDeleteMessage;

  /// T3：练习任务卡提交（复用发送链路，由会话动作承接）
  final void Function(String content) onPracticeSubmit;

  const WritingCoachMessageList({
    super.key,
    required this.chatState,
    required this.isInitLoading,
    required this.sessionId,
    required this.streamStageLabel,
    required this.isDiagnosing,
    required this.scrollController,
    required this.onAdopt,
    required this.onTeachPrinciple,
    required this.onPartialAgreementSubmit,
    required this.onPartialAgreementSkip,
    required this.onFocusInput,
    required this.onDeleteMessage,
    required this.onPracticeSubmit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // P2-3：初始化未完成时显示 loading，避免先闪空状态再突然出现消息
    if (isInitLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }
    // T3：练习任务卡 + 结果指示器（activePracticeTask / trainingResult 非空时渲染在列表底部）
    final practiceState = ref.watch(practiceStoreProvider);
    // T4：评估报告（messageId → EvaluationData）
    final evaluationState = ref.watch(evaluationReportsProvider);
    final practiceWidgets = _buildPracticeWidgets(ref, practiceState);
    if (chatState.messages.isEmpty && !chatState.isStreaming) {
      return _buildEmptyState();
    }
    return _buildScrollList(ref, context, practiceWidgets, evaluationState);
  }

  /// 空状态：居中「有问题问教练」提示。
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: AppColors.disabledText,
          ),
          SizedBox(height: 8),
          Text('有问题问教练', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  /// 练习任务卡 / 结果指示器（并入滚动列表底部，避免固定高度 Column 溢出）。
  List<Widget> _buildPracticeWidgets(WidgetRef ref, PracticeState state) {
    final widgets = <Widget>[];
    if (state.activePracticeTask != null) {
      widgets.add(
        PracticeTaskCard(
          task: state.activePracticeTask!,
          submitting: state.isSubmitting,
          onSubmit: onPracticeSubmit,
          onSkip: () => ref.read(practiceStoreProvider.notifier).skipPractice(),
        ),
      );
    }
    if (state.trainingResult != null) {
      widgets.add(
        PracticeResultIndicator(
          result: state.trainingResult!,
          onDismiss: () =>
              ref.read(practiceStoreProvider.notifier).setTrainingResult(null),
          onRetry: () =>
              ref.read(practiceStoreProvider.notifier).retryPractice(),
        ),
      );
    }
    return widgets;
  }

  /// 滚动列表：消息 + 流式占位/气泡 + 练习卡，全部包裹 RepaintBoundary。
  Widget _buildScrollList(
    WidgetRef ref,
    BuildContext context,
    List<Widget> practiceWidgets,
    EvaluationReportsState evaluationState,
  ) {
    final messages = chatState.messages;
    final streamingOverhead = chatState.isStreaming ? 1 : 0;
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            // X-039-Batch1：12→md / 8→sm
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            itemCount:
                messages.length + streamingOverhead + practiceWidgets.length,
            itemBuilder: (context, index) {
              final practiceIndex = index - messages.length - streamingOverhead;
              if (practiceIndex >= 0) {
                return RepaintBoundary(
                  key: ValueKey('coach-item-practice-$practiceIndex'),
                  child: practiceWidgets[practiceIndex],
                );
              }
              if (index == messages.length && chatState.isStreaming) {
                return _buildStreamingItem();
              }
              return _buildMessageItem(
                ref,
                context,
                messages[index],
                evaluationState,
              );
            },
          ),
        ),
      ],
    );
  }

  /// 流式 item：占位（无内容/诊断阶段）或流式气泡（带阶段角标）。
  Widget _buildStreamingItem() {
    // 批次51：诊断阶段即使已有流式内容也显示占位（交付物是 DiagnosisCard，
    // 隐藏流式前导文本，避免「先长文本后变卡片」跳变）。
    final isDiagnosisStage = streamStageLabel?.startsWith('正在诊断') ?? false;
    if (chatState.streamingContent.isEmpty || isDiagnosisStage) {
      return RepaintBoundary(
        key: const ValueKey('coach-item-thinking'),
        child: ThinkingPlaceholder(
          isDiagnosing: isDiagnosing,
          label: streamStageLabel,
        ),
      );
    }
    final streamMsg = Message(
      id: '__streaming__',
      sessionId: sessionId ?? '',
      role: 'assistant',
      content: chatState.streamingContent,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      messageType: 'chat',
    );
    final streamBubble = MessageBubble(message: streamMsg, isStreaming: true);
    // 批次49：流式气泡顶部加阶段角标（与 message_list 一致）
    if (streamStageLabel == null) {
      return RepaintBoundary(
        key: const ValueKey('coach-item-__streaming__'),
        child: streamBubble,
      );
    }
    return RepaintBoundary(
      key: const ValueKey('coach-item-__streaming__'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            // X-039-Batch1：12→md / 2→xxs
            padding: const EdgeInsets.only(
              left: AppSpacing.md,
              bottom: AppSpacing.xxs,
            ),
            child: Text(streamStageLabel!, style: AppTextStyles.microCaption),
          ),
          streamBubble,
        ],
      ),
    );
  }

  /// 单条消息 item：卡片分派（命中）或普通气泡，均支持长按删除。
  Widget _buildMessageItem(
    WidgetRef ref,
    BuildContext context,
    Message msg,
    EvaluationReportsState evaluationState,
  ) {
    // 批次5（5.1）：卡片分派统一走 MessageCardDispatcher
    final card = dispatchMessageCard(
      msg: msg,
      isStreamingBubble: false,
      evaluationReport: evaluationState.reports[msg.id],
      onTeachPrinciple: onTeachPrinciple,
      onDismissEvaluationReport: () => ref
          .read(evaluationReportsProvider.notifier)
          .dismissEvaluationReport(msg.id),
      onAdoptSuggestion: onAdopt != null ? () => onAdopt!(msg.content) : null,
      // 批次81：三卡回调接线（H1-H3）
      onContinueTraining: () =>
          ref.read(practiceStoreProvider.notifier).retryPractice(),
      onViewProfile: () => context.push(AppRoutes.growthDetail),
      onBackToChat: onFocusInput,
      onAddContent: onFocusInput,
      onContinueChat: onFocusInput,
      onPartialAgreementSubmit: onPartialAgreementSubmit,
      onPartialAgreementSkip: onPartialAgreementSkip,
    );
    if (card != null) {
      // 批次53：RepaintBoundary 隔离；批次74：卡片消息支持长按删除
      return RepaintBoundary(
        key: ValueKey('coach-item-${msg.id}'),
        child: GestureDetector(
          onLongPress: () => onDeleteMessage(msg),
          child: card,
        ),
      );
    }
    // 批次74：普通气泡长按删除（对齐对话页长按删除心智）
    return RepaintBoundary(
      key: ValueKey('coach-item-${msg.id}'),
      child: MessageBubble(message: msg, onLongPress: onDeleteMessage),
    );
  }
}
