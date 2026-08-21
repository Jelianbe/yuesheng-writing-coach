// ─────────────────────────────────────────────────────────────
// ChatService — 主编排器
// 复刻 yuesheng-android/src/services/chat-service.ts 的 sendMessage 主链路
//
// 简化范围（"先主路核心"原则）：
//   - Reviewer 门控 / Editor / Teacher 分支已实现（批次 1-7 补齐，
//     见步骤 5.1.1 Reviewer 门控 + chat_gates.dart 触发与持久化）
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

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
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
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart';
import 'package:writingcoach/services/reply_receipt_guard.dart';
import 'package:writingcoach/services/conflict_detector.dart';
import 'package:writingcoach/services/dialogue_tag_detector.dart';
import 'package:writingcoach/services/event_causality_detector.dart';
import 'package:writingcoach/services/grammar_lexical_detector.dart';
import 'package:writingcoach/services/outline_parser.dart';
import 'package:writingcoach/services/outline_service.dart';
import 'package:writingcoach/services/fact_parser.dart';
import 'package:writingcoach/services/genui_parser.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_service.dart';
import 'package:writingcoach/services/evaluation_service.dart'
    show EvaluationService, EvaluationPassRateExtension;
import 'package:writingcoach/services/focus_resolver.dart' as focus;
import 'package:writingcoach/services/style_technique_router.dart';
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/services/phase_mapper_resolver.dart';
import 'package:writingcoach/services/phase_transition.dart';
import 'package:writingcoach/services/skill_dispatcher.dart';
import 'package:writingcoach/services/skill_layers.dart';
import 'package:writingcoach/services/student_profile.dart';
import 'package:writingcoach/services/training_evaluator.dart';
import 'package:writingcoach/services/training_input_builder.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/services/chat_gates.dart';
import 'package:writingcoach/services/intent_classifier.dart';
import 'package:writingcoach/services/style_fingerprint.dart';
import 'package:writingcoach/services/editor_service.dart';
import 'package:writingcoach/services/reviewer_service.dart';
import 'package:writingcoach/services/reviewer_validator.dart';
import 'package:writingcoach/services/teacher_service.dart';
import 'package:writingcoach/services/teacher_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';
part 'chat_service_diagnosis.dart';
part 'chat_service_diagnosis_apply.dart';
part 'chat_service_diagnosis_focus.dart';
part 'chat_service_diagnosis_support.dart';
part 'chat_service_send_diagnosis_lock.dart';
part 'chat_service_send_inject.dart';
part 'chat_service_send_observations.dart';
part 'chat_service_observers.dart';
part 'chat_service_send_parse.dart';
part 'chat_service_send_persist.dart';
part 'chat_service_send_run.dart';
part 'chat_service_send.dart';

/// 批次64（B62f）：诊断请求标记——章节诊断 prompt 的特征子串，
/// 用于判定"本次消息是对章节正文的诊断请求"，才触发声线漂移检测。
const String _kDiagnosisRequestMarker = '写作诊断分析';

/// 流式回调
class SendMessageCallbacks {
  final void Function(String delta) onStream;
  final FutureOr<void> Function(String fullContent, String messageId)
  onComplete;
  final void Function(String error) onError;

  /// 训练结果回调（subphase==FEEDBACK 且 parseTrainingResult 命中时触发）
  final void Function(TrainingResult result)? onTrainingResult;

  /// 用户主动取消时触发（区别于 onError：取消是预期行为，不应标记消息失败）
  final void Function()? onCancelled;

  const SendMessageCallbacks({
    required this.onStream,
    required this.onComplete,
    required this.onError,
    this.onTrainingResult,
    this.onCancelled,
  });
}

/// 发送消息选项
class SendMessageOptions {
  final TeachingPhase phase;
  final AttitudeLevel attitude;
  final CancelToken? cancelToken;

  /// 批次64（B62g）：编辑器最近一次编辑时间（秒）。写作页传入，
  /// 心流判定叠加"编辑器活跃"；对话页不传（null）仅用消息频率判定。
  final int? lastEditorEditAtSec;

  /// 批次71：本消息携带的 @ 引用快照（JSON 数组字符串）。
  /// 随 user 消息落库，气泡底部展示引用徽章。
  final String? referencesJson;

  const SendMessageOptions({
    required this.phase,
    required this.attitude,
    this.cancelToken,
    this.lastEditorEditAtSec,
    this.referencesJson,
  });
}

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
  final EditorObservationRepository _editorObservationRepo;

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
  /// 批次7 O2：保留仓储引用，服务改为首次使用时懒加载（_ensureOutlineService），
  /// 解耦 eager 构造，避免「装配依赖」成为静默条件——只要装配了 repo 服务必然可用。
  final OutlineRepository? _outlineRepo;

  /// 懒加载缓存：_ensureOutlineService 首次调用时由 _outlineRepo 构建
  OutlineService? _outlineService;

  /// B1：诊断连续失败计数（内存态，按 session 隔离）。
  /// 用于诊断失败卡阈值门控——连续失败达 UILimits.failureWarningThreshold 才插卡，
  /// 避免偶发单次失败也打扰用户；普通聊天（非诊断轮次）不计入。
  final Map<String, int> _consecutiveDiagnosisFails = {};

  // ───────────────────────── B1 消息卡片确定性触发 ─────────────────────────

  /// 诊断失败卡阈值门控（B1）。
  ///
  /// [attempted] 表示该轮是否确实发起了诊断（AI 输出含 [YS_DIAGNOSIS] 块，
  /// 或走显式诊断链路 commitDiagnosisFromContent）。仅当 attempted && !success
  /// 才计为一次失败，普通聊天（解析为 null）不会误触发。
  ///
  /// 连续失败达 UILimits.failureWarningThreshold 时插入诊断失败卡，
  /// failureCount 传入当前连续失败次数（与卡片 UI 的额外提示阈值对齐）。
  Future<void> _recordDiagnosisOutcome(
    String sessionId, {
    required bool attempted,
    required bool success,
  }) async {
    if (!attempted) return; // 非诊断轮次：不动计数
    if (success) {
      _consecutiveDiagnosisFails[sessionId] = 0;
      return;
    }
    final count = (_consecutiveDiagnosisFails[sessionId] ?? 0) + 1;
    _consecutiveDiagnosisFails[sessionId] = count;
    if (count >= UILimits.failureWarningThreshold) {
      try {
        await insertDiagnosisFailedCard(_sessionRepo, sessionId, count);
      } catch (e) {
        debugPrint('[SafeRun] 诊断失败卡插入失败不阻断主流程: $e');
      }
    }
  }

  /// 阶段总结卡（B1）：某症候训练达标 mastered 时插入，汇总该症候进展。
  ///
  /// 在 chat_service_send 两处 mastered 迁移点（步骤 6.3 评估 / 反馈后重评估）调用，
  /// 与 resolveSyndromesBatch 成对，确保「达标→解锁」同时留下可读的进展卡片。
  Future<void> _insertPhaseSummaryOnMastered(
    String sessionId,
    String syndromeId,
    String syndromeName,
    int trainingCount,
  ) async {
    try {
      await insertPhaseSummaryCard(
        _sessionRepo,
        sessionId,
        PhaseSummaryCardPayload(
          result: 'passed',
          resolvedSyndromeCount: 1,
          trainingCount: trainingCount,
          trend: 'improving',
          syndromeChanges: [
            SyndromeChangeItem(
              syndromeId: syndromeId,
              syndromeName: syndromeName,
              trend: 'improving',
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('[SafeRun] 阶段总结卡插入失败不阻断主流程: $e');
    }
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
    GenUiCapability genUi = const GenUiParser(),
    MaterialCapability material = const MaterialCapabilityImpl(),
    TeachingCapability teaching = const TeachingCapabilityImpl(),
    DiagnosisCapability diagnosis = const DiagnosisCapabilityImpl(),
    CharacterFactRepository? characterFactRepo,
    EventFactRepository? eventFactRepo,
    SubplotFactRepository? subplotFactRepo,
    OutlineRepository? outlineRepo,
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
       _editorObservationRepo = editorObservationRepo,
       _genUi = genUi,
       _material = material,
       _teaching = teaching,
       _diagnosis = diagnosis,
       _characterFactRepo = characterFactRepo,
       _eventFactRepo = eventFactRepo,
       _subplotFactRepo = subplotFactRepo,
       _outlineRepo = outlineRepo;

  /// 懒加载大纲服务（批次7 O2）
  ///
  /// 装配了 outlineRepo → 首次使用即构建并缓存；未装配 → 返回 null。
  /// 所有大纲注入/沉淀入口统一走本方法，保证「装配即可用」单一事实源。
  OutlineService? _ensureOutlineService() {
    _outlineService ??= _outlineRepo != null
        ? OutlineService(_outlineRepo)
        : null;
    return _outlineService;
  }

  // 引用内容预加载缓存（每次 sendMessage 调用前预加载，调用后清空）
  // 原因：buildReferencesContext 是同步纯函数，需要同步访问 DAO 数据
  final Map<String, AttachedFileRow> _cachedAttachedFiles = {};
  final Map<String, ChapterBrief> _cachedChapters = {};
  final Map<String, ManuscriptDetail> _cachedManuscripts = {};

  // 批次59：心流判定——记录每个 session 最近一次用户消息发送时间（秒级）
  final Map<String, int> _lastUserSendAtSec = {};

  // 批次63（B62b）：L1 意图向量——每个 session 最近 3 次交互意图（供 prompt 构造）
  final Map<String, List<String>> _recentIntentsBySession = {};

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

/// 内部 focus 历史条目
class _FocusHistoryItem {
  final String focusId;
  final int timestamp;
  const _FocusHistoryItem({required this.focusId, required this.timestamp});
}
