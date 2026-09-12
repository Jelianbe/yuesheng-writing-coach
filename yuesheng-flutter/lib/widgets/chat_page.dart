// ─────────────────────────────────────────────────────────────
// ChatPage — 主聊天页（T6 接线版本）：ChatStore + MessageList + ChatInput
// + chat_service 接线。R-019 真分解：本文件仅保留宿主 State；48 个原
// part/extension 动作方法 → 6 个控制器 + [ChatPageHost] 接口，UI 装配 →
// chat_page_body.dart / chat_page_sections.dart（详见 chat_page_host.dart）。
// MVP 范围：只处理 chat 类型消息，不实现 ChatModals 等高级特性。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_theme.dart';
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../providers/app_providers.dart';
import '../providers/chat_store.dart';
import '../providers/evaluation_providers.dart';
import '../providers/session_providers.dart';
import '../services/attitude_advisor.dart';
import '../types/teaching_types.dart';
import 'chat_attitude_controller.dart';
import 'chat_diagnosis_controller.dart';
import 'chat_input.dart';
import 'chat_messages_controller.dart';
import 'chat_page_body.dart';
import 'chat_page_host.dart';
import 'chat_page_sections.dart';
import 'chat_reference_controller.dart';
import 'chat_session_controller.dart';
import 'chat_teaching_controller.dart';
import 'onboarding_questionnaire.dart';
import 'session_drawer.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> implements ChatPageHost {
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

  /// 当前会话主引用书名（references isPrimary==1 的 title），头部小字展示。
  String? _primaryRefTitle;

  AttitudeSuggestion? _attitudeSuggestion;

  /// 批次 12 态度建议：上次建议时间（冷却期判定，对齐 RN lastSuggestionTime）
  int? _lastSuggestionTime;

  bool _showTaskPanel = false;

  /// 批次 18 活跃问题面板：当前会话活跃问题列表（对齐 RN activeProblems）
  List<ActiveProblemView> _activeProblems = [];

  bool _pendingSessionHandled = false;

  /// B20：最近一次发起的消息加载目标会话 ID；快速切换会话时仅最新回调可写入。
  String? _loadingSessionId;

  // ── R-019 真分解：动作控制器（经 ChatPageHost 注入）──
  late final ChatTeachingController _teaching = ChatTeachingController(this);
  late final ChatDiagnosisController _diagnosis = ChatDiagnosisController(
    this,
    _teaching,
  );
  late final ChatSessionController _session = ChatSessionController(this);
  late final ChatReferenceController _reference = ChatReferenceController(
    this,
    _session,
  );
  late final ChatMessagesController _messages = ChatMessagesController(
    this,
    _teaching,
  );
  late final ChatAttitudeController _attitudeController =
      ChatAttitudeController(this, _diagnosis);

  // ── ChatPageHost 实现（共享状态读取）──
  @override
  String get inputText => _inputText;

  @override
  AttitudeLevel get attitude => _attitude;

  @override
  TeachingPhase get phase => _phase;

  @override
  String? get primaryRefTitle => _primaryRefTitle;

  @override
  AttitudeSuggestion? get attitudeSuggestion => _attitudeSuggestion;

  @override
  int? get lastSuggestionTime => _lastSuggestionTime;

  @override
  List<ActiveProblemView> get activeProblems => _activeProblems;

  @override
  List<SessionWithPhase> get sessions => _sessions;

  @override
  GlobalKey<ChatInputState> get chatInputKey => _chatInputKey;

  // ── ChatPageHost 实现（共享状态写入，内部 setState）──
  @override
  void setInputText(String value) => setState(() => _inputText = value);

  @override
  void setAttitude(AttitudeLevel value) => setState(() => _attitude = value);

  @override
  void applyAttitudeState(AttitudeLevel attitude, TeachingPhase phase) =>
      setState(() {
        _attitude = attitude;
        _phase = phase;
      });

  @override
  void setPrimaryRefTitle(String? value) =>
      setState(() => _primaryRefTitle = value);

  @override
  void setAttitudeSuggestion(
    AttitudeSuggestion? suggestion, {
    int? lastSuggestionTime,
  }) => setState(() {
    _attitudeSuggestion = suggestion;
    if (lastSuggestionTime != null) _lastSuggestionTime = lastSuggestionTime;
  });

  @override
  void setActiveProblems(List<ActiveProblemView> value) =>
      setState(() => _activeProblems = value);

  @override
  void setSessions(List<SessionWithPhase> value) =>
      setState(() => _sessions = value);

  @override
  void clearComposerState() => setState(() {
    _inputText = '';
    // 对齐 RN reset 模态 store（lastSuggestionTime 为页面级不清）
    _attitudeSuggestion = null;
  });

  @override
  void scheduleAttitudeCheck() => _attitudeController.scheduleAttitudeCheck();

  @override
  void initState() {
    super.initState();
    _session.loadSessions();
  }

  /// 打开会话抽屉（打开前先释放输入框焦点：真机实证点汉堡会唤起输入法）
  void _openSessionDrawer() {
    FocusManager.instance.primaryFocus?.unfocus();
    _scaffoldKey.currentState?.openDrawer();
  }

  void _toggleTaskPanel() => setState(() => _showTaskPanel = !_showTaskPanel);

  /// 注册三个 ref.listen（选章自动诊断 / 待打开会话 / bootstrap 就绪）
  void _registerListeners() {
    // 批次 13：成长页「写作诊断」选章 → 切 Tab 后自动诊断（startDiagnosis 语义）
    ref.listen<String?>(pendingDiagnosisChapterProvider, (previous, next) {
      if (next != null && next.isNotEmpty) _diagnosis.handleAutoDiagnose(next);
    });

    // 批次 30：作品详情页「相关对话」点击 → 切 Tab 后打开目标会话
    ref.listen<String?>(pendingOpenSessionProvider, (previous, next) {
      if (next != null && next.isNotEmpty) _session.consumePendingSession(next);
    });

    // bootstrap 完成后加载已有消息
    ref.listen<AsyncValue<SessionBootstrapState>>(sessionBootstrapProvider, (
      previous,
      next,
    ) {
      final bootstrap = next.valueOrNull;
      if (bootstrap != null && !bootstrap.shouldShowOnboarding) {
        _onBootstrapReady(bootstrap);
      }
    });
  }

  /// bootstrap 就绪：加载态度/引用/会话列表，回读消息并恢复评估报告
  void _onBootstrapReady(SessionBootstrapState bootstrap) {
    final sessionId = bootstrap.sessionId;
    _attitudeController.loadAttitude(sessionId);
    _reference.loadPrimaryRefTitle(); // 头部小字：当前主引用书名
    _session.loadSessions(); // 切换/新建会话后刷新列表（updated_at/标题变化）
    // 批次4-M3：恢复该会话的评估报告 + 当前轮次（应用重启/会话切换后）
    ref.read(evaluationReportsProvider.notifier).restoreForSession(sessionId);
    // B20：记录最新发起的加载请求，旧请求的异步回调若已不是最新则丢弃
    _loadingSessionId = sessionId;
    final sessionRepo = SessionRepository(ref.read(appDatabaseProvider));
    sessionRepo.listMessages(sessionId).then((messages) {
      if (!mounted) return;
      if (_loadingSessionId != sessionId) return;
      ref.read(chatStoreProvider.notifier).setMessages(messages);
    });
  }

  /// 兜底消费初始 pending 会话：ChatPage 全新挂载时 pending 可能已先于
  /// 监听注册被设置（ref.listen 不 fire 初始值），build 时读一次并在帧后消费
  void _consumeInitialPendingSession() {
    if (_pendingSessionHandled) return;
    final pending = ref.read(pendingOpenSessionProvider);
    if (pending == null || pending.isEmpty) return;
    _pendingSessionHandled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session.consumePendingSession(pending);
    });
  }

  /// bootstrap 就绪后的主体装配（渲染树见 chat_page_body.dart）
  Widget _buildBody(ChatState chatState) {
    return ChatPageBody(
      chatState: chatState,
      attitude: _attitude,
      phase: _phase,
      primaryRefTitle: _primaryRefTitle,
      attitudeSuggestion: _attitudeSuggestion,
      activeProblems: _activeProblems,
      showTaskPanel: _showTaskPanel,
      inputText: _inputText,
      chatInputKey: _chatInputKey,
      onInputChange: setInputText,
      onToggleTaskPanel: _toggleTaskPanel,
      onOpenSessionDrawer: _openSessionDrawer,
      attitudeController: _attitudeController,
      diagnosis: _diagnosis,
      teaching: _teaching,
      reference: _reference,
      messages: _messages,
      session: _session,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapAsync = ref.watch(sessionBootstrapProvider);
    final chatState = ref.watch(chatStoreProvider);
    _registerListeners();
    _consumeInitialPendingSession();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      // SessionDrawer：会话管理抽屉（ChatHeader 汉堡按钮入口）
      drawer: SessionDrawer(
        sessions: _sessions,
        currentSessionId: bootstrapAsync.valueOrNull?.sessionId,
        onSelect: _session.handleSwitchSession,
        onCreate: _session.handleCreateSession,
        // 批次73：长按会话删除；v30：重命名/置顶/批量删除
        onDelete: _session.handleDeleteSession,
        onRename: _session.handleRenameSession,
        onTogglePin: _session.handleTogglePinSession,
        onBatchDelete: _session.handleBatchDeleteSessions,
      ),
      body: bootstrapAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => ChatBootstrapErrorView(error: error),
        data: (bootstrap) => Stack(
          children: [
            _buildBody(chatState),
            OnboardingQuestionnaire(
              visible: bootstrap.shouldShowOnboarding,
              onComplete: _messages.handleOnboardingComplete,
              onSkip: _messages.handleOnboardingSkip,
            ),
          ],
        ),
      ),
    );
  }
}
