// MessageAssemblyService — 消息装配与流程窗口（ADR-0004 步 5 批 3）
//
// 从 `ChatServiceSend` extension 抽出的独立类 + DI（ADR-0004 §2 R-3），
// 承接 B 簇 7 个成员 + E 簇 3 个成员（原 `chat_service.dart` 内约 314 行）：
//   B: assembleSendContext / loadSessionContext / assembleMessagesAndInject
//      / excludeNoviceMessages / collectPriorUserTexts / writeUserMessage
//      / hasOutlineReference
//   E: observeAndResolveFlow / observeBridgeEntry / resolveFlowWindow
//
// 切口依据（实测调用图）：E 簇是 **B 簇的下层**（`assembleSendContext` 调
// `observeAndResolveFlow`），不是并列簇 ⇒ 两簇同批搬出，E 作为本类的内部方法。
//
// ★ 注入 `PromptAssemblyService`（批 2 的产物）——不是循环依赖：
//   C 簇（prompt 组装）**不读** B 簇任何数据（实测其只依赖 messageInjector
//   / teaching / appStateRepo / routeHysteresis），故 B → C 单向注入成立。
//   原代码里 `_assembleMessagesAndInject` 与 `_finalizeSendContext` 直接调
//   `_promptService`，搬出后必须改为注入。
//
// ★ `_lastUserSendAtSec` 用 **读写回调**注入而非传 Map：它是 ChatService 上的
//   **可变 Map**（`chat_service.dart:288`），E 簇会**写**它
//   （`observeAndResolveFlow` 内 `[sessionId] = nowAtSec`）。
//   若把 Map 本身传进来虽可行，但把宿主状态所有权一并交出——用
//   `readLastSendAt` / `writeLastSendAt` 两个回调保持所有权仍在宿主。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/contracts/reference_capability.dart';
import 'package:writingcoach/data/database/database.dart' show Message;
import 'package:writingcoach/data/repositories/diagnosis_repository.dart'
    show ActiveProblemView, DiagnosisRepository;
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/features/onboarding/novice_mode_guide.dart'
    show kNoviceMessageType;
import 'package:writingcoach/services/chat_context_builder.dart'
    show ReferenceItem;
import 'package:writingcoach/services/chat_gates.dart' show isInFlow;
import 'package:writingcoach/services/chat_message_types.dart';
import 'package:writingcoach/services/chat_service_diagnosis_focus.dart';
import 'package:writingcoach/services/llm_client.dart' show ChatMessage;
import 'package:writingcoach/services/prompt_assembly_service.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 教学态准备结果（对应原 `_TeachingContext`，字段与**可空性**逐一对齐）。
typedef TeachingContextResult = ({
  TeachingSubphase? subphase,
  bool isBeginner,
  BeginnerLevel? beginnerLevel,
  TeachingPhase phase,
});

/// 流程窗口判定结果（对应原 `_FlowWindow`）。
typedef FlowWindowResult = ({bool flowBypassed, bool rapidFire});

/// 会话上下文加载结果（对应原 `_LoadedContext`，逐字段对齐）。
typedef LoadedContextResult = ({
  List<Message> history,
  String userMessageId,
  TeachingSubphase? currentSubphase,
  bool isBeginner,
  BeginnerLevel? beginnerLevel,
  TeachingPhase effectivePhase,
  List<ActiveProblemView> activeProblems,
  bool isOutlineContext,
});

/// 上下文注入装配结果（对应原 `_AssembledContext`，逐字段对齐）。
typedef AssembledContextResult = ({
  List<ChatMessage> messages,
  ReferenceItem? primaryRef,
  String? chapterContent,
  String? trainingSyndromeId,
  Map<String, List<int>> stageIndexes,
  void Function(String) markStage,
});

/// 装配后的发送上下文（对应原 `_SendContext`，逐字段对齐）。
typedef SendContextResult = ({
  List<ChatMessage> messages,
  String userMessageId,
  ReferenceItem? primaryRef,
  String? chapterContent,
  String? trainingSyndromeId,
  List<ActiveProblemView> activeProblems,
  TeachingSubphase? currentSubphase,
  bool rapidFire,
  bool flowBypassed,
});

/// 消息装配服务（构造依赖全部注入，无隐式全局）。
class MessageAssemblyService {
  MessageAssemblyService({
    required this._sessionRepo,
    required this._diagnosisRepo,
    required this._referenceRepo,
    required this._diagnosisFocus,
    required PromptAssemblyService promptService,
    required this._prepareTeachingState,
    required this._readLastSendAt,
    required this._writeLastSendAt,
  }) : _prompt = promptService;

  final SessionRepository _sessionRepo;
  final DiagnosisRepository _diagnosisRepo;
  final ReferenceCapability _referenceRepo;
  final ChatServiceDiagnosisFocus _diagnosisFocus;

  /// 批 2 的 prompt 组装服务（单向注入，见文件头说明）。
  final PromptAssemblyService _prompt;

  /// A 簇成员提升为函数注入。
  final Future<TeachingContextResult> Function(
    String sessionId,
    TeachingSubphase? subphase,
    TeachingPhase fallbackPhase,
  )
  _prepareTeachingState;

  final int? Function(String sessionId) _readLastSendAt;
  final void Function(String sessionId, int nowAtSec) _writeLastSendAt;

  // ── E 簇：流程窗口 ───────────────────────────────────────────────────

  /// 桥接入口观测（仅训练阶段打一行；非practice 直接返回）。
  void observeBridgeEntry(
    String sessionId,
    TeachingSubphase? currentSubphase,
    TeachingPhase phase,
    List<ActiveProblemView> activeProblems,
  ) {
    if (currentSubphase != TeachingSubphase.practice) return;
    debugPrint(
      '[Bridge] 训练阶段进入 | sessionId=$sessionId '
      '| phase=${phase.value} | subphase=practice '
      '| activeProblems=${activeProblems.length}',
    );
  }

  /// Teacher 升级阀 + 心流窗口判定（批次1 O1 / 批次59，R-019 拆出）。
  Future<FlowWindowResult> resolveFlowWindow(
    String sessionId,
    List<ActiveProblemView> activeProblems,
    int? lastEditorEditAtSec,
    int nowAtSec,
    String content,
  ) async {
    final flowBypassed = await _diagnosisFocus.shouldBypassFlowWindow(
      sessionId,
      activeProblems,
    );
    final rapidFire = isInFlow(
      lastSendAtSec: _readLastSendAt(sessionId),
      lastEditorEditAtSec: lastEditorEditAtSec,
      nowAtSec: nowAtSec,
      bypassFlowWindow: flowBypassed,
      // 批次6（6.8 M4）：求助关键词（不会/怎么/卡住了/没思路）命中
      // → 绕过心流抑制，主动求助及时反馈
      helpSignal: content,
    );
    return (flowBypassed: flowBypassed, rapidFire: rapidFire);
  }

  /// 桥接观测 + 升级阀/心流窗口判定 + 记录本轮发送时刻。
  Future<FlowWindowResult> observeAndResolveFlow({
    required String sessionId,
    required String content,
    required SendMessageOptions options,
    required LoadedContextResult loaded,
    required int nowAtSec,
  }) async {
    observeBridgeEntry(
      sessionId,
      loaded.currentSubphase,
      loaded.effectivePhase,
      loaded.activeProblems,
    );
    final flow = await resolveFlowWindow(
      sessionId,
      loaded.activeProblems,
      options.lastEditorEditAtSec,
      nowAtSec,
      content,
    );
    _writeLastSendAt(sessionId, nowAtSec);
    return flow;
  }

  // ── B 簇：消息装配 ───────────────────────────────────────────────────

  /// 1-7. 用户消息落库 + 上下文装配（R-019 第二层编排 helper）。
  Future<SendContextResult> assembleSendContext({
    required String sessionId,
    required String content,
    required SendMessageOptions options,
    required TeachingSubphase? subphase,
    required int nowAtSec,
  }) async {
    final loaded = await loadSessionContext(
      sessionId,
      content,
      options,
      subphase,
      nowAtSec,
    );
    // 桥接观测 + Teacher 升级阀/心流窗口判定
    final flow = await observeAndResolveFlow(
      sessionId: sessionId,
      content: content,
      options: options,
      loaded: loaded,
      nowAtSec: nowAtSec,
    );
    // 5-5.2. system prompt + 上下文注入（委托 MessageInjector）
    final assembled = await assembleMessagesAndInject(
      sessionId: sessionId,
      content: content,
      options: options,
      loaded: loaded,
    );
    return _finalizeSendContext(
      loaded,
      assembled,
      flow,
      sessionId,
      content,
      options,
    );
  }

  /// 6.5-7. 临场约束 + 历史/纪律/预算 + 返回装配（R-019 拆出）。
  SendContextResult _finalizeSendContext(
    LoadedContextResult loaded,
    AssembledContextResult assembled,
    FlowWindowResult flow,
    String sessionId,
    String content,
    SendMessageOptions options,
  ) {
    // 6.5 临场输出约束：在所有教学内容注入后、历史对话前追加（recency bias）
    assembled.messages.add(
      ChatMessage(role: 'system', content: kLiveOutputConstraints),
    );
    // 7. 追加历史消息 + 每轮必变提示 + 纪律重申 + token 预算闸门
    _prompt.appendHistoryAndConstraints(
      loaded.history,
      assembled.messages,
      assembled.markStage,
      assembled.stageIndexes,
      sessionId: sessionId,
      content: content,
      wholeChapterModeActive: options.wholeChapterModeActive,
    );
    debugPrint(
      '[ChatService] 步骤7: 发送到 LLM 的 messages 数量=${assembled.messages.length}（含 system + history）',
    );
    return (
      messages: assembled.messages,
      userMessageId: loaded.userMessageId,
      primaryRef: assembled.primaryRef,
      chapterContent: assembled.chapterContent,
      trainingSyndromeId: assembled.trainingSyndromeId,
      activeProblems: loaded.activeProblems,
      currentSubphase: loaded.currentSubphase,
      rapidFire: flow.rapidFire,
      flowBypassed: flow.flowBypassed,
    );
  }

  /// 1-4. 用户消息落库 + 会话/教学上下文加载（R-019 第二层编排 helper）。
  Future<LoadedContextResult> loadSessionContext(
    String sessionId,
    String content,
    SendMessageOptions options,
    TeachingSubphase? subphase,
    int nowAtSec,
  ) async {
    // 1. 写入用户消息（批次71：@ 引用快照随 user 消息落库；D2 落库前校验会话）
    final userMessageId = await writeUserMessage(sessionId, content, options);

    // 2. 获取历史消息（已含 user）
    final rawHistory = await _sessionRepo.listMessages(sessionId);
    // C123：剔除纯新手模式问答（不喂 LLM 诊断上下文；DB 与 UI 仍全量保留）。
    // 咽喉点：loaded.history 同时供 appendHistory 与 collectPriorUserTexts
    // 消费，此处一处过滤即切断两条泄漏。
    final history = excludeNoviceMessages(rawHistory);
    debugPrint(
      '[ChatService] 步骤2: 历史消息 ${history.length} 条（已剔除 novice ${rawHistory.length - history.length} 条）',
    );

    // 3. 读取 teaching state（批次6 M2：DB currentPhase 优先于 options.phase）
    final teaching = await _prepareTeachingState(
      sessionId,
      subphase,
      options.phase,
    );
    final currentSubphase = teaching.subphase;
    final isBeginner = teaching.isBeginner;
    final beginnerLevel = teaching.beginnerLevel;
    final effectivePhase = teaching.phase;

    // 4. 加载活跃症候
    final activeProblems = await _diagnosisRepo.listActiveProblems(sessionId);
    debugPrint('[ChatService] 步骤4: 活跃症候 ${activeProblems.length} 个');

    // 5. P2-8：大纲语境判定——会话引用含 outline 角色附属文件（用户 @ 大纲文件）
    final isOutlineContext = await hasOutlineReference(sessionId);
    debugPrint('[ChatService] 步骤5: 大纲语境=$isOutlineContext');
    return (
      history: history,
      userMessageId: userMessageId,
      currentSubphase: currentSubphase,
      isBeginner: isBeginner,
      beginnerLevel: beginnerLevel,
      effectivePhase: effectivePhase,
      activeProblems: activeProblems,
      isOutlineContext: isOutlineContext,
    );
  }

  /// C123：剔除纯新手模式问答消息（messageType == kNoviceMessageType）。
  ///
  /// 这些是 UI 层固定引导 / 学员三字段采集回答，不是学员真实写作文本；
  /// 混入诊断上下文会污染后续真实诊断。只作用于「喂 LLM 的 history 副本」，
  /// 不改 DB、不影响 UI 全量展示。
  List<Message> excludeNoviceMessages(List<Message> history) {
    return history.where((m) => m.messageType != kNoviceMessageType).toList();
  }

  /// 5-5.2. system prompt + 上下文注入装配（R-019 第二层编排 helper）。
  Future<AssembledContextResult> assembleMessagesAndInject({
    required String sessionId,
    required String content,
    required SendMessageOptions options,
    required LoadedContextResult loaded,
  }) async {
    // D1/D2 Phase 2：解析当前激活教练人格（用户预设 → 注入其语气；系统预设/null → 原路径）。
    final activePersona = await _prompt.resolveActivePersona();
    final messages = _prompt.buildSystemPrompt(
      loaded.effectivePhase,
      options.attitude,
      loaded.currentSubphase,
      loaded.isBeginner,
      sessionId: sessionId,
      isOutlineContext: loaded.isOutlineContext,
      options: options,
      activePersona: activePersona,
      content: content,
    );
    // 可降级阶段 → 消息索引（运行时 token 预算闸门裁剪依据）
    final stageIndexes = <String, List<int>>{};
    void markStage(String stage) {
      (stageIndexes[stage] ??= []).add(messages.length);
    }

    final priorUserTexts = collectPriorUserTexts(loaded);

    final injected = await _prompt.injectContext(
      sessionId: sessionId,
      content: content,
      messages: messages,
      markStage: markStage,
      activeProblems: loaded.activeProblems,
      currentSubphase: loaded.currentSubphase,
      beginnerLevel: loaded.beginnerLevel,
      phase: loaded.effectivePhase,
      priorUserTexts: priorUserTexts,
    );
    return (
      messages: messages,
      primaryRef: injected.primaryRef,
      chapterContent: injected.chapterContent,
      trainingSyndromeId: injected.trainingSyndromeId,
      stageIndexes: stageIndexes,
      markStage: markStage,
    );
  }

  /// ADR-C106 A7：热度所需历史 user 文本（时间正序，R-019 拆出）。
  ///
  /// loaded.history 在 writeUserMessage 之后取、已含本轮 user 消息，故倒序取
  /// user 时跳过末条（本轮 content），避免 [content, ...priorUserTexts]
  /// double-count。再反序回填为时间正序。
  List<String> collectPriorUserTexts(LoadedContextResult loaded) {
    final priorUserTexts = <String>[];
    var skippedCurrent = false;
    for (var i = loaded.history.length - 1; i >= 0; i--) {
      final m = loaded.history[i];
      if (m.role != 'user') continue;
      if (!skippedCurrent) {
        skippedCurrent = true;
        continue;
      }
      priorUserTexts.add(m.content);
    }
    return priorUserTexts.reversed.toList();
  }

  /// P2 收尾：写用户消息（会话存在性校验 + 落库 + 快照）。R-019 拆出。
  ///
  /// D2：会话可能已被删除/清库，UI 持有的过期 ID 直接 INSERT 会外键约束失败
  /// 且报错不可读 → 落库前显式校验，明确抛错走 onError。
  Future<String> writeUserMessage(
    String sessionId,
    String content,
    SendMessageOptions options,
  ) async {
    if (!await _sessionRepo.sessionExists(sessionId)) {
      throw Exception('会话不存在或已被删除，请重新打开教练面板');
    }
    final id = await _sessionRepo.addMessage(
      sessionId,
      'user',
      content,
      referencesJson: options.referencesJson,
    );
    debugPrint('[ChatService] 步骤1: user 消息已写入 id=$id');
    return id;
  }

  /// P2-8：大纲语境判定——会话引用中存在 fileRole=='outline' 的附属文件。
  /// 引用解析失败 / 无 file 引用 → false（降级安全：不触发大纲语境即维持原行为）。
  Future<bool> hasOutlineReference(String sessionId) async {
    try {
      final refs = await _referenceRepo.listReferences(sessionId);
      final fileRefs = refs.where((r) => r.refType == 'file').toList();
      if (fileRefs.isEmpty) return false;
      final files = await _referenceRepo.getAttachedFilesByIds(
        fileRefs.map((r) => r.refId).toList(),
      );
      return files.any((f) => f.fileRole == 'outline');
    } catch (_) {
      // R-028 边界：引用查询失败不阻断发送，按非大纲语境降级
      return false;
    }
  }
}
