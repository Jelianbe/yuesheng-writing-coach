// ─────────────────────────────────────────────────────────────
// chat_page_sections — 聊天页消息列表 / 错误条 / 输入栏分区组件
//
// 从 chat_page.dart 的 192 行 `_buildBody`（形态 b：页面骨架过长）真分解
// 而来：纯渲染 + 回调装配，State 私有方法均经控制器公有 API 传入。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/app_theme.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/fact_batch_providers.dart';
import '../providers/practice_providers.dart';
import '../router/app_routes.dart';
import 'chat_input.dart';
import 'chat_messages_controller.dart';
import 'chat_reference_controller.dart';
import 'chat_teaching_controller.dart';
import 'chat_welcome.dart';
import 'message_list.dart';

/// 消息列表分区（含练习卡 / 评估报告 / 空态欢迎）
class ChatMessageSection extends ConsumerWidget {
  final ChatState chatState;
  final PracticeState practiceState;
  final EvaluationReportsState evaluationState;
  final Map<String, FactBatchRecord> factBatches;
  final ChatTeachingController teaching;
  final ChatReferenceController reference;
  final ChatMessagesController messages;

  const ChatMessageSection({
    super.key,
    required this.chatState,
    required this.practiceState,
    required this.evaluationState,
    required this.factBatches,
    required this.teaching,
    required this.reference,
    required this.messages,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MessageList(
      messages: chatState.messages,
      isStreaming: chatState.isStreaming,
      streamingContent: chatState.streamingContent,
      streamStageLabel: chatState.streamStageLabel,
      failedMessageIds: chatState.failedMessageIds,
      onRetry: messages.handleRetry,
      onDelete: messages.handleDelete,
      activePracticeTask: practiceState.activePracticeTask,
      trainingResult: practiceState.trainingResult,
      isPracticeSubmitting: practiceState.isSubmitting,
      onSubmitPractice: teaching.submitPractice,
      onSkipPractice: reference.handleSkipPractice,
      onDismissResult: () =>
          ref.read(practiceStoreProvider.notifier).setTrainingResult(null),
      onRetryPractice: () =>
          ref.read(practiceStoreProvider.notifier).retryPractice(),
      evaluationReports: evaluationState.reports,
      // C78 批次3（FR-10）：批次沉淀提示卡数据（内存态，重启即失）
      factBatches: factBatches,
      onDismissEvaluationReport: (messageId) => ref
          .read(evaluationReportsProvider.notifier)
          .dismissEvaluationReport(messageId),
      onSaveToFile: reference.handleSaveToFile,
      // 批次61：Teacher 建议卡「教我原理」→ 发消息请求讲解
      onTeachPrinciple: teaching.handleTeachPrinciple,
      // 批次81：三卡回调接线（H1-H3）
      onContinueTraining: messages.handleContinueTraining,
      onViewProfile: messages.handleViewProfile,
      onBackToChat: messages.handleFocusChatInput,
      onAddContent: messages.handleFocusChatInput,
      onContinueChat: messages.handleFocusChatInput,
      onPartialAgreementSubmit: messages.handlePartialAgreementSubmit,
      onPartialAgreementSkip: messages.handlePartialAgreementSkip,
      // 空态 → 欢迎态（对齐 RN messages.length===0 → ChatWelcome）
      emptyWidget: Center(
        child: ChatWelcome(
          onStartWriting: () => context.go(AppRoutes.bookshelf),
        ),
      ),
    );
  }
}

/// bootstrap 失败态（P2-7：release 构建中不向用户展示 stack trace 技术细节）
class ChatBootstrapErrorView extends StatelessWidget {
  final Object error;

  const ChatBootstrapErrorView({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 32, color: AppColors.danger),
          const SizedBox(height: 8),
          const Text('初始化失败，请重试', style: AppTextStyles.body),
          const SizedBox(height: 4),
          if (kDebugMode)
            Text(
              '$error',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textTertiary,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}

/// 发送失败错误条（release 静默：不展示异常技术细节，对齐 P2-7 铁律）
class ChatErrorBar extends ConsumerWidget {
  final ChatState chatState;

  const ChatErrorBar({super.key, required this.chatState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: AppColors.dangerBg,
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kDebugMode ? chatState.error! : '发送失败，请稍后重试',
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: () => ref.read(chatStoreProvider.notifier).clearError(),
          ),
        ],
      ),
    );
  }
}

/// 底部输入栏分区
class ChatComposerSection extends StatelessWidget {
  final String inputText;
  final bool isStreaming;
  final GlobalKey<ChatInputState> chatInputKey;
  final ValueChanged<String> onInputChange;
  final ChatTeachingController teaching;
  final ChatReferenceController reference;

  const ChatComposerSection({
    super.key,
    required this.inputText,
    required this.isStreaming,
    required this.chatInputKey,
    required this.onInputChange,
    required this.teaching,
    required this.reference,
  });

  @override
  Widget build(BuildContext context) {
    return ChatInput(
      key: chatInputKey,
      input: inputText,
      isStreaming: isStreaming,
      onInputChange: onInputChange,
      onSend: teaching.handleSend,
      onStop: teaching.cancelGeneration,
      onUploadFile: reference.handleUploadFile,
      onMention: reference.handleMention,
    );
  }
}
