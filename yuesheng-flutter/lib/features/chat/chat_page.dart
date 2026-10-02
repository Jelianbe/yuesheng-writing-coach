// ─────────────────────────────────────────────────────────────
// ChatPage — 主聊天页（T6 接线版本）：ChatStore + MessageList + ChatInput
// + chat_service 接线。R-019 真分解：本文件仅保留宿主 State；48 个原
// part/extension 动作方法 → 6 个控制器 + [ChatPageHost] 接口，UI 装配 →
// chat_page_body.dart / chat_page_sections.dart（详见 chat_page_host.dart）。
// MVP 范围：只处理 chat 类型消息，不实现 ChatModals 等高级特性。
// ─────────────────────────────────────────────────────────────

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_palette.dart';
import '../../data/database/database.dart';
import '../../data/repositories/diagnosis_repository.dart';
import '../../data/repositories/app_state_repository.dart';
import '../../data/repositories/session_repository.dart';
import '../../providers/app_providers.dart';
import '../../providers/chat_store.dart';
import '../../providers/evaluation_providers.dart';
import '../../providers/reasoning_tier_provider.dart';
import '../../providers/session_providers.dart';
import '../../services/attitude_advisor.dart';
import '../../types/teaching_types.dart';
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
import 'package:writingcoach/features/onboarding/novice_mode_guide.dart';
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

  /// C129（断点 B）：本会话是否已锁定自身态度（persistAttitude 写过
  /// teaching_state.attitudeLevel）。true → 头部态度区显示「本会话已锁定」，
  /// 设置页改全局教练不影响本会话。
  bool _attitudeLocked = false;

  /// 当前激活的教练人格名（用户自定义 → 显示名；系统预设 / 无 → null）。
  String? _activePersonaName;

  /// 批次 10 头部状态区：当前教学阶段（loadAttitudeState 返回 phase）
  TeachingPhase _phase = TeachingPhase.p0Engage;

  /// 当前会话主引用书名（references isPrimary==1 的 title），头部小字展示。
  String? _primaryRefTitle;

  AttitudeSuggestion? _attitudeSuggestion;

  /// 批次 12 态度建议：上次建议时间（冷却期判定，对齐 RN lastSuggestionTime）
  int? _lastSuggestionTime;

  bool _showTaskPanel = false;

  /// ADR-C122：纯新手模式激活态（➕ → 纯新手模式 → 学员回答解析期间）。
  /// 激活期间学员发送走本地 novice 通道（不调 LLM），解析完成或超限后复位。
  bool _noviceActive = false;

  /// ADR-C122：novice 追问轮数（达到 kNoviceMaxRetries 后按默认值落库兜底）。
  int _noviceRetries = 0;

  /// 强制滚底的单帧 flag（build 读取后立即清除，保证 MessageList 下一帧
  /// 收到 true 并滚到底）。两条强意图路径会设置：
  ///   1. ADR-C122 novice 注入（用户点「开始引导」/提交回答触发）；
  ///   2. 会话切换（抽屉选会话/新建/相关对话跳转/删除兜底）——切到等长或
  ///      更短会话时旧的「消息长度增长」条件不成立，必须靠此 flag 强滚到底。
  bool _forceScrollRequested = false;

  /// 批次 18 活跃问题面板：当前会话活跃问题列表（对齐 RN activeProblems）
  List<ActiveProblemView> _activeProblems = [];

  bool _pendingSessionHandled = false;

  /// B20：最近一次发起的消息加载目标会话 ID；快速切换会话时仅最新回调可写入。
  String? _loadingSessionId;

  /// 最近一次 bootstrap 就绪的会话 ID；用于判定「是否真的切换了会话」。
  /// 同会话 refresh（novice 落库后 refresh / reloadMessages 同会话刷新）
  /// 不会改变它，故不设滚底 flag（B18 不劫持常规刷新）。
  String? _lastBootstrapSessionId;

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
  bool get isAttitudeLocked => _attitudeLocked;

  @override
  String? get activePersonaName => _activePersonaName;

  TeachingMode _teachingMode = TeachingMode.socratic;

  @override
  TeachingMode get teachingMode => _teachingMode;

  /// 载入全局教学方式偏好（coach_teaching_mode KV，默认 socratic）。
  Future<void> _loadTeachingMode() async {
    try {
      final raw = await AppStateRepository(
        ref.read(appDatabaseProvider),
      ).getCoachTeachingMode();
      if (!mounted) return;
      setState(
        () => _teachingMode =
            TeachingMode.fromString(raw) ?? TeachingMode.socratic,
      );
    } catch (_) {
      // 读不到 → 保持默认 socratic
    }
  }

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
  void setAttitude(AttitudeLevel value) {
    setState(() => _attitude = value);
    // A6：态度档与教练人格收敛为单一真源（coach_persona_active）。
    // 此前这里只写 coach_attitude，而读取端 getActiveCoachPersonaId 优先读
    // coach_persona_active——一旦用户在教练设置里选过人格，头部切档 UI 变了
    // 但注入语气没变。改走 setActiveCoachPersona：系统预设（value 即
    // doubao/yuesheng/sensei）会同时双写 coach_persona_active + coach_attitude，
    // 与教练设置页选人完全同路；旧用户只写过 coach_attitude 的读取回退不受影响。
    AppStateRepository(
      ref.read(appDatabaseProvider),
    ).setActiveCoachPersona(value.name);
  }

  @override
  void applyAttitudeState(
    AttitudeLevel attitude,
    TeachingPhase phase, {
    String? activePersonaName,
    bool isAttitudeLocked = false,
  }) => setState(() {
    _attitude = attitude;
    _phase = phase;
    _attitudeLocked = isAttitudeLocked;
    if (activePersonaName != null) _activePersonaName = activePersonaName;
  });

  @override
  void setAttitudeLocked(bool value) => setState(() => _attitudeLocked = value);

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
  void cancelActiveGeneration() => _teaching.cancelGeneration();

  @override
  void initState() {
    super.initState();
    _session.loadSessions();
    // 思考档位：水合 app_state（幂等，设置页亦可能触发），
    // 使输入框开关与头部菜单首帧即为持久化值而非默认「标准」
    ref.read(reasoningTierProvider.notifier).hydrate();
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

    // C129（断点 A）：设置页改/删教练 → 已打开会话重新 resolve 态度。
    // 仅 bootstrap 就绪后响应（未就绪则跳过：就绪时 _onBootstrapReady 自会
    // 加载最新全局）。锁定会话 loadAttitudeState 仍返回其锁定值——只重载，
    // 不改「会话级锁定 > 全局」的优先级。
    ref.listen<int>(coachPersonaRevisionProvider, (previous, next) {
      final bootstrap = ref.read(sessionBootstrapProvider).valueOrNull;
      if (bootstrap == null) return;
      _attitudeController.loadAttitude(bootstrap.sessionId);
    });

    // bootstrap 完成后加载已有消息（ADR-C122：问卷退役，不再等待问卷）
    ref.listen<AsyncValue<SessionBootstrapState>>(sessionBootstrapProvider, (
      previous,
      next,
    ) {
      final bootstrap = next.valueOrNull;
      if (bootstrap != null) {
        _onBootstrapReady(bootstrap);
      }
    });
  }

  /// bootstrap 就绪：加载态度/引用/会话列表，回读消息并恢复评估报告
  void _onBootstrapReady(SessionBootstrapState bootstrap) {
    final sessionId = bootstrap.sessionId;
    // 仅当会话真的变了才在下一帧强滚底。首次加载（_lastBootstrapSessionId
    // 为 null，视为切换）亦无害：旧消息列表为空，长度 0→N 的常规分支本就会
    // 滚到底，强 flag 不改变首屏落点。
    final isSessionSwitched = _lastBootstrapSessionId != sessionId;
    _lastBootstrapSessionId = sessionId;
    _attitudeController.loadAttitude(sessionId);
    _loadTeachingMode();
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
      // 与会话消息写入同一同步块设 flag（无 await 间隙，避免其他 rebuild
      // 提前单帧消费）。切到等长/更短会话时长度不增，MessageList 靠
      // 「首条 sessionId 不同 = 整体替换」分支识别并强滚到底。
      if (isSessionSwitched) _forceScrollRequested = true;
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
  Widget _buildBody(ChatState chatState, bool scrollRequested) {
    return ChatPageBody(
      chatState: chatState,
      attitude: _attitude,
      attitudeLocked: _attitudeLocked,
      phase: _phase,
      primaryRefTitle: _primaryRefTitle,
      activePersonaName: _activePersonaName,
      attitudeSuggestion: _attitudeSuggestion,
      activeProblems: _activeProblems,
      showTaskPanel: _showTaskPanel,
      inputText: _inputText,
      chatInputKey: _chatInputKey,
      onInputChange: setInputText,
      onToggleTaskPanel: _toggleTaskPanel,
      onOpenSessionDrawer: _openSessionDrawer,
      // ADR-C122：纯新手模式（➕ 面板项）+ novice 期间发送走本地通道
      onNoviceMode: _startNoviceMode,
      onSendOverride: _noviceActive ? _handleNoviceAnswer : null,
      forceScrollToBottom: scrollRequested,
      attitudeController: _attitudeController,
      diagnosis: _diagnosis,
      teaching: _teaching,
      reference: _reference,
      messages: _messages,
      session: _session,
    );
  }

  // ── ADR-C122：纯新手模式（取代 onboarding 问卷 + 卡片墙）──

  /// 开始纯新手模式：固定确认弹窗 → 确认后插入固定首条消息
  /// （AI 主动自我介绍 + 主动询问三字段），激活 novice 解析态。
  Future<void> _startNoviceMode() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(kNoviceModeDialogTitle),
        content: const Text(kNoviceModeDialogContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('开始引导'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    debugPrint('[C122] _startNoviceMode ok=true, waiting bootstrap future');
    // 等 bootstrap 就绪再继续：首次 read 时异步 provider 可能仍在加载，
    // valueOrNull 会静默返回 null（真机：弹窗关闭但首条消息不出现）。
    final bootstrap = await ref.read(sessionBootstrapProvider.future);
    debugPrint('[C122] bootstrap ready: ${bootstrap.sessionId}');
    if (!mounted) return;
    // 先激活 novice 态（setState 触发 rebuild，onSendOverride 生效）
    // 再注入首条消息——避免 build 快照在激活前读到 null override
    setState(() {
      _noviceActive = true;
      _noviceRetries = 0;
    });
    debugPrint('[C122] novice active, injecting first message');
    await _injectAssistantMessage(kNoviceModeFirstMessage);
    debugPrint('[C122] first message injected');
  }

  /// novice 期间学员发送：本地解析三字段 → 落库（复用 onboarding_service
  /// 三步迁移）→ 插入固定分支引导；解析不完整 → 固定追问（有上限）。
  Future<void> _handleNoviceAnswer(String text) async {
    final bootstrap = await ref.read(sessionBootstrapProvider.future);
    if (!mounted) return;
    // 学员回答先落库（user 消息，保证会话上下文连续）
    final repo = SessionRepository(ref.read(appDatabaseProvider));
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final userId = await repo.addMessage(
      bootstrap.sessionId,
      'user',
      text,
      messageType: kNoviceMessageType,
    );
    ref
        .read(chatStoreProvider.notifier)
        .addMessage(
          Message(
            id: userId,
            sessionId: bootstrap.sessionId,
            role: 'user',
            content: text,
            timestamp: now,
            messageType: kNoviceMessageType,
          ),
        );

    if (isNoviceAnswerComplete(text)) {
      await _commitNoviceData(bootstrap.sessionId, text);
      final data = buildNoviceOnboardingData(text);
      final guide = isBeginnerGuide(data.proficiency)
          ? kNoviceModeBeginnerGuide
          : kNoviceModeAdvancedGuide;
      setState(() => _noviceActive = false);
      await _injectAssistantMessage(guide);
    } else if (_noviceRetries < kNoviceMaxRetries) {
      setState(() => _noviceRetries++);
      await _injectAssistantMessage(kNoviceModeFollowUpMessage);
    } else {
      // 两次追问仍无法识别 → 默认值落库 + 兜底引导（不让学员卡死）
      await _commitNoviceData(bootstrap.sessionId, text);
      setState(() => _noviceActive = false);
      await _injectAssistantMessage(kNoviceModeFallbackGuide);
    }
  }

  /// 落库 + 刷新 bootstrap（复用问卷同款三步迁移；隐私告知由
  /// ChatMessagesController.maybeShowPrivacyNotice 兜底）。
  Future<void> _commitNoviceData(String sessionId, String text) async {
    final data = buildNoviceOnboardingData(text);
    await ref.read(onboardingServiceProvider).submitOnboarding(sessionId, data);
    await ref.read(sessionBootstrapProvider.notifier).refresh();
    await _messages.maybeShowPrivacyNotice();
  }

  /// 插入一条 assistant 固定消息（DB 落库 + 内存追加即时渲染）。
  /// 注入前设置强制滚底 flag（单帧消费：下一帧 build 读取后清除）——
  /// novice 注入是用户主动触发的强意图，必须立即可见。
  Future<void> _injectAssistantMessage(String content) async {
    final bootstrap = await ref.read(sessionBootstrapProvider.future);
    if (!mounted) return;
    final repo = SessionRepository(ref.read(appDatabaseProvider));
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final id = await repo.addMessage(
      bootstrap.sessionId,
      'assistant',
      content,
      messageType: kNoviceMessageType,
    );
    if (!mounted) return;
    // 与 store 更新同一同步块：避免 await 间隙内其他 rebuild 提前消费 flag
    _forceScrollRequested = true;
    ref
        .read(chatStoreProvider.notifier)
        .addMessage(
          Message(
            id: id,
            sessionId: bootstrap.sessionId,
            role: 'assistant',
            content: content,
            timestamp: now,
            messageType: kNoviceMessageType,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapAsync = ref.watch(sessionBootstrapProvider);
    final chatState = ref.watch(chatStoreProvider);
    // 单帧消费强制滚底 flag（读取后立即清除；本帧 MessageList 的
    // didUpdateWidget 会收到 true 并滚到底）。覆盖 novice 注入与会话切换两条路径。
    final scrollRequested = _forceScrollRequested;
    _forceScrollRequested = false;
    _registerListeners();
    _consumeInitialPendingSession();

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: context.palette.background,
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
        data: (bootstrap) =>
            Stack(children: [_buildBody(chatState, scrollRequested)]),
      ),
    );
  }
}
