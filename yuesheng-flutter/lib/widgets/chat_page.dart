// ─────────────────────────────────────────────────────────────
// ChatPage — 主聊天页（T6 接线版本）
// 串联 ChatStore + MessageList + ChatInput + chat_service
//
// 架构：
//   - sessionBootstrapProvider：管理 bootstrap（sessionId + shouldShowOnboarding）
//   - chatStoreProvider：管理聊天状态（messages / isStreaming / error）
//   - chatServiceProvider：发送消息 + 流式回复
//
// MVP 范围：
//   - 只处理 chat 类型消息
//   - 不实现诊断卡片 / 教学建议卡片 / ChatModals 等高级特性
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';

import '../config/app_theme.dart';
import 'yue_sheet.dart';
import '../config/shared_constants.dart';
import '../data/database/database.dart';
import '../data/repositories/chapter_repository.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/reference_repository.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/practice_providers.dart';
import '../providers/session_providers.dart';
import '../providers/work_import_providers.dart';
import '../router/app_router.dart';
import '../services/attitude_advisor.dart';
import '../services/chat_service.dart';
import '../services/message_card_service.dart';
import '../services/progressive_diagnosis.dart';
import '../services/work_import_service.dart';
import '../types/teaching_types.dart';
import 'attitude_suggestion_banner.dart';
import 'abandon_practice_modal.dart';
import 'chat_header.dart';
import 'chat_input.dart';
import 'chat_welcome.dart';
import 'encouragement_text.dart';
import 'import_success_sheet.dart';
import 'message_list.dart';
import 'onboarding_questionnaire.dart';
import 'partial_agreement_card.dart';
import 'reference_bar.dart';
import 'reference_picker.dart';
import 'save_to_file_sheet.dart';
import 'session_drawer.dart';
import 'task_panel.dart';
import 'work_import_sheet.dart';
part 'chat_attitude.dart';
part 'chat_teaching.dart';
part 'chat_session.dart';
part 'chat_reference.dart';
part 'chat_messages.dart';


class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  String _inputText = '';

  /// Scaffold key（ChatHeader 汉堡按钮 → openDrawer）
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 批次70：ChatInput GlobalKey —— 用于在 @ 触发选择后调用 insertMention
  /// 精确插入到光标位置，而非简单拼接在末尾
  final GlobalKey<ChatInputState> _chatInputKey = GlobalKey<ChatInputState>();

  /// 会话列表（SessionDrawer 数据源，listSessionsWithPhase）
  List<SessionWithPhase> _sessions = [];

  /// T6 态度切换：当前态度档位（bootstrap 后从 teaching_state 加载）
  AttitudeLevel _attitude = AttitudeLevel.doubao;

  /// 批次 10 头部状态区：当前教学阶段（loadAttitudeState 返回 phase）
  TeachingPhase _phase = TeachingPhase.p0Engage;

  /// 批次 10 头部状态区：当前 P2 子阶段（teaching_state.current_subphase）
  TeachingSubphase? _subphase;

  /// 批次 12 态度建议：当前展示的建议（null = 不展示）
  AttitudeSuggestion? _attitudeSuggestion;

  /// 批次 12 态度建议：上次建议时间（冷却期判定，对齐 RN lastSuggestionTime）
  int? _lastSuggestionTime;

  /// 批次 18 活跃问题面板：是否展开任务面板（对齐 RN showTaskPanel）
  bool _showTaskPanel = false;

  /// 批次 18 活跃问题面板：当前会话活跃问题列表（对齐 RN activeProblems）
  List<ActiveProblemView> _activeProblems = [];

  /// 批次 30：shell 重建时待打开会话已消费标志（防 build 期重复消费）
  bool _pendingSessionHandled = false;

  /// B20：最近一次发起的消息加载目标会话 ID。快速切换会话时，
  /// 仅最新请求的回调可写入 chatStore，旧的异步结果直接丢弃，杜绝乱序覆盖。
  String? _loadingSessionId;

  /// 当前进行中的流式请求取消令牌；非 null 表示正在生成，可用于「停止生成」。
  CancelToken? _cancelToken;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }



































  // ════════════ 批次81：三卡回调接线（H1-H3）════════════










  @override
  Widget build(BuildContext context) {
    final bootstrapAsync = ref.watch(sessionBootstrapProvider);
    final chatState = ref.watch(chatStoreProvider);

    // 批次 13：成长页「写作诊断」选章 → 切 Tab 后自动诊断（startDiagnosis 语义）
    ref.listen<String?>(pendingDiagnosisChapterProvider, (previous, next) {
      if (next != null && next.isNotEmpty) {
        _handleAutoDiagnose(next);
      }
    });

    // 批次 30：作品详情页「相关对话」点击 → 切 Tab 后打开目标会话
    // 常规路径（书架 push 进入详情页，shell 存活）：pending 设置后监听触发消费
    ref.listen<String?>(pendingOpenSessionProvider, (previous, next) {
      if (next != null && next.isNotEmpty) {
        _consumePendingSession(next);
      }
    });
    // 兜底：详情页可能经 context.go('/') 重建 shell，ChatPage 全新挂载时
    // pending 已先于监听注册被设置（ref.listen 不 fire 初始值），
    // build 时读一次并在帧后消费（_pendingSessionHandled 防重复消费）
    if (!_pendingSessionHandled) {
      final pending = ref.read(pendingOpenSessionProvider);
      if (pending != null && pending.isNotEmpty) {
        _pendingSessionHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _consumePendingSession(pending);
        });
      }
    }

    // bootstrap 完成后加载已有消息
    ref.listen<AsyncValue<SessionBootstrapState>>(sessionBootstrapProvider, (
      previous,
      next,
    ) {
      final bootstrap = next.valueOrNull;
      if (bootstrap != null && !bootstrap.shouldShowOnboarding) {
        _loadAttitude(bootstrap.sessionId);
        _loadSubphase(bootstrap.sessionId);
        _loadSessions(); // 切换/新建会话后刷新列表（updated_at/标题变化）
        // 批次4-M3：恢复该会话的评估报告 + 当前轮次（应用重启/会话切换后）
        ref
            .read(evaluationReportsProvider.notifier)
            .restoreForSession(bootstrap.sessionId);
        final targetSessionId = bootstrap.sessionId;
        // B20：记录最新发起的加载请求，旧请求的异步回调若已不是最新则丢弃，
        // 避免快速切换会话时 last-write-wins 乱序覆盖（不依赖 currentSessionId 是否被设置）。
        _loadingSessionId = targetSessionId;
        final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
        sessionRepo.listMessages(targetSessionId).then((messages) {
          if (!mounted) return;
          if (_loadingSessionId != targetSessionId) return;
          ref.read(chatStoreProvider.notifier).setMessages(messages);
        });
      }
    });

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      // SessionDrawer：会话管理抽屉（ChatHeader 汉堡按钮入口）
      drawer: SessionDrawer(
        sessions: _sessions,
        currentSessionId: bootstrapAsync.valueOrNull?.sessionId,
        onSelect: _handleSwitchSession,
        onCreate: _handleCreateSession,
        // 批次73：长按会话删除
        onDelete: _handleDeleteSession,
      ),
      body: bootstrapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Padding(
          padding: const EdgeInsets.all(16),
          // P2-7：release 构建中不向用户展示 stack trace 技术细节
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 32,
                color: AppColors.danger,
              ),
              const SizedBox(height: 8),
              const Text(
                '初始化失败，请重试',
                style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
              ),
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
        ),
        data: (bootstrap) => _buildBody(bootstrap, chatState),
      ),
    );
  }

  Widget _buildBody(SessionBootstrapState bootstrap, ChatState chatState) {
    // T3 训练系统：读取练习状态（activePracticeTask / trainingResult / isSubmitting）
    final practiceState = ref.watch(practiceStoreProvider);
    // T4 评估报告：messageId → EvaluationData
    final evaluationState = ref.watch(evaluationReportsProvider);

    // 批次 10 头部状态区：
    // 鼓励文案显示条件（对齐 RN showEncouragement）：存在诊断结果消息
    final hasDiagnosis = chatState.messages.any(
      (m) => m.messageType == 'diagnosis_result',
    );
    final encouragementSeed = chatState.messages
        .where((m) => m.messageType == 'diagnosis_result')
        .map((m) => m.timestamp)
        .fold<int>(0, (a, b) => a + b);
    return Stack(
      children: [
        Column(
          children: [
            // ChatHeader：聊天头部状态区（标题/入口徽章/会话列表/更多菜单）
            ChatHeader(
              currentAttitude: _attitude,
              currentPhase: _phase,
              currentSubphase: _subphase,
              onAttitudeChange: _handleAttitudeChange,
              onNextSubphase: _handleNextSubphase,
              onOpenSessionDrawer: () =>
                  _scaffoldKey.currentState?.openDrawer(),
              onOpenProfile: _handleOpenProfile,
              // 批次 29：头部 ⋯ 左侧新建对话快捷入口
              onNewSession: _handleCreateSession,
              // 引用管理：更多菜单入口 → ReferenceBar 管理弹层
              onOpenReferences: _handleOpenReferences,
            ),
            // 批次 12：态度建议横幅（对齐 RN 位于头部下方、内容上方）
            if (_attitudeSuggestion != null)
              AttitudeSuggestionBanner(
                suggestion: _attitudeSuggestion!,
                onAccept: _handleAcceptAttitudeSuggestion,
                onDismiss: _handleDismissAttitudeSuggestion,
              ),
            // 批次 18：P2 阶段任务面板开关（对齐 RN chat.tsx L396-400 taskToggle）
            if (_phase == TeachingPhase.p2PracticeLoop)
              InkWell(
                onTap: () => setState(() => _showTaskPanel = !_showTaskPanel),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    border: Border(
                      bottom: BorderSide(color: AppColors.borderSoft),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.task_alt,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _showTaskPanel
                            ? '收起任务'
                            : '任务 (${_activeProblems.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // 鼓励文案（对齐 RN chat.tsx L404：诊断完成后显示）
            if (hasDiagnosis && !chatState.isStreaming)
              EncouragementText(seed: encouragementSeed),
            // 批次 18：P2 阶段 + 展开时显示活跃问题面板（对齐 RN taskPanelContainer height 200）
            if (_phase == TeachingPhase.p2PracticeLoop && _showTaskPanel)
              SizedBox(
                height: 200,
                child: TaskPanel(
                  problems: _activeProblems,
                  onMarkComplete: _handleMarkComplete,
                  // 批次75：活跃问题条目移除入口（主观不再追踪）
                  onRemove: _handleRemoveProblem,
                ),
              ),
            Expanded(
              child: MessageList(
                messages: chatState.messages,
                isStreaming: chatState.isStreaming,
                streamingContent: chatState.streamingContent,
                streamStageLabel: chatState.streamStageLabel,
                failedMessageIds: chatState.failedMessageIds,
                onRetry: _handleRetry,
                onDelete: _handleDelete,
                activePracticeTask: practiceState.activePracticeTask,
                trainingResult: practiceState.trainingResult,
                isPracticeSubmitting: practiceState.isSubmitting,
                onSubmitPractice: _submitPractice,
                onSkipPractice: _handleSkipPractice,
                onDismissResult: () => ref
                    .read(practiceStoreProvider.notifier)
                    .setTrainingResult(null),
                onRetryPractice: () =>
                    ref.read(practiceStoreProvider.notifier).retryPractice(),
                evaluationReports: evaluationState.reports,
                onDismissEvaluationReport: (messageId) => ref
                    .read(evaluationReportsProvider.notifier)
                    .dismissEvaluationReport(messageId),
                onSaveToFile: _handleSaveToFile,
                // 批次61：Teacher 建议卡「教我原理」→ 发消息请求讲解
                onTeachPrinciple: _handleTeachPrinciple,
                // 批次81：三卡回调接线（H1-H3）
                onContinueTraining: _handleContinueTraining,
                onViewProfile: _handleViewProfile,
                onBackToChat: _handleFocusChatInput,
                onAddContent: _handleFocusChatInput,
                onContinueChat: _handleFocusChatInput,
                onPartialAgreementSubmit: _handlePartialAgreementSubmit,
                onPartialAgreementSkip: _handlePartialAgreementSkip,
                // 空态 → 欢迎态（对齐 RN messages.length===0 → ChatWelcome）
                // 批次62：空态补行动引导——「去书架写一写」切到书架 Tab
                emptyWidget: Center(
                  child: ChatWelcome(
                    onStartWriting: () => context.go(AppRoutes.bookshelf),
                  ),
                ),
              ),
            ),
            if (chatState.error != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                color: AppColors.dangerBg,
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        // release 静默：不向用户展示异常技术细节（对齐 P2-7 铁律）
                        kDebugMode ? chatState.error! : '发送失败，请稍后重试',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.danger,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () =>
                          ref.read(chatStoreProvider.notifier).clearError(),
                    ),
                  ],
                ),
              ),
            ChatInput(
              key: _chatInputKey,
              input: _inputText,
              isStreaming: chatState.isStreaming,
              onInputChange: (text) {
                setState(() => _inputText = text);
              },
              onSend: _handleSend,
              onStop: _cancelGeneration,
              onUploadFile: _handleUploadFile,
              onMention: _handleMention,
            ),
          ],
        ),
        OnboardingQuestionnaire(
          visible: bootstrap.shouldShowOnboarding,
          onComplete: _handleOnboardingComplete,
          onSkip: _handleOnboardingSkip,
        ),
      ],
    );
  }
}
