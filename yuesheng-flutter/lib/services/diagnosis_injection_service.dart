// ─────────────────────────────────────────────────────────────
// DiagnosisInjectionService — 诊断协议注入 + 诊断流程（ADR-0004 步 5 批 1）
//
// 从 `ChatServiceSend` extension 抽出的**独立类 + DI**（ADR-0004 §2 R-3）。
// 原状：`extension ChatServiceSend on ChatService` 1193 行（`chat_service.dart:653`
// -1845），其中本文件承接 13 个成员（约 392 行），是全仓唯一超限 extension 块。
//
// 为什么以「诊断簇」作第一个切口（实测调用图，非按名字猜簇）：
//   · 诊断簇与 prompt 注入簇（C）之间**零交叉调用** ⇒ 切口最干净；
//   · 外部只被 `ChatService._sendMessageCore` 调一次（`_applyDiagnosisInjection`
//     与 `_runDiagnosisFlow`）⇒ 无双向依赖；
//   · 内部是一条自洽链：`_applyDiagnosisInjection → _injectDiagnosisFor →
//     _injectDiagnosisProtocolAndLog → _maybeInjectDiagnosisProtocol →
//     {_buildDirectExplainBlock, _buildFadingBlock}`。
//
// ★ 为何 `_hasDiagnosisContext` 只收 `activeProblems`（而非整个 ctx）：
//   `_SendContext` 是 `chat_service.dart:639` 的**文件私有 typedef**，独立类看不到
//   它。实测该判定只需 `ctx.activeProblems`（另加 `options.chapterFullText`），
//   `_applyDiagnosisInjection` 只需 `ctx.messages` ⇒ **只传这两个字段**，
//   不动 `_SendContext` 的可见性、不扩大公开面。
//
// ★ 为何 `_resolveDirectExplainThreshold` 与 `_logSafeRun` 是**函数注入**：
//   二者分别是 C 簇（prompt 注入）与 A 簇（发送主链）的私有成员。Dart 中独立类
//   **无法访问**其他类的私有成员 ⇒ 必须由构造参数传入函数类型。这是 ADR-0004
//   §2 R-3「独立类 + DI」里 DI 的真实含义，不是泛指「传几个对象」。
//
// R-019：本文件所有函数均 ≤50 行（`_runDiagnosisFlow` 51 行处见下方拆分说明）。
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/llm_client.dart' show ChatMessage;
import 'package:writingcoach/services/chat_context_builder.dart'
    show ReferenceItem;
import 'package:writingcoach/types/teaching_types.dart';
import 'package:writingcoach/services/chat_message_types.dart';
import 'package:writingcoach/services/chat_service_diagnosis_focus.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/feedback_tier.dart';
import 'package:writingcoach/services/intent_classifier.dart';
import 'package:writingcoach/services/chat_gates.dart';

/// 诊断簇服务：从 ChatService 抽出的独立类（构造依赖全部注入，无隐式全局）。
class DiagnosisInjectionService {
  DiagnosisInjectionService({
    required this._diagnosisRepo,
    required this._stateRepo,
    required DiagnosisFlowHandler flowHandler,
    required this._replyObserver,
    required this._resolveDirectExplainThreshold,
    required this._diagnosisProtocolSuffix,
    required this._logSafeRun,
  }) : _flow = flowHandler;

  final DiagnosisRepository _diagnosisRepo;
  final TeachingStateRepository _stateRepo;
  final DiagnosisFlowHandler _flow;
  final ChatServiceReplyObserver _replyObserver;

  /// C 簇成员提升为函数注入（跨簇私有成员不可访问）。
  final Future<int> Function() _resolveDirectExplainThreshold;

  /// `ChatService.kDiagnosisProtocolSuffix`（ADR-C82 协议文本）注入。
  ///
  /// ★ 为什么不直接 import `chat_service.dart`：那个常量是 `ChatService` 的
  ///   static 成员，而 `chat_service.dart` 会 import 本文件（宿主持有本服务实例）
  ///   ⇒ 直接引用会形成**循环 import**。故由宿主在建服务时传入，
  ///   协议文本仍保持**单一真源**（不在本文件复制一份）。
  final String _diagnosisProtocolSuffix;

  /// A 簇成员提升为函数注入（跨簇私有成员不可访问）。
  final void Function(String label, Object error, StackTrace stack) _logSafeRun;

  // ── 协议注入链 ─────────────────────────────────────────────────────────

  /// 诊断协议注入编排（ADR-C82 + TH 五批判据）。
  ///
  /// TH 五批：判据并入「会话级诊断上下文」—— 教学场景的通用措辞
  ///（「这段怎么改」）不再注入协议，避免落库诊断 + 二次 Teacher 调用。
  Future<void> applyDiagnosisInjection({
    required List<ChatMessage> messages,
    required String content,
    required SendMessageOptions options,
    required String sessionId,
    required bool hasDiagnosisContext,
  }) async {
    await _injectDiagnosisFor(
      messages,
      content,
      options.chapterFullText,
      hasDiagnosisContext: hasDiagnosisContext,
      sessionId: sessionId,
    );
  }

  Future<void> _injectDiagnosisFor(
    List<ChatMessage> messages,
    String content,
    String? chapterFullText, {
    required bool hasDiagnosisContext,
    required String sessionId,
  }) async {
    await _injectDiagnosisProtocolAndLog(
      messages,
      content,
      chapterFullText: chapterFullText,
      hasDiagnosisContext: hasDiagnosisContext,
      sessionId: sessionId,
    );
  }

  /// 原版（删除前）会对 >40 字符消息打前 20 + 后 20 字符 —— 含用户原文片段，
  /// 触X-040 PHI P2 风险（debug 日志被外发/截图即泄漏用户输入）。
  Future<void> _injectDiagnosisProtocolAndLog(
    List<ChatMessage> messages,
    String content, {
    String? chapterFullText,
    required bool hasDiagnosisContext,
    required String sessionId,
  }) async {
    await _maybeInjectDiagnosisProtocol(
      messages,
      content,
      chapterFullText: chapterFullText,
      hasDiagnosisContext: hasDiagnosisContext,
      sessionId: sessionId,
    );
    debugPrint(
      '[ChatService] ADR-C82 请求结构: ${messages.map((m) => "${m.role}[${m.content.length}]").join(" | ")}',
    );
  }

  /// 诊断意图 → user 消息侧注入诊断协议（ADR-C82；R-019 ≤50 行）。
  ///
  /// TH 五批：判据不只有措辞 —— 弱信号措辞需 [hasDiagnosisContext] 佐证，
  /// 否则教学场景的「这段怎么改」会误触发注入（后果见 intent_classifier）。
  ///
  /// ★ 2026-10-04 症状格式污染修复（真机 0.4.1 反馈：说问题时出现
  /// 「【（症状名）】：（症状说明）」）。根因不在模型，在**同一条 user 消息里
  /// 混了三套标记**：协议块用 `[YS_DIAGNOSIS]`、全貌块用 `【】` 标题、
  /// 清单项又用「序号. [P005] 名——落在哪句」。模型在「直接说问题」模式下
  /// 一旦命中全貌分支（症候数 ≥ threshold，默认 5）就会把三种格式混编。
  /// 学员看到的是「AI 在念内部协议」，教学感直接崩掉。
  /// 修法是**纯格式层，不动协议、不动选 P 能力**（见_buildDirectExplainBlock）。
  Future<void> _maybeInjectDiagnosisProtocol(
    List<ChatMessage> messages,
    String content, {
    String? chapterFullText,
    required bool hasDiagnosisContext,
    required String sessionId,
  }) async {
    if (!isDiagnosisRequest(
      content,
      hasDiagnosisContext: hasDiagnosisContext,
    )) {
      return;
    }
    final lastUser = messages.lastIndexWhere((m) => m.role == 'user');
    if (lastUser < 0) return;
    final m = messages[lastUser];
    // 批次98：诊断全文运行时注入（不落库）—— 对话历史只展示简洁消息，
    // AI 侧仍收到全文；历史重放不含全文（避免长对话被整章内容稀释）。
    final fullTextBlock = chapterFullText == null || chapterFullText.isEmpty
        ? ''
        : '\n\n## 待诊断全文\n\n$chapterFullText';
    final directExplain = await _buildDirectExplainBlock();
    // ADR-C134：fading 支架渐退 override 块（运行时条件注入；无复发/失败 → ''）。
    final fadingBlock = await _buildFadingBlock(sessionId);
    messages[lastUser] = ChatMessage(
      role: m.role,
      content:
          '${m.content}$fullTextBlock\n\n$_diagnosisProtocolSuffix$directExplain$fadingBlock',
    );
  }

  /// 全貌清单块（症状数 ≥ 阈值时逐条列全部症候，让学员选）。
  ///
  /// R-019：2026-10-04 从 [_maybeInjectDiagnosisProtocol] 拆出 —— 那个函数因
  /// 本修复的论证注释涨到 57 行（上限 50）。拆的是**独立职责 + 独立失败模式**
  ///（它要 await 阈值、且是唯一带格式约束的地方），不是为凑行数的机械切分。
  ///
  /// 格式约束（2026-10-04，三条缺一不可）：
  ///  ① 标题用方括号族（与 `[YS_DIAGNOSIS]` 同族），消掉 `【】`；
  ///  ② 清单项**显式声明为纯文本、禁用任何括号包裹**；
  ///  ③ 正面追加「不要把症候名用括号括起来」，堵住混编。
  /// 保留 `[P005]` 仍是必须 —— 学员回「先练 P005」要能被
  /// message_injector._parseUserFocusFromMessage 的 P00x 正则命中，
  /// 否则系统会静默丢弃学员的选择、回退到 AI 自挑的顶优先级。
  Future<String> _buildDirectExplainBlock() async {
    final threshold = await _resolveDirectExplainThreshold();
    return '\n\n[全貌呈现]\n'
        '（全貌模式临时覆盖密度约束——选完一条后回到常规密度「一次只抛一个点」。）\n'
        '若本次识别出的症候数量 ≥ $threshold：\n'
        '1. 用编号列出全部症候——每条写成一行，行首是「序号. [P005] 症候名称」，'
        '破折号后接「落在哪一句」，如「1. [P005] 对话生硬——落在哪句」，**不要给改法**；\n'
        '2. 列表里每条就是一行普通文字，**不要把症候名用括号括起来**，'
        '也不要写成「症状名：说明」这种键值对；\n'
        '3. 末尾问一句"这些都在，你想先动哪个"，把选择权交给学员；\n'
        '4. 学员选定一条后，才对那一条展开"怎么改"（走正常教学流程）。\n'
        '若少于 $threshold，按正常教学方式聚焦讲解 1-2 条。';
  }

  /// ADR-C134/C139：fading 介入层级块（运行时条件注入）。
  ///
  /// ADR-C139（D1 修复）：不再因「无复发」提前返回 '' —— 改为始终输出三档介入
  /// 契约块，使 c=0「指认根因 + 受限示范单句」在纯首次诊断时可达（此前 c=0 返回
  /// null → LLM 转引导式追问、无示范句）。复发明细仅 prior≥1 时追加；仓储查询
  /// 失败仍降级 ''。R-028：诊断仓储为边界层，try/catch 降级留痕，不阻断主链路。
  Future<String> _buildFadingBlock(String sessionId) async {
    try {
      final recurrence = await _diagnosisRepo.countConfirmedDiagnosesBySyndrome(
        sessionId,
      );
      final eligibility = await _resolveFadingEligibility(sessionId);
      return buildFadingBlock(recurrence, eligibility) ?? '';
    } catch (e, st) {
      _logSafeRun('fading 块装配失败（降级不注入）', e, st);
      return '';
    }
  }

  /// ADR-C134：学员反馈资格裁决 —— 仅 N3/N4 独立级视为 highStable（可用引导提问）；
  /// 教学状态取不到 / 偏低级一律降级 all（低水平/消沉不得用提问类，安全方向）。
  Future<FeedbackEligibility> _resolveFadingEligibility(
    String sessionId,
  ) async {
    try {
      final ts = await _stateRepo.getTeachingState(sessionId);
      final level = BeginnerLevel.fromString(ts?.beginnerLevel);
      if (level == BeginnerLevel.n3Diagnose ||
          level == BeginnerLevel.n4Independent) {
        return FeedbackEligibility.highStableOnly;
      }
    } catch (e, st) {
      _logSafeRun('fading 资格裁决失败（降级 all）', e, st);
    }
    return FeedbackEligibility.all;
  }

  /// 本轮是否处于**诊断上下文** —— 确定性信号，不由措辞反推（TH 五批）。
  ///
  /// ① 本轮携带待诊断全文 ⇒ 「诊断本章 / 选中文本」入口；
  /// ② 会话已产生活跃症候 ⇒ 此前诊断成功过（含诊断后续轮、反馈、重试）。
  ///
  /// 二者皆否即为教学 / 自由对话轮次 ⇒ 弱信号措辞不参与诊断判定。
  ///
  /// ★ 只收 `activeProblems`（原实现收整个 `_SendContext`，见文件头说明）。
  bool hasDiagnosisContext({
    required SendMessageOptions options,
    required List<ActiveProblemView> activeProblems,
  }) {
    if (options.chapterFullText?.isNotEmpty ?? false) return true;
    return activeProblems.isNotEmpty;
  }

  /// 区分「用户主动取消」与「真实失败」（取消走 onCancelled，其余走 onError）。
  bool resolveDiagnosisOnly(String content) {
    final diagnosisOnly = isDiagnosisOnlyRequest(content);
    if (diagnosisOnly) {
      debugPrint('[ChatService] FT-22: 检测到「只诊断」边界声明，跳过 teacher 建议');
    }
    return diagnosisOnly;
  }

  // ── 诊断流程（9-11：解析 + 提交 + 训练 + onComplete）────────────────────

  /// 9-11 诊断解析 + 提交 + 训练 + onComplete（ADR-C74 K-9，R-019 收尾 helper）。
  Future<void> runDiagnosisFlow({
    required String sessionId,
    required String content,
    required String fullContent,
    required bool inDiagnosisBlock,
    required ReferenceItem? primaryRef,
    required String? chapterContent,
    required String? trainingSyndromeId,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required bool rapidFire,
    required bool flowBypassed,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
    final parsed = await _parseAndPersistDiagnosis(
      sessionId: sessionId,
      content: content,
      fullContent: fullContent,
      inDiagnosisBlock: inDiagnosisBlock,
      primaryRef: primaryRef,
      chapterContent: chapterContent,
      callbacks: callbacks,
      options: options,
    );
    // 步骤 10 空响应提前结束（onError 已触发，等价原 return）
    if (parsed.aborted) return;
    await _commitDiagnosisAndSuggestions(
      sessionId: sessionId,
      content: content,
      parsed: parsed,
      primaryRef: primaryRef,
      rapidFire: rapidFire,
      flowBypassed: flowBypassed,
      callbacks: callbacks,
      options: options,
      currentSubphase: currentSubphase,
    );
    await _finishTrainingAndComplete(
      sessionId: sessionId,
      content: content,
      parsed: parsed,
      trainingSyndromeId: trainingSyndromeId,
      activeProblems: activeProblems,
      currentSubphase: currentSubphase,
      callbacks: callbacks,
      options: options,
    );
  }

  Future<ParseAndPersistResult> _parseAndPersistDiagnosis({
    required String sessionId,
    required String content,
    required String fullContent,
    required bool inDiagnosisBlock,
    required ReferenceItem? primaryRef,
    required String? chapterContent,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
    // FT-22：检测「只诊断不要建议」边界声明，命中则跳过 teacher stream
    final diagnosisOnly = resolveDiagnosisOnly(content);
    // P0-1：解析 directExplain 阈值透传给 Teacher 门控 —— 症候数 ≥ 阈值时本轮
    // 只列名+问先动哪个，跳过 Teacher 抢先给改法（等学员选定后再展开）。
    final directExplainThreshold = await _resolveDirectExplainThreshold();
    return _flow.parseAndPersist(
      sessionId: sessionId,
      fullContent: fullContent,
      inDiagnosisBlock: inDiagnosisBlock,
      primaryRef: primaryRef,
      chapterContent: chapterContent,
      callbacks: callbacks,
      options: options,
      diagnosisOnly: diagnosisOnly,
      directExplainThreshold: directExplainThreshold,
    );
  }

  /// 诊断提交 + Teacher suggestion + GenUI 卡片 + 回复长度观测（R-019 拆出）。
  Future<void> _commitDiagnosisAndSuggestions({
    required String sessionId,
    required String content,
    // 由 dynamic 收窄为具体类型：严格模式下 4 处字段访问（parsed.diagnosis /
    // messageId / teacherResult / genuiComponents）报 argument_type_not_assignable。
    // 实参本就是 ParseAndPersistResult（_parseAndPersistDiagnosis 返回类型），
    // 属纯类型层修正、零行为变更。
    required ParseAndPersistResult parsed,
    required ReferenceItem? primaryRef,
    required bool rapidFire,
    required bool flowBypassed,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
    required TeachingSubphase? currentSubphase,
  }) async {
    await _flow.commitDiagnosisAndSuggestions(
      sessionId: sessionId,
      diagnosis: parsed.diagnosis,
      messageId: parsed.messageId,
      primaryRef: primaryRef,
      teacherResult: parsed.teacherResult,
      rapidFire: rapidFire,
      flowBypassed: flowBypassed,
      genuiComponents: parsed.genuiComponents,
    );
    // 批次 50 临时测量：回复长度观测（仅 debug 留痕不干预）
    _replyObserver.observeReplyLength(
      parsed.displayContent,
      content,
      options.attitude,
      currentSubphase,
    );
  }

  /// 训练结果解析 + teaching_history 写入 + onComplete（R-019 拆出）。
  Future<void> _finishTrainingAndComplete({
    required String sessionId,
    required String content,
    // 同 _commitDiagnosisAndSuggestions：dynamic → 具体类型（严格模式
    // argument_type_not_assignable ×4）。
    required ParseAndPersistResult parsed,
    required String? trainingSyndromeId,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
    await _flow.handleTrainingResult(
      sessionId: sessionId,
      currentSubphase: currentSubphase,
      displayContent: parsed.displayContent,
      userContent: content,
      trainingSyndromeId: trainingSyndromeId,
      activeProblems: activeProblems,
      callbacks: callbacks,
      // ADR-C105 A1：协议块的模型自主判定（在 parseAndPersist 内从 fullContent 解析）
      trainingResult: parsed.trainingResult,
    );
    await callbacks.onComplete(parsed.finalContent, parsed.messageId);
    debugPrint('[ChatService] sendMessage 完成 | onComplete 已触发');
  }
}
