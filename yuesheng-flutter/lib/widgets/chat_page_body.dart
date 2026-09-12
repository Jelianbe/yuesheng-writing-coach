// ─────────────────────────────────────────────────────────────
// chat_page_body — 聊天页主体视图（头部/任务面板/消息/输入装配）
//
// 从 chat_page.dart 的 192 行 `_buildBody`（形态 b：页面骨架过长）真分解
// 而来：宿主只保留数据装配，渲染树拆为 [ChatPageBody] 及其分区组件。
// 消息/错误条/输入栏分区见 chat_page_sections.dart。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/fact_batch_providers.dart';
import '../providers/practice_providers.dart';
import '../services/attitude_advisor.dart';
import '../types/teaching_types.dart';
import 'attitude_suggestion_banner.dart';
import 'chat_attitude_controller.dart';
import 'chat_diagnosis_controller.dart';
import 'chat_header.dart';
import 'chat_input.dart';
import 'chat_messages_controller.dart';
import 'chat_page_sections.dart';
import 'chat_reference_controller.dart';
import 'chat_session_controller.dart';
import 'chat_teaching_controller.dart';
import 'encouragement_text.dart';
import 'task_panel.dart';

/// 聊天页主体（bootstrap 就绪后）
class ChatPageBody extends ConsumerWidget {
  final ChatState chatState;
  final AttitudeLevel attitude;
  final TeachingPhase phase;
  final String? primaryRefTitle;
  final AttitudeSuggestion? attitudeSuggestion;
  final List<ActiveProblemView> activeProblems;
  final bool showTaskPanel;
  final String inputText;
  final GlobalKey<ChatInputState> chatInputKey;
  final ValueChanged<String> onInputChange;
  final VoidCallback onToggleTaskPanel;
  final VoidCallback onOpenSessionDrawer;
  final ChatAttitudeController attitudeController;
  final ChatDiagnosisController diagnosis;
  final ChatTeachingController teaching;
  final ChatReferenceController reference;
  final ChatMessagesController messages;
  final ChatSessionController session;

  const ChatPageBody({
    super.key,
    required this.chatState,
    required this.attitude,
    required this.phase,
    required this.primaryRefTitle,
    required this.attitudeSuggestion,
    required this.activeProblems,
    required this.showTaskPanel,
    required this.inputText,
    required this.chatInputKey,
    required this.onInputChange,
    required this.onToggleTaskPanel,
    required this.onOpenSessionDrawer,
    required this.attitudeController,
    required this.diagnosis,
    required this.teaching,
    required this.reference,
    required this.messages,
    required this.session,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practiceState = ref.watch(practiceStoreProvider);
    final evaluationState = ref.watch(evaluationReportsProvider);
    final factBatches = ref.watch(factBatchProvider);
    return Column(
      children: [
        ChatHeaderSection(
          attitude: attitude,
          primaryRefTitle: primaryRefTitle,
          suggestion: attitudeSuggestion,
          onOpenSessionDrawer: onOpenSessionDrawer,
          attitudeController: attitudeController,
          session: session,
          reference: reference,
          messages: messages,
        ),
        ChatTaskSection(
          chatState: chatState,
          phase: phase,
          showTaskPanel: showTaskPanel,
          activeProblems: activeProblems,
          onToggle: onToggleTaskPanel,
          diagnosis: diagnosis,
        ),
        Expanded(
          child: ChatMessageSection(
            chatState: chatState,
            practiceState: practiceState,
            evaluationState: evaluationState,
            factBatches: factBatches,
            teaching: teaching,
            reference: reference,
            messages: messages,
          ),
        ),
        if (chatState.error != null) ChatErrorBar(chatState: chatState),
        ChatComposerSection(
          inputText: inputText,
          isStreaming: chatState.isStreaming,
          chatInputKey: chatInputKey,
          onInputChange: onInputChange,
          teaching: teaching,
          reference: reference,
        ),
      ],
    );
  }
}

/// 头部状态区：ChatHeader + 态度建议横幅
class ChatHeaderSection extends StatelessWidget {
  final AttitudeLevel attitude;
  final String? primaryRefTitle;
  final AttitudeSuggestion? suggestion;
  final VoidCallback onOpenSessionDrawer;
  final ChatAttitudeController attitudeController;
  final ChatSessionController session;
  final ChatReferenceController reference;
  final ChatMessagesController messages;

  const ChatHeaderSection({
    super.key,
    required this.attitude,
    required this.primaryRefTitle,
    required this.suggestion,
    required this.onOpenSessionDrawer,
    required this.attitudeController,
    required this.session,
    required this.reference,
    required this.messages,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ChatHeader(
          currentAttitude: attitude,
          onAttitudeChange: attitudeController.handleAttitudeChange,
          onOpenSessionDrawer: onOpenSessionDrawer,
          onOpenProfile: messages.handleOpenProfile,
          // 批次 29：头部 ⋯ 左侧新建对话快捷入口
          onNewSession: session.handleCreateSession,
          primaryRefTitle: primaryRefTitle,
          onTapPrimaryRef: reference.handleOpenReferences,
        ),
        // 批次 12：态度建议横幅（对齐 RN 位于头部下方、内容上方）
        if (suggestion != null)
          AttitudeSuggestionBanner(
            suggestion: suggestion!,
            onAccept: attitudeController.handleAcceptAttitudeSuggestion,
            onDismiss: attitudeController.handleDismissAttitudeSuggestion,
          ),
      ],
    );
  }
}

/// P2 阶段任务区：任务开关 + 鼓励文案 + 活跃问题面板
class ChatTaskSection extends StatelessWidget {
  final ChatState chatState;
  final TeachingPhase phase;
  final bool showTaskPanel;
  final List<ActiveProblemView> activeProblems;
  final VoidCallback onToggle;
  final ChatDiagnosisController diagnosis;

  const ChatTaskSection({
    super.key,
    required this.chatState,
    required this.phase,
    required this.showTaskPanel,
    required this.activeProblems,
    required this.onToggle,
    required this.diagnosis,
  });

  @override
  Widget build(BuildContext context) {
    // 批次 10：鼓励文案显示条件（对齐 RN showEncouragement：存在诊断结果消息）
    final hasDiagnosis = chatState.messages.any(
      (m) => m.messageType == 'diagnosis_result',
    );
    final encouragementSeed = chatState.messages
        .where((m) => m.messageType == 'diagnosis_result')
        .map((m) => m.timestamp)
        .fold<int>(0, (a, b) => a + b);
    final isP2 = phase == TeachingPhase.p2PracticeLoop;
    return Column(
      children: [
        // 批次 18：P2 阶段任务面板开关（对齐 RN chat.tsx L396-400 taskToggle）
        if (isP2)
          TaskToggleBar(
            showTaskPanel: showTaskPanel,
            problemCount: activeProblems.length,
            onTap: onToggle,
          ),
        // 鼓励文案（对齐 RN chat.tsx L404：诊断完成后显示）
        if (hasDiagnosis && !chatState.isStreaming)
          EncouragementText(seed: encouragementSeed),
        // 批次 18：P2 阶段 + 展开时显示活跃问题面板（对齐 RN taskPanelContainer height 200）
        if (isP2 && showTaskPanel)
          SizedBox(
            height: 200,
            child: TaskPanel(
              problems: activeProblems,
              onMarkComplete: diagnosis.handleMarkComplete,
              // 批次75：活跃问题条目移除入口（主观不再追踪）
              onRemove: diagnosis.handleRemoveProblem,
            ),
          ),
      ],
    );
  }
}

/// 任务面板展开/收起开关条
class TaskToggleBar extends StatelessWidget {
  final bool showTaskPanel;
  final int problemCount;
  final VoidCallback onTap;

  const TaskToggleBar({
    super.key,
    required this.showTaskPanel,
    required this.problemCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.smx,
        ),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(bottom: BorderSide(color: AppColors.borderSoft)),
        ),
        child: Row(
          children: [
            const Icon(Icons.task_alt, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              showTaskPanel ? '收起任务' : '任务 ($problemCount)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
