// PromptAssemblyService — prompt 组装与上下文注入（ADR-0004 步 5 批 2）
//
// 从 `ChatServiceSend` extension 抽出的独立类 + DI（ADR-0004 §2 R-3），
// 承接 8 个成员（详见下方类文档）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/config/token_budget_table.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
import 'package:writingcoach/data/database/database.dart' show Message;
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart'
    show ActiveProblemView;
import 'package:writingcoach/services/chat_message_types.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show ReferenceItem;
import 'package:writingcoach/services/intent_classifier.dart';
import 'package:writingcoach/services/l2_route_hysteresis.dart';
import 'package:writingcoach/services/llm_client.dart' show ChatMessage;
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/prompt_sanitizer.dart';
import 'package:writingcoach/services/token_budget_guard.dart';
import 'package:writingcoach/types/coach_persona.dart';
import 'package:writingcoach/types/coach_persona_seed.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 预算闸门结果日志 + X-040 PHI 素材缺失提示（R-019 拆出，A 簇成员）。
///
/// 签名与 `ChatService._logBudgetOutcome` **逐字一致**（2 参：报告 + 消息列表）。
typedef BudgetOutcomeLogger =
    void Function(BudgetGuardReport guardReport, List<ChatMessage> messages);

/// prompt 组装服务（构造依赖全部注入，无隐式全局）。
class PromptAssemblyService {
  PromptAssemblyService({
    required this._teaching,
    required this._routeHysteresis,
    required this._messageInjector,
    required this._appStateRepo,
    required this._readDisabledSyndromeIds,
    required this._logBudgetOutcome,
    required this._wholeChapterBlock,
  });

  final TeachingCapability _teaching;
  final L2RouteHysteresis _routeHysteresis;
  final MessageInjector _messageInjector;
  final AppStateRepository? _appStateRepo;

  /// 禁用症候集的**现取**通道（字段可变，见文件头说明）。
  final Set<String> Function() _readDisabledSyndromeIds;

  /// A 簇成员提升为函数注入。
  final BudgetOutcomeLogger _logBudgetOutcome;

  /// `ChatService.kWholeChapterMinimalSupportBlock` 注入（避免 import 循环）。
  final String _wholeChapterBlock;

  // ── system prompt 组装 ───────────────────────────────────────────────

  /// 组装 system prompt（P1-4 诊断场景护栏 + L2 迟滞覆写）。
  List<ChatMessage> buildSystemPrompt(
    TeachingPhase phase,
    AttitudeLevel attitude,
    TeachingSubphase? subphase,
    bool isBeginner, {
    required String sessionId,
    bool isOutlineContext = false,
    required SendMessageOptions options,
    CoachPersona? activePersona,
    String? content,
  }) {
    // P1-4：当前消息措辞触发诊断协议但 l2Mode 非 diagnosis 阶段时，
    // 强制注入「先建现场」护栏（避免 P3 阶段裸奔诊断）。
    final forceSceneFirst =
        content != null &&
        isDiagnosisRequest(content, hasDiagnosisContext: false);
    final skillCtx = SkillLoadContext(
      phase: phase,
      attitude: attitude,
      teachingMode: options.teachingMode,
      subphase: subphase,
      isBeginner: isBeginner,
      isOutlineContext: isOutlineContext,
      disabledSyndromeIds: _readDisabledSyndromeIds(),
      activePersona: activePersona,
      forceDiagnosisSceneFirst: forceSceneFirst,
    );
    final rawMode = _teaching.resolveL2Mode(skillCtx);
    final override = _routeHysteresis.overrideFor(sessionId, rawMode);
    if (override != null) {
      // R-022 过程可见：迟滞是**静默**的行为变更（L2 组被覆盖），
      // 只在真正抑制时打一行（正常会话极少触发，不会刷屏）。
      debugPrint(
        '[ChatService] U2 迟滞：L2 组由 ${rawMode.name} 抑制为 ${override.name}'
        '（session=$sessionId）',
      );
    }
    final promptResult = _teaching.buildSystemPrompt(
      skillCtx,
      modeOverride: override,
    );
    return <ChatMessage>[
      ChatMessage(role: 'system', content: promptResult.systemPrompt),
    ];
  }

  /// D1/D2 Phase 2：解析当前激活教练人格。
  ///
  /// - 未装配 AppStateRepository 或读取失败 → null（走系统预设路径，行为零变化）。
  /// - 激活项为系统预设 / 未知（回退 gentle）→ null（原 attitude-* 路径，快照锁守护）。
  /// - 激活项为用户自定义人格（isSystem == false）→ 返回该人格，供注入其systemPromptFragment。
  Future<CoachPersona?> resolveActivePersona() async {
    final repo = _appStateRepo;
    if (repo == null) return null;
    try {
      final activeId = await repo.getActiveCoachPersonaId();
      if (activeId == null) return null;
      final customs = await repo.getCustomCoachPersonas();
      final resolved = resolveActiveCoachPersona(activeId, customs);
      return resolved.isSystem ? null : resolved;
    } catch (_) {
      return null;
    }
  }

  /// Resolve the active coach persona's direct-explain threshold (Part A).
  /// System preset / unknown / read failure -> default 5 (system presets are
  /// not user-editable via the coach card UI).
  Future<int> resolveDirectExplainThreshold() async {
    final repo = _appStateRepo;
    if (repo == null) return kDefaultDirectExplainThreshold;
    try {
      final activeId = await repo.getActiveCoachPersonaId();
      if (activeId == null) return kDefaultDirectExplainThreshold;
      final builtIn = builtInCoachPersonaById(activeId);
      if (builtIn != null) {
        final override = await repo.getCoachPersonaDirectThreshold(activeId);
        return override ?? builtIn.directExplainThreshold;
      }
      final customs = await repo.getCustomCoachPersonas();
      for (final p in customs) {
        if (p.id == activeId) return p.directExplainThreshold;
      }
      return kDefaultDirectExplainThreshold;
    } catch (_) {
      return kDefaultDirectExplainThreshold;
    }
  }

  // ── 上下文注入（5.0-5.2）─────────────────────────────────────────

  /// 5.0-5.2 上下文注入装配（R-019 拆出，委托 MessageInjector）。
  ///
  /// 返回 record 而非原私有 typedef `_InjectedContext`（文件私有，独立类
  /// 看不到它）——字段与原 typedef **逐一同序**。
  Future<
    ({
      ReferenceItem? primaryRef,
      String? chapterContent,
      String? trainingSyndromeId,
    })
  >
  injectContext({
    required String sessionId,
    required String content,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required BeginnerLevel? beginnerLevel,
    required TeachingPhase phase,
    List<String> priorUserTexts = const [],
  }) async {
    final base = await _injectBaseContext(
      sessionId: sessionId,
      content: content,
      messages: messages,
      markStage: markStage,
      priorUserTexts: priorUserTexts,
    );
    // P2-9：FSRS 复习调度（P3 档，activeProblems 数据与注入同源）
    await _messageInjector.injectReviewSchedule(
      sessionId: sessionId,
      phase: phase,
      messages: messages,
      markStage: markStage,
    );
    final trainingSyndromeId = await _messageInjector.injectDiagnosisLock(
      sessionId: sessionId,
      content: content,
      activeProblems: activeProblems,
      currentSubphase: currentSubphase,
      beginnerLevel: beginnerLevel,
      messages: messages,
      markStage: markStage,
    );
    return (
      primaryRef: base.primaryRef,
      chapterContent: base.chapterContent,
      trainingSyndromeId: trainingSyndromeId,
    );
  }

  /// P2 收尾：基础注入链（画像 → 引用 → 章节观察 → 大纲事实/文件）。
  Future<({ReferenceItem? primaryRef, String? chapterContent})>
  _injectBaseContext({
    required String sessionId,
    required String content,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
    List<String> priorUserTexts = const [],
  }) async {
    await _messageInjector.injectProfileAndIntents(
      sessionId: sessionId,
      content: content,
      messages: messages,
      markStage: markStage,
    );
    final refCtx = await _messageInjector.injectReferences(
      sessionId: sessionId,
      messages: messages,
      markStage: markStage,
    );
    final primaryRef = refCtx.primaryRef;
    final chapterContent = refCtx.chapterContent;
    await _messageInjector.injectChapterObservations(
      sessionId: sessionId,
      content: content,
      primaryRef: primaryRef,
      messages: messages,
      markStage: markStage,
      priorUserTexts: priorUserTexts,
    );
    await _messageInjector.injectOutlineFactsAndFiles(
      content: content,
      primaryRef: primaryRef,
      messages: messages,
      markStage: markStage,
    );
    return (primaryRef: primaryRef, chapterContent: chapterContent);
  }

  // ── 历史追加 + 约束 ──────────────────────────────────────────────────

  /// 7. 追加历史消息 + 每轮必变提示 + 纪律重申 + token 预算闸门（R-019 编排 helper）。
  ///
  /// ★ A-1（2026-09-15）：[sessionId]/[content] 为「每轮必变提示」注入所需。
  /// 顺序契约（上下文缓存前缀稳定性）：
  ///   system prompt → 稳定注入段 → Live 约束 → 历史 → **本方法注入的
  ///   意图/颗粒度提示** → 纪律重申 → 预算闸门
  /// 意图/颗粒度依赖当前 user 消息与会话滚动意图窗口，逐轮必变；若留在
  /// 注入段中段，会让其后的一切（含追加式历史）每轮全价 miss。
  void appendHistoryAndConstraints(
    List<Message> history,
    List<ChatMessage> messages,
    void Function(String) markStage,
    Map<String, List<int>> stageIndexes, {
    required String sessionId,
    required String content,
    bool wholeChapterModeActive = false,
  }) {
    _appendHistory(history, messages, markStage);
    _messageInjector.injectTrailingHints(
      sessionId: sessionId,
      content: content,
      messages: messages,
    );
    // L2 注入纵深防御（R-027 人工确认）：发送前清洗 user 消息中的
    // 已知指令 token（<system>/[INST] 等转义），防反向注入。
    // 只作用于 LLM 输入副本，不影响落库的用户原文。
    _sanitizeUserMessages(messages);
    _appendDisciplineReminder(messages);
    // ADR-C137 批2：完整章模式激活 → 末尾追加「按需介入」system 块
    // （存在感 + 求助即答 + R-009 边界重申）。非激活路径不追加 ⇒
    // 消息序列与锚点逐字节一致（锚点用例均不传该 flag）。
    if (wholeChapterModeActive) {
      messages.add(const ChatMessage(role: 'system', content: ''));
      // 用构造期注入的块文本替换（const 构造器不接受运行期字符串）。
      messages[messages.length - 1] = ChatMessage(
        role: 'system',
        content: _wholeChapterBlock,
      );
    }
    _logBudgetOutcome(
      TokenBudgetGuard.apply(messages, stageIndexes: stageIndexes),
      messages,
    );
  }

  /// L2 输入清洗：对所有 role=user 的 LLM 输入消息做指令 token 转义。
  /// 只改发送给模型的副本（messages 列表），落库原文不受影响。
  void _sanitizeUserMessages(List<ChatMessage> messages) {
    for (var i = 0; i < messages.length; i++) {
      final m = messages[i];
      if (m.role != 'user') continue;
      final cleaned = sanitizeUserContent(m.content);
      if (cleaned != m.content) {
        messages[i] = ChatMessage(role: m.role, content: cleaned);
      }
    }
  }

  /// 追加历史消息（R-019 拆出）。
  ///
  /// 批次 B-2（输入侧上下文细化）：历史条数封顶——防止长会话无界增长
  /// 挤占教学注入预算；当前 user 消息总是最后一条，必然保留。
  /// TokenBudgetGuard 阶段级裁剪仍作兜底。
  ///
  /// A-1b（前缀稳定化）：头部改由 [LlmInputLimits.historyStartIndex]
  /// **按批对齐**裁剪。原逐条滑窗（`sublist(total - 20)`）令历史首条每轮
  /// 前移，它是历史块的首字节 ⇒ 缓存从该处整段失效，追加式历史每轮全价
  /// miss。对齐后头部约每 `historyTrimBatch / 2` 轮才前移一次，其余轮次
  /// 历史块与前轮严格前缀相同 ⇒ 命中缓存。
  void _appendHistory(
    List<Message> history,
    List<ChatMessage> messages,
    void Function(String) markStage,
  ) {
    final from = LlmInputLimits.historyStartIndex(history.length);
    final capped = from == 0 ? history : history.sublist(from);
    for (final m in capped) {
      markStage(BudgetStageNames.history);
      messages.add(ChatMessage(role: m.role, content: m.content));
    }
  }

  /// 历史后追加 L1 核心纪律重申（批次4 4.3 + X-040 PHI P2，R-019 拆出）。
  void _appendDisciplineReminder(List<ChatMessage> messages) {
    messages.add(
      ChatMessage(
        role: 'system',
        content:
            '# 回复纪律（最后提醒）\n\n'
            '长历史易稀释前置约束，此处重申 L1 核心纪律，回复时严格遵守：\n\n'
            '1. 不替用户写句子、不替用户做决定；\n'
            '2. 一次只抛一个点，删掉铺垫；\n'
            '3. 示范按当前态度档位执行：温柔语气/yuesheng 最小示范，sensei 零示范只给方向；\n'
            '4. 诊断结论必须基于用户实际文本，不假定被预算闸门裁掉的素材内容；\n'
            '5. 回复去 AI 味，不用"让我来帮你"等套话；\n'
            '6. 诊断块按 [YS_DIAGNOSIS]...[/YS_DIAGNOSIS] 标记输出（用户请求诊断时），卡片块用对应标签，不裸露 JSON。',
      ),
    );
  }
}
