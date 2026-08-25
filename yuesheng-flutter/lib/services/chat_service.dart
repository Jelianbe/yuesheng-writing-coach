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
import 'package:writingcoach/services/student_profile.dart';
import 'package:writingcoach/services/training_evaluator.dart';
import 'package:writingcoach/services/training_input_builder.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/services/chat_gates.dart';
import 'package:writingcoach/services/intent_classifier.dart';
import 'package:writingcoach/services/style_fingerprint.dart';
import 'package:writingcoach/services/teacher_service.dart';
import 'package:writingcoach/services/teacher_validator.dart';
import 'package:writingcoach/types/teaching_types.dart';

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

extension ChatServiceDiagnosis on ChatService {
  /// 批次64（B62f）：声线漂移提示上下文——引导 AI 以提问方式温和指出其中一条
  String _buildDriftHintContext(List<String> hints) {
    return '## 声线漂移检测（L3→L1 实时反馈）\n\n'
        '检测到写作特征与既有风格基线出现明显偏差。\n'
        '若合适，请用**提问的方式**温和地向学员指出**其中一条**'
        '（结合具体数字，如"你的句子长度通常 15-20 字，但这部分平均只有 8 字——'
        '是刻意加速，还是无意识的变化？"），一次只问一个点，不展开成诊断。\n'
        '偏差项：\n- ${hints.join('\n- ')}';
  }

  /// A6：时序知识图谱事实提取协议（诊断章节正文时注入）
  ///
  /// 指导 AI 在诊断回复中附加 [YS_FACT] 块，提取人物/事件/支线三类结构化事实，
  /// 供系统 upsert 到 TKG 三表，驱动时序矛盾/因果链/情节闭环检测。
  /// 与 [YS_DIAGNOSIS]、[YS_ENTITY] 并列独立，输出顺序排在最后。
  String _buildFactProtocolContext() {
    return '## 时序知识图谱事实沉淀（输出顺序约束）\n\n'
        '【输出顺序】若同时输出诊断块、实体块与事实块，**必须严格按此顺序**：\n'
        '  1. [YS_DIAGNOSIS] 症候块（若诊断要求）；\n'
        '  2. [YS_ENTITY] 实体记忆块；\n'
        '  3. [YS_FACT] 事实块（本条）；\n'
        '  4. 之后再写面向学员的自然语言诊断与教学建议。\n\n'
        '若章节正文出现值得长期记住的**结构化事实**（人物属性断言、关键事件、'
        '支线收束），请在回复中附加 [YS_FACT] JSON 块，供系统沉淀为时序知识图谱。'
        '增量更新：仅记录当前章节新增或变化的事实，不重复已沉淀内容。'
        '完全无新事实（无人物属性变化、无关键事件、无支线进展）可不输出该块。\n\n'
        '格式：\n'
        '[YS_FACT]\n'
        '{\n'
        '  "characters": [\n'
        '    {"name":"人物名","assertions":[\n'
        '      {"attribute":"属性名(如独生子女状态/性格/职业/身份)","value":"属性值",'
        '"chapter":3}\n'
        '    ]}\n'
        '  ],\n'
        '  "events": [\n'
        '    {"name":"事件名","event_type":"决定|转折|突发|冲突|日常",'
        '"chapter":5,"participants":["人物名"],"description":"一句话概述",'
        '"cause_event_name":"触发本事件的前因事件名（无前因则省略）"}\n'
        '  ],\n'
        '  "subplots": [\n'
        '    {"name":"支线名","introduced_chapter":3,"resolved_chapter":null,'
        '"description":"支线梗概"}\n'
        '  ]\n'
        '}\n'
        '[/YS_FACT]\n\n'
        '规则：\n'
        '- characters：记录本章新增或变化的人物属性断言。attribute 用规范属性名'
        '（如「独生子女状态」「性格」「职业」「身份」「关系」），value 为原文可验证的具体值，'
        'chapter 为该断言出现的章节序号。同一人物可多条断言。\n'
        '- events：记录关键事件（决定/转折/突发类必记，冲突/日常视重要性）。'
        'event_type 从「决定|转折|突发|冲突|日常」中选一。participants 为参与人物名列表。'
        'description 一句话概述事件（≤30字）。'
        'cause_event_name 填触发本事件的前因事件名（须与既有事件 name 一致），'
        '用于构建因果链；无前因触发（如开篇事件）则省略此字段。\n'
        '- subplots：记录支线引入或回收。introduced_chapter 填首次引入章节，'
        'resolved_chapter 填本章回收章节（未回收填 null）。'
        '若本章回收了既有支线，必须输出该条并填入 resolved_chapter。\n'
        '- **完整性硬约束**：[YS_FACT] 包裹的 JSON 必须语法合法、完整闭合。'
        '如担心篇幅，请压缩自然语言诊断说明以保证事实块完整。';
  }

  /// 批次74：快速读取某章节对应手稿下的实体数（用于 combinedContent 空时判真故障）
  Future<int> _readOutlineEntityCount(String chapterId) async {
    try {
      final outlineService = _ensureOutlineService();
      if (outlineService == null) return 0;
      final chapter = await _chapterRepo.getChapter(chapterId);
      if (chapter == null) return 0;
      // 复用已公开 buildEntityIndexContext 非空推 count
      final ctx = await outlineService.buildEntityIndexContext(
        chapter.manuscriptId,
      );
      if (ctx == null) return 0;
      // 保守估算：每行实体前缀算 1 个
      return '\n$ctx'.split('\n- [').length - 1;
    } catch (e) {
      debugPrint('[SafeRun] 大纲实体检索计数失败: $e');
      return 0;
    }
  }

  /// 处理分块诊断生成的完整 AI 输出（D4-A）
  ///
  /// 当 runProgressiveDiagnosis 返回非 null 时，由 WritingCoachPanel 调用。
  /// 复用 sendMessage 的步骤 9-11（解析 + 持久化 + 卡片），不含 Teacher 触发。
  Future<String> commitDiagnosisFromContent({
    required String sessionId,
    required String fullContent,
  }) async {
    // 步骤 9: 解析诊断
    final rawParse = _diagnosis.parseDiagnosis(fullContent);
    String displayContent = rawParse.displayContent;
    ParsedDiagnosis? diagnosis = rawParse.diagnosis;

    if (diagnosis != null) {
      final startIndex = fullContent.indexOf(kDiagnosisStart);
      final endIndex = fullContent.indexOf(
        kDiagnosisEnd,
        startIndex + kDiagnosisStart.length,
      );
      if (startIndex != -1 && endIndex != -1) {
        final jsonStr = fullContent
            .substring(startIndex + kDiagnosisStart.length, endIndex)
            .trim();
        try {
          final rawJson = jsonDecode(jsonStr);
          final validation = _diagnosis.validateDiagnosisOutput(
            rawParse.displayContent,
            rawJson,
          );
          displayContent = validation.displayContent;
          diagnosis = validation.diagnosis;
        } catch (e) {
          debugPrint(
            '[SafeRun] commitDiagnosisFromContent JSON 解析失败沿用 rawParse: $e',
          );
        }
      }
    }

    // 批次74 A1：D4-A 渐进诊断也沉淀大纲 + 写确认卡
    // （commitDiagnosisFromContent 不传 primaryRef，内部会从 session 查当前章节主引用；
    //   无装配/无大纲块/非章节 → 静默跳过）
    await _applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );

    // A6：D4-A 路径也沉淀事实到 TKG 三表
    await _applyFactExtractionFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );

    // 批次74：剥离 [YS_ENTITY] 协议块（防原始 JSON 落库）
    displayContent = stripOutlineBlock(displayContent);
    // A6：剥离 [YS_FACT] 协议块
    displayContent = stripFactBlock(displayContent);

    // 步骤 10: 写入 assistant 消息
    if (displayContent.trim().isEmpty) {
      displayContent = '诊断完成';
    }
    final messageId = await _sessionRepo.addMessage(
      sessionId,
      'assistant',
      displayContent,
    );
    debugPrint(
      '[ChatService] commitDiagnosisFromContent: assistant 消息已写入 | messageId=$messageId | contentLen=${displayContent.length}',
    );

    // 步骤 11: 持久化诊断结果 + 卡片
    if (diagnosis != null) {
      // D4 修复：从 session 引用解析 primaryRef，传入 targetRefType/targetRefId
      String? d4TargetRefType;
      String? d4TargetRefId;
      try {
        final refs = await _referenceRepo.listReferences(sessionId);
        if (refs.isNotEmpty) {
          final primary = refs.firstWhere(
            (r) => r.isPrimary == 1,
            orElse: () => refs.first,
          );
          d4TargetRefType = primary.refType;
          d4TargetRefId = primary.refId;
        }
      } catch (e) {
        debugPrint('[SafeRun] commitDiagnosisFromContent 引用查询失败: $e');
      }

      try {
        await _diagnosisService.commitDiagnosisWithHistory(
          DiagnosisInput(
            sessionId: sessionId,
            messageId: messageId,
            syndromes: diagnosis.syndromes.map((s) => s.toJson()).toList(),
            suggestedActions: diagnosis.suggestedActions,
            confidence: diagnosis.confidence,
            rootCauseAnalysis: diagnosis.rootCauseAnalysis,
            nextFocus: diagnosis.nextFocus,
            feedbackSummary: diagnosis.feedbackSummary,
            currentTeachingFocusId: diagnosis.currentTeachingFocusId,
            focusReason: diagnosis.focusReason,
            teachingMode: diagnosis.teachingMode?.value,
            targetRefType: d4TargetRefType,
            targetRefId: d4TargetRefId,
          ),
        );

        // 批次10（C3）：D4-A 分块诊断同样 = 旧训练轮终结 → 重置子阶段，
        // 与 sendMessage 主路径（L1400-1406）对称，防 feedback 残留
        try {
          await _stateRepo.updateSubphase(sessionId, null);
        } catch (e) {
          debugPrint('[SafeRun] commitDiagnosisFromContent 诊断后重置子阶段失败: $e');
        }

        // S5 修复：D4-A 路径也沉淀 style_profile（与 sendMessage 主路径对齐）
        if (diagnosis.styleProfile != null) {
          try {
            await _studentModelRepo.updateStyleProfile(
              sessionId,
              diagnosis.styleProfile!,
            );
          } catch (e) {
            debugPrint('[SafeRun] commitDiagnosisFromContent 风格画像沉淀失败: $e');
          }
        }

        try {
          await insertDiagnosisResultCard(
            _sessionRepo,
            sessionId,
            DiagnosisResultCardPayload(
              syndromeCount: diagnosis.syndromes.length,
              syndromes: diagnosis.syndromes
                  .map(
                    (s) => DiagnosisSyndromeCard(
                      syndromeId: s.syndromeId,
                      name: s.name,
                      severity: s.severity.value,
                      evidenceCount: s.evidence.length,
                    ),
                  )
                  .toList(),
              suggestedActions: diagnosis.suggestedActions,
              confidence: diagnosis.confidence,
              diagnosisId: messageId,
            ),
          );
        } catch (e) {
          debugPrint('[SafeRun] commitDiagnosisFromContent 卡片插入失败: $e');
        }

        // 批次6 D1：分块诊断路径复用阶段迁移（resolver + M4-A 自动迁移 + M4-C 达标率校验），
        // 与 sendMessage 单次诊断路径行为一致，超长章节诊断完成后也能推进阶段/升级卡片
        await _applyPhaseMigration(sessionId: sessionId, diagnosis: diagnosis);
      } catch (e) {
        debugPrint('[SafeRun] commitDiagnosisFromContent 诊断写入失败: $e');
      }
    }

    // B1：D4-A 分块诊断链路必为诊断；成败记录 → 失败卡阈值门控
    await _recordDiagnosisOutcome(
      sessionId,
      attempted: true,
      success: diagnosis != null,
    );

    return messageId;
  }
}

extension ChatServiceDiagnosisApply on ChatService {
  /// 大纲实体提取 + 确认卡写入（批次72/73/74 D4-A 共用）
  ///
  /// 失败/未装配/无大纲块/非章节主引用 → 静默跳过不抛。
  /// 优先使用入参传入的 primaryRef（sendMessage 路径）；
  /// 若未传（commitDiagnosisFromContent 路径）则从 session 的当前引用取。
  Future<void> _applyOutlineEntitiesFromContent({
    required String sessionId,
    required String fullContent,
    ReferenceItem? primaryRef,
  }) async {
    if (_ensureOutlineService() == null) return;
    // 若调用方未传入 primaryRef（D4-A 路径），从 session 装配主引用
    ReferenceItem? pRef = primaryRef;
    if (pRef == null) {
      try {
        final refs = await _referenceRepo.listReferences(sessionId);
        if (refs.isNotEmpty) {
          final items = refs
              .map(
                (r) => ReferenceItem(
                  refType: r.refType,
                  refId: r.refId,
                  title: r.title,
                  isPrimary: r.isPrimary,
                  manuscriptId: r.manuscriptId,
                  excerptRange: r.excerptRange,
                ),
              )
              .toList();
          pRef = items.firstWhere(
            (r) => r.isPrimary == 1,
            orElse: () => items.first,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] commitOutlineChangeFromContent 引用查询失败: $e');
        return;
      }
    }
    if (pRef?.refType != 'chapter') return;
    try {
      final outlineExtraction = parseOutlineExtraction(fullContent);
      if (outlineExtraction == null || outlineExtraction.entities.isEmpty) {
        return;
      }
      final chapter = await _chapterRepo.getChapter(pRef!.refId);
      if (chapter == null) return;
      final results = await _ensureOutlineService()!.applyOutlineExtraction(
        manuscriptId: chapter.manuscriptId,
        extraction: outlineExtraction,
        sourceChapterId: chapter.id,
        sourceChapterNo: chapter.sortOrder,
      );
      debugPrint(
        '[ChatService] 大纲提取落库 | 实体数=${outlineExtraction.entities.length}',
      );
      for (final r in results) {
        if (r.impressions.isEmpty) continue;
        await insertOutlineConfirmationCard(
          _sessionRepo,
          sessionId,
          OutlineConfirmationPayload(
            confirmationId: generateUuid(),
            entityId: r.entityId,
            entityType: r.entityType,
            entityKey: r.entityKey,
            isNewEntity: r.isNewEntity,
            impressions: r.impressions
                .map(
                  (im) => OutlineImpressionPayload(
                    id: im.id,
                    text: im.text,
                    conflictWith: im.conflictWith,
                  ),
                )
                .toList(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[SafeRun] commitOutlineChangeFromContent 大纲落库失败: $e');
    }
  }

  /// A6：事实提取落库（时序知识图谱写入路径）
  ///
  /// 从 AI 诊断回复中提取 [YS_FACT] 块，将人物/事件/支线事实
  /// upsert 到 character_fact/event_fact/subplot_fact 三表。
  /// 失败/未装配/无事实块/非章节 → 静默跳过不抛。
  /// 优先使用入参 primaryRef（sendMessage 路径）；
  /// 若未传（commitDiagnosisFromContent 路径）则从 session 引用取。
  Future<void> _applyFactExtractionFromContent({
    required String sessionId,
    required String fullContent,
    ReferenceItem? primaryRef,
  }) async {
    // 三表仓储至少一个未装配 → 跳过
    if (_characterFactRepo == null &&
        _eventFactRepo == null &&
        _subplotFactRepo == null) {
      return;
    }

    // 解析 primaryRef（同 _applyOutlineEntitiesFromContent 模式）
    ReferenceItem? pRef = primaryRef;
    if (pRef == null) {
      try {
        final refs = await _referenceRepo.listReferences(sessionId);
        if (refs.isNotEmpty) {
          final items = refs
              .map(
                (r) => ReferenceItem(
                  refType: r.refType,
                  refId: r.refId,
                  title: r.title,
                  isPrimary: r.isPrimary,
                  manuscriptId: r.manuscriptId,
                  excerptRange: r.excerptRange,
                ),
              )
              .toList();
          pRef = items.firstWhere(
            (r) => r.isPrimary == 1,
            orElse: () => items.first,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] persistTeacherSuggestion 失败: $e');
        return;
      }
    }
    if (pRef?.refType != 'chapter') return;

    try {
      final extraction = parseFactExtraction(fullContent);
      if (extraction == null || extraction.isEmpty) return;

      final chapter = await _chapterRepo.getChapter(pRef!.refId);
      if (chapter == null) return;
      final manuscriptId = chapter.manuscriptId;
      final chapterNo = chapter.sortOrder;
      final now = nowSec();

      // 人物事实 → character_fact
      if (_characterFactRepo != null) {
        for (final c in extraction.characters) {
          await _characterFactRepo.upsertCharacter(
            manuscriptId: manuscriptId,
            name: c.name,
            firstSeenChapter: chapterNo,
            firstSeenAt: now,
            assertions: c.assertions,
          );
        }
      }

      // 事件事实 → event_fact
      // 批次3-D4：两轮写入——先 upsert 全部事件（不带因果边），
      // 再反查 causeEventName 对应 id 填入 cause_event_id
      if (_eventFactRepo != null) {
        // 第一轮：upsert 全部事件
        for (final e in extraction.events) {
          await _eventFactRepo.upsertEvent(
            manuscriptId: manuscriptId,
            name: e.name,
            eventType: e.eventType,
            chapter: e.chapter ?? chapterNo,
            participants: e.participants,
            description: e.description,
          );
        }
        // 第二轮：填因果边（causeEventName → causeEventId）
        for (final e in extraction.events) {
          final causeName = e.causeEventName;
          if (causeName == null) continue;
          final self = await _eventFactRepo.getEvent(manuscriptId, e.name);
          final cause = await _eventFactRepo.getEvent(manuscriptId, causeName);
          if (self != null && cause != null) {
            await _eventFactRepo.updateCauseEventId(self.id, cause.id);
          } else {
            // 批次6（6.11 L5/V10）：因果边反查失败不再静默丢弃——
            // 打日志留痕，便于排查前因名称不一致导致关联未建立
            debugPrint(
              '[FactExtract] 因果边反查失败未关联: 事件="$e.name" '
              '前因="$causeName"（self=${self != null ? '找到' : '缺失'}'
              ' / cause=${cause != null ? '找到' : '缺失'}）',
            );
          }
        }
      }

      // 支线事实 → subplot_fact
      if (_subplotFactRepo != null) {
        for (final s in extraction.subplots) {
          await _subplotFactRepo.upsertSubplot(
            manuscriptId: manuscriptId,
            name: s.name,
            introducedChapter: s.introducedChapter ?? chapterNo,
            resolvedChapter: s.resolvedChapter,
            resolvedAt: s.resolvedChapter != null ? now : null,
            description: s.description,
          );
        }
      }

      debugPrint(
        '[ChatService] A6 事实提取落库 | 人物=${extraction.characters.length} '
        '事件=${extraction.events.length} 支线=${extraction.subplots.length}',
      );
    } catch (e) {
      debugPrint('[SafeRun] 事实提取三表落库失败: $e');
    }
  }
}

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

  /// 从用户消息解析 focus 切换意图
  ///
  /// 只解析明确的 P\d+ 编号匹配（"我想练 P003"等），代词"这个"暂不实现
  String? _parseUserFocusFromMessage(
    String content,
    List<ActiveProblemView> activeProblems,
  ) {
    // 批次4（4.5 O9）：放宽覆盖表达变体（先练练/练一下/我想练/想先解决/聚焦/主攻等）
    final patterns = [
      RegExp(r'我想?先?(?:解决|练|练习|练练|练一下)\s*(P\d+)', caseSensitive: false),
      RegExp(r'先?(?:解决|练|练习|练练|练一下)(?:一练)?\s*(P\d+)', caseSensitive: false),
      RegExp(r'(?:聚焦|专注|主攻|重点练)\s*(P\d+)', caseSensitive: false),
    ];

    final activeIds = activeProblems.map((p) => p.syndromeId).toSet();

    for (final pattern in patterns) {
      final match = pattern.firstMatch(content);
      if (match != null && match.groupCount >= 1) {
        final id = match.group(1)!.toUpperCase();
        if (activeIds.contains(id)) return id;
      }
    }
    return null;
  }

  /// 构建 focus 历史条目（从诊断历史提取最近 N 条 focus_id）
  Future<List<_FocusHistoryItem>> _buildFocusHistory(String sessionId) async {
    try {
      final diagnoses = await _diagnosisRepo.listDiagnosisHistory(sessionId);
      final threshold = FocusSwitch.threshold;
      final items = <_FocusHistoryItem>[];
      for (final d in diagnoses.take(threshold)) {
        final focusId = d.currentTeachingFocusId;
        if (focusId != null && focusId.isNotEmpty) {
          items.add(
            _FocusHistoryItem(focusId: focusId, timestamp: d.timestamp),
          );
        }
      }
      return items;
    } catch (e) {
      debugPrint('[SafeRun] loadAttachedFilesForManuscript 失败: $e');
      return [];
    }
  }

  /// 映射 focus-resolver 的 FocusSource 到 chat_context_builder 的 FocusSource
  FocusSource _mapFocusSource(focus.FocusSource source) {
    switch (source) {
      case focus.FocusSource.aiSuggested:
        return FocusSource.aiSuggested;
      case focus.FocusSource.userOverride:
        return FocusSource.userOverride;
      case focus.FocusSource.fallback:
        return FocusSource.fallback;
      case focus.FocusSource.none:
        return FocusSource.none;
    }
  }
}

extension ChatServiceDiagnosisSupport on ChatService {
  /// 阶段迁移统一处理（批次6 D1）——AI 驱动 resolver + M4-A 自动迁移 + M4-C 达标率校验
  ///
  /// 供 [sendMessage] 与 [commitDiagnosisFromContent] 复用，保证两条诊断路径行为一致：
  ///   - sendMessage：单次诊断（≤4000 字）
  ///   - commitDiagnosisFromContent：超长分块诊断（>4000 字，progressive 路径）
  ///
  /// 内部职责（均 try/catch 包裹，失败不阻断主流程）：
  ///   1. diagnosis 输出 suggestedPhase/suggestedBeginnerLevel 时 → phase-mapper resolver
  ///   2. effectivePhase → M4-B validatePhaseTransition 校验 → updatePhase + 子阶段重置 + 升级卡片
  ///   3. effectiveBeginnerLevel → updateBeginnerLevel
  ///   4. 所有活跃症候已 resolved → M4-A 自动迁移（M4-C 达标率 ≥ phasePassRate 才放行）
  Future<void> _applyPhaseMigration({
    required String sessionId,
    required ParsedDiagnosis? diagnosis,
  }) async {
    // 批次1（C5/H3）：路径1（AI 驱动）成功迁移后，路径2（M4-A 自动）不得
    // 再无条件继续，防止同轮链式双跳（如 P1→P2→P3）
    var path1Migrated = false;
    // ── 1. AI 驱动路径：phase-mapper resolver ──
    if (diagnosis != null &&
        (diagnosis.suggestedPhase != null ||
            diagnosis.suggestedBeginnerLevel != null)) {
      try {
        final currentState = await _stateRepo.getTeachingState(sessionId);
        final currentBeginnerLevelStr = currentState?.beginnerLevel;
        final currentBeginnerLevel = BeginnerLevel.fromString(
          currentBeginnerLevelStr,
        );

        // 计算连续失败训练次数（仅 N3 触发降级检查时需要）
        int consecutiveFailedTrainings = 0;
        if (currentBeginnerLevel == BeginnerLevel.n3Diagnose) {
          try {
            final allHistory = await _studentModelRepo.getTeachingHistory(
              sessionId,
            );
            final activeProblems = await _diagnosisRepo.listActiveProblems(
              sessionId,
            );
            final focusSyndromeId =
                diagnosis.currentTeachingFocusId ??
                activeProblems.firstOrNull?.syndromeId;
            if (focusSyndromeId != null) {
              final trainingRecords =
                  allHistory
                      .where(
                        (r) =>
                            r['type'] == 'training' &&
                            r['syndromeId'] == focusSyndromeId,
                      )
                      .toList()
                    ..sort((a, b) {
                      final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
                      final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
                      return ta.compareTo(tb);
                    });
              for (int i = trainingRecords.length - 1; i >= 0; i--) {
                if (trainingRecords[i]['result'] == 'failed') {
                  consecutiveFailedTrainings++;
                } else {
                  break;
                }
              }
            }
          } catch (e) {
            debugPrint('[SafeRun] resolver 训练记录读取失败: $e');
          }
        }

        final resolverResult = resolvePhaseMapper(
          PhaseMapperInput(
            currentPhase: TeachingPhase.fromString(currentState?.currentPhase),
            currentBeginnerLevel: currentBeginnerLevel,
            suggestedPhase: diagnosis.suggestedPhase,
            suggestedBeginnerLevel: diagnosis.suggestedBeginnerLevel,
            consecutiveFailedTrainings: consecutiveFailedTrainings,
          ),
        );

        final effectivePhase = resolverResult.effectivePhase;
        if (effectivePhase != null) {
          // M4-B: 阶段迁移合法性校验——拦截非法跳级/回退
          // （如 P2→P0、P3→P1 等），仅放行相邻递进或 P4→P2 回退
          final prevPhaseValue = currentState?.currentPhase;
          final currentPhaseForValidation =
              TeachingPhase.fromString(prevPhaseValue) ??
              TeachingPhase.p0Engage;
          if (validatePhaseTransition(
            currentPhaseForValidation,
            effectivePhase,
          )) {
            await _stateRepo.updatePhase(sessionId, effectivePhase.value);
            // 批次9：阶段真实变化时插入 phase_upgrade 卡片（对齐 RN insertPhaseUpgradeCard）
            if (prevPhaseValue != effectivePhase.value) {
              path1Migrated = true;
              // M4-D: 阶段迁移时重置子阶段，避免上一阶段子阶段残留
              await _stateRepo.updateSubphase(sessionId, null);
              try {
                await insertPhaseUpgradeCard(
                  _sessionRepo,
                  sessionId,
                  PhaseUpgradeCardPayload(
                    from: prevPhaseValue ?? TeachingPhase.p0Engage.value,
                    to: effectivePhase.value,
                  ),
                );
              } catch (e) {
                debugPrint('[SafeRun] 卡片插入失败不影响阶段迁移: $e');
              }
            }
          } else {
            debugPrint(
              '[SafeRun] M4-B: 阶段迁移非法已拦截 '
              '$currentPhaseForValidation → $effectivePhase',
            );
          }
        }
        if (resolverResult.effectiveBeginnerLevel != null) {
          await _stateRepo.updateBeginnerLevel(
            sessionId,
            resolverResult.effectiveBeginnerLevel!.value,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] resolver 失败不阻断主流程: $e');
      }
    }

    // 批次1（C5/H3）：路径1 已成功迁移 → 直接返回，路径2 仅当路径1 无有效迁移时评估
    if (path1Migrated) return;

    // ── 2. 自动迁移路径：M4-A + M4-C 达标率校验 ──
    // 所有活跃症候已 resolved 时，代码侧主动推进阶段（不依赖 AI suggestedPhase）
    // 守卫：仅在 P2 及以后触发（P0/P1 阶段迁移由 AI suggested_phase 驱动）
    // M4-C: passRate >= phasePassRate(0.7) 才允许迁移，避免手动标记完成跳过训练升阶
    try {
      final remaining = await _diagnosisRepo.listActiveProblems(sessionId);
      if (remaining.isEmpty) {
        final ts = await _stateRepo.getTeachingState(sessionId);
        final currentPhase =
            TeachingPhase.fromString(ts?.currentPhase) ??
            TeachingPhase.p0Engage;
        if (currentPhase != TeachingPhase.p0Engage &&
            currentPhase != TeachingPhase.p1World) {
          final evalService = EvaluationService(
            _diagnosisRepo,
            _studentModelRepo,
          );
          final passRate = await evalService.computePassRateForPhaseMigration(
            sessionId,
          );
          if (passRate >= EvaluationThresholds.phasePassRate) {
            final next = nextPhase(currentPhase);
            // M4-B: nextPhase 已保证相邻递进，validatePhaseTransition 双重校验
            if (next != null && validatePhaseTransition(currentPhase, next)) {
              await _stateRepo.updatePhase(sessionId, next.value);
              await _stateRepo.updateSubphase(sessionId, null);
              try {
                await insertPhaseUpgradeCard(
                  _sessionRepo,
                  sessionId,
                  PhaseUpgradeCardPayload(
                    from: currentPhase.value,
                    to: next.value,
                  ),
                );
              } catch (e) {
                debugPrint('[SafeRun] 自动迁移卡片插入失败: $e');
              }
            }
          } else {
            debugPrint(
              '[SafeRun] M4-C: 达标率 $passRate < '
              '${EvaluationThresholds.phasePassRate}，阶段暂不迁移',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[SafeRun] 自动迁移失败不阻断主流程: $e');
    }
  }

  /// 7.2（批次16）：介入级别修正原因说明。
  ///
  /// D3（复发/L3）或 performance_gate（G1-G5）命中时返回一句说明，
  /// 供介入级别注入消息标注修正原因，帮助 AI 校准教学力度；未命中返回空串。
  /// 规则顺序与 interventionLevelForTrainingCount 完全一致（D3 > G1 > G2 > G3 > 次数 > G4 > G5）。
  String _buildInterventionAdjustmentNote({
    required int trainingCount,
    required Severity currentSeverity,
    required bool relapse,
    required TrainingPerformance? performance,
  }) {
    // D3（批次8）：复发 / L3 无条件回退 I do（最高优先级）
    if (relapse) return '（本轮因复发回退脚手架到 I do）';
    if (currentSeverity == Severity.l3) {
      return '（本轮因严重度 L3 回退脚手架到 I do）';
    }
    if (performance == null) return '';

    // 基础次数档位（与 interventionLevelForTrainingCount 同口径）
    final base = trainingCount >= 4
        ? InterventionLevel.youDo
        : trainingCount >= 2
        ? InterventionLevel.weDo
        : InterventionLevel.iDo;

    // 延迟撤脚手架（保守）
    if (performance.consecutiveFails >= 3) {
      return '（连续 ${performance.consecutiveFails} 次未达标，回退脚手架到 I do）';
    }
    if (performance.passRate < 0.5 && base != InterventionLevel.iDo) {
      final pct = (performance.passRate * 100).round();
      return '（历史达标率 $pct%，回退脚手架一档）';
    }
    if (performance.consecutiveFails >= 2 && base == InterventionLevel.youDo) {
      return '（最近两次未达标，暂不进入独立练习）';
    }

    // 提前撤脚手架（正向）
    if (base == InterventionLevel.iDo &&
        performance.totalCount >= 1 &&
        performance.consecutivePasses == performance.totalCount) {
      return '（首次训练即通过，提前进入引导练习）';
    }
    if (base == InterventionLevel.weDo &&
        performance.totalCount >= 2 &&
        performance.consecutivePasses == performance.totalCount) {
      return '（连续训练全部通过，提前进入独立练习）';
    }

    return '';
  }
}

extension ChatServiceSendDiagnosisLock on ChatService {
  Future<String?> _injectDiagnosisLock({
    required String sessionId,
    required String content,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required BeginnerLevel? beginnerLevel,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    // 6. 跨轮次诊断锁定注入（若有活跃症候）
    // trainingSyndromeId 用于 appendTeachingHistory 写 training 记录（批次1-7-2）
    String? trainingSyndromeId;
    if (activeProblems.isNotEmpty) {
      // 6.1 focus-resolver 6 项校验门控
      final aiSuggestedFocusId = await _diagnosisRepo.getLatestTeachingFocus(
        sessionId,
      );
      final focusHistory = await _buildFocusHistory(sessionId);
      final userFocusOverride = _parseUserFocusFromMessage(
        content,
        activeProblems,
      );

      // 转换为 focus-resolver 输入类型
      final focusProblems = activeProblems
          .map(
            (p) => FocusProblem(
              syndromeId: p.syndromeId,
              syndromeName: p.syndromeName,
              severity: Severity.fromString(p.severity) ?? Severity.l2,
              confirmationStatus:
                  ConfirmationStatus.fromString(p.confirmationStatus) ??
                  ConfirmationStatus.suspected,
              status: 'active',
              confirmedAt: p.confirmedAt,
            ),
          )
          .toList();

      final focusResult = focus.resolveTeachingFocus(
        focus.ResolveFocusInput(
          problems: focusProblems,
          aiSuggestedFocusId: aiSuggestedFocusId,
          userFocusOverride: userFocusOverride,
          subphase: currentSubphase,
          focusHistory: focusHistory
              .map(
                (h) => focus.FocusHistoryEntry(
                  focusId: h.focusId,
                  timestamp: h.timestamp,
                ),
              )
              .toList(),
          // 批次60：学员当前技能层级（fallback 软优先层级≤当前+1）
          studentSkillLevel: skillLevelForBeginner(beginnerLevel),
        ),
      );

      // 6.2 若有拒绝理由，注入提示给 AI
      if (focusResult.rejectReason != null) {
        messages.add(
          ChatMessage(
            role: 'system',
            content: '# Focus 切换提示\n\n${focusResult.rejectReason}',
          ),
        );
      }

      if (focusResult.activatedFocusId != null) {
        trainingSyndromeId = focusResult.activatedFocusId;
      }

      // 6.3 训练评估注入
      final focusSyndromeId =
          focusResult.activatedFocusId ?? activeProblems.first.syndromeId;
      final focusProblem = activeProblems
          .where((p) => p.syndromeId == focusSyndromeId)
          .firstOrNull;
      if (focusProblem != null) {
        // 批次60：介入级别注入（逐步撤除脚手架，独立于训练评估）
        // D3（批次8）：综合 severity + 复发信号；7.2（批次16）：performance_gate 表现感知
        try {
          // 7.2：一次拉取训练历史得表现（totalCount = 训练次数），
          // 替代 countTrainingForSyndrome 单独查询，避免「次数+表现」双倍 I/O
          final performance = await computeTrainingPerformance(
            _studentModelRepo,
            sessionId,
            focusSyndromeId,
          );
          final trainingCount = performance?.totalCount ?? 0;
          // D3：复发信号 = 该症候曾毕业（跨 session resolved），本 session 又活跃
          bool relapse = false;
          try {
            relapse = await _diagnosisRepo.hasResolvedHistory(focusSyndromeId);
          } catch (e) {
            debugPrint('[SafeRun] 复发信号查询失败降级 false: $e');
          }
          final currentSeverity =
              Severity.fromString(focusProblem.severity) ?? Severity.l2;
          final intervention = interventionLevelForTrainingCount(
            trainingCount,
            currentSeverity: currentSeverity,
            relapse: relapse,
            performance: performance,
          );
          // D3 / 7.2：修正原因说明（命中时注入，帮助 AI 校准教学力度）
          final adjustmentNote = _buildInterventionAdjustmentNote(
            trainingCount: trainingCount,
            currentSeverity: currentSeverity,
            relapse: relapse,
            performance: performance,
          );
          messages.add(
            ChatMessage(
              role: 'system',
              content:
                  '# 训练介入级别（逐步撤除脚手架）\n\n'
                  '本症候已训练 $trainingCount 次，本轮采用介入级别：'
                  '${intervention.value}（${intervention.label}）。'
                  '${adjustmentNote.isEmpty ? '' : '$adjustmentNote\n'}'
                  '按级别组织训练：\n'
                  '- I do：给完整示范参考 + 常见错误提醒 + 自查锚点，让学员先看懂\n'
                  '- We do：常见错误提醒 + 自查锚点保留，示范改为引导方向，学员动手写为主\n'
                  '- You do：只给自查锚点，不做示范，学员独立练习 + 你来点评\n'
                  '（本注入是参考输入，具体执行由你按学员情况判断）',
            ),
          );
        } catch (e) {
          debugPrint('[SafeRun] 训练评估注入失败不阻断主流程: $e');
        }
        try {
          final trainingInput = await buildTrainingInputForActiveSyndrome(
            _studentModelRepo,
            sessionId,
            focusSyndromeId,
            ActiveProblemMeta(
              currentSeverity:
                  Severity.fromString(focusProblem.severity) ?? Severity.l2,
            ),
            // v19：传 DiagnosisRepo 让 startingTeachingState 优先读持久化起点
            diagnosisRepo: _diagnosisRepo,
          );
          if (trainingInput != null) {
            final summary = buildEvaluationSummary(
              focusSyndromeId,
              trainingInput,
            );
            // T2 修复：FSM 状态迁移时写回 DB（与 EvaluationService 同款逻辑）
            if (summary.teachingState != trainingInput.teachingState) {
              try {
                await _diagnosisRepo.updateTeachingState(
                  sessionId,
                  focusSyndromeId,
                  summary.teachingState.value,
                );
                // 正向达标：mastered → 立即解锁
                if (summary.teachingState == TeachingState.mastered) {
                  try {
                    await _diagnosisRepo.resolveSyndromesBatch(sessionId, [
                      focusSyndromeId,
                    ]);
                  } catch (e) {
                    debugPrint('[SafeRun] resolveSyndromesBatch 内层: $e');
                  }
                  // B1：达标→解锁同时插入阶段总结卡，汇总该症候进展
                  await _insertPhaseSummaryOnMastered(
                    sessionId,
                    focusSyndromeId,
                    focusProblem.syndromeName,
                    trainingInput.passRateInput.totalCount,
                  );
                }
              } catch (e) {
                debugPrint('[SafeRun] FSM updateTeachingState 外层: $e');
              }
            }
            if (summary.contextInjection.isNotEmpty) {
              messages.add(
                ChatMessage(role: 'system', content: summary.contextInjection),
              );
            }
          }
          // T1 修复：注入当前焦点症候的完整训练教学知识
          // （核心本质/教学要点/常见误区/严重度参考/教学素材库）
          try {
            final trainingKnowledge = getTrainingContent([focusSyndromeId]);
            if (trainingKnowledge.isNotEmpty) {
              markStage(BudgetStageNames.trainingKnowledge);
              messages.add(
                ChatMessage(role: 'system', content: trainingKnowledge),
              );
            }
          } catch (e) {
            debugPrint('[SafeRun] 知识库注入失败不阻断主流程: $e');
          }
        } catch (e) {
          debugPrint('[SafeRun] 训练上下文构建失败不阻断主流程: $e');
        }
      }

      // 6.4 L3 结构化症候详情
      final activeSyndromeViews = activeProblems
          .map(
            (p) => ActiveSyndromeView(
              syndromeId: p.syndromeId,
              syndromeName: p.syndromeName,
              severity: Severity.fromString(p.severity) ?? Severity.l2,
              confirmationStatus: ConfirmationStatus.fromString(
                p.confirmationStatus,
              ),
            ),
          )
          .toList();

      // 2026-08-18 批次：文笔画像→技法旁路路由（设计 docs/2026-08-18-*.md）
      // 五维非健康值→文笔层技法候选，门控通过才注入；失败不阻断主流程
      String? styleTechniqueSection;
      try {
        final latestStyleProfile = await _studentModelRepo
            .getLatestStyleProfile();
        final suggestion = routeStyleTechniques(
          styleProfile: latestStyleProfile,
          activeProblems: activeSyndromeViews,
          // 症候级 mastered → 技法集合派生（active_problem.teaching_state）
          masteredTechniqueIds: deriveMasteredTechniqueIds(activeProblems),
          focusSyndromeId: focusResult.activatedFocusId,
        );
        styleTechniqueSection = formatStyleTechniqueSection(suggestion);
      } catch (e) {
        debugPrint('[SafeRun] 文笔画像旁路路由失败不阻断主流程: $e');
      }

      final structuredContext = buildStructuredSyndromeContext(
        activeSyndromeViews,
        activeFocus: ActiveFocusContext(
          focusId: focusResult.activatedFocusId,
          source: _mapFocusSource(focusResult.source),
          reason: focusResult.reason,
        ),
        styleTechniqueSection: styleTechniqueSection,
      );
      markStage(BudgetStageNames.l3Structure);
      messages.add(ChatMessage(role: 'system', content: structuredContext));

      // 批次60：学员技能层级软引导（AI 自主判断优先，仅提示不硬性）
      final studentSkillLevel = skillLevelForBeginner(beginnerLevel);
      if (studentSkillLevel != null) {
        messages.add(
          ChatMessage(
            role: 'system',
            content:
                '# 学员技能层级\n\n'
                '学员当前技能层级：${studentSkillLevel.value} ${studentSkillLevel.label}。\n'
                '反馈建议：优先给当前层级+1 以内的问题做重点反馈；'
                '若诊断出更高层级的问题可以提及，但作为次要项，不要一次展开超出学员理解范围的内容。',
          ),
        );
      }
    }
    return trainingSyndromeId;
  }
}

extension ChatServiceSendInject on ChatService {
  Future<void> _injectProfileAndIntents({
    required String sessionId,
    required String content,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    // 5.0 学员画像注入（跨会话上下文）
    // 真源：chat-service.ts L218 buildStudentContext
    try {
      final profileResult = await buildStudentContext(
        diagnosisRepo: _diagnosisRepo,
        studentModelRepo: _studentModelRepo,
        sessionRepo: _sessionRepo,
        sessionId: sessionId,
      );
      if (profileResult.text.isNotEmpty) {
        markStage(BudgetStageNames.studentProfile);
        messages.add(ChatMessage(role: 'system', content: profileResult.text));
      }
    } catch (e) {
      debugPrint('[SafeRun] 画像注入失败不阻断主流程: $e');
    }

    // 5.0.0b S2/S3 修复：注入上一轮教学焦点的 focus_reason + next_focus
    // 闭合 teaching_plan 3元组协议的"下一轮注入"承诺
    try {
      final latestDiag = await _diagnosisRepo.getLatestDiagnosis(sessionId);
      if (latestDiag != null) {
        final parts = <String>[];
        if (latestDiag.focusReason != null &&
            latestDiag.focusReason!.isNotEmpty) {
          parts.add('**上一轮教学焦点理由**：${latestDiag.focusReason}');
        }
        if (latestDiag.nextFocus != null && latestDiag.nextFocus!.isNotEmpty) {
          parts.add('**上轮设定的下一步方向**：${latestDiag.nextFocus}');
        }
        if (parts.isNotEmpty) {
          messages.add(
            ChatMessage(
              role: 'system',
              content:
                  '# 上一轮教学计划延续（系统注入）\n\n'
                  '${parts.join('\n\n')}\n\n'
                  '请保持教学连贯性，延续上轮设定的方向。',
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[SafeRun] 教学计划延续注入失败不阻断主流程: $e');
    }

    // 5.0.1 交互意图分类（批次63 B62b，A2 落地）
    // L1 数据模型「意图识别分类器 + 最近3次意图向量」→ 决定 prompt 构造与触发策略
    final intent = classifyUserIntent(content);
    final recentIntents = _recentIntentsBySession.putIfAbsent(
      sessionId,
      () => [],
    );
    recentIntents.add(intent.value);
    if (recentIntents.length > 3) recentIntents.removeAt(0);
    final intentNote = buildIntentInstruction(intent, recentIntents);
    if (intentNote != null) {
      messages.add(ChatMessage(role: 'system', content: intentNote));
    }

    // 5.0.2 回复颗粒度控制：用户请求「长话短说/详细点」时注入（standard 不注入）
    // 落地教学行为对照表 9.2「反馈颗粒度」行（说详细点/简单说说就行 → 调整 detail level）
    final detailNote = buildReplyDetailInstruction(detectReplyDetail(content));
    if (detailNote != null) {
      messages.add(ChatMessage(role: 'system', content: detailNote));
    }
  }

  Future<({ReferenceItem? primaryRef, String? chapterContent})>
  _injectReferences({
    required String sessionId,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    // 5.1 引用内容注入（作品/章节/素材文件）
    // 真源：chat-service.ts L230-246 buildReferencesContext
    // 同时记录 primaryRef 供 5.2 附属文件注入使用
    ReferenceItem? primaryRef;
    try {
      final refs = await _referenceRepo.listReferences(sessionId);
      if (refs.isNotEmpty) {
        final referenceItems = refs
            .map(
              (r) => ReferenceItem(
                refType: r.refType,
                refId: r.refId,
                title: r.title,
                isPrimary: r.isPrimary,
                manuscriptId: r.manuscriptId,
                excerptRange: r.excerptRange,
              ),
            )
            .toList();
        // 记录主引用（isPrimary == 1），供 5.2 附属文件注入推导 manuscriptId
        primaryRef = referenceItems.firstWhere(
          (r) => r.isPrimary == 1,
          orElse: () => referenceItems.first,
        );

        final resolvers = ReferenceResolvers(
          fileResolver: (fileId) {
            // 同步包装：buildReferencesContext 是同步函数，需要 sync resolver
            // 由于 drift 是 async，这里用 _cachedAttachedFiles 预加载
            return _cachedAttachedFiles[fileId];
          },
          chapterResolver: (chapterId) {
            return _cachedChapters[chapterId];
          },
          manuscriptResolver: (manuscriptId) {
            return _cachedManuscripts[manuscriptId];
          },
        );
        // 预加载所有引用的详情到缓存
        await _preloadReferenceDetails(refs);
        final referencesContext = buildReferencesContext(
          referenceItems,
          resolvers: resolvers,
        );
        if (referencesContext.isNotEmpty) {
          markStage(BudgetStageNames.references);
          messages.add(ChatMessage(role: 'system', content: referencesContext));
        }
        // 清理缓存
        _cachedAttachedFiles.clear();
        _cachedChapters.clear();
        _cachedManuscripts.clear();
      }
    } catch (e) {
      debugPrint('[SafeRun] 引用内容注入失败不阻断主流程: $e');
    }

    return (primaryRef: primaryRef, chapterContent: null);
  }

  Future<void> _injectOutlineFactsAndFiles({
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    // 5.1.8 大纲实体记忆（批次72 大纲层 + 批次74 协议告知）：
    // 触发时机：用户请求章节诊断且主引用为章节、装配了 outlineRepo
    // 协议说明：无条件注入（零实体也注入）→ AI 从首轮即知晓 [YS_ENTITY] 协议，闭环可启动
    // 实体索引：有实体才注入（供 matched_entity_id/conflict_with 引用，防幻觉）
    if (content.contains(_kDiagnosisRequestMarker) &&
        primaryRef?.refType == 'chapter' &&
        _ensureOutlineService() != null) {
      try {
        final outlineService = _ensureOutlineService()!;
        messages.add(
          ChatMessage(
            role: 'system',
            content: outlineService.buildEntityProtocolContext(),
          ),
        );
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null) {
          final ctx = await outlineService.buildEntityIndexContext(
            chapter.manuscriptId,
          );
          if (ctx != null) {
            messages.add(ChatMessage(role: 'system', content: ctx));
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 大纲记忆注入失败不阻断主流程: $e');
      }
    }

    // 5.1.9 A6：时序知识图谱事实提取协议注入
    // 触发条件：章节引用 + 至少一个 fact 仓储已装配
    // 输出顺序：[YS_DIAGNOSIS] → [YS_ENTITY] → [YS_FACT] → 自然语言
    // 批次4（4.10 L4）：移除诊断标记硬约束——训练/评估/自由讨论等非诊断消息
    // 在章节会话中也注入，避免学员练习文本中的事实被漏提
    if (primaryRef?.refType == 'chapter' &&
        (_characterFactRepo != null ||
            _eventFactRepo != null ||
            _subplotFactRepo != null)) {
      messages.add(
        ChatMessage(role: 'system', content: _buildFactProtocolContext()),
      );
    }

    // 5.2 附属文件上下文注入（V3：AI 可读取书籍下所有文件）
    // 真源：chat-service.ts L311-335
    // 从 primaryRef 推 manuscriptId，列书籍下所有附属文件，格式化后注入
    try {
      String? manuscriptId;
      if (primaryRef != null) {
        if (primaryRef.refType == 'manuscript') {
          manuscriptId = primaryRef.refId;
        } else if (primaryRef.refType == 'chapter') {
          final chapter = await _chapterRepo.getChapter(primaryRef.refId);
          manuscriptId = chapter?.manuscriptId;
        }
      }
      if (manuscriptId != null) {
        final files = await _referenceRepo.listAttachedFiles(manuscriptId);
        if (files.isNotEmpty) {
          final fileInfos = files
              .map(
                (f) => AttachedFileInfo(
                  fileName: f.fileName,
                  fileRole: f.fileRole,
                  content: f.content,
                ),
              )
              .toList();
          final fileContext = _material.formatAttachedFiles(fileInfos);
          if (fileContext != null && fileContext.isNotEmpty) {
            markStage(BudgetStageNames.attachedFiles);
            messages.add(ChatMessage(role: 'system', content: fileContext));
          }
        }
      }
    } catch (e) {
      debugPrint('[SafeRun] 附属文件注入失败不阻断主流程: $e');
    }
  }
}

extension ChatServiceSendObservations on ChatService {
  Future<void> _injectChapterObservations({
    required String sessionId,
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    // 5.1.2 声线漂移检测（批次64 B62f，F10 实时化）：
    // L3 定量指纹（style_fingerprint）→ L1 实时提示
    // 触发时机：用户请求章节诊断（content 含诊断标记）且主引用为章节
    // 基线策略：首次建立；无漂移时随最新文本滑动重锚（合法演化不误报）
    // 漂移命中 → 注入本轮 prompt，AI 以提问式语言温和指出（软引导非硬拦截）
    if (content.contains(_kDiagnosisRequestMarker) &&
        primaryRef?.refType == 'chapter') {
      try {
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null) {
          final current = extractStyleFingerprint(chapter.content);
          if (current != null) {
            final baseline = await _studentModelRepo.getStyleFingerprint(
              sessionId,
            );
            final hints = (baseline == null || baseline.sentencesCount == 0)
                ? const <String>[]
                : detectVoiceDrift(baseline, current);
            if (hints.isEmpty) {
              await _studentModelRepo.updateStyleFingerprint(
                sessionId,
                current,
              );
            } else {
              messages.add(
                ChatMessage(
                  role: 'system',
                  content: _buildDriftHintContext(hints),
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 漂移检测失败不阻断主流程: $e');
      }
    }

    // 5.1.3 时序矛盾冲突观察（批次66 B62i，A6 首步，挂 F05/P018 补充）：
    // 触发时机：用户请求章节诊断且主引用为章节；人物知识仓储已装配
    // 数据源：character_fact（作品级人物断言，断言带章节/时间维度）
    // 无人物断言数据 → 无观察项 → 不注入（零 token 成本）
    if (content.contains(_kDiagnosisRequestMarker) &&
        primaryRef?.refType == 'chapter' &&
        _characterFactRepo != null) {
      try {
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null) {
          final facts = await _characterFactRepo.listCharacters(
            chapter.manuscriptId,
          );
          if (facts.isNotEmpty) {
            final inputs = facts
                .map(
                  (f) => (
                    name: f.name,
                    assertions: CharacterFactRepository.parseAssertions(
                      f.assertions,
                    ),
                  ),
                )
                .toList();
            final raw = detectCharacterConflicts(inputs);
            // O11（批次6 6.5）：正文反查最早断言值的首现片段作触发原文摘录；
            // 正文不含关键词时 excerpt 为 null，上下文降级不输出摘录
            final observations = raw
                .map(
                  (o) => ConflictObservation(
                    characterName: o.characterName,
                    attribute: o.attribute,
                    orderedValues: o.orderedValues,
                    description: o.description,
                    excerpt: findKeywordExcerpt(
                      chapter.content,
                      o.orderedValues.first.value,
                    ),
                  ),
                )
                .toList();
            final ctx = buildConflictObservationsContext(observations);
            if (ctx != null) {
              messages.add(ChatMessage(role: 'system', content: ctx));
            }
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 冲突检测失败不阻断主流程: $e');
      }
    }

    // 5.1.4 因果链断裂观察（批次67 B62j，A6 第二迭代 F07，挂 P021/P016 补充）：
    // 触发时机：用户请求章节诊断且主引用为章节；事件知识仓储已装配
    // 数据源：event_fact（作品级事件节点，带章节 + 因果边）
    // 无事件数据 → 无观察项 → 不注入（零 token 成本）
    if (content.contains(_kDiagnosisRequestMarker) &&
        primaryRef?.refType == 'chapter' &&
        _eventFactRepo != null) {
      try {
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null) {
          final events = await _eventFactRepo.listEvents(chapter.manuscriptId);
          if (events.isNotEmpty) {
            final inputs = events
                .map(
                  (e) => (
                    name: e.name,
                    chapter: e.chapter,
                    eventType: e.eventType,
                    causeEventId: e.causeEventId,
                    effectEventId: e.effectEventId,
                  ),
                )
                .toList();
            final raw = detectCausalityBreaks(inputs);
            // O11（批次6 6.5）：正文反查事件名首现片段作触发原文摘录；
            // 正文不含事件名时 excerpt 为 null，上下文降级不输出摘录
            final observations = raw
                .map(
                  (o) => CausalityBreakObservation(
                    name: o.name,
                    chapter: o.chapter,
                    eventType: o.eventType,
                    description: o.description,
                    excerpt: findKeywordExcerpt(chapter.content, o.name),
                  ),
                )
                .toList();
            final ctx = buildCausalityBreakContext(observations);
            if (ctx != null) {
              messages.add(ChatMessage(role: 'system', content: ctx));
            }
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 因果链检测失败不阻断主流程: $e');
      }
    }

    // 5.1.5 情节闭环观察（批次67 B62j，A6 第二迭代 F11，挂 P014/P017 补充）：
    // 触发时机：用户请求章节诊断且主引用为章节；支线知识仓储已装配
    // 数据源：subplot_fact（作品级支线节点，带引入/回收章节）
    // 当前章节 = 主引用章节 sortOrder；无支线数据 → 不注入（零 token 成本）
    if (content.contains(_kDiagnosisRequestMarker) &&
        primaryRef?.refType == 'chapter' &&
        _subplotFactRepo != null) {
      try {
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null) {
          final subplots = await _subplotFactRepo.listSubplots(
            chapter.manuscriptId,
          );
          if (subplots.isNotEmpty) {
            final inputs = subplots
                .map(
                  (s) => (
                    name: s.name,
                    introducedChapter: s.introducedChapter,
                    resolvedChapter: s.resolvedChapter,
                  ),
                )
                .toList();
            final raw = detectUnclosedSubplots(
              inputs,
              currentChapter: chapter.sortOrder,
            );
            // O11（批次6 6.5）：正文反查支线名首现片段作触发原文摘录；
            // 正文不含支线名时 excerpt 为 null，上下文降级不输出摘录
            final observations = raw
                .map(
                  (o) => UnclosedSubplotObservation(
                    name: o.name,
                    introducedChapter: o.introducedChapter,
                    currentChapter: o.currentChapter,
                    description: o.description,
                    excerpt: findKeywordExcerpt(chapter.content, o.name),
                  ),
                )
                .toList();
            final ctx = buildSubplotClosureContext(observations);
            if (ctx != null) {
              messages.add(ChatMessage(role: 'system', content: ctx));
            }
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 情节闭环检测失败不阻断主流程: $e');
      }
    }

    // 5.1.6 基础文法观察（批次70 F12，挂 P022 重复用词/基础语病 补充）：
    // 触发时机：用户请求章节诊断且主引用为章节
    // 数据源：章节正文（纯规则文本检测，无仓储依赖）
    // 无检出问题 → 不注入（零 token 成本）
    if (content.contains(_kDiagnosisRequestMarker) &&
        primaryRef?.refType == 'chapter') {
      try {
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null) {
          final issues = detectGrammarLexicalIssues(chapter.content);
          final ctx = buildGrammarLexicalContext(issues);
          if (ctx != null) {
            messages.add(ChatMessage(role: 'system', content: ctx));
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 基础文法检测失败不阻断主流程: $e');
      }
    }

    // 5.1.7 对话标签观察（批次71 F02，挂 P011 对话疲劳症 增强补充）：
    // 触发时机：用户请求章节诊断且主引用为章节
    // 数据源：章节正文（纯规则文本检测，无仓储依赖）
    // 无检出问题 → 不注入（零 token 成本）
    if (content.contains(_kDiagnosisRequestMarker) &&
        primaryRef?.refType == 'chapter') {
      try {
        final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
        if (chapter != null) {
          final issues = detectDialogueTagIssues(chapter.content);
          final ctx = buildDialogueTagContext(issues);
          if (ctx != null) {
            messages.add(ChatMessage(role: 'system', content: ctx));
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 对话标签检测失败不阻断主流程: $e');
      }
    }
  }
}

extension ChatServiceObservers on ChatService {
  /// D8 轻量观测：评估顺序（学员自评 → 改前改后对比 → AI 评估）
  /// 约束源为 skill 指令（skill_registry.dart 阶段3 三步评估流程），非代码强制；
  /// 此处仅 debug 级留痕「FEEDBACK 回复是否按顺序走全三步」，不改变任何行为。
  /// 检测标记：自评引导（"你自己觉得改得怎么样"类）→ 改前改后对比（唯一不可省略）
  /// → 评估三档（含"达标"字样）。观测失败不阻断主流程。
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

  /// 预加载所有引用的详情到缓存（buildReferencesContext 调用前使用）
  ///
  /// A-3 遗留 N+1 消除：原实现逐条引用各发 1~2 次查询（getChapter /
  /// getManuscript+listChapters / getAttachedFile），N 条引用最多 2N 次查询且
  /// 在每次发送的热路径上执行。改为按 refType 分组，每类单次 `WHERE id IN(...)`
  /// 批量取全（chapter 1 次 / file 1 次 / manuscript 2 次），与原实现填充的
  /// 缓存键值完全等价（ChapterBrief/ManuscriptDetail/AttachedFileRow 字段不变）。
  /// 每类批量查询独立 try/catch，保留「单类失败不阻断其它」语义；目标被删的 id
  /// 自然不在结果集，等价原 `if (ch != null)` 跳过。
  Future<void> _preloadReferenceDetails(List<ReferencedItem> refs) async {
    if (refs.isEmpty) return;

    final chapterIds = <String>[];
    final manuscriptIds = <String>[];
    final fileIds = <String>[];
    for (final ref in refs) {
      switch (ref.refType) {
        case 'chapter':
          chapterIds.add(ref.refId);
        case 'manuscript':
          manuscriptIds.add(ref.refId);
        case 'file':
          fileIds.add(ref.refId);
      }
    }

    // 章节引用：单次 WHERE id IN(...) 取全
    if (chapterIds.isNotEmpty) {
      try {
        final chapters = await _chapterRepo.getChaptersByIds(chapterIds);
        for (final ch in chapters) {
          _cachedChapters[ch.id] = ChapterBrief(
            id: ch.id,
            title: ch.title,
            wordCount: ch.wordCount,
            sortOrder: ch.sortOrder,
            content: ch.content,
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] 章节批量加载失败不阻断整体: $e');
      }
    }

    // 素材文件引用：单次 WHERE id IN(...) 取全
    if (fileIds.isNotEmpty) {
      try {
        final files = await _referenceRepo.getAttachedFilesByIds(fileIds);
        for (final f in files) {
          _cachedAttachedFiles[f.id] = f;
        }
      } catch (e) {
        debugPrint('[SafeRun] 素材批量加载失败不阻断整体: $e');
      }
    }

    // 作品引用：manuscripts 单次取全 + 其章节单次取全（2 查询替代 2N）
    if (manuscriptIds.isNotEmpty) {
      try {
        final manuscripts = await _manuscriptRepo.getManuscriptsByIds(
          manuscriptIds,
        );
        final msById = {for (final m in manuscripts) m.id: m};

        final chapters = await _chapterRepo.listChaptersForManuscripts(
          manuscriptIds,
        );
        final chaptersByMs = <String, List<ChapterBrief>>{};
        for (final ch in chapters) {
          (chaptersByMs[ch.manuscriptId] ??= []).add(
            ChapterBrief(
              id: ch.id,
              title: ch.title,
              wordCount: ch.wordCount,
              sortOrder: ch.sortOrder,
              content: ch.content,
            ),
          );
        }

        for (final id in manuscriptIds) {
          final m = msById[id];
          if (m == null) continue; // 目标被删，跳过（等价原 if(m==null) continue）
          _cachedManuscripts[id] = ManuscriptDetail(
            genre: m.genre,
            description: m.description,
            chapters: chaptersByMs[id] ?? const [],
          );
        }
      } catch (e) {
        debugPrint('[SafeRun] 作品批量加载失败不阻断整体: $e');
      }
    }
  }
}

extension ChatServiceSendParse on ChatService {
  Future<
    ({
      bool aborted,
      String displayContent,
      ParsedDiagnosis? diagnosis,
      TeacherResult? teacherResult,
      String messageId,
      String finalContent,
      List<GenUiComponent>? genuiComponents,
    })
  >
  _parseAndPersist({
    required String sessionId,
    required String fullContent,
    required bool inDiagnosisBlock,
    required ReferenceItem? primaryRef,
    required String? chapterContent,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
  }) async {
    // 9. 解析 + 第二层后置校验
    final rawParse = _diagnosis.parseDiagnosis(fullContent);
    debugPrint(
      '[ChatService] 步骤9: parseDiagnosis | displayContent 长度=${rawParse.displayContent.length} | diagnosis=${rawParse.diagnosis != null ? "有(${rawParse.diagnosis!.syndromes.length} 症候)" : "无"}',
    );

    String displayContent = rawParse.displayContent;
    ParsedDiagnosis? diagnosis = rawParse.diagnosis;

    // 步骤 9.1：大纲提取落库（批次72，独立 OUTLINE 块，失败/未装配不阻断）
    // 批次73：落库后为含 pending 印象的实体写入确认卡片
    await _applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
      primaryRef: primaryRef,
    );

    // 步骤 9.2：A6 事实提取落库（时序知识图谱写入路径，失败不阻断）
    await _applyFactExtractionFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
      primaryRef: primaryRef,
    );

    if (diagnosis != null) {
      // 提取诊断块原始 JSON 供 validator 用
      final startIndex = fullContent.indexOf(kDiagnosisStart);
      final endIndex = fullContent.indexOf(
        kDiagnosisEnd,
        startIndex + kDiagnosisStart.length,
      );
      if (startIndex != -1 && endIndex != -1) {
        final jsonStr = fullContent
            .substring(startIndex + kDiagnosisStart.length, endIndex)
            .trim();
        try {
          final rawJson = jsonDecode(jsonStr);
          final validation = _diagnosis.validateDiagnosisOutput(
            rawParse.displayContent,
            rawJson,
            attitude: options.attitude,
          );
          displayContent = validation.displayContent;
          diagnosis = validation.diagnosis;
        } catch (e) {
          debugPrint('[SafeRun] JSON 解析失败沿用 rawParse: $e');
        }
      }
    }

    // 批次74：剥离 [YS_ENTITY] 协议块（诊断缺块时 displayContent 会含原始 JSON，
    // 校验回填也可能重新引入），确保展示/落库内容不含协议原文
    displayContent = stripOutlineBlock(displayContent);
    // A6：剥离 [YS_FACT] 协议块（事实提取块，与实体块并列独立）
    displayContent = stripFactBlock(displayContent);
    // B-1：剥离 [YS_GENUI] 协议块（GenUI 组件块，独立于诊断/事实）
    displayContent = stripGenuiBlock(displayContent);
    // B-1：解析 GenUI 组件（用于后续确定性插入 genui 卡片）
    final genuiComponents = _genUi.parseGenuiBlock(fullContent);

    // B1：诊断成败记录 → 连续失败达阈值插诊断失败卡。
    // attempted 仅当 AI 确实输出了 [YS_DIAGNOSIS] 块（inDiagnosisBlock），
    // 普通聊天解析为 null 不计入，避免误触发「诊断失败」卡。
    await _recordDiagnosisOutcome(
      sessionId,
      attempted: inDiagnosisBlock,
      success: diagnosis != null,
    );

    // Diagnosis → Teacher 条件触发（C3）
    // 真源：chat-service.ts L626-655
    String teacherDisplayContent = '';
    TeacherResult? teacherResult;
    if (diagnosis != null &&
        shouldTriggerTeacherForDiagnosis(diagnosis.syndromes)) {
      try {
        final teacherStream = await callTeacherStream(
          _llmClient,
          TeacherDiagnosisInput(
            diagnosis: diagnosis,
            chapterContent: chapterContent ?? '',
          ),
          callbacks.onStream,
          cancelToken: options.cancelToken,
        );
        teacherDisplayContent = teacherStream.displayContent;
        teacherResult = teacherStream.teacher;
      } catch (e) {
        debugPrint('[SafeRun] Teacher 失败不影响 Diagnosis 已有输出: $e');
      }
    }

    // 合并 Diagnosis + Teacher 输出（RN L657-660）
    // 注意：不修改 displayContent，保留原始值供 parseTrainingResult 使用（RN L767 注释）
    final combinedContent =
        displayContent +
        (teacherDisplayContent.isNotEmpty ? '\n\n$teacherDisplayContent' : '');

    // 10. 写入 assistant 消息
    // 批次74：仅大纲装配的章节诊断才放宽空判断：
    //   - diagnosis 解析成功 或 已落库实体 → 说明可能被协议块（YS_DIAGNOSIS/YS_ENTITY）
    //     占据首位，拦截器 displayLength=0 导致 combinedContent 空 → 给默认文案「诊断完成。」继续。
    //   - 无大纲装配 或 三空齐发（说明空+诊断空+实体空）→ 维持 RN 原语义，onError。
    bool treatAsValid = false;
    if (combinedContent.trim().isEmpty &&
        _ensureOutlineService() != null &&
        primaryRef?.refType == 'chapter') {
      if (diagnosis != null) {
        treatAsValid = true;
      } else {
        final c = await _readOutlineEntityCount(primaryRef!.refId);
        if (c > 0) treatAsValid = true;
      }
    }
    if (combinedContent.trim().isEmpty && !treatAsValid) {
      debugPrint('[ChatService] 步骤10: combinedContent 为空，触发 onError');
      callbacks.onError('AI 返回为空');
      return (
        aborted: true,
        displayContent: displayContent,
        diagnosis: diagnosis,
        teacherResult: teacherResult,
        messageId: '',
        finalContent: '',
        genuiComponents: genuiComponents,
      );
    }
    final finalContent = combinedContent.trim().isEmpty
        ? '诊断完成。'
        : combinedContent;

    // P0 机器回执态（2026-08-18，ADR-P0）：教练不替用户执行「保存/导出/应用/修改」
    // 等副作用动作；若回复自称「已X」但本回合无真实机器回执，降级为「建议X」，
    // 避免「我已替你做过」的虚假承诺。receipts 仅依据本次 service 实际落库构造：
    // 诊断结构化数据已在步骤 11 commitDiagnosisWithHistory 落库，故允许「已保存」。
    final performedActions = <ReceiptAction>{
      if (diagnosis != null) ReceiptAction.saved,
    };
    final receiptResult = ReplyReceiptGuard.sanitize(
      finalContent,
      receipts: performedActions,
    );
    final assistantContent = receiptResult.text;

    final messageId = await _sessionRepo.addMessage(
      sessionId,
      'assistant',
      assistantContent,
    );
    debugPrint(
      '[ChatService] 步骤10: assistant 消息已写入 | messageId=$messageId | contentLen=${assistantContent.length}'
      "${receiptResult.status == ReceiptStatus.humanReviewPending ? ' | 回执降级: ${receiptResult.downgraded.map((a) => a.claimPhrase).join('、')}' : ''}",
    );
    return (
      aborted: false,
      displayContent: displayContent,
      diagnosis: diagnosis,
      teacherResult: teacherResult,
      messageId: messageId,
      finalContent: finalContent,
      genuiComponents: genuiComponents,
    );
  }
}

extension ChatServiceSendPersist on ChatService {
  Future<void> _commitDiagnosisAndSuggestions({
    required String sessionId,
    required ParsedDiagnosis? diagnosis,
    required String messageId,
    required ReferenceItem? primaryRef,
    required TeacherResult? teacherResult,
    required bool rapidFire,
    required bool flowBypassed,
    required List<GenUiComponent>? genuiComponents,
  }) async {
    // B-1：若有 GenUI 组件，确定性插入 genui 卡片（不阻断主流程）
    if (genuiComponents != null && genuiComponents.isNotEmpty) {
      try {
        await insertGenuiCard(
          _sessionRepo,
          sessionId,
          GenuiCardPayload(components: genuiComponents),
        );
      } catch (e) {
        debugPrint('[SafeRun] GenUI 卡片插入失败不阻断主流程: $e');
      }
    }

    // 11. 若有诊断：commitDiagnosisWithHistory + phase-mapper resolver
    if (diagnosis != null) {
      try {
        await _diagnosisService.commitDiagnosisWithHistory(
          DiagnosisInput(
            sessionId: sessionId,
            messageId: messageId,
            syndromes: diagnosis.syndromes.map((s) => s.toJson()).toList(),
            suggestedActions: diagnosis.suggestedActions,
            confidence: diagnosis.confidence,
            rootCauseAnalysis: diagnosis.rootCauseAnalysis,
            nextFocus: diagnosis.nextFocus,
            feedbackSummary: diagnosis.feedbackSummary,
            currentTeachingFocusId: diagnosis.currentTeachingFocusId,
            focusReason: diagnosis.focusReason,
            teachingMode: diagnosis.teachingMode?.value,
            targetRefType: primaryRef?.refType,
            targetRefId: primaryRef?.refId,
          ),
        );

        // 批次1（C3）：新诊断提交 = 旧训练轮终结 → 重置子阶段，防 feedback 残留
        //（阶段不变时 subphase 不再永久残留；阶段变化路径也会重置，双保险）
        try {
          await _stateRepo.updateSubphase(sessionId, null);
        } catch (e) {
          debugPrint('[SafeRun] 诊断后重置子阶段失败: $e');
        }

        // phase-mapper resolver 接线 + M4-A/M4-B/M4-C 阶段迁移（批次6 D1 抽取为共享方法）
        // 供 sendMessage 与 commitDiagnosisFromContent 复用，保证两条诊断路径行为一致
        await _applyPhaseMigration(sessionId: sessionId, diagnosis: diagnosis);

        // AUDIT-REF-5: 诊断完成后确定性插入诊断结果卡片
        // 真源：chat-service.ts L742-755
        try {
          await insertDiagnosisResultCard(
            _sessionRepo,
            sessionId,
            DiagnosisResultCardPayload(
              syndromeCount: diagnosis.syndromes.length,
              syndromes: diagnosis.syndromes
                  .map(
                    (s) => DiagnosisSyndromeCard(
                      syndromeId: s.syndromeId,
                      name: s.name,
                      severity: s.severity.value,
                      evidenceCount: s.evidence.length,
                    ),
                  )
                  .toList(),
              suggestedActions: diagnosis.suggestedActions,
              confidence: diagnosis.confidence,
              diagnosisId: messageId,
            ),
          );
        } catch (e) {
          debugPrint('[SafeRun] 诊断卡片插入失败不阻断主流程: $e');
        }

        // 批次53：诊断附带 style_profile 时沉淀写作风格画像
        // 独立 try-catch（落库失败不阻断诊断主流程）
        final styleProfile = diagnosis.styleProfile;
        if (styleProfile != null) {
          try {
            await _studentModelRepo.updateStyleProfile(sessionId, styleProfile);
          } catch (e) {
            debugPrint('[SafeRun] 风格画像落库失败不阻断主流程: $e');
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] 诊断写入失败不阻断消息存储: $e');
      }
    }

    // R6：Diagnosis 分支 Teacher suggestion 写入（两分支复用 persistTeacherSuggestion）
    // 真源：chat-service.ts L762-765（位于 if(diagnosis) 块外，独立 try-catch）
    if (teacherResult != null) {
      try {
        final suggestionId = await persistTeacherSuggestion(
          _teacherSuggestionRepo,
          teacherResult,
          sessionId,
          messageId,
          'diagnosis',
          isRapidFire: rapidFire,
        );
        // D6：建议落库成功后，写 teacher_suggestion 卡片消息（症候名称而非代号）
        // 批次1（O1）：升级阀绕过心流窗口时以轻量提示替代独立卡片——建议文本已
        // 并入 assistant 消息（combinedContent），不再重复插卡打断写作心流
        if (suggestionId != null && !flowBypassed) {
          final targetTask = teacherResult.trainingTask;
          String? targetName;
          if (targetTask?.targetSyndromeId != null && diagnosis != null) {
            targetName = diagnosis.syndromes
                .where((s) => s.syndromeId == targetTask!.targetSyndromeId)
                .map((s) => s.name)
                .firstOrNull;
          }
          try {
            await insertTeacherSuggestionCard(
              _sessionRepo,
              sessionId,
              TeacherSuggestionCardPayload(
                suggestionId: suggestionId,
                teachingDecision: teacherResult.teachingDecision,
                naturalLanguage: teacherResult.naturalLanguage,
                taskType: targetTask?.taskType ?? '',
                taskDescription: targetTask?.taskDescription ?? '',
                difficulty: targetTask?.difficulty ?? '',
                evaluationCriteria: targetTask?.evaluationCriteria ?? const [],
                targetSyndromeId: targetTask?.targetSyndromeId,
                targetSyndromeName: targetName,
                source: 'diagnosis',
                locationMarks: teacherResult.locationMarks,
              ),
            );
          } catch (e) {
            debugPrint('[SafeRun] 建议卡片插入失败不阻断主流程: $e');
          }
        }
      } catch (e) {
        debugPrint('[SafeRun] Teacher suggestion 落库失败: $e');
      }
    }
  }

  Future<void> _handleTrainingResult({
    required String sessionId,
    required TeachingSubphase? currentSubphase,
    required String displayContent,
    required String? trainingSyndromeId,
    required List<ActiveProblemView> activeProblems,
    required SendMessageCallbacks callbacks,
  }) async {
    // 11. 训练结果解析 + teaching_history 写入
    // 真源：chat-service.ts L767-793
    // 条件：subphase == FEEDBACK 且 parseTrainingResult 命中
    // trainingSyndromeId 来自 focus-resolver（步骤 6.2）
    // 注意：基于 displayContent（不含诊断块），避免误触发
    if (currentSubphase == TeachingSubphase.feedback) {
      // D8 轻量观测：评估顺序（学员自评 → 改前改后对比 → AI 评估）
      // 约束源为 skill 指令（skill_registry.dart 阶段3），非代码强制；
      // 仅 debug 留痕观测回复是否按顺序走全三步，不改变行为。
      _observeEvaluationOrder(displayContent);
      final trainingResult = _diagnosis.parseTrainingResult(displayContent);
      if (trainingResult != null) {
        try {
          if (trainingSyndromeId != null) {
            await _studentModelRepo.appendTeachingHistory(sessionId, {
              'type': 'training',
              'syndromeId': trainingSyndromeId,
              'result': trainingResult.value,
              'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
              'sessionId': sessionId,
            });
            // T3 修复：训练记录写入后，用新历史重跑 FSM 并持久化状态
            // 步骤 6.3 在 LLM 调用前评估，此时训练记录尚未写入；
            // 训练完成后需重评估，确保 FSM 状态反映最新训练结果。
            try {
              final problem = activeProblems
                  .where((p) => p.syndromeId == trainingSyndromeId)
                  .firstOrNull;
              if (problem != null) {
                final reEvalInput = await buildTrainingInputForActiveSyndrome(
                  _studentModelRepo,
                  sessionId,
                  trainingSyndromeId,
                  ActiveProblemMeta(
                    currentSeverity:
                        Severity.fromString(problem.severity) ?? Severity.l2,
                  ),
                  diagnosisRepo: _diagnosisRepo,
                );
                if (reEvalInput != null) {
                  final reEvalSummary = buildEvaluationSummary(
                    trainingSyndromeId,
                    reEvalInput,
                  );
                  if (reEvalSummary.teachingState !=
                      reEvalInput.teachingState) {
                    await _diagnosisRepo.updateTeachingState(
                      sessionId,
                      trainingSyndromeId,
                      reEvalSummary.teachingState.value,
                    );
                    if (reEvalSummary.teachingState == TeachingState.mastered) {
                      try {
                        await _diagnosisRepo.resolveSyndromesBatch(sessionId, [
                          trainingSyndromeId,
                        ]);
                      } catch (e) {
                        debugPrint('[SafeRun] 重评估resolveSyndromesBatch: $e');
                      }
                      // B1：达标→解锁同时插入阶段总结卡，汇总该症候进展
                      await _insertPhaseSummaryOnMastered(
                        sessionId,
                        trainingSyndromeId,
                        problem.syndromeName,
                        reEvalInput.passRateInput.totalCount,
                      );
                    }
                  }
                }
              }
            } catch (e) {
              debugPrint('[SafeRun] 重评估失败不阻断主流程: $e');
            }
          }
        } catch (e) {
          debugPrint('[SafeRun] 训练记录写入失败: $e');
        }
        // 批次1（C3）：训练轮终结（反馈已解析命中）→ 重置子阶段，防 feedback 残留
        // 后续含"达标/未达标"字样消息不再误归属旧训练轮
        try {
          await _stateRepo.updateSubphase(sessionId, null);
        } catch (e) {
          debugPrint('[SafeRun] 训练轮终结重置子阶段失败: $e');
        }
        // onTrainingResult 回调：通知 UI 展示训练结果（T3 接线）
        callbacks.onTrainingResult?.call(trainingResult);
      }
    }
  }
}

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
extension ChatServiceSend on ChatService {
  Future<void> _sendMessageCore(
    String sessionId,
    String content,
    SendMessageCallbacks callbacks,
    SendMessageOptions options, {
    TeachingSubphase? subphase,
  }) async {
    debugPrint(
      '[ChatService] sendMessage 开始 | session=$sessionId | content="${content.length > 50 ? '${content.substring(0, 50)}...' : content}" | phase=${options.phase} | attitude=${options.attitude}',
    );
    // 批次59/64：心流判定（Just-in-Time 触发三问第 3 问）
    // 批次64（B62g）：叠加编辑器活跃——距上一条消息 < 60s 或最近 120s 内有编辑
    // 批次1（O1）：Teacher 升级阀——某症候严重度/诊断次数达阈值时绕过心流窗口
    //（判定放在步骤 4 加载活跃症候之后，见下方 _shouldBypassFlowWindow）
    final nowAtSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      // 1. 写入用户消息
      // 批次71：@ 引用快照随 user 消息落库（气泡底部引用徽章展示 + 点击跳转）
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

      // 3. 读取 teaching state
      TeachingSubphase? currentSubphase = subphase;
      bool isBeginner = false;
      BeginnerLevel? beginnerLevel; // 批次60：技能层级软引导用
      // 批次6 M2：阶段上下文优先取 DB 持久化 currentPhase。
      // options.phase 由 UI 层硬编码（chat_page 恒为 p0Engage），可能与学员真实阶段
      // 不一致——已到 P2/P3 的学员在聊天页发消息，AI 仍按 P0 语境响应。DB 为准。
      var effectivePhase = options.phase;
      try {
        final ts = await _stateRepo.getTeachingState(sessionId);
        if (ts != null) {
          currentSubphase =
              subphase ?? TeachingSubphase.fromString(ts.currentSubphase);
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
        currentSubphase = subphase;
      }

      // 4. 加载活跃症候
      final activeProblems = await _diagnosisRepo.listActiveProblems(sessionId);
      debugPrint('[ChatService] 步骤4: 活跃症候 ${activeProblems.length} 个');

      // 批次1（O1）：Teacher 升级阀——慢性/重度症候绕过心流窗口，让建议出得来
      final flowBypassed = await _shouldBypassFlowWindow(
        sessionId,
        activeProblems,
      );
      final rapidFire = isInFlow(
        lastSendAtSec: _lastUserSendAtSec[sessionId],
        lastEditorEditAtSec: options.lastEditorEditAtSec,
        nowAtSec: nowAtSec,
        bypassFlowWindow: flowBypassed,
        // 批次6（6.8 M4）：求助关键词（不会/怎么/卡住了/没思路）命中
        // → 绕过心流抑制，主动求助及时反馈
        helpSignal: content,
      );
      _lastUserSendAtSec[sessionId] = nowAtSec;

      // 5. 拼接 system prompt（L1 + L2）
      final skillCtx = SkillLoadContext(
        phase: effectivePhase,
        attitude: options.attitude,
        subphase: currentSubphase,
        isBeginner: isBeginner,
      );
      final promptResult = _teaching.buildSystemPrompt(skillCtx);

      final messages = <ChatMessage>[
        ChatMessage(role: 'system', content: promptResult.systemPrompt),
      ];

      // 可降级阶段 → 消息索引（运行时 token 预算闸门裁剪依据，2026-08-11）
      // 只记录非保底层；systemPrompt 内嵌的 L2 组与保底阶段不记录、不裁。
      final stageIndexes = <String, List<int>>{};
      void markStage(String stage) {
        (stageIndexes[stage] ??= []).add(messages.length);
      }

      // 5.0-5.2 上下文注入（R-019 三级拆分：步骤块提取至 chat_service_send_*.dart）
      await _injectProfileAndIntents(
        sessionId: sessionId,
        content: content,
        messages: messages,
        markStage: markStage,
      );
      final refCtx = await _injectReferences(
        sessionId: sessionId,
        messages: messages,
        markStage: markStage,
      );
      final primaryRef = refCtx.primaryRef;
      final chapterContent = refCtx.chapterContent;
      await _injectChapterObservations(
        sessionId: sessionId,
        content: content,
        primaryRef: primaryRef,
        messages: messages,
      );
      await _injectOutlineFactsAndFiles(
        content: content,
        primaryRef: primaryRef,
        messages: messages,
        markStage: markStage,
      );
      final trainingSyndromeId = await _injectDiagnosisLock(
        sessionId: sessionId,
        content: content,
        activeProblems: activeProblems,
        currentSubphase: currentSubphase,
        beginnerLevel: beginnerLevel,
        messages: messages,
        markStage: markStage,
      );
      // 6.5 临场输出约束：在所有教学内容注入后、历史对话前追加
      // 真源：RN e8c46bb（表达密度提交）——利用 LLM recency bias
      // 确保表达密度规则不被后面的详细教学内容覆盖
      //（Flutter 曾缺失：三档态度 skill 表达密度小节 + 本约束，批次 41 补齐）
      // 示范规则以当前态度档位为准：doubao/yuesheng 最小示范，sensei 零示范（只给方向）
      messages.add(
        ChatMessage(role: 'system', content: kLiveOutputConstraints),
      );

      // 7. 追加历史消息
      for (final m in history) {
        markStage(BudgetStageNames.history);
        messages.add(ChatMessage(role: m.role, content: m.content));
      }

      // 批次4（4.3）：临场输出约束双保险——历史消息后再追加极简提醒。
      // 主约束在历史之前（利用 recency bias），此处兜底防止长历史稀释其优先级；
      // 只重复最核心的一条，不重复整段约束。
      messages.add(
        ChatMessage(
          role: 'system',
          content: '# 回复纪律（最后提醒）\n\n本次回复：一次只抛一个点，删掉铺垫，示范按态度档位执行。',
        ),
      );

      // 7.0 运行时 token 预算闸门（2026-08-11 体检落地）
      // 总估算超 maxBudget 时按 TokenBudgetTable.planDegradation() 顺序
      // 整段裁掉已标记的可降级阶段；超 warning 线不裁仅提示。
      final guardReport = TokenBudgetGuard.apply(
        messages,
        stageIndexes: stageIndexes,
      );
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
      debugPrint(
        '[ChatService] 步骤7: 发送到 LLM 的 messages 数量=${messages.length}（含 system + history）',
      );

      // 8. 流式调用 + 拦截诊断块（R-019：提取为 _streamLlm）
      final streamResult = await _streamLlm(
        messages: messages,
        callbacks: callbacks,
        options: options,
      );
      final fullContent = streamResult.fullContent;
      final inDiagnosisBlock = streamResult.inDiagnosisBlock;

      // 9-10. 解析 + 校验 + 落库（R-019：提取为 _parseAndPersist）
      final parsed = await _parseAndPersist(
        sessionId: sessionId,
        fullContent: fullContent,
        inDiagnosisBlock: inDiagnosisBlock,
        primaryRef: primaryRef,
        chapterContent: chapterContent,
        callbacks: callbacks,
        options: options,
      );
      // 步骤 10 空响应提前结束（onError 已触发，等价原 return）
      if (parsed.aborted) return;

      // 11. 诊断提交 + Teacher suggestion + GenUI 卡片（R-019：提取为 _commitDiagnosisAndSuggestions）
      await _commitDiagnosisAndSuggestions(
        sessionId: sessionId,
        diagnosis: parsed.diagnosis,
        messageId: parsed.messageId,
        primaryRef: primaryRef,
        teacherResult: parsed.teacherResult,
        rapidFire: rapidFire,
        flowBypassed: flowBypassed,
        genuiComponents: parsed.genuiComponents,
      );
      // 批次50 临时测量：回复长度观测（决策前置：先量化 standard 档是否真超长）
      // 仅 debug 留痕不干预；批次 52 汇成节奏体检报告后按结论处置。
      _observeReplyLength(
        parsed.displayContent,
        content,
        options.attitude,
        currentSubphase,
      );

      // 11. 训练结果解析 + teaching_history 写入（R-019：提取为 _handleTrainingResult）
      await _handleTrainingResult(
        sessionId: sessionId,
        currentSubphase: currentSubphase,
        displayContent: parsed.displayContent,
        trainingSyndromeId: trainingSyndromeId,
        activeProblems: activeProblems,
        callbacks: callbacks,
      );
      await callbacks.onComplete(parsed.finalContent, parsed.messageId);
      debugPrint('[ChatService] sendMessage 完成 | onComplete 已触发');
    } catch (e) {
      debugPrint('[ChatService] sendMessage 异常: $e');
      // 区分「用户主动取消」与「真实失败」：取消是预期行为，
      // 走 onCancelled 让 UI 优雅复位（不标记消息失败、不弹红错）；
      // 其余异常走 onError。
      final cancelled =
          e is LlmRequestCancelledException ||
          (options.cancelToken?.isCancelled ?? false);
      if (cancelled) {
        callbacks.onCancelled?.call();
      } else {
        callbacks.onError(e is Exception ? e.toString() : '发送失败');
      }
    }
  }
}
