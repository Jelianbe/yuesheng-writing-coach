// ─────────────────────────────────────────────────────────────
// ChatService — 主编排器
// 复刻 yuesheng-android/src/services/chat-service.ts 的 sendMessage 主链路
//
// 简化范围（"先主路核心"原则）：
//   - Editor / Teacher 分支已实现（批次 1-7 补齐，
//     见 chat_gates.dart 触发与持久化）
//   - onTrainingResult 回调已接线（SendMessageCallbacks.onTrainingResult，
//     步骤 11 解析训练结果后触发，UI 侧 WritingCoachPanel/ChatPage 消费）
//
// 已实现主链路：
//   1. addMessage(user) → listMessages
//   2. getTeachingState → subphase + isBeginner
//   3. listActiveProblems
//   4. buildSystemPromptV2 → system message
//   5. focus-resolver + training-evaluator + L3 结构化症候详情
//   6. streamChat + 拦截诊断块
//   7. parseDiagnosis + validateDiagnosisOutput
//   8. addMessage(assistant)
//   9. commitDiagnosisWithHistory + phase-mapper resolver + updatePhase/updateBeginnerLevel
//  10. parseTrainingResult + appendTeachingHistory（FEEDBACK 子阶段）
//  11. onComplete
//
// 学员画像注入（批次1-7-3）：
//   - 在 system prompt 之后、引用内容注入之前，插入 buildStudentContext 文本
// ─────────────────────────────────────────────────────────────

// 私有字段（_xxx）+ 公开命名参数（xxx）模式无法用 initializing formal
// ignore_for_file: prefer_initializing_formals

// ADR-C74 K-7：5 个 _inject* 方法 + 11 跟随 helper + _insertPhaseSummaryOnMastered
// 迁至 MessageInjector（lib/services/message_injector.dart），ChatService 改为
// 委派。下游消费者（DiagnosisCommitter K-2..K-5 字段 + MessageInjector 装配参数）
// 仍需 ChatService 持仓储引用作为 DI 中转，故以下字段在 ChatService 内部暂未
// 直接消费但保留（X-041c / 批次66-72 装配契约不变，测试 fixture 兼容）。
// ignore_for_file: unused_field

import 'chat_service_diagnosis_focus.dart';
import 'dart:async';

import 'package:dio/dio.dart' show DioException;
import 'package:writingcoach/services/error_handler.dart';
import 'package:writingcoach/services/l2_route_hysteresis.dart';
import 'package:flutter/foundation.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/contracts/reference_capability.dart';
import 'package:writingcoach/services/token_budget_guard.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/app_state_repository.dart';
import 'package:writingcoach/services/diagnosis_tier_bridge.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_message_types.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/chat_training_parser.dart'
    show kTrainingStart;
import 'package:writingcoach/services/outline_parser.dart';
import 'package:writingcoach/services/fact_parser.dart';
import 'package:writingcoach/services/genui_parser.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/llm_output_guard.dart';
import 'package:writingcoach/services/llm_usage.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/stage_drop_notice.dart';
import 'package:writingcoach/services/chat_gates.dart';
import 'package:writingcoach/services/diagnosis_injection_service.dart';
import 'package:writingcoach/services/prompt_assembly_service.dart';
import 'package:writingcoach/features/onboarding/novice_mode_guide.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 批次64（B62f）诊断请求标记（ADR-C74 K-7 迁至 MessageInjector：
/// lib/services/message_injector.dart._kDiagnosisRequestMarker）

/// ChatService 依赖：所有 Repository + LlmClient
class ChatService {
  final SessionRepository _sessionRepo;
  final TeachingStateRepository _stateRepo;
  final DiagnosisRepository _diagnosisRepo;
  final ReferenceCapability _referenceRepo;
  final LlmClient _llmClient;

  /// X-041c：训练结果持久化仓储（可选——不装配则跳过 training_results 落库）
  /// 真源：PracticeStore.trainingResult 仅存内存态；装配后训练轮反馈命中时
  /// 同步写入 training_results 表，补全 GrowthStore.trainingStats 数据源。
  /// 设计为可选参数：避免破坏 30+ 处现有测试构造（默认 null 跳过回写）。

  /// D1/D2 Phase 2：应用状态仓储（可选——不装配则跳过用户自定义人格注入，
  /// 走系统预设路径，行为零变化。避免破坏 30+ 处现有测试构造，同 trainingResultRepo）。
  final AppStateRepository? _appStateRepo;

  /// 诊断编辑器：用户永久关闭的症候 ID（由 UI 层在诊断开始前从
  /// AppStateRepository 读入后设置；空集 = 全启用，历史行为）。
  Set<String> disabledSyndromeIds = const {};

  // ─── 四大纯能力（选项 B 依赖倒置：经 capability provider 注入，默认 const impl） ───
  // 阶段 1：消费层从顶层纯函数迁移到能力方法；impl 为纯委托，行为零变更。
  // 生产侧经 chatServiceProvider 读 capability provider 注入；测试替身
  // （_FakeChatService）override sendMessage 整体、不触达本字段，默认值无害。
  final TeachingCapability _teaching;

  /// 批次66（B62i）：人物知识仓储（可选——不装配则跳过时序矛盾观察）

  /// 批次67（B62j）：事件知识仓储（可选——不装配则跳过 F07 因果链观察）

  /// 批次67（B62j）：支线知识仓储（可选——不装配则跳过 F11 情节闭环观察）

  /// 批次72（大纲层）：大纲仓储（可选——装配后实体索引注入 + 提取落库才可用）
  /// K-9 起 outlineRepo 由 DiagnosisFlowHandler / MessageInjector 各自持有，
  /// ChatService 不再直接消费；保留构造参数以兼容既有测试 fixture（无副作用）。

  /// 诊断提交编排器（ADR-C74 K-1 骨架）
  ///
  /// K-1 阶段：nullable + ChatService 不消费，仅证明「独立类 + DI」路径
  /// 可行（X-025-ARCH 教训复盘）。K-2 ~ K-5 阶段随方法迁入时逐步收紧为
  /// non-null + required；K-5 收尾时本字段升级。

  /// 系统消息注入编排器（ADR-C74 K-7）
  ///
  /// sendMessage 主流程中 5 个 system 消息注入步骤（5.0 学员画像 / 5.1 引用 /
  /// 5.1.x 章节观察 / 5.2 附属文件 / 6 诊断锁）的独立持有者。
  /// ChatService 改为委派，自身不持有注入链逻辑。X-025-ARCH 教训：
  /// 必须是「独立类 + DI」模式，不可用 extension 拆分。
  final MessageInjector _messageInjector;

  /// 诊断流编排器（ADR-C74 K-9）
  ///
  /// sendMessage 主流程中 4 个诊断链方法（步骤 9-10 解析 + 持久化 /
  /// 步骤 11 提交 + Teacher + GenUI / 步骤 11 FEEDBACK 训练结果）的独立持有者。
  /// 连续失败计数、_diagnosisDropLog、_recordDiagnosisOutcome、_readOutlineEntityCount
  /// 等 helper 一并随方法迁入本类。X-025-ARCH 教训：必须是「独立类 + DI」模式，
  /// 不可用 extension 拆分。
  final DiagnosisFlowHandler _diagnosisFlowHandler;

  /// 阶段总结卡 helper（ADR-C74 K-7 随 _injectDiagnosisLock / _handleTrainingResult
  /// 迁至 MessageInjector，见 lib/services/message_injector.dart）。

  /// 公开委派（ADR-C74 K-9）：分块诊断生成的完整 AI 输出（D4-A）。
  ///
  /// 由 ChatDiagnosisController 调用（lib/widgets/chat_diagnosis_controller.dart）。
  /// 实现已迁 DiagnosisFlowHandler；本方法保留同名同参同返回以保证
  /// 调用方零改动（K-5 同款薄壳委派）。
  Future<String> commitDiagnosisFromContent({
    required String sessionId,
    required String fullContent,
    String? chapterContent,
  }) async {
    _diagnosisFlowHandler.disabledSyndromeIds = disabledSyndromeIds;
    return _diagnosisFlowHandler.commitDiagnosisFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
      chapterContent: chapterContent,
    );
  }

  ChatService({
    required SessionRepository sessionRepo,
    required TeachingStateRepository stateRepo,
    required DiagnosisRepository diagnosisRepo,
    required ReferenceCapability referenceRepo,
    required LlmClient llmClient,
    // X-041c：可选装配，不传则跳过 training_results 落库（不破坏现有测试构造）
    // D1/D2 Phase 2：可选装配，不传则无用户人格注入（行为零变化，同 trainingResultRepo）
    AppStateRepository? appStateRepo,
    TeachingCapability teaching = const TeachingCapabilityImpl(),
    // ★ U2（2026-09-15）：L2 路由迟滞器（会话级、纯内存）。可选装配，
    // 不传则自建 —— 不破坏既有测试构造（与 trainingResultRepo 同模式）。
    L2RouteHysteresis? routeHysteresis,
    // ADR-C74 K-1：诊断提交编排器，K-1 阶段 nullable（不破坏现有 30+ 测试构造）
    // ADR-C74 K-7：系统消息注入编排器，required（与 diagnosisCommitter 同模式）。
    // 「独立类 + DI」拆分路径，X-025-ARCH 教训复盘。
    required MessageInjector messageInjector,
    // ADR-C74 K-9：诊断流编排器，required（与 diagnosisCommitter / messageInjector 同模式）。
    // commitDiagnosisFromContent 公开委派 + parseAndPersist / commitDiagnosisAndSuggestions /
    // handleTrainingResult 内部三步委派。
    required DiagnosisFlowHandler diagnosisFlowHandler,
  }) : _sessionRepo = sessionRepo,
       _stateRepo = stateRepo,
       _diagnosisRepo = diagnosisRepo,
       _referenceRepo = referenceRepo,
       _llmClient = llmClient,
       _appStateRepo = appStateRepo,
       _teaching = teaching,
       _routeHysteresis = routeHysteresis ?? L2RouteHysteresis(),
       _messageInjector = messageInjector,
       _diagnosisFlowHandler = diagnosisFlowHandler;

  // ── B5（2026-10-06）：从 extension 收敛为独立类的两个协作对象 ──
  //
  // 原先两块（`ChatServiceDiagnosisFocus` 36 行 / `ChatServiceObservers` 32 行）
  // 是 extension，靠「跨对象访问私有成员」拿到 `_diagnosisRepo` 与 `_logSafeRun`。
  // 收敛后改为显式协作对象：依赖由构造注入，调用点不变（仅方法名前缀）。
  //
  // ⚠️ `_diagnosisFocus` 在**构造器之后**声明，因为它的 `onSafeRun` 回调要传
  //   本对象的 `_logSafeRun` 引用，而 Dart 初始化列表里不能引用 `this` 的方法 ——
  //   `late final` 兜住这一点（首次调用发生在发送消息时，远晚于构造）。
  late final ChatServiceDiagnosisFocus _diagnosisFocus =
      ChatServiceDiagnosisFocus(
        diagnosisRepo: _diagnosisRepo,
        onSafeRun: _logSafeRun,
      );

  /// 回复长度观测（B5：原 `ChatServiceObservers`，零依赖故无构造参数）。
  final ChatServiceReplyObserver _replyObserver =
      const ChatServiceReplyObserver();

  /// ★ ADR-0004 步 5 批 1：以下两个协议文本常量原在 extension
  ///   `ChatServiceSend` 内，抽诊断簇时被连带删除。提到 class 顶层是
  ///   因class 体要把它注入 `DiagnosisInjectionService`（extension 成员
  ///   在 class 体内不可见），而 Dart 允许 extension 读宿主 static
  ///   （已实测）⇒ 测试侧 `ChatServiceSend.kX` 调用形态不变。
  /// 实验验证：user 侧注入后 deepseek-v4-flash 稳定输出 [YS_DIAGNOSIS] 块。
  static const String kDiagnosisProtocolSuffix =
      '\n\n[输出要求·最高优先级]\n'
      '用户明确请求诊断。除正文回复外，必须在回复**最末尾**附加结构化诊断块，'
      '严格使用协议标记：\n'
      '[YS_DIAGNOSIS]\n'
      '{"syndromes": [{"syndrome_id": "P001", "name": "症候名称", "severity": "L2", '
      '"evidence": ["原文片段"], "explanation": "判定理由"}], '
      '"suggested_actions": ["A009"], "confidence": 0.8, '
      '"root_cause_analysis": "根因（可选）", "next_focus": "下步焦点（可选）", '
      '"feedback_summary": "反馈总结（可选）", "suggested_phase": "阶段（可选）"}\n'
      '[/YS_DIAGNOSIS]\n'
      '块内容必须与正文结论一致，不得伪造症候。'
      '不要使用 markdown 代码块（```）包裹诊断 JSON；'
      '必须用 [YS_DIAGNOSIS] 与 [/YS_DIAGNOSIS] 标记，不要省略。';

  /// ADR-C137 批2：完整章模式「按需介入」块（追加到消息序列末尾的 system 指令）。
  ///
  /// 注入条件：SendMessageOptions.wholeChapterModeActive == true（学员在写作页
  /// 激活「这一章我自己写」后，经 chat runner 透传）。非完整章路径不追加。
  ///
  /// R-009 形态（逐字锁定）：只给存在感 + 求助即答 + 边界重申；
  /// 不含任何代写句子/段落、打分、处方、达标线——块本身就是「最小介入」指令。
  static const String kWholeChapterMinimalSupportBlock =
      '# 按需介入（完整章模式）\n\n'
      '学员已主动声明「这一章我自己写」。在本章达到其自设字数目标前，保持最小介入：\n\n'
      '1. 存在感：让学员知道你在（一句「我在，随时叫我」即可），不主动点评、'
      '不主动给改法、不催更、不追问进度；\n'
      '2. 求助即答：仅当学员主动提问或求助时，才恢复正常介入、深入解答；'
      '学员这次开口即视为求助；\n'
      '3. R-009 边界重申：不替学员写句子或段落，不打分，不开处方；'
      '只给结构性提问与方向。';

  ///
  /// **懒加载**（late final +惰性初始化）：构造期不建，因为其构造参数含两个
  /// **本类私有成员**的函数闭包（`_resolveDirectExplainThreshold` 属 C 簇、
  /// `_logSafeRun` 属 A 簇），构造期无法安全引用（会与 `final` 字段初始化顺序
  /// 纠缠）。首次使用时才建，此时所有字段已就绪。
  ///
  /// ⚠️ 循环依赖已避免：`kDiagnosisProtocolSuffix` 是本类的 static 常量，
  ///   新文件**不 import 本文件**（否则循环），改由下方构造时传入 ⇒ 协议文本
  ///   仍保持**单一真源**（不在新文件复制）。
  late final DiagnosisInjectionService _diagnosisService =
      DiagnosisInjectionService(
        diagnosisRepo: _diagnosisRepo,
        stateRepo: _stateRepo,
        flowHandler: _diagnosisFlowHandler,
        replyObserver: _replyObserver,
        resolveDirectExplainThreshold:
            _promptService.resolveDirectExplainThreshold,
        diagnosisProtocolSuffix: kDiagnosisProtocolSuffix,
        logSafeRun: _logSafeRun,
      );

  /// ADR-0004 步 5 批 2：prompt 组装簇（C）已抽出为独立类 + DI。
  ///
  /// **懒加载**理由同 [_diagnosisService]：构造参数含 C/A 簇私有成员的闭包。
  /// `disabledSyndromeIds` 用**getter 注入**而非值注入——它是**可变字段**
  /// （`:101`，并在 `:155`/`:473` 同步给 `_diagnosisFlowHandler`），
  /// 值注入会留下陈旧快照 ⇒ 注入 `() => disabledSyndromeIds` 现取。
  late final PromptAssemblyService _promptService = PromptAssemblyService(
    teaching: _teaching,
    routeHysteresis: _routeHysteresis,
    messageInjector: _messageInjector,
    appStateRepo: _appStateRepo,
    readDisabledSyndromeIds: () => disabledSyndromeIds,
    logBudgetOutcome: _logBudgetOutcome,
    wholeChapterBlock: kWholeChapterMinimalSupportBlock,
  );

  // 引用内容预加载缓存（ADR-C74 K-7 迁至 MessageInjector：见 lib/services/message_injector.dart）

  // 批次59：心流判定——记录每个 session 最近一次用户消息发送时间（秒级）
  final Map<String, int> _lastUserSendAtSec = {};

  /// ★ U2（2026-09-15）：L2 路由迟滞状态（会话级、纯内存、不落库）。
  /// 消掉训练轮结束后 `updateSubphase(null)` 引起的自动回切。
  /// 见 lib/services/l2_route_hysteresis.dart。
  final L2RouteHysteresis _routeHysteresis;

  // 批次63（B62b）意图向量缓存位于 MessageInjector（ADR-C74 K-7 迁入；
  // ★ A-1 起由 injectTrailingHints 在**历史之后**注入，见该处注释）

  // ════════════ 会话/态度管理 ════════════

  // ★ 2026-10-06（N5 甲档）：原 `initSession()` 已删 —— 它是**生产零调用的死方法**
  //   （唯一调用方是测试），且其口径「listSessions() 全局取 updated_at 最新、
  //   无作品过滤」若被复用即会跨书串上下文。生产两条会话初始化路径均不走它：
  //   ① 写作页教练面板 → WritingCoachSessionBootstrapper.initSession()
  //      （按章隔离：findSessionForChapter）
  //   ② 聊天页 → session_providers._resolveSessionId()
  //      （显式目标 > LAST_SESSION_KEY > updated_at 最新 > 新建；chat 页
  //      设计上不感知作品维度，全局口径是有意语义，非疏漏）
  //   保留登记以防有人重新捡起这个无过滤口径。

  /// 加载会话的态度状态
  Future<
    ({
      AttitudeLevel attitude,
      TeachingPhase phase,
      String? activePersonaName,
      bool isAttitudeLocked,
    })
  >
  loadAttitudeState(String sessionId) async {
    final ts = await _stateRepo.getTeachingState(sessionId);
    // New session without a persisted attitude -> fall back to the global
    // active persona's attitude (not hard default gentle).
    final persistedLevel = AttitudeLevel.fromString(ts?.attitudeLevel);
    var attitude = persistedLevel ?? await _resolveGlobalAttitude();
    return (
      attitude: attitude,
      phase:
          TeachingPhase.fromString(ts?.currentPhase) ?? TeachingPhase.p0Engage,
      // 无持久态度且回退到全局激活人格时，带出激活人格名（自定义 → 显示名，系统 → null）。
      // 供聊天页菜单体现「当前教练」，消除「自定义了却显示温柔语气」的错觉。
      activePersonaName: persistedLevel == null
          ? await _resolveActivePersonaName()
          : null,
      // C129（断点 B）：会话是否已锁定自身态度（persistAttitude 写过
      // teaching_state.attitudeLevel）。锁定会话仍以此值为准，设置页改全局
      // 教练不影响它；UI 据此显示「本会话已锁定」徽标。
      isAttitudeLocked: persistedLevel != null,
    );
  }

  /// 全局激活人格名：用户自定义人格 → 其 name；系统预设 / 无 / 读失败 → null。
  Future<String?> _resolveActivePersonaName() async {
    final persona = await _promptService.resolveActivePersona();
    return persona?.name;
  }

  /// Global fallback for a new session with no persisted attitude.
  /// Resolves the active persona (system preset / custom) attitude;
  /// no AppStateRepository / read failure -> gentle (previous behavior).
  Future<AttitudeLevel> _resolveGlobalAttitude() async {
    final repo = _appStateRepo;
    if (repo == null) return AttitudeLevel.gentle;
    try {
      return await repo.resolveGlobalCoachAttitude();
    } catch (_) {
      return AttitudeLevel.gentle;
    }
  }

  /// 持久化态度切换
  Future<void> persistAttitude(String sessionId, AttitudeLevel attitude) async {
    await _stateRepo.persistAttitude(sessionId, attitude.value);
  }

  // ════════════ sendMessage 主链路 ════════════

  /// 发送消息并接收流式回复
  ///
  /// 流程：
  /// 1. 写入用户消息
  /// 2. 获取历史消息（含刚写入的 user）
  /// 3. 读取 teaching_state（subphase + beginner_level）
  /// 4. 加载活跃症候
  /// 5. buildSystemPromptV2 拼接 L1+L2
  /// 6. focus-resolver + training-evaluator + L3 结构化症候详情注入
  /// 7. streamChat 流式调用，拦截 [YS_DIAGNOSIS] 块
  /// 8. parseDiagnosis + validateDiagnosisOutput
  /// 9. addMessage(assistant)
  /// 10. 若有诊断：commitDiagnosis + phase-mapper resolver

  /// 批次6（6.3）：流式拦截标记最大长度（取全部被拦截标记的**最长值**）。
  /// 现值来源：`kTrainingStart='[YS_TRAINING]'`=**15**（ADR-C105 A1 新增，
  /// 此前最长者为 `kDiagnosisStart='[YS_DIAGNOSIS]'`=14）。
  ///
  /// ⚠️ 本常量**只影响 rescan 窗口的回退距离（性能）**，不承担正确性：
  ///   ① 「不泄漏半截标记」由 [_blockPendingPrefix] 保证（跨 chunk 暂缓转发）；
  ///   ② `indexOf` 的起点恒 ≤ `displayLength` ⇒ 任何起点 ≥ displayLength 的
  ///      标记必被发现，与窗口大小无关。
  /// 新增协议块时**照抄最长值**即可，但**必须**同步另外两处：
  /// [DiagnosisFlowHandler._stripProtocolBlocks] 与 [_blockPendingPrefix]，
  /// 否则会重演 ADR-C105 A1（协议块全仓无剥离/无拦截）。
  static const int _kMaxStreamMarkerLen = 15;

  /// 批次6（6.10）：fullContent 内存上限——超过则截断头部（协议块/诊断信息在
  /// 尾部，尾部价值最高；displayLength 同步左移保持索引一致）。
  /// 正常回复远低于上限，仅在极端超长流式时触发，防内存无限累积。
  static const int _kFullContentMaxLen = 200 * 1024;

  /// 取两个 index 中更早出现者（-1 视为不存在，返回另一个）
  static int _earliestMarkerIndex(int a, int b) {
    if (a == -1) return b;
    if (b == -1) return a;
    return a < b ? a : b;
  }

  /// 取多个 index 中最早出现者（-1 视为不存在；空列表返回 -1）。
  /// 与 [_blockPendingPrefix] 的 max-reduce 对偶，min-reduce 形式统一（CR-54）。
  static int _earliestMarkerIndexList(List<int> indexes) {
    if (indexes.isEmpty) return -1;
    return indexes.reduce(_earliestMarkerIndex);
  }

  /// 检查 fullContent 尾部是否命中任一协议块标记的某个前缀
  ///（[YS_DIAGNOSIS] / ```diagnosis / [YS_ENTITY] / [YS_FACT] / [YS_GENUI] /
  ///  [YS_TRAINING]），返回需暂缓转发的后缀长度（防分隔符跨 chunk 到达时误转发）
  ///
  /// ADR-C105 A1：`[YS_TRAINING]`（15 字符）此前**不在本表内** ⇒ 与前缀共享关系
  /// 导致半截标记被当作正文转发（实测：`#C105-1b①` 由「onStream 不含标记」断言抓获）。
  static int _blockPendingPrefix(String fullContent) {
    final diag = getPendingMarkerPrefix(fullContent);
    final mdDiag = _pendingPrefix(fullContent, kMarkdownDiagOpen);
    final outline = _pendingPrefix(fullContent, kOutlineStart);
    final fact = _pendingPrefix(fullContent, kFactStart);
    final genui = _pendingPrefix(fullContent, kGenuiStart);
    final training = _pendingPrefix(fullContent, kTrainingStart);
    return [
      diag,
      mdDiag,
      outline,
      fact,
      genui,
      training,
    ].reduce((a, b) => a > b ? a : b);
  }

  static int _pendingPrefix(String fullContent, String marker) {
    for (var len = marker.length - 1; len > 0; len--) {
      final prefix = marker.substring(0, len);
      if (fullContent.endsWith(prefix)) return len;
    }
    return 0;
  }

  // ════════════ 辅助方法 ════════════

  // ════════════ 辅助 API ════════════

  /// 加载会话的消息历史
  Future<List<Message>> loadMessages(String sessionId) async {
    return _sessionRepo.listMessages(sessionId);
  }

  /// 加载子阶段
  Future<TeachingSubphase?> loadSubphase(String sessionId) async {
    final ts = await _stateRepo.getTeachingState(sessionId);
    return TeachingSubphase.fromString(ts?.currentSubphase);
  }

  /// 设置子阶段（**用户动作驱动的显式入口**）
  ///
  /// ★ U2（2026-09-15）：显式变更同时清空 L2 路由迟滞状态 —— 否则
  /// 「跳过练习」（chat_reference_controller.handleSkipPractice → 本方法）
  /// 会被迟滞多留一轮训练语境，等于没听用户指令。
  ///
  /// 注意区分：训练轮结束后的**自动**回切走的是 `_stateRepo.updateSubphase`
  ///（diagnosis_flow_handler.dart:1144），不经此处 ⇒ 迟滞在那边正常生效。
  Future<void> setSubphase(String sessionId, TeachingSubphase? subphase) async {
    _routeHysteresis.reset(sessionId);
    await _stateRepo.updateSubphase(sessionId, subphase?.value);
  }

  // ════════════ 批次50 回复长度临时观测 ════════════

  // ════════════ 引用内容预加载 ════════════

  // 批次96-25：sendMessage 主流程逐字迁至 chat_service_send.dart 的
  // `_sendMessageCore`（extension 方法，保留 this 语义）。此处保留薄实例方法，
  // 以维持子类 override / 测试替身（_FakeChatService）的派发语义。
  Future<void> sendMessage(
    String sessionId,
    String content,
    SendMessageCallbacks callbacks,
    SendMessageOptions options, {
    TeachingSubphase? subphase,
  }) async {
    _diagnosisFlowHandler.disabledSyndromeIds = disabledSyndromeIds;
    await _sendMessageCore(
      sessionId,
      content,
      callbacks,
      options,
      subphase: subphase,
    );
  }
}

// K-9 移除: commitDiagnosisFromContent + _readOutlineEntityCount 已迁 DiagnosisFlowHandler
// B5（2026-10-06）：`extension ChatServiceDiagnosisFocus` 已收敛为独立类
// （见 lib/services/chat_service_diagnosis_focus.dart）

// ADR-C74 K-7 迁出至 MessageInjector：extension ChatServiceDiagnosisSupport
// 整块删除（仅含 _buildInterventionAdjustmentNote，迁入 MessageInjector._buildInterventionAdjustmentNote）

// ADR-C74 K-7 迁出至 MessageInjector：ChatServiceSendDiagnosisLock

// ADR-C74 K-7 迁出至 MessageInjector：ChatServiceSendInject

// ADR-C74 K-7 迁出至 MessageInjector：ChatServiceSendObservations

// B5（2026-10-06）：`extension ChatServiceObservers` 已收敛为独立类
// （见 lib/services/chat_service_diagnosis_focus.dart）

// ADR-C74 K-7 迁出至 MessageInjector：_preloadReferenceDetails
// （跟随 _injectReferences 迁入 lib/services/message_injector.dart）
// K-9 移除: _parseAndPersist 已迁 DiagnosisFlowHandler
// K-9 移除: _commitDiagnosisAndSuggestions + _handleTrainingResult 已迁 DiagnosisFlowHandler
/// TH 九批：主对话链路的埋点上下文。
///
/// **刻意不含 sessionId**：传入它需要给 `_streamLlm` 加形参、进而给
/// `_sendMessageCore` 的调用点加一行 —— 而后者 R-019 实测正好 50 行
/// （零余量），加一行即破限。本批立身之本是「不改既有代码」，故不为此
/// 改写既有结构；sessionId 留待经 `SendMessageOptions` 一次性引入。
const _kMainChatCallContext = LlmCallContext(purpose: LlmCallPurpose.mainChat);

extension ChatServiceSendRun on ChatService {
  Future<({String fullContent, bool inDiagnosisBlock})> _streamLlm({
    required List<ChatMessage> messages,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
    // 8. 流式调用 + 拦截诊断块
    String fullContent = '';
    // ★ 两个标志**刻意分离**（ADR-C105 v5 P1-2）：
    //   - `blockIntercepted`：已进入「协议块拦截模式」，从标记处起停止转发（**任何**标记）。
    //   - `inDiagnosisBlock`：本轮**确实发起了诊断**（仅 `[YS_DIAGNOSIS]` / ```diagnosis）。
    //     它下游喂给 `_recordDiagnosisOutcome(attempted:)`，契约（diagnosis_flow_handler
    //     .dart:288-289）明写是「AI 输出含 [YS_DIAGNOSIS] 块」。若被 `[YS_TRAINING]` /
    //     `[YS_OUTLINE]` / `[YS_FACT]` / `[YS_GENUI]` 置位，则纯训练轮会被误记为
    //     「发起诊断却失败」，连续 2 轮即插入「诊断失败卡」（用户可见误报）。
    bool inDiagnosisBlock = false;
    bool blockIntercepted = false;
    int displayLength = 0;
    int streamChunkCount = 0;

    debugPrint('[ChatService] 步骤8: 开始 streamChat 调用...');
    // TH 九批：标注主对话链路（一次性标记，LlmClient 入口即消费）。
    _llmClient.markCallContext(_kMainChatCallContext);
    await _llmClient.streamChat(messages, (response) {
      if (response.isDone) {
        debugPrint('[ChatService] 步骤8: streamChat 收到 [DONE]');
        return;
      }
      if (response.content.isEmpty) return;

      streamChunkCount++;
      fullContent += response.content;
      // 批次6（6.10）：内存上限截断——超限丢弃头部，displayLength 同步左移
      //（已转发内容不受影响，仅服务端解析缓冲降载）
      if (fullContent.length > ChatService._kFullContentMaxLen) {
        final overflow = fullContent.length - ChatService._kFullContentMaxLen;
        fullContent = fullContent.substring(overflow);
        displayLength = (displayLength - overflow).clamp(0, fullContent.length);
        debugPrint(
          '[ChatService] 步骤8: fullContent 超上限截断头部 $overflow 字符（上限 $ChatService._kFullContentMaxLen）',
        );
      }
      if (streamChunkCount <= 3 || streamChunkCount % 10 == 0) {
        debugPrint(
          '[ChatService] 步骤8: chunk#$streamChunkCount | delta="${response.content.length > 30 ? '${response.content.substring(0, 30)}...' : response.content}" | fullLen=${fullContent.length}',
        );
      }

      if (blockIntercepted) return;

      // 拦截诊断块、大纲记忆块（[YS_ENTITY]）、事实块（[YS_FACT]）、
      // GENUI 块（[YS_GENUI]）、训练判定块（[YS_TRAINING]，ADR-C105 A1）：
      // 任一标记出现即从该处起不再转发，避免原始协议 JSON 泄漏到流式展示
      // 批次6（6.3）：O(n²) → O(n)——安全区已转发到 displayLength，标记只可能
      // 出现在末尾 ≤ 最大标记长的窗口内（含跨 chunk 拼接），从窗口起点起搜，
      // 避免每 chunk 对全量 fullContent 做三次 indexOf 扫描。
      final scanStart = displayLength > ChatService._kMaxStreamMarkerLen
          ? displayLength - ChatService._kMaxStreamMarkerLen + 1
          : 0;
      final diagMarkerIndex = fullContent.indexOf(kDiagnosisStart, scanStart);
      final mdDiagMarkerIndex = fullContent.indexOf(
        kMarkdownDiagOpen,
        scanStart,
      );
      final outlineMarkerIndex = fullContent.indexOf(kOutlineStart, scanStart);
      final factMarkerIndex = fullContent.indexOf(kFactStart, scanStart);
      final genuiMarkerIndex = fullContent.indexOf(kGenuiStart, scanStart);
      final trainingMarkerIndex = fullContent.indexOf(
        kTrainingStart,
        scanStart,
      );
      final markerIndex = ChatService._earliestMarkerIndexList([
        diagMarkerIndex,
        mdDiagMarkerIndex,
        outlineMarkerIndex,
        factMarkerIndex,
        genuiMarkerIndex,
        trainingMarkerIndex,
      ]);
      if (markerIndex != -1) {
        final newDisplay = fullContent.substring(displayLength, markerIndex);
        if (newDisplay.isNotEmpty) callbacks.onStream(newDisplay);
        displayLength = markerIndex;
        blockIntercepted = true;
        // 见本函数顶部注释：只有诊断类标记才置 `inDiagnosisBlock`（成败计数用），
        // 其余协议块（大纲 / 事实 / GENUI / 训练）只切拦截模式。
        if (markerIndex == diagMarkerIndex ||
            markerIndex == mdDiagMarkerIndex) {
          inDiagnosisBlock = true;
        }
        debugPrint(
          '[ChatService] 步骤8: 检测到协议块标记，切换到拦截模式 | displayLength=$displayLength | 诊断块=${inDiagnosisBlock ? "是" : "否"}',
        );
        return;
      }

      final pendingLen = ChatService._blockPendingPrefix(fullContent);
      final safeEnd = pendingLen > 0
          ? fullContent.length - pendingLen
          : fullContent.length;
      if (safeEnd > displayLength) {
        final newDisplay = fullContent.substring(displayLength, safeEnd);
        if (newDisplay.isNotEmpty) callbacks.onStream(newDisplay);
        displayLength = safeEnd;
      }
    }, cancelToken: options.cancelToken);
    // ★ ADR-C105 v5（第 2 轮自检 P2-2）：补一次**全文**诊断标记判定。
    // 流式阶段只把「最早出现的标记」与诊断标记比对，而一旦任一标记命中即
    // `blockIntercepted` 短路（`return`）⇒ 若 `[YS_TRAINING]` / `[YS_OUTLINE]` 等
    // **排在诊断块之前**，其后的 `[YS_DIAGNOSIS]` 在整个流里都扫不到 ⇒
    // `inDiagnosisBlock` 漏置位（**假阴性**：真诊断失败不计入，少插失败卡）。
    // 这里在流结束后对完整回复补判一次，使语义与契约（「输出含 [YS_DIAGNOSIS] 块」
    // ⇒ attempted）字面一致；O(n) 一次，与 `parseDiagnosis` 的判定同源。
    if (!inDiagnosisBlock &&
        (fullContent.contains(kDiagnosisStart) ||
            fullContent.contains(kMarkdownDiagOpen))) {
      inDiagnosisBlock = true;
    }
    debugPrint(
      '[ChatService] 步骤8: streamChat 完成 | 总 chunk=$streamChunkCount | fullContent 长度=${fullContent.length} | inDiagnosisBlock=$inDiagnosisBlock',
    );
    // 入档批次：AI 输出轻量校验（空/重复 loop/元文本）——只留痕不截断，
    // 阈值校准后再决定是否干预（写作场景误拦风险高于模型抽风）
    if (fullContent.isNotEmpty) {
      final assessment = assessLlmOutput(fullContent);
      if (assessment.isProblematic) {
        debugPrint(
          '[ChatService] 输出校验命中: ${assessment.detail} | blank=${assessment.isBlank} repeat=${assessment.hasRepetition} meta=${assessment.hasMetaText}',
        );
      }
    }
    return (fullContent: fullContent, inDiagnosisBlock: inDiagnosisBlock);
  }
}

// ignore_for_file: invalid_use_of_protected_member

/// sendMessage 主流程实现（批次96-25 从宿主逐字迁出，行为零变更）。
/// 命名为 _sendMessageCore 以避免遮蔽宿主保留的薄实例方法 sendMessage，
/// 从而维持子类 override / 测试替身（_FakeChatService）的派发语义。
/// teaching state 解析结果（R-019 拆出，供 _sendMessageCore 使用）。
typedef _TeachingContext = ({
  TeachingSubphase? subphase,
  bool isBeginner,
  BeginnerLevel? beginnerLevel,
  TeachingPhase phase,
});

/// 心流窗口判定结果（R-019 拆出）。
typedef _FlowWindow = ({bool flowBypassed, bool rapidFire});

/// 上下文注入装配结果（R-019 拆出，供 _sendMessageCore 使用）。

/// 会话/教学上下文加载结果（R-019 第二层编排拆出）。
typedef _LoadedContext = ({
  List<Message> history,

  /// ADR-C84：本次落库的用户消息 id（立即上屏回调用）
  String userMessageId,
  TeachingSubphase? currentSubphase,
  bool isBeginner,
  BeginnerLevel? beginnerLevel,
  TeachingPhase effectivePhase,
  List<ActiveProblemView> activeProblems,

  /// P2-8：大纲语境（会话引用含 outline 角色文件）——驱动 L2 outline 组加载
  bool isOutlineContext,
});

/// 消息列表 + 注入装配结果（R-019 第二层编排拆出）。
typedef _AssembledContext = ({
  List<ChatMessage> messages,
  ReferenceItem? primaryRef,
  String? chapterContent,
  String? trainingSyndromeId,
  Map<String, List<int>> stageIndexes,
  void Function(String) markStage,
});

/// sendMessageCore 装配完成后的完整发送上下文（R-019 拆出）。
typedef _SendContext = ({
  List<ChatMessage> messages,

  /// ADR-C84：本次落库的用户消息 id（发送后立即上屏用）
  String userMessageId,
  ReferenceItem? primaryRef,
  String? chapterContent,
  String? trainingSyndromeId,
  List<ActiveProblemView> activeProblems,
  TeachingSubphase? currentSubphase,
  bool rapidFire,
  bool flowBypassed,
});

extension ChatServiceSend on ChatService {
  // ★ ADR-0004 步 5 批 1：以下两个 static 常量原位于 D 簇成员区间内，
  //   抽 DiagnosisInjectionService 时被连带删除，此处**逐字恢复原位**。
  //   它们的归属是「协议文本真源」，不属于诊断链的逻辑，故随 extension 保留。

  Future<void> _sendMessageCore(
    String sessionId,
    String content,
    SendMessageCallbacks callbacks,
    SendMessageOptions options, {
    TeachingSubphase? subphase,
  }) async {
    _logSendStart(sessionId, content, options);
    try {
      // 1-7. 用户消息落库 + 上下文装配（R-019 第二层编排拆出）
      final ctx = await _assembleSendContext(
        sessionId,
        content,
        options,
        subphase,
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      // ADR-C84：用户消息落库即通知 UI 上屏（不等 AI 回复）
      await _notifyUserMessagePersisted(ctx, callbacks);
      // ADR-C82：诊断意图 → user 消息侧注入诊断协议 + 请求结构观测
      // （ADR-0004 步 5 批 1：诊断簇已抽出独立类，此处改调服务）
      await _applyDiagnosisInjection(ctx, content, options, sessionId);
      _attachUserAttachments(ctx.messages, options); // C147 图片挂最后 user 消息
      // 8. 流式调用 + 拦截诊断块（R-019：提取为 _streamLlm）
      final streamResult = await _streamLlm(
        messages: ctx.messages,
        callbacks: callbacks,
        options: options,
      );
      final fullContent = streamResult.fullContent;
      final inDiagnosisBlock = streamResult.inDiagnosisBlock;
      // 9-11. 解析 + 提交 + 训练 + onComplete（ADR-C74 K-9 迁至 DiagnosisFlowHandler）
      // （ADR-0004 步 5 批 1：诊断簇已抽出独立类 + R-019 减负，此处改调本文件
      //   的转接 helper `_runDiagnosisFlow`，避免主链被 13 行参数撑过 50 行）
      await _runDiagnosisFlow(
        sessionId: sessionId,
        ctx: ctx,
        content: content,
        fullContent: fullContent,
        inDiagnosisBlock: inDiagnosisBlock,
        callbacks: callbacks,
        options: options,
      );
    } catch (e) {
      _handleSendError(e, callbacks, options);
    }
  }

  /// 9-11 诊断流程转接（ADR-0004 步 5 批 1：R-019 减负，从 `_sendMessageCore`
  /// 抽出）。与 [_applyDiagnosisInjection] 同性质——**纯参数转接**，逻辑在
  /// `DiagnosisInjectionService.runDiagnosisFlow` 内；这里只把 `_SendContext`
  /// 的 6 个字段摊平（该typedef 是本文件私有，独立类看不到）。
  Future<void> _runDiagnosisFlow({
    required String sessionId,
    required _SendContext ctx,
    required String content,
    required String fullContent,
    required bool inDiagnosisBlock,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
    await _diagnosisService.runDiagnosisFlow(
      sessionId: sessionId,
      content: content,
      fullContent: fullContent,
      inDiagnosisBlock: inDiagnosisBlock,
      primaryRef: ctx.primaryRef,
      chapterContent: ctx.chapterContent,
      trainingSyndromeId: ctx.trainingSyndromeId,
      activeProblems: ctx.activeProblems,
      currentSubphase: ctx.currentSubphase,
      rapidFire: ctx.rapidFire,
      flowBypassed: ctx.flowBypassed,
      callbacks: callbacks,
      options: options,
    );
  }

  /// ADR-C82 诊断注入编排（ADR-0004 步 5 批 1：R-019 减负，从 `_sendMessageCore`
  /// 抽出）。诊断簇本身已搬进 [DiagnosisInjectionService]，此处只做**参数转接**：
  /// 把 `_SendContext` 的两个字段（`messages` / `activeProblems`）摊平传入 ——
  /// `_SendContext` 是本文件私有 typedef，独立类看不到它（详见方案 §9）。
  Future<void> _applyDiagnosisInjection(
    _SendContext ctx,
    String content,
    SendMessageOptions options,
    String sessionId,
  ) async {
    await _diagnosisService.applyDiagnosisInjection(
      messages: ctx.messages,
      content: content,
      options: options,
      sessionId: sessionId,
      hasDiagnosisContext: _diagnosisService.hasDiagnosisContext(
        options: options,
        activeProblems: ctx.activeProblems,
      ),
    );
  }

  /// ADR-C84：落库的用户消息回调 UI 上屏（流式中断/失败也保证消息可见）。
  Future<void> _notifyUserMessagePersisted(
    _SendContext ctx,
    SendMessageCallbacks callbacks,
  ) async {
    if (callbacks.onUserMessagePersisted == null) return;
    final userMessage = await _sessionRepo.getMessage(ctx.userMessageId);
    if (userMessage != null) {
      callbacks.onUserMessagePersisted!(userMessage);
    }
  }

  /// 把 SendMessageOptions.attachmentBlocks 合并到最后一条 user 消息的
  /// contentBlocks（text 块保留诊断注入后的正文 + image_url 块）。无附件则零改动。
  void _attachUserAttachments(
    List<ChatMessage> messages,
    SendMessageOptions options,
  ) {
    final blocks = options.attachmentBlocks;
    if (blocks == null || blocks.isEmpty) return;
    final lastUser = messages.lastIndexWhere((m) => m.role == 'user');
    if (lastUser < 0) return;
    final m = messages[lastUser];
    messages[lastUser] = ChatMessage(
      role: m.role,
      content: m.content,
      contentBlocks: [ChatContentBlock.text(m.content), ...blocks],
    );
  }

  /// 读取并解析 teaching state（批次6 M2：DB currentPhase 优先）。
  /// 返回阶段/等级上下文（R-019 拆出）。
  ///
  /// ★ B6-N（2026-10-06）`beginnerLevel` 的来源改为「tier 优先」：
  ///   `teaching_state.beginner_level` 是**冷启动一次性自评**（用户改不了）；
  ///   而成长页/设置页的「你写到哪了？」三档（`DiagnosisPrefs.tier`）此前
  ///   **零消费**——只驱动后缀词。现按「显式选择优先」让 tier 覆盖它，
  ///   接入**已有的**分级诊断库链路（`message_injector` 的层级注入 +
  ///   `focus_resolver` 的 focus 排序），零 schema 改动、零 prompt 正文改动
  ///   ⇒ **不触 R-027**。
  ///   ⚠️ **不写库**：tier 覆盖只在本次调用内存中生效——写
  ///   `teaching_state.beginner_level` 会污染那列「入门自评」的语义
  ///   （它有 CHECK 约束且被冷启动流程当采集目标）。
  ///   详见 `lib/services/diagnosis_tier_bridge.dart` 头注（含与 2026-09-26
  ///   「方案 A」决策的关系：桥接**不生成禁用集**，仍走软引导通道）。
  Future<_TeachingContext> _prepareTeachingState(
    String sessionId,
    TeachingSubphase? fallbackSubphase,
    TeachingPhase fallbackPhase,
  ) async {
    TeachingSubphase? currentSubphase = fallbackSubphase;
    bool isBeginner = false;
    BeginnerLevel? beginnerLevel; // 批次60：技能层级软引导用
    var effectivePhase = fallbackPhase;
    try {
      final ts = await _stateRepo.getTeachingState(sessionId);
      if (ts != null) {
        currentSubphase =
            fallbackSubphase ?? TeachingSubphase.fromString(ts.currentSubphase);
        final level = ts.beginnerLevel;
        // B6-N：tier 覆盖 beginner_level（理由见本函数 doc 注 + bridge 头注）
        final prefs = await _appStateRepo?.getDiagnosisPrefs();
        beginnerLevel = resolveBeginnerLevelFromTier(
          tier: prefs?.tier,
          beginnerLevel: BeginnerLevel.fromString(level),
        );
        // isBeginner 与 beginnerLevel 必须**同源**（同处派生），否则用户选
        // 「想被挑刺」却仍被新手门控 ⇒ 门控与实际层级不一致。
        isBeginner =
            beginnerLevel != null &&
            beginnerLevel != BeginnerLevel.n4Independent &&
            beginnerLevel != BeginnerLevel.n3Diagnose;
        final dbPhase = TeachingPhase.fromString(ts.currentPhase);
        if (dbPhase != null) effectivePhase = dbPhase;
      }
    } catch (e, st) {
      _logSafeRun('getTeachingState+解析失败', e, st);
      currentSubphase = fallbackSubphase;
    }
    return (
      subphase: currentSubphase,
      isBeginner: isBeginner,
      beginnerLevel: beginnerLevel,
      phase: effectivePhase,
    );
  }

  /// 记录「应当桥接」的训练阶段进入时刻（仅观测不阻断，R-019 拆出）。
  void _observeBridgeEntry(
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
  Future<_FlowWindow> _resolveFlowWindow(
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
      lastSendAtSec: _lastUserSendAtSec[sessionId],
      lastEditorEditAtSec: lastEditorEditAtSec,
      nowAtSec: nowAtSec,
      bypassFlowWindow: flowBypassed,
      // 批次6（6.8 M4）：求助关键词（不会/怎么/卡住了/没思路）命中
      // → 绕过心流抑制，主动求助及时反馈
      helpSignal: content,
    );
    return (flowBypassed: flowBypassed, rapidFire: rapidFire);
  }

  /// 区分「用户主动取消」与「真实失败」（取消走 onCancelled，其余走 onError）。
  void _handleSendError(
    Object e,
    SendMessageCallbacks callbacks,
    SendMessageOptions options,
  ) {
    debugPrint('[ChatService] sendMessage 异常: $e');
    final cancelled =
        e is LlmRequestCancelledException ||
        (options.cancelToken?.isCancelled ?? false);
    if (cancelled) {
      callbacks.onCancelled?.call();
    } else {
      callbacks.onError(e is Exception ? e.toString() : '发送失败');
      _logSendFailure(e, options);
    }
  }

  /// ADR-C84 后续：发送失败落库留痕（取消是预期行为不记录）。
  /// captureError 内部自动脱敏（A12：防 API Key 泄漏），
  /// 使「发送/输出失败」可度量、可归类。
  void _logSendFailure(Object e, SendMessageOptions options) {
    final msg = e is Exception ? e.toString() : '发送失败';
    ErrorHandler.instance.captureError(
      level: 'error',
      category: e is DioException ? 'network' : 'api',
      message: 'sendMessage 失败: $msg',
      context: {
        'phase': options.phase.value,
        'attitude': options.attitude.value,
      },
    );
  }

  /// 记录 sendMessage 入口调试信息（R-019 拆出）。
  void _logSendStart(
    String sessionId,
    String content,
    SendMessageOptions options,
  ) {
    debugPrint(
      '[ChatService] sendMessage 开始 | session=$sessionId | contentLen=${content.length} | phase=${options.phase} | attitude=${options.attitude}',
    );
  }

  /// 桥接观测 + Teacher 升级阀/心流窗口判定（R-019 拆出）。
  Future<_FlowWindow> _observeAndResolveFlow(
    String sessionId,
    String content,
    SendMessageOptions options,
    _LoadedContext loaded,
    int nowAtSec,
  ) async {
    _observeBridgeEntry(
      sessionId,
      loaded.currentSubphase,
      loaded.effectivePhase,
      loaded.activeProblems,
    );
    final flow = await _resolveFlowWindow(
      sessionId,
      loaded.activeProblems,
      options.lastEditorEditAtSec,
      nowAtSec,
      content,
    );
    _lastUserSendAtSec[sessionId] = nowAtSec;
    return flow;
  }

  /// 1-7. 用户消息落库 + 上下文装配（R-019 第二层编排 helper）。
  Future<_SendContext> _assembleSendContext(
    String sessionId,
    String content,
    SendMessageOptions options,
    TeachingSubphase? subphase,
    int nowAtSec,
  ) async {
    final loaded = await _loadSessionContext(
      sessionId,
      content,
      options,
      subphase,
      nowAtSec,
    );
    // 桥接观测 + Teacher 升级阀/心流窗口判定
    final flow = await _observeAndResolveFlow(
      sessionId,
      content,
      options,
      loaded,
      nowAtSec,
    );

    // 5-5.2. system prompt + 上下文注入（委托 MessageInjector）
    final assembled = await _assembleMessagesAndInject(
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
  _SendContext _finalizeSendContext(
    _LoadedContext loaded,
    _AssembledContext assembled,
    _FlowWindow flow,
    String sessionId,
    String content,
    SendMessageOptions options,
  ) {
    // 6.5 临场输出约束：在所有教学内容注入后、历史对话前追加（recency bias）
    assembled.messages.add(
      ChatMessage(role: 'system', content: kLiveOutputConstraints),
    );
    // 7. 追加历史消息 + 每轮必变提示 + 纪律重申 + token 预算闸门
    // （ADR-0004 步 5 批 2：改调 prompt 组装服务）
    _promptService.appendHistoryAndConstraints(
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
  Future<_LoadedContext> _loadSessionContext(
    String sessionId,
    String content,
    SendMessageOptions options,
    TeachingSubphase? subphase,
    int nowAtSec,
  ) async {
    // 1. 写入用户消息（批次71：@ 引用快照随 user 消息落库；D2 落库前校验会话）
    final userMessageId = await _writeUserMessage(sessionId, content, options);

    // 2. 获取历史消息（已含 user）
    final rawHistory = await _sessionRepo.listMessages(sessionId);
    // C123：剔除纯新手模式问答（不喂 LLM 诊断上下文；DB 与 UI 仍全量保留）。
    // 咽喉点：loaded.history 同时供 _appendHistory 与 _collectPriorUserTexts
    // 消费，此处一处过滤即切断两条泄漏。
    final history = _excludeNoviceMessages(rawHistory);
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
    final isOutlineContext = await _hasOutlineReference(sessionId);
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
  List<Message> _excludeNoviceMessages(List<Message> history) {
    return history.where((m) => m.messageType != kNoviceMessageType).toList();
  }

  /// 5-5.2. system prompt + 上下文注入装配（R-019 第二层编排 helper）。
  Future<_AssembledContext> _assembleMessagesAndInject({
    required String sessionId,
    required String content,
    required SendMessageOptions options,
    required _LoadedContext loaded,
  }) async {
    // D1/D2 Phase 2：解析当前激活教练人格（用户预设 → 注入其语气；系统预设/null → 原路径）。
    // （ADR-0004 步 5 批 2：以下三处改调prompt 组装服务）
    final activePersona = await _promptService.resolveActivePersona();
    final messages = _promptService.buildSystemPrompt(
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

    final priorUserTexts = _collectPriorUserTexts(loaded);

    final injected = await _promptService.injectContext(
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
  /// loaded.history 在 _writeUserMessage 之后取、已含本轮 user 消息，故倒序取
  /// user 时跳过末条（本轮 content），避免 [content, ...priorUserTexts]
  /// double-count。再反序回填为时间正序。
  List<String> _collectPriorUserTexts(_LoadedContext loaded) {
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
  Future<String> _writeUserMessage(
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
  Future<bool> _hasOutlineReference(String sessionId) async {
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

  /// 预算闸门结果日志 + X-040 PHI 素材缺失提示（R-019 拆出）。
  void _logBudgetOutcome(
    BudgetGuardReport guardReport,
    List<ChatMessage> messages,
  ) {
    if (guardReport.triggered) {
      debugPrint(
        '[ChatService] 预算闸门触发降级: 裁 ${guardReport.droppedMessageCount} 条'
        '（${guardReport.droppedStages.join('、')}）'
        ' | ${guardReport.totalBefore}→${guardReport.totalAfter} tokens',
      );
    } else if (guardReport.overWarning) {
      debugPrint(
        '[ChatService] 预算超警告线未裁剪: ~${guardReport.totalBefore}'
        ' > ${(TokenEstimate.maxBudget * TokenEstimate.warningRatio).round()}',
      );
    }
    // C17：release 下 debugPrint 不可见 ⇒ 旁路落 error_logs，事后可查「本轮
    // 是否触发降级、裁了哪几段」。只放 stage 名/token 数，绝不放 prompt 正文。
    if (guardReport.triggered || guardReport.overWarning) {
      recordBudgetOutcomeLog(guardReport);
    }
    if (guardReport.dropped) {
      // S1（R2）：素材/观察段缺失提示生成迁入 StageDropNotice（ADR-C74
      // 三步法，chat_service 零净增）。X-040 素材文案逐字不变（回归测试
      // 冻结）；ruleDetectors 为新增的知情截断提示（Q0 裁定）。
      final notice = StageDropNotice.build(
        guardReport.droppedStages,
        countByStage: guardReport.droppedCountByStage,
      );
      if (notice != null) {
        messages.add(ChatMessage(role: 'system', content: notice));
      }
    }
  }

  /// SafeRun 降级统一留痕（CR-53）。
  ///
  /// 本类的失败路径一律「不阻断主流程」——异常已被 catch 处理、不会上抛，
  /// 按 V1.4 P0-2 处置判据缺的是**留痕**不是捕获。此前只有 debugPrint，
  /// 而 release 构建不输出 → 生产环境这些降级全程静默、无法归因。
  /// 保留 debugPrint（开发期即时可见）+ captureError 落 error_logs。
  /// 同模式实现见 diagnosis_committer.dart:142 / diagnosis_flow_handler.dart:198 /
  /// message_injector.dart:1487 —— 4 份分散实现本批先不抽公用 helper，逐文件独立维护。
  void _logSafeRun(String stage, Object e, StackTrace s) {
    debugPrint('[SafeRun] $stage: $e');
    ErrorHandler.instance.captureError(
      level: 'error',
      category: 'database',
      message: '[SafeRun] $stage: $e',
      stack: s.toString(),
    );
  }
}

/// C17：预算降级 / 超警告线的旁路留痕（可单测接缝）。
///
/// release 下 debugPrint 无效 ⇒ 仅 debugPrint 会让「本轮是否触发降级、裁了哪
/// 几段」在发布版完全不可观测。这里旁路写一条 info/api 行，`event='llm_budget'`
/// （查询侧据 C14 三态分派把它从调用统计里排除）。只放 stage 名 / token 数，
/// **绝不放 prompt 正文**（R-029）；captureError 自身做 A12 脱敏。
@visibleForTesting
void recordBudgetOutcomeLog(BudgetGuardReport r) {
  ErrorHandler.instance.captureError(
    level: 'info',
    category: 'api',
    message: '[budget] triggered=${r.triggered} overWarning=${r.overWarning}',
    context: <String, dynamic>{
      'event': 'llm_budget',
      'triggered': r.triggered,
      'overWarning': r.overWarning,
      'totalBefore': r.totalBefore,
      'totalAfter': r.totalAfter,
      'droppedStages': r.droppedStages,
      'droppedMessageCount': r.droppedMessageCount,
    },
  );
}
