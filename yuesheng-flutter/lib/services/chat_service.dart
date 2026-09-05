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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/config/token_budget_table.dart';
import 'package:writingcoach/contracts/reference_capability.dart';
import 'package:writingcoach/services/token_budget_guard.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/editor_observation_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/training_result_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_message_types.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/outline_parser.dart';
import 'package:writingcoach/services/fact_parser.dart';
import 'package:writingcoach/services/genui_parser.dart';
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_flow_handler.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_service.dart';
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/chat_gates.dart';
import 'package:writingcoach/services/intent_classifier.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 批次64（B62f）诊断请求标记（ADR-C74 K-7 迁至 MessageInjector：
/// lib/services/message_injector.dart._kDiagnosisRequestMarker）

/// ChatService 依赖：所有 Repository + LlmClient
class ChatService {
  final SessionRepository _sessionRepo;
  final TeachingStateRepository _stateRepo;
  final DiagnosisRepository _diagnosisRepo;
  final StudentModelRepository _studentModelRepo;
  final ReferenceCapability _referenceRepo;
  final ChapterRepository _chapterRepo;
  final ManuscriptRepository _manuscriptRepo;
  final LlmClient _llmClient;
  final DiagnosisService _diagnosisService;
  final TeacherSuggestionRepository _teacherSuggestionRepo;

  /// X-041c：训练结果持久化仓储（可选——不装配则跳过 training_results 落库）
  /// 真源：PracticeStore.trainingResult 仅存内存态；装配后训练轮反馈命中时
  /// 同步写入 training_results 表，补全 GrowthStore.trainingStats 数据源。
  /// 设计为可选参数：避免破坏 30+ 处现有测试构造（默认 null 跳过回写）。
  final TrainingResultRepository? _trainingResultRepo;

  // ─── 四大纯能力（选项 B 依赖倒置：经 capability provider 注入，默认 const impl） ───
  // 阶段 1：消费层从顶层纯函数迁移到能力方法；impl 为纯委托，行为零变更。
  // 生产侧经 chatServiceProvider 读 capability provider 注入；测试替身
  // （_FakeChatService）override sendMessage 整体、不触达本字段，默认值无害。
  final GenUiCapability _genUi;
  final MaterialCapability _material;
  final TeachingCapability _teaching;
  final DiagnosisCapability _diagnosis;

  /// 批次66（B62i）：人物知识仓储（可选——不装配则跳过时序矛盾观察）
  final CharacterFactRepository? _characterFactRepo;

  /// 批次67（B62j）：事件知识仓储（可选——不装配则跳过 F07 因果链观察）
  final EventFactRepository? _eventFactRepo;

  /// 批次67（B62j）：支线知识仓储（可选——不装配则跳过 F11 情节闭环观察）
  final SubplotFactRepository? _subplotFactRepo;

  /// 批次72（大纲层）：大纲仓储（可选——装配后实体索引注入 + 提取落库才可用）
  /// K-9 起 outlineRepo 由 DiagnosisFlowHandler / MessageInjector 各自持有，
  /// ChatService 不再直接消费；保留构造参数以兼容既有测试 fixture（无副作用）。
  final OutlineRepository? _outlineRepo;

  /// 诊断提交编排器（ADR-C74 K-1 骨架）
  ///
  /// K-1 阶段：nullable + ChatService 不消费，仅证明「独立类 + DI」路径
  /// 可行（X-025-ARCH 教训复盘）。K-2 ~ K-5 阶段随方法迁入时逐步收紧为
  /// non-null + required；K-5 收尾时本字段升级。
  final DiagnosisCommitter _diagnosisCommitter;

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
  /// 由 WritingCoachPanel 调用（lib/widgets/chat_teaching.dart L53）。
  /// 实现已迁 DiagnosisFlowHandler；本方法保留同名同参同返回以保证
  /// 调用方零改动（K-5 同款薄壳委派）。
  Future<String> commitDiagnosisFromContent({
    required String sessionId,
    required String fullContent,
  }) async {
    return _diagnosisFlowHandler.commitDiagnosisFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );
  }

  ChatService({
    required SessionRepository sessionRepo,
    required TeachingStateRepository stateRepo,
    required DiagnosisRepository diagnosisRepo,
    required StudentModelRepository studentModelRepo,
    required ReferenceCapability referenceRepo,
    required ChapterRepository chapterRepo,
    required ManuscriptRepository manuscriptRepo,
    required LlmClient llmClient,
    required TeacherSuggestionRepository teacherSuggestionRepo,
    required EditorObservationRepository editorObservationRepo,
    // X-041c：可选装配，不传则跳过 training_results 落库（不破坏现有测试构造）
    TrainingResultRepository? trainingResultRepo,
    GenUiCapability genUi = const GenUiParser(),
    MaterialCapability material = const MaterialCapabilityImpl(),
    TeachingCapability teaching = const TeachingCapabilityImpl(),
    DiagnosisCapability diagnosis = const DiagnosisCapabilityImpl(),
    CharacterFactRepository? characterFactRepo,
    EventFactRepository? eventFactRepo,
    SubplotFactRepository? subplotFactRepo,
    OutlineRepository? outlineRepo,
    // ADR-C74 K-1：诊断提交编排器，K-1 阶段 nullable（不破坏现有 30+ 测试构造）
    required DiagnosisCommitter diagnosisCommitter,
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
       _studentModelRepo = studentModelRepo,
       _referenceRepo = referenceRepo,
       _chapterRepo = chapterRepo,
       _manuscriptRepo = manuscriptRepo,
       _llmClient = llmClient,
       _diagnosisService = DiagnosisService(
         diagnosisRepo: diagnosisRepo,
         studentModelRepo: studentModelRepo,
       ),
       _teacherSuggestionRepo = teacherSuggestionRepo,
       _trainingResultRepo = trainingResultRepo,
       _genUi = genUi,
       _material = material,
       _teaching = teaching,
       _diagnosis = diagnosis,
       _characterFactRepo = characterFactRepo,
       _eventFactRepo = eventFactRepo,
       _subplotFactRepo = subplotFactRepo,
       _outlineRepo = outlineRepo,
       _diagnosisCommitter = diagnosisCommitter,
       _messageInjector = messageInjector,
       _diagnosisFlowHandler = diagnosisFlowHandler;

  // 引用内容预加载缓存（ADR-C74 K-7 迁至 MessageInjector：见 lib/services/message_injector.dart）

  // 批次59：心流判定——记录每个 session 最近一次用户消息发送时间（秒级）
  final Map<String, int> _lastUserSendAtSec = {};

  // 批次63（B62b）意图向量缓存（ADR-C74 K-7 随 _injectProfileAndIntents 迁至 MessageInjector）

  // ════════════ 会话/态度管理 ════════════

  /// 取或建默认会话（优先复用最近会话）
  Future<String> initSession() async {
    final sessions = await _sessionRepo.listSessions();
    if (sessions.isNotEmpty) return sessions.first.id;
    return _sessionRepo.createBlankSession();
  }

  /// 加载会话的态度状态
  Future<({AttitudeLevel attitude, TeachingPhase phase})> loadAttitudeState(
    String sessionId,
  ) async {
    final ts = await _stateRepo.getTeachingState(sessionId);
    return (
      attitude:
          AttitudeLevel.fromString(ts?.attitudeLevel) ?? AttitudeLevel.doubao,
      phase:
          TeachingPhase.fromString(ts?.currentPhase) ?? TeachingPhase.p0Engage,
    );
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

  /// 批次6（6.3）：流式拦截标记最大长度
  ///（kDiagnosisStart='[YS_DIAGNOSIS]'=14 / kOutlineStart='[YS_ENTITY]'=11 /
  ///  kFactStart='[YS_FACT]'=9）——标记只可能出现在末尾 ≤ 此长度的窗口内
  static const int _kMaxStreamMarkerLen = 14;

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

  /// 检查 fullContent 尾部是否命中任一协议块标记（[YS_DIAGNOSIS]/[YS_ENTITY]/[YS_FACT]/[YS_GENUI]）的
  /// 某个前缀，返回需暂缓转发的后缀长度（防分隔符跨 chunk 到达时误转发）
  static int _blockPendingPrefix(String fullContent) {
    final diag = getPendingMarkerPrefix(fullContent);
    final outline = _pendingPrefix(fullContent, kOutlineStart);
    final fact = _pendingPrefix(fullContent, kFactStart);
    final genui = _pendingPrefix(fullContent, kGenuiStart);
    return [diag, outline, fact, genui].reduce((a, b) => a > b ? a : b);
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

  /// 设置子阶段
  Future<void> setSubphase(String sessionId, TeachingSubphase? subphase) async {
    await _stateRepo.updateSubphase(sessionId, subphase?.value);
  }

  // ════════════ D8 评估顺序轻量观测 ════════════

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
extension ChatServiceDiagnosisFocus on ChatService {
  /// 批次1（O1）：Teacher 升级阀——某症候严重度达阈值或诊断次数达阈值时，
  /// 绕过心流窗口（持续写作学员「编辑器活跃 120s」恒真 → 建议永远出不来 →
  /// identified 永不前进 → M4-A 永不满足）。返回 true 时允许建议正常输出。
  Future<bool> _shouldBypassFlowWindow(
    String sessionId,
    List<ActiveProblemView> activeProblems,
  ) async {
    if (activeProblems.isEmpty) return false;
    // 严重度阈值：存在 L3 重度症候即绕过
    if (activeProblems.any((p) {
      final sev = Severity.fromString(p.severity);
      return sev != null && sev.index >= kFlowBypassMinSeverity.index;
    })) {
      return true;
    }
    // 诊断次数阈值：某症候累计诊断次数达阈值即绕过（统计失败降级为不绕过）
    try {
      final history = await _studentModelRepo.getTeachingHistory(sessionId);
      for (final p in activeProblems) {
        final diagnosisCount = history.where((r) {
          if (r['type'] != 'diagnosis') return false;
          final syndromes = r['syndromes'];
          return syndromes is List && syndromes.contains(p.syndromeId);
        }).length;
        if (diagnosisCount >= kFlowBypassDiagnosisCount) return true;
      }
    } catch (e) {
      debugPrint('[SafeRun] 升级阀诊断次数统计失败，降级为不绕过: $e');
    }
    return false;
  }

  // ADR-C74 K-7 迁出至 MessageInjector（lib/services/message_injector.dart）：
  // _parseUserFocusFromMessage / _buildFocusHistory / _mapFocusSource
  // （_injectDiagnosisLock 的跟随 helper）
}

// ADR-C74 K-7 迁出至 MessageInjector：extension ChatServiceDiagnosisSupport
// 整块删除（仅含 _buildInterventionAdjustmentNote，迁入 MessageInjector._buildInterventionAdjustmentNote）

// ADR-C74 K-7 迁出至 MessageInjector：ChatServiceSendDiagnosisLock

// ADR-C74 K-7 迁出至 MessageInjector：ChatServiceSendInject

// ADR-C74 K-7 迁出至 MessageInjector：ChatServiceSendObservations

extension ChatServiceObservers on ChatService {
  /// D8 轻量观测：评估顺序（学员自评 → 改前改后对比 → AI 评估）
  /// 约束源为 skill 指令（skill_registry.dart 阶段3 三步评估流程），非代码强制；
  /// 此处仅 debug 级留痕「FEEDBACK 回复是否按顺序走全三步」，不改变任何行为。
  /// 检测标记：自评引导（"你自己觉得改得怎么样"类）→ 改前改后对比（唯一不可省略）
  /// → 评估三档（含"达标"字样）。观测失败不阻断主流程。
  /// ADR-C74 K-9：随 _handleTrainingResult 迁至 DiagnosisFlowHandler（仅内部消费者），
  /// 此处删除 23 行死代码（保持 R-019 baseline 不新增）。
  // ignore: unused_element  K-9 死代码占位，行为零变更
  void _observeEvaluationOrder(String reply) {
    if (!kDebugMode) return;
    final hasSelfEval = RegExp(r'你自己(觉得|认为)|你觉得(自己|刚才)?改得').hasMatch(reply);
    final hasContrast = RegExp(
      r'改(之前|以前|前).{0,60}(改(之后|以后|后)|现在.{0,20}(是|变成))',
    ).hasMatch(reply);
    final hasAssessment = reply.contains('达标');
    debugPrint(
      '[D8 评估顺序观测] 自评引导=$hasSelfEval 改前改后对比=$hasContrast '
      '评估三档=$hasAssessment（仅观测不干预）',
    );
  }

  /// 批次50 临时测量：回复长度观测（standard 档是否真超长）
  /// 「回复颗粒度真人感收敛」决策前置——先量化标准档回复长度分布再决定约束方案。
  /// 仅 debug 级留痕（长度 + 分档 + 颗粒度 + 态度 + 子阶段 + 意图），不改变任何行为；
  /// 批次 52 汇成节奏体检报告后按结论决定保留或删除。观测失败不阻断主流程。
  void _observeReplyLength(
    String reply,
    String userInput,
    AttitudeLevel attitude,
    TeachingSubphase? subphase,
  ) {
    if (!kDebugMode) return;
    final len = reply.length;
    String bucket;
    if (len <= 30) {
      bucket = '≤30(一句)';
    } else if (len <= 80) {
      bucket = '31-80(短段)';
    } else if (len <= 160) {
      bucket = '81-160(中段)';
    } else {
      bucket = '>160(长段)';
    }
    final detail = detectReplyDetail(userInput);
    final intent = classifyUserIntent(userInput);
    debugPrint(
      '[批次50 回复长度观测] 长度=$len($bucket) 颗粒度=${detail.value} '
      '态度=${attitude.value} 子阶段=${subphase?.value ?? 'null'} '
      '意图=${intent.value}（仅观测不干预）',
    );
  }
}

// ADR-C74 K-7 迁出至 MessageInjector：_preloadReferenceDetails
// （跟随 _injectReferences 迁入 lib/services/message_injector.dart）
// K-9 移除: _parseAndPersist 已迁 DiagnosisFlowHandler
// K-9 移除: _commitDiagnosisAndSuggestions + _handleTrainingResult 已迁 DiagnosisFlowHandler
extension ChatServiceSendRun on ChatService {
  Future<({String fullContent, bool inDiagnosisBlock})> _streamLlm({
    required List<ChatMessage> messages,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
    // 8. 流式调用 + 拦截诊断块
    String fullContent = '';
    bool inDiagnosisBlock = false;
    int displayLength = 0;
    int streamChunkCount = 0;

    debugPrint('[ChatService] 步骤8: 开始 streamChat 调用...');
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

      if (inDiagnosisBlock) return;

      // 拦截诊断块、大纲记忆块（[YS_ENTITY]）、事实块（[YS_FACT]）：
      // 任一标记出现即从该处起不再转发，避免原始协议 JSON 泄漏到流式展示
      // 批次6（6.3）：O(n²) → O(n)——安全区已转发到 displayLength，标记只可能
      // 出现在末尾 ≤ 最大标记长的窗口内（含跨 chunk 拼接），从窗口起点起搜，
      // 避免每 chunk 对全量 fullContent 做三次 indexOf 扫描。
      final scanStart = displayLength > ChatService._kMaxStreamMarkerLen
          ? displayLength - ChatService._kMaxStreamMarkerLen + 1
          : 0;
      final diagMarkerIndex = fullContent.indexOf(kDiagnosisStart, scanStart);
      final outlineMarkerIndex = fullContent.indexOf(kOutlineStart, scanStart);
      final factMarkerIndex = fullContent.indexOf(kFactStart, scanStart);
      final genuiMarkerIndex = fullContent.indexOf(kGenuiStart, scanStart);
      final markerIndex = ChatService._earliestMarkerIndex(
        ChatService._earliestMarkerIndex(
          ChatService._earliestMarkerIndex(diagMarkerIndex, outlineMarkerIndex),
          factMarkerIndex,
        ),
        genuiMarkerIndex,
      );
      if (markerIndex != -1) {
        final newDisplay = fullContent.substring(displayLength, markerIndex);
        if (newDisplay.isNotEmpty) callbacks.onStream(newDisplay);
        displayLength = markerIndex;
        inDiagnosisBlock = true;
        debugPrint(
          '[ChatService] 步骤8: 检测到协议块标记，切换到拦截模式 | displayLength=$displayLength',
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
    debugPrint(
      '[ChatService] 步骤8: streamChat 完成 | 总 chunk=$streamChunkCount | fullContent 长度=${fullContent.length} | inDiagnosisBlock=$inDiagnosisBlock',
    );
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
typedef _InjectedContext = ({
  ReferenceItem? primaryRef,
  String? chapterContent,
  String? trainingSyndromeId,
});

/// 会话/教学上下文加载结果（R-019 第二层编排拆出）。
typedef _LoadedContext = ({
  List<Message> history,
  TeachingSubphase? currentSubphase,
  bool isBeginner,
  BeginnerLevel? beginnerLevel,
  TeachingPhase effectivePhase,
  List<ActiveProblemView> activeProblems,
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
  ReferenceItem? primaryRef,
  String? chapterContent,
  String? trainingSyndromeId,
  List<ActiveProblemView> activeProblems,
  TeachingSubphase? currentSubphase,
  bool rapidFire,
  bool flowBypassed,
});

extension ChatServiceSend on ChatService {
  Future<void> _sendMessageCore(
    String sessionId,
    String content,
    SendMessageCallbacks callbacks,
    SendMessageOptions options, {
    TeachingSubphase? subphase,
  }) async {
    _logSendStart(sessionId, content, options);
    final nowAtSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      // 1-7. 用户消息落库 + 上下文装配（R-019 第二层编排拆出）
      final ctx = await _assembleSendContext(
        sessionId,
        content,
        options,
        subphase,
        nowAtSec,
      );
      // 8. 流式调用 + 拦截诊断块（R-019：提取为 _streamLlm）
      final streamResult = await _streamLlm(
        messages: ctx.messages,
        callbacks: callbacks,
        options: options,
      );
      final fullContent = streamResult.fullContent;
      final inDiagnosisBlock = streamResult.inDiagnosisBlock;

      // 9-11. 解析 + 提交 + 训练 + onComplete（ADR-C74 K-9 迁至 DiagnosisFlowHandler）
      await _runDiagnosisFlow(
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
    } catch (e) {
      _handleSendError(e, callbacks, options);
    }
  }

  /// 读取并解析 teaching state（批次6 M2：DB currentPhase 优先）。
  /// 返回阶段/等级上下文（R-019 拆出）。
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
        beginnerLevel = BeginnerLevel.fromString(level);
        isBeginner =
            level != null &&
            level != BeginnerLevel.n4Independent.value &&
            level != BeginnerLevel.n3Diagnose.value;
        final dbPhase = TeachingPhase.fromString(ts.currentPhase);
        if (dbPhase != null) effectivePhase = dbPhase;
      }
    } catch (e) {
      debugPrint('[SafeRun] getTeachingState+解析失败: $e');
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
    final flowBypassed = await _shouldBypassFlowWindow(
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

  /// FT-22：检测「只诊断不要建议」边界声明（R-019 拆出）。
  bool _resolveDiagnosisOnly(String content) {
    final diagnosisOnly = isDiagnosisOnlyRequest(content);
    if (diagnosisOnly) {
      debugPrint('[ChatService] FT-22: 检测到「只诊断」边界声明，跳过 teacher 建议');
    }
    return diagnosisOnly;
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
    }
  }

  /// 记录 sendMessage 入口调试信息（R-019 拆出）。
  void _logSendStart(
    String sessionId,
    String content,
    SendMessageOptions options,
  ) {
    debugPrint(
      '[ChatService] sendMessage 开始 | session=$sessionId | content="${content.length > 50 ? '${content.substring(0, 50)}...' : content}" | phase=${options.phase} | attitude=${options.attitude}',
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
    return _finalizeSendContext(loaded, assembled, flow);
  }

  /// 6.5-7. 临场约束 + 历史/纪律/预算 + 返回装配（R-019 拆出）。
  _SendContext _finalizeSendContext(
    _LoadedContext loaded,
    _AssembledContext assembled,
    _FlowWindow flow,
  ) {
    // 6.5 临场输出约束：在所有教学内容注入后、历史对话前追加（recency bias）
    assembled.messages.add(
      ChatMessage(role: 'system', content: kLiveOutputConstraints),
    );
    // 7. 追加历史消息 + 纪律重申 + token 预算闸门
    _appendHistoryAndConstraints(
      loaded.history,
      assembled.messages,
      assembled.markStage,
      assembled.stageIndexes,
    );
    debugPrint(
      '[ChatService] 步骤7: 发送到 LLM 的 messages 数量=${assembled.messages.length}（含 system + history）',
    );
    return (
      messages: assembled.messages,
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
    // 1. 写入用户消息（批次71：@ 引用快照随 user 消息落库）
    await _sessionRepo.addMessage(
      sessionId,
      'user',
      content,
      referencesJson: options.referencesJson,
    );
    debugPrint('[ChatService] 步骤1: user 消息已写入');

    // 2. 获取历史消息（已含 user）
    final history = await _sessionRepo.listMessages(sessionId);
    debugPrint('[ChatService] 步骤2: 历史消息 ${history.length} 条');

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
    return (
      history: history,
      currentSubphase: currentSubphase,
      isBeginner: isBeginner,
      beginnerLevel: beginnerLevel,
      effectivePhase: effectivePhase,
      activeProblems: activeProblems,
    );
  }

  /// 5-5.2. system prompt + 上下文注入装配（R-019 第二层编排 helper）。
  Future<_AssembledContext> _assembleMessagesAndInject({
    required String sessionId,
    required String content,
    required SendMessageOptions options,
    required _LoadedContext loaded,
  }) async {
    final messages = _buildSystemPrompt(
      loaded.effectivePhase,
      options.attitude,
      loaded.currentSubphase,
      loaded.isBeginner,
    );
    // 可降级阶段 → 消息索引（运行时 token 预算闸门裁剪依据）
    final stageIndexes = <String, List<int>>{};
    void markStage(String stage) {
      (stageIndexes[stage] ??= []).add(messages.length);
    }

    final injected = await _injectContext(
      sessionId: sessionId,
      content: content,
      messages: messages,
      markStage: markStage,
      activeProblems: loaded.activeProblems,
      currentSubphase: loaded.currentSubphase,
      beginnerLevel: loaded.beginnerLevel,
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

  /// 拼接 system prompt（L1 + L2，R-019 拆出）。
  List<ChatMessage> _buildSystemPrompt(
    TeachingPhase phase,
    AttitudeLevel attitude,
    TeachingSubphase? subphase,
    bool isBeginner,
  ) {
    final skillCtx = SkillLoadContext(
      phase: phase,
      attitude: attitude,
      subphase: subphase,
      isBeginner: isBeginner,
    );
    final promptResult = _teaching.buildSystemPrompt(skillCtx);
    return <ChatMessage>[
      ChatMessage(role: 'system', content: promptResult.systemPrompt),
    ];
  }

  /// 5.0-5.2 上下文注入装配（R-019 拆出，委托 MessageInjector）。
  Future<_InjectedContext> _injectContext({
    required String sessionId,
    required String content,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required BeginnerLevel? beginnerLevel,
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
    );
    await _messageInjector.injectOutlineFactsAndFiles(
      content: content,
      primaryRef: primaryRef,
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
      primaryRef: primaryRef,
      chapterContent: chapterContent,
      trainingSyndromeId: trainingSyndromeId,
    );
  }

  /// 7. 追加历史消息 + 纪律重申 + token 预算闸门（R-019 编排 helper）。
  void _appendHistoryAndConstraints(
    List<Message> history,
    List<ChatMessage> messages,
    void Function(String) markStage,
    Map<String, List<int>> stageIndexes,
  ) {
    _appendHistory(history, messages, markStage);
    _appendDisciplineReminder(messages);
    _logBudgetOutcome(
      TokenBudgetGuard.apply(messages, stageIndexes: stageIndexes),
      messages,
    );
  }

  /// 追加历史消息（R-019 拆出）。
  void _appendHistory(
    List<Message> history,
    List<ChatMessage> messages,
    void Function(String) markStage,
  ) {
    for (final m in history) {
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
            '3. 示范按当前态度档位执行：doubao/yuesheng 最小示范，sensei 零示范只给方向；\n'
            '4. 诊断结论必须基于用户实际文本，不假定被预算闸门裁掉的素材内容；\n'
            '5. 回复去 AI 味，不用"让我来帮你"等套话；\n'
            '6. 诊断块用 ```diagnosis``` 包裹，卡片块用对应标签，不裸露 JSON。',
      ),
    );
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
    if (guardReport.dropped) {
      final materialStages = guardReport.droppedStages
          .where(
            (s) =>
                s == BudgetStageNames.references ||
                s == BudgetStageNames.attachedFiles ||
                s == BudgetStageNames.fact,
          )
          .toList();
      if (materialStages.isNotEmpty) {
        messages.add(
          ChatMessage(
            role: 'system',
            content:
                '# 素材缺失提示（X-040 PHI）\n\n'
                '由于本轮 token 预算超限，已裁掉以下用户素材：${materialStages.join('、')}。\n'
                '回复时：\n'
                '1. 不得假定素材内容直接给出诊断结论；\n'
                '2. 若回复需这些内容支撑，明确告知用户需重新提供或简化提供；\n'
                '3. 可基于现有上下文（活跃症候 + 历史对话）做方向性引导。',
          ),
        );
      }
    }
  }

  /// FT-22 边界检测 + 诊断解析落库（R-019 拆出）。
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
    final diagnosisOnly = _resolveDiagnosisOnly(content);
    return _diagnosisFlowHandler.parseAndPersist(
      sessionId: sessionId,
      fullContent: fullContent,
      inDiagnosisBlock: inDiagnosisBlock,
      primaryRef: primaryRef,
      chapterContent: chapterContent,
      callbacks: callbacks,
      options: options,
      diagnosisOnly: diagnosisOnly,
    );
  }

  /// 9-11 诊断解析 + 提交 + 训练 + onComplete（ADR-C74 K-9，R-019 收尾 helper）。
  Future<void> _runDiagnosisFlow({
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

  /// 诊断提交 + Teacher suggestion + GenUI 卡片 + 回复长度观测（R-019 拆出）。
  Future<void> _commitDiagnosisAndSuggestions({
    required String sessionId,
    required String content,
    required dynamic parsed,
    required ReferenceItem? primaryRef,
    required bool rapidFire,
    required bool flowBypassed,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
    required TeachingSubphase? currentSubphase,
  }) async {
    await _diagnosisFlowHandler.commitDiagnosisAndSuggestions(
      sessionId: sessionId,
      diagnosis: parsed.diagnosis,
      messageId: parsed.messageId,
      primaryRef: primaryRef,
      teacherResult: parsed.teacherResult,
      rapidFire: rapidFire,
      flowBypassed: flowBypassed,
      genuiComponents: parsed.genuiComponents,
    );
    // 批次50 临时测量：回复长度观测（仅 debug 留痕不干预）
    _observeReplyLength(
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
    required dynamic parsed,
    required String? trainingSyndromeId,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
    await _diagnosisFlowHandler.handleTrainingResult(
      sessionId: sessionId,
      currentSubphase: currentSubphase,
      displayContent: parsed.displayContent,
      userContent: content,
      trainingSyndromeId: trainingSyndromeId,
      activeProblems: activeProblems,
      callbacks: callbacks,
    );
    await callbacks.onComplete(parsed.finalContent, parsed.messageId);
    debugPrint('[ChatService] sendMessage 完成 | onComplete 已触发');
  }
}
