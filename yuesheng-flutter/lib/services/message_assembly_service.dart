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

/// 喂 LLM 的 history 副本需剔除的消息类型白名单（单一真源）。
///
/// - `novice_chat`（C123）：UI 层固定引导 / 学员三字段采集回答，
///   不是学员真实写作文本，混入诊断上下文会污染后续真实诊断。
/// - `diagnosis_result`（P1 · 外部反馈 2026-10-08）：payload JSON 内
///   `syndromes[].evidence` 是**学员原文的逐字引用**，且落成 role='system'；
///   `_appendHistory` 不看 messageType、原样全量追加（窗口 20–29 条）
///   ⇒ 旧证据句能存活 10 轮以上。学员改完文本回来二次诊断时，模型逐字复制
///   旧证据句比在「## 待诊断全文」里重新定位便宜得多 ⇒「明明改了还照样
///   指出来、引的还是原来那句」。
///
/// ★ 两条都**只作用于喂 LLM 的副本**：不改 DB、不影响 UI 全量展示。
/// ★ 剔掉 `diagnosis_result` 不损失教学连续性：结构化症候记忆走
///   `injectDiagnosisLock(activeProblems:)` 的 DB 查询路（`listActiveProblems`），
///   不依赖 history ⇒ 切断「逐字句复制」、保留「此前诊断过哪些症候」。
/// ★ messageType 为 TEXT 自由取值（无 CHECK 约束），新增过滤值零 schema 迁移。
/// ⚠️ 不变量：剔除后**必须仍含本轮 user 消息** —— 现有 user 消息的
///   messageType 是 `'chat'`（`tables.dart` 默认值），故 `'chat'` 绝不可入白名单。
const Set<String> kHistoryExcludedMessageTypes = {
  kNoviceMessageType,
  'diagnosis_result',
};

/// 按 [kHistoryExcludedMessageTypes] 剔除消息类型（纯函数、无状态）。
List<Message> excludeFromLlmHistory(List<Message> history) {
  return history
      .where((m) => !kHistoryExcludedMessageTypes.contains(m.messageType))
      .toList();
}

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

    // 2. 获取历史消息（已含 user）+ 整形为「喂 LLM 的副本」（剔污染类型）。
    //
    // C123（novice_chat）与 P1（diagnosis_result）两类剔除都在 [_shapeHistoryForLlm]
    // 内完成（其文档注释含本步的抽出归因）；咽喉点不变：loaded.history 同时供
    // appendHistory 与 collectPriorUserTexts 消费，此处一处整形即切断两条泄漏。
    final rawHistory = await _sessionRepo.listMessages(sessionId);
    final history = _shapeHistoryForLlm(rawHistory);

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

  /// 薄别名 → [excludeFromLlmHistory]。**白名单真源 = [kHistoryExcludedMessageTypes]**。
  ///
  /// ⚠️ 方法名只写「novice」，实际剔除面**比名字宽**：现含 C123 的
  /// `novice_chat`（UI 层固定引导 / 学员三字段采集回答，不是学员真实写作
  /// 文本，混入诊断上下文会污染后续真实诊断）与 P1 的 `diagnosis_result`
  /// （payload JSON 内 `syndromes[].evidence` 是原文逐字引用）。
  ///
  /// 保留本方法名只为不扩大改动面（`loadSessionContext` 的既有注释与
  /// debugPrint 都指向它）；要增删剔除类型**只改白名单常量一处**。
  List<Message> excludeNoviceMessages(List<Message> history) =>
      excludeFromLlmHistory(history);

  /// P1（二次诊断证据句污染 · 外部反馈 2026-10-08）：剔除「上一轮诊断卡」
  /// 这类**逐字含旧证据句**的消息，只在「喂 LLM 的 history 副本」里剔。
  ///
  /// 根因（逐字实测）：`insertDiagnosisResultCard` 把 payload JSON 落成
  /// role='system' / messageType='diagnosis_result' 消息，而 JSON 内
  /// `syndromes[].evidence` 是**学员原文的逐字引用**（`DiagnosisSyndromeCard`
  /// 注释：「证据原文（诊断解析出的问题片段引用）」）；`_appendHistory` 不看
  /// messageType、原样全量追加（`LlmInputLimits.maxHistoryMessages=20` /
  /// `historyTrimBatch=10` ⇒ 实际窗口 20–29 条）⇒ 旧证据句能存活 10 轮以上，
  /// 且是 system 角色。学员改完文本回来做二次诊断时，模型逐字复制旧证据句
  /// 比在「## 待诊断全文」里重新定位便宜得多 ⇒「明明改了还照样指出来、引的
  /// 还是原来那句」。
  ///
  /// ★ 为什么剔掉不损失教学连续性：结构化症候记忆走**另一条路** ——
  ///   `injectDiagnosisLock(activeProblems: …)` 的数据源是 DB 查询
  ///   （`listActiveProblems`，见 `loadSessionContext`），**不依赖 history**
  ///   里的卡片消息。P1 只切断「逐字句复制」，保留「此前诊断过哪些症候」。
  ///
  /// 不动 DB、不动 UI 全量展示、不改任何 prompt 正文 ⇒ **不触 R-027**。
  /// messageType 为 TEXT 自由取值（无 CHECK 约束），新增过滤值零 schema 迁移。
  ///
  /// ★ 实现已薄化为转发：**白名单真源 = [kHistoryExcludedMessageTypes]**，
  ///   与 [excludeNoviceMessages] 共用同一个纯函数 [excludeFromLlmHistory]。
  ///   ⚠️ 方法名只写「诊断卡」，实际剔除面**比名字宽**（还含 C123 的
  ///   `novice_chat`）；保留本方法名只为不扩大改动面（`loadSessionContext`
  ///   调用点已指向它）。要增删剔除类型**只改白名单常量一处**。
  List<Message> excludeDiagnosisCardMessages(List<Message> history) =>
      excludeFromLlmHistory(history);

  /// 喂 LLM 的 history 副本整形：按 [kHistoryExcludedMessageTypes] 剔除
  /// 污染类型 + 按类型分组计数打日志。
  ///
  /// 抽出理由 = **职责独立**（喂 LLM 的副本整形），不是为凑 R-019 行数；
  /// 内联时实测把 `loadSessionContext` 顶到 **52 行**、门禁 5 FAIL（基线无
  /// 此条 ⇒ 按新增拦截）。内部复用 [excludeFromLlmHistory]，白名单仍是单一真源。
  ///
  /// ★ 为什么按类型分组计数（不用「两次减法凑数」）：白名单将来若加第三种
  ///   类型（`teacher_suggestion` 待裁定），减法会算错；分组后计数自动跟着对。
  List<Message> _shapeHistoryForLlm(List<Message> rawHistory) {
    final kept = excludeFromLlmHistory(rawHistory);
    final dropped = <String, int>{};
    for (final m in rawHistory) {
      if (!kHistoryExcludedMessageTypes.contains(m.messageType)) continue;
      dropped[m.messageType] = (dropped[m.messageType] ?? 0) + 1;
    }
    final detail = dropped.entries.isEmpty
        ? '（无剔除）'
        : '（已剔除 '
              '${dropped.entries.map((e) => '${e.key} ${e.value} 条').join(' + ')}）';
    debugPrint('[ChatService] 步骤2: 历史消息 ${kept.length} 条$detail');
    return kept;
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
