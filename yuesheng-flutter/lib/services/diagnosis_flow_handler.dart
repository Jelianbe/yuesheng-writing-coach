// ─────────────────────────────────────────────────────────────
// DiagnosisFlowHandler — 诊断流编排器（独立类）
//
// ADR-C74 批次 K-9 拆分重构产物。从 ChatService 抽出 sendMessage
// 主流程中 4 个诊断链路方法（聚类 B 诊断链）：
//   - commitDiagnosisFromContent（公开委派，K-9 后续可瘦身）
//   - _parseAndPersist
//   - _commitDiagnosisAndSuggestions
//   - _handleTrainingResult
//
// 字段依赖建模原则（同 DiagnosisCommitter / MessageInjector 样板）：
//   - 必备依赖（required）：10 个仓储 / 服务 / 编排器
//   - 可选依赖（X-041c 模式）：1 个 nullable 仓储，不装配则跳过对应落库
//   - 能力（capability 注入）：1 个 DiagnosisCapability
//   - 内部状态：1 个按 session 隔离的连续失败计数（来自 ChatService K-1 迁出）
//
// 实施节奏（K-9）：
//   K-9：迁 4 个诊断链方法 + _recordDiagnosisOutcome helper + _diagnosisDropLog
//        + _readOutlineEntityCount helper
//
// 关键不变量：
//   - chatServiceProvider 注入本类实例；ChatService 改为委派
//   - 与 MessageInjector（K-7）/ DiagnosisCommitter（K-1 ~ K-5）同源同构
//   - X-025-ARCH 教训：必须是「独立类 + DI」模式，不可用 extension 拆分
// ─────────────────────────────────────────────────────────────

// 私有字段（_xxx）+ 公开命名参数（xxx）模式无法用 initializing formal
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/contracts/genui_capability.dart'
    show GenUiCapability, GenUiComponent;
import 'package:writingcoach/contracts/reference_capability.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart'
    show ActiveProblemView, DiagnosisInput, DiagnosisRepository;
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/teacher_suggestion_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/data/repositories/training_result_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show ReferenceItem;
import 'package:writingcoach/services/chat_gates.dart'
    show persistTeacherSuggestion, shouldTriggerTeacherForDiagnosis;
import 'package:writingcoach/services/chat_message_types.dart'
    show SendMessageCallbacks, SendMessageOptions;
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/diagnosis_parser.dart';
import 'package:writingcoach/services/diagnosis_service.dart';
import 'package:writingcoach/services/fact_parser.dart' show stripFactBlock;
import 'package:writingcoach/services/genui_parser.dart' show stripGenuiBlock;
import 'package:writingcoach/services/llm_client.dart';
import 'package:writingcoach/services/message_card_service.dart'
    show
        DiagnosisResultCardPayload,
        DiagnosisSyndromeCard,
        GenuiCardPayload,
        PhaseSummaryCardPayload,
        TeacherSuggestionCardPayload,
        insertDiagnosisFailedCard,
        insertDiagnosisResultCard,
        insertGenuiCard,
        insertTeacherSuggestionCard;
import 'package:writingcoach/services/message_injector.dart';
import 'package:writingcoach/services/outline_parser.dart'
    show stripOutlineBlock;
import 'package:writingcoach/services/outline_service.dart';
import 'package:writingcoach/services/reply_receipt_guard.dart';
import 'package:writingcoach/services/teacher_service.dart'
    show TeacherDiagnosisInput, callTeacherStream;
import 'package:writingcoach/services/teacher_validator.dart'
    show TeacherResult;
import 'package:writingcoach/services/training_evaluator.dart'
    show buildEvaluationSummary;
import 'package:writingcoach/services/training_input_builder.dart'
    show ActiveProblemMeta, buildTrainingInputForActiveSyndrome;
import 'package:writingcoach/types/teaching_types.dart';

/// K-9 parseAndPersist 聚合返回（record 具名化，字段访问方式不变）。
typedef ParseAndPersistResult = ({
  bool aborted,
  String displayContent,
  ParsedDiagnosis? diagnosis,
  TeacherResult? teacherResult,
  String messageId,
  String finalContent,
  List<GenUiComponent>? genuiComponents,
});

/// K-9 中间结果：解析 + 校验 + 协议剥离后的诊断输出。
/// C78 批次3：factCount / factManuscriptId = 本轮净新增人物断言（FR-10）。
typedef _ParsedOutput = ({
  String displayContent,
  ParsedDiagnosis? diagnosis,
  List<GenUiComponent>? genuiComponents,
  int factCount,
  String? factManuscriptId,
});

/// K-9 中间结果：Teacher 触发输出。
typedef _TeacherOutcome = ({String displayContent, TeacherResult? teacher});

/// 诊断流编排器
///
/// sendMessage 主流程中 4 个诊断链路方法（步骤 9-11：解析 + 持久化 + 卡片 +
/// 训练结果）的独立持有者。通过 callbacks / output record 参数与 chat_service
/// 主链解耦。
class DiagnosisFlowHandler {
  // ─── 必备依赖（聚类 B 共性）───
  final SessionRepository _sessionRepo;
  final TeachingStateRepository _stateRepo;
  final DiagnosisRepository _diagnosisRepo;
  final StudentModelRepository _studentModelRepo;
  final ReferenceCapability _referenceRepo;
  final ChapterRepository _chapterRepo;
  final TeacherSuggestionRepository _teacherSuggestionRepo;
  final LlmClient _llmClient;
  final DiagnosisService _diagnosisService;
  final DiagnosisCommitter _diagnosisCommitter;
  final MessageInjector _messageInjector;

  // ─── 可选依赖（X-041c 模式：nullable，不装配则跳过对应落库）───
  final TrainingResultRepository? _trainingResultRepo;

  // ─── 能力（capability 注入）───
  final DiagnosisCapability _diagnosis;
  final GenUiCapability _genUi;

  // ─── 可选仓储：装配后启用大纲服务懒加载 ───
  final OutlineRepository? _outlineRepo;

  /// 大纲服务懒加载缓存（K-9 从 ChatService._ensureOutlineService 迁出）
  OutlineService? _outlineService;

  /// C78 批次3（FR-10）：批次沉淀回调——messageId 已知后登记
  /// （count, manuscriptId）到内存态注册表（ADR-C78 冲突 C：不落库）。
  /// 可选装配；回调形状与 fact_batch_providers.OnFactBatch 结构一致
  /// （服务层不 import providers，依赖方向保持 services ← 上层装配）。
  final void Function({
    required String messageId,
    required int count,
    required String? manuscriptId,
  })?
  _onFactBatch;

  /// B1：诊断连续失败计数（来自 ChatService K-1 迁出，按 session 隔离）。
  /// 用于诊断失败卡阈值门控——连续失败达 UILimits.failureWarningThreshold 才插卡，
  /// 避免偶发单次失败也打扰用户；普通聊天（非诊断轮次）不计入。
  final Map<String, int> _consecutiveDiagnosisFails = {};

  DiagnosisFlowHandler({
    required SessionRepository sessionRepo,
    required TeachingStateRepository stateRepo,
    required DiagnosisRepository diagnosisRepo,
    required StudentModelRepository studentModelRepo,
    required ReferenceCapability referenceRepo,
    required ChapterRepository chapterRepo,
    required TeacherSuggestionRepository teacherSuggestionRepo,
    required LlmClient llmClient,
    required DiagnosisCommitter diagnosisCommitter,
    required MessageInjector messageInjector,
    required DiagnosisCapability diagnosis,
    required GenUiCapability genUi,
    TrainingResultRepository? trainingResultRepo,
    OutlineRepository? outlineRepo,
    void Function({
      required String messageId,
      required int count,
      required String? manuscriptId,
    })?
    onFactBatch,
  }) : _sessionRepo = sessionRepo,
       _stateRepo = stateRepo,
       _diagnosisRepo = diagnosisRepo,
       _studentModelRepo = studentModelRepo,
       _referenceRepo = referenceRepo,
       _chapterRepo = chapterRepo,
       _teacherSuggestionRepo = teacherSuggestionRepo,
       _llmClient = llmClient,
       _diagnosisService = DiagnosisService(
         diagnosisRepo: diagnosisRepo,
         studentModelRepo: studentModelRepo,
       ),
       _diagnosisCommitter = diagnosisCommitter,
       _messageInjector = messageInjector,
       _diagnosis = diagnosis,
       _genUi = genUi,
       _trainingResultRepo = trainingResultRepo,
       _outlineRepo = outlineRepo,
       _onFactBatch = onFactBatch;

  /// FR-10：count > 0 才登记（无新增不发提示卡——「沉淀 N 条」必须真实）。
  void _notifyFactBatch({
    required String messageId,
    required int count,
    required String? manuscriptId,
  }) {
    if (count <= 0) return;
    _onFactBatch?.call(
      messageId: messageId,
      count: count,
      manuscriptId: manuscriptId,
    );
  }

  // ════════════════════════════════════════════════════════════
  // Helpers
  // ════════════════════════════════════════════════════════════

  /// 懒加载大纲服务（批次7 O2，从 ChatService._ensureOutlineService 迁出）
  OutlineService? _ensureOutlineService() {
    _outlineService ??= _outlineRepo != null
        ? OutlineService(_outlineRepo)
        : null;
    return _outlineService;
  }

  /// 诊断块被拒 / 字段静默丢弃的日志片段（ADR-C63，N1 / N26）。
  String _diagnosisDropLog(ParseResult r) {
    if (r.rejectReason == null && r.notes.isEmpty) return '';
    final parts = <String>[];
    if (r.rejectReason != null) {
      parts.add('被拒原因=${r.rejectReason}');
    }
    if (r.notes.isNotEmpty) {
      parts.add('静默丢弃=${r.notes.join(",")}');
    }
    return ' | ${parts.join(" | ")}';
  }

  /// B1：诊断失败卡阈值门控（B1，从 ChatService._recordDiagnosisOutcome 迁出）。
  ///
  /// [attempted] 表示该轮是否确实发起了诊断（AI 输出含 [YS_DIAGNOSIS] 块，
  /// 或走显式诊断链路 commitDiagnosisFromContent）。仅当 attempted && !success
  /// 才计为一次失败，普通聊天（解析为 null）不会误触发。
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

  /// 批次74：快速读取某章节对应手稿下的实体数（从 extension ChatServiceDiagnosis
  /// 迁出）。仅用于 _parseAndPersist combinedContent 空时判真故障。
  Future<int> _readOutlineEntityCount(String chapterId) async {
    try {
      final outlineService = _ensureOutlineService();
      if (outlineService == null) return 0;
      final chapter = await _chapterRepo.getChapter(chapterId);
      if (chapter == null) return 0;
      final ctx = await outlineService.buildEntityIndexContext(
        chapter.manuscriptId,
      );
      if (ctx == null) return 0;
      return '\n$ctx'.split('\n- [').length - 1;
    } catch (e) {
      debugPrint('[SafeRun] 大纲实体检索计数失败: $e');
      return 0;
    }
  }

  // ════════════════════════════════════════════════════════════
  // 4 个诊断链方法 — 4 步委派 + 1 公开 API
  // ════════════════════════════════════════════════════════════

  /// 公开 API：处理分块诊断生成的完整 AI 输出（D4-A）。
  ///
  /// 当 runProgressiveDiagnosis 返回非 null 时，由 WritingCoachPanel 调用。
  /// 复用 sendMessage 的步骤 9-11（解析 + 持久化 + 卡片），不含 Teacher 触发。
  Future<String> commitDiagnosisFromContent({
    required String sessionId,
    required String fullContent,
  }) async {
    // 步骤 9: 解析诊断
    final rawParse = _diagnosis.parseDiagnosis(fullContent);
    final parsed = await _parseDiagnosisFromContent(
      fullContent: fullContent,
      rawParse: rawParse,
    );
    final persisted = await _persistOutlineAndStrip(
      sessionId: sessionId,
      fullContent: fullContent,
      displayContent: parsed.displayContent,
    );
    final messageId = await _writeAssistantMessage(
      sessionId,
      persisted.cleaned,
    );
    // C78 批次3（FR-10）：messageId 已知 → 登记批次提示卡（内存态）
    _notifyFactBatch(
      messageId: messageId,
      count: persisted.factCount,
      manuscriptId: persisted.factManuscriptId,
    );
    final diagnosis = parsed.diagnosis;

    // 步骤 11: 持久化诊断结果 + 卡片
    if (diagnosis != null) {
      await _persistDiagnosisFromContent(
        sessionId: sessionId,
        messageId: messageId,
        diagnosis: diagnosis,
      );
    }

    // B1：诊断连续失败计数（attempted 恒 true）
    await _recordDiagnosisOutcome(
      sessionId,
      attempted: true,
      success: diagnosis != null,
    );

    return messageId;
  }

  /// 私有 helper：解析 + 第二层 JSON 校验（提取自 commitDiagnosisFromContent）。
  Future<({String displayContent, ParsedDiagnosis? diagnosis})>
  _parseDiagnosisFromContent({
    required String fullContent,
    required ParseResult rawParse,
  }) async {
    // ADR-C63：仅在有异常时输出，正常路径不增加噪声
    final dropLog = _diagnosisDropLog(rawParse);
    if (dropLog.isNotEmpty) {
      debugPrint('[ChatService] commitDiagnosisFromContent 解析诊断$dropLog');
    }
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
    return (displayContent: displayContent, diagnosis: diagnosis);
  }

  /// 私有 helper：大纲/事实沉淀 + 协议块剥离（提取自 commitDiagnosisFromContent）。
  /// C78 批次3：返回剥离后内容 + 本轮净新增人物断言（FR-10，messageId 生成后登记）。
  Future<({String cleaned, int factCount, String? factManuscriptId})>
  _persistOutlineAndStrip({
    required String sessionId,
    required String fullContent,
    required String displayContent,
  }) async {
    // 批次74 A1：D4-A 渐进诊断也沉淀大纲 + 写确认卡
    await _diagnosisCommitter.applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );
    // A6：D4-A 路径也沉淀事实到 TKG 三表
    final outcome = await _diagnosisCommitter.applyFactExtractionFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
    );
    // 批次74：剥离 [YS_ENTITY] 协议块（防原始 JSON 落库）
    var cleaned = stripOutlineBlock(displayContent);
    // A6：剥离 [YS_FACT] 协议块
    cleaned = stripFactBlock(cleaned);
    return (
      cleaned: cleaned,
      factCount: outcome.count,
      factManuscriptId: outcome.manuscriptId,
    );
  }

  /// 私有 helper：写入 assistant 消息（提取自 commitDiagnosisFromContent）。
  Future<String> _writeAssistantMessage(
    String sessionId,
    String displayContent,
  ) async {
    var content = displayContent;
    if (content.trim().isEmpty) {
      content = '诊断完成';
    }
    final messageId = await _sessionRepo.addMessage(
      sessionId,
      'assistant',
      content,
    );
    debugPrint(
      '[ChatService] commitDiagnosisFromContent: assistant 消息已写入 | messageId=$messageId | contentLen=${content.length}',
    );
    return messageId;
  }

  /// 私有 helper：解析主引用（提取自 commitDiagnosisFromContent）。
  Future<({String? refType, String? refId})> _resolvePrimaryRef(
    String sessionId,
  ) async {
    try {
      final refs = await _referenceRepo.listReferences(sessionId);
      if (refs.isNotEmpty) {
        final primary = refs.firstWhere(
          (r) => r.isPrimary == 1,
          orElse: () => refs.first,
        );
        return (refType: primary.refType, refId: primary.refId);
      }
    } catch (e) {
      debugPrint('[SafeRun] commitDiagnosisFromContent 引用查询失败: $e');
    }
    return (refType: null, refId: null);
  }

  /// 私有 helper：诊断结果持久化 + 卡片（提取自 commitDiagnosisFromContent）。
  Future<void> _persistDiagnosisFromContent({
    required String sessionId,
    required String messageId,
    required ParsedDiagnosis diagnosis,
  }) async {
    final ref = await _resolvePrimaryRef(sessionId);
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
          targetRefType: ref.refType,
          targetRefId: ref.refId,
        ),
      );
      try {
        await _stateRepo.updateSubphase(sessionId, null);
      } catch (e) {
        debugPrint('[SafeRun] commitDiagnosisFromContent 诊断后重置子阶段失败: $e');
      }
      await _persistStyleProfileIfAny(sessionId, diagnosis.styleProfile);
      await _commitDiagnosisCardAndPhaseMig(
        sessionId: sessionId,
        diagnosis: diagnosis,
        messageId: messageId,
      );
    } catch (e) {
      debugPrint('[SafeRun] commitDiagnosisFromContent 诊断写入失败: $e');
    }
  }

  /// 私有 helper：从 commitDiagnosisFromContent 抽出「卡片插入 + 阶段迁移」段
  /// （保持 R-019 ≤ 50 行）。
  Future<void> _commitDiagnosisCardAndPhaseMig({
    required String sessionId,
    required ParsedDiagnosis diagnosis,
    required String messageId,
  }) async {
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
    await _diagnosisCommitter.applyPhaseMigration(
      sessionId: sessionId,
      diagnosis: diagnosis,
    );
  }

  /// 步骤 9-10：解析 + 第二层后置校验 + Teacher 触发 + assistant 消息落库。
  /// 返回 parsed record（含 diagnosis / teacherResult / messageId / abort 标志）。
  Future<ParseAndPersistResult> parseAndPersist({
    required String sessionId,
    required String fullContent,
    required bool inDiagnosisBlock,
    required ReferenceItem? primaryRef,
    required String? chapterContent,
    required SendMessageCallbacks callbacks,
    required SendMessageOptions options,
    bool diagnosisOnly = false,
  }) async {
    final parsed = await _parseAndValidate(
      sessionId: sessionId,
      fullContent: fullContent,
      inDiagnosisBlock: inDiagnosisBlock,
      primaryRef: primaryRef,
      options: options,
    );
    final teacher = parsed.diagnosis != null
        ? await _triggerTeacherForDiagnosis(
            sessionId: sessionId,
            diagnosis: parsed.diagnosis!,
            chapterContent: chapterContent,
            options: options,
            callbacks: callbacks,
            diagnosisOnly: diagnosisOnly,
          )
        : (displayContent: '', teacher: null);
    return _persistParsedOutput(
      sessionId: sessionId,
      parsed: parsed,
      teacher: teacher,
      primaryRef: primaryRef,
      callbacks: callbacks,
    );
  }

  /// 私有 helper：解析 + 大纲/事实沉淀 + 二次校验 + 协议剥离（parseAndPersist 前段）。
  Future<_ParsedOutput> _parseAndValidate({
    required String sessionId,
    required String fullContent,
    required bool inDiagnosisBlock,
    required ReferenceItem? primaryRef,
    required SendMessageOptions options,
  }) async {
    final rawParse = _diagnosis.parseDiagnosis(fullContent);
    debugPrint(
      '[ChatService] 步骤9: parseDiagnosis | displayContent 长度=${rawParse.displayContent.length} | diagnosis=${rawParse.diagnosis != null ? "有(${rawParse.diagnosis!.syndromes.length} 症候)" : "无"}'
      '${_diagnosisDropLog(rawParse)}',
    );
    var displayContent = rawParse.displayContent;
    ParsedDiagnosis? diagnosis = rawParse.diagnosis;

    final factOutcome = await _persistContentArtifacts(
      sessionId: sessionId,
      fullContent: fullContent,
      primaryRef: primaryRef,
    );

    final validated = _validateDiagnosisBlock(
      fullContent: fullContent,
      rawParse: rawParse,
      displayContent: displayContent,
      diagnosis: diagnosis,
      attitude: options.attitude,
    );
    displayContent = validated.displayContent;
    diagnosis = validated.diagnosis;

    // 协议块剥离 + GenUI 解析
    displayContent = _stripProtocolBlocks(displayContent);
    final genuiComponents = _genUi.parseGenuiBlock(fullContent);

    // B1：诊断成败记录
    await _recordDiagnosisOutcome(
      sessionId,
      attempted: inDiagnosisBlock,
      success: diagnosis != null,
    );

    return (
      displayContent: displayContent,
      diagnosis: diagnosis,
      genuiComponents: genuiComponents,
      factCount: factOutcome.count,
      factManuscriptId: factOutcome.manuscriptId,
    );
  }

  /// 协议块剥离（R-019 真分解：三个协议块剥离聚合为一处）。
  String _stripProtocolBlocks(String content) {
    var cleaned = stripOutlineBlock(content);
    cleaned = stripFactBlock(cleaned);
    cleaned = stripGenuiBlock(cleaned);
    return cleaned;
  }

  /// 诊断展示内容 + Teacher 展示内容拼接（空段不加换行）。
  String _combineDisplayContent(_ParsedOutput parsed, _TeacherOutcome teacher) {
    return parsed.displayContent +
        (teacher.displayContent.isNotEmpty
            ? '\n\n${teacher.displayContent}'
            : '');
  }

  /// 私有 helper：大纲实体 + 事实提取沉淀（parseAndPersist 前段）。
  /// C78 批次3：返回事实提取结果（净新增条数 + 作品ID，FR-10）。
  Future<({int count, String? manuscriptId})> _persistContentArtifacts({
    required String sessionId,
    required String fullContent,
    required ReferenceItem? primaryRef,
  }) async {
    await _diagnosisCommitter.applyOutlineEntitiesFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
      primaryRef: primaryRef,
    );
    return _diagnosisCommitter.applyFactExtractionFromContent(
      sessionId: sessionId,
      fullContent: fullContent,
      primaryRef: primaryRef,
    );
  }

  /// 私有 helper：诊断块 JSON 二次校验（parseAndPersist 前段）。
  ({String displayContent, ParsedDiagnosis? diagnosis})
  _validateDiagnosisBlock({
    required String fullContent,
    required ParseResult rawParse,
    required String displayContent,
    required ParsedDiagnosis? diagnosis,
    required AttitudeLevel attitude,
  }) {
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
            attitude: attitude,
          );
          return (
            displayContent: validation.displayContent,
            diagnosis: validation.diagnosis,
          );
        } catch (e) {
          debugPrint('[SafeRun] JSON 解析失败沿用 rawParse: $e');
        }
      }
    }
    return (displayContent: displayContent, diagnosis: diagnosis);
  }

  /// 私有 helper：Diagnosis → Teacher 条件触发（C3，parseAndPersist 中段）。
  Future<_TeacherOutcome> _triggerTeacherForDiagnosis({
    required String sessionId,
    required ParsedDiagnosis diagnosis,
    required String? chapterContent,
    required SendMessageOptions options,
    required SendMessageCallbacks callbacks,
    required bool diagnosisOnly,
  }) async {
    String teacherDisplayContent = '';
    TeacherResult? teacherResult;
    if (shouldTriggerTeacherForDiagnosis(diagnosis.syndromes) &&
        !diagnosisOnly) {
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
    return (displayContent: teacherDisplayContent, teacher: teacherResult);
  }

  /// 私有 helper：combinedContent + 空响应判真 + 写消息（parseAndPersist 后段）。
  Future<ParseAndPersistResult> _persistParsedOutput({
    required String sessionId,
    required _ParsedOutput parsed,
    required _TeacherOutcome teacher,
    required ReferenceItem? primaryRef,
    required SendMessageCallbacks callbacks,
  }) async {
    final combinedContent = _combineDisplayContent(parsed, teacher);
    final resolved = await _resolveFinalAssistantContent(
      sessionId: sessionId,
      combinedContent: combinedContent,
      diagnosis: parsed.diagnosis,
      primaryRef: primaryRef,
    );
    if (resolved.aborted) {
      debugPrint('[ChatService] 步骤10: combinedContent 为空，触发 onError');
      callbacks.onError('AI 返回为空');
      return _abortedResult(
        displayContent: parsed.displayContent,
        diagnosis: parsed.diagnosis,
        teacherResult: teacher.teacher,
        genuiComponents: parsed.genuiComponents,
      );
    }
    final messageId = await _sessionRepo.addMessage(
      sessionId,
      'assistant',
      resolved.assistantContent,
    );
    debugPrint(
      '[ChatService] 步骤10: assistant 消息已写入 | messageId=$messageId | contentLen=${resolved.assistantContent.length}${resolved.receiptNote}',
    );
    // C78 批次3（FR-10）：messageId 已知 → 登记批次提示卡（内存态）
    _notifyFactBatch(
      messageId: messageId,
      count: parsed.factCount,
      manuscriptId: parsed.factManuscriptId,
    );
    return (
      aborted: false,
      displayContent: parsed.displayContent,
      diagnosis: parsed.diagnosis,
      teacherResult: teacher.teacher,
      messageId: messageId,
      finalContent: resolved.finalContent,
      genuiComponents: parsed.genuiComponents,
    );
  }

  /// 私有 helper：空响应判真故障 + 回执（parseAndPersist 后段）。
  Future<
    ({
      bool aborted,
      String finalContent,
      String assistantContent,
      String receiptNote,
    })
  >
  _resolveFinalAssistantContent({
    required String sessionId,
    required String combinedContent,
    required ParsedDiagnosis? diagnosis,
    required ReferenceItem? primaryRef,
  }) async {
    bool treatAsValid = false;
    if (combinedContent.trim().isEmpty) {
      if (diagnosis != null) {
        treatAsValid = true;
      } else if (_ensureOutlineService() != null &&
          primaryRef?.refType == 'chapter') {
        final c = await _readOutlineEntityCount(primaryRef!.refId);
        if (c > 0) treatAsValid = true;
      }
    }
    if (combinedContent.trim().isEmpty && !treatAsValid) {
      return (
        aborted: true,
        finalContent: '',
        assistantContent: '',
        receiptNote: '',
      );
    }
    final finalContent = combinedContent.trim().isEmpty
        ? '诊断完成。'
        : combinedContent;
    final performedActions = <ReceiptAction>{
      if (diagnosis != null) ReceiptAction.saved,
    };
    final receiptResult = ReplyReceiptGuard.sanitize(
      finalContent,
      receipts: performedActions,
    );
    final note = receiptResult.status == ReceiptStatus.humanReviewPending
        ? ' | 回执降级: ${receiptResult.downgraded.map((a) => a.claimPhrase).join('、')}'
        : '';
    return (
      aborted: false,
      finalContent: finalContent,
      assistantContent: receiptResult.text,
      receiptNote: note,
    );
  }

  /// 私有 helper：空响应中止结果（parseAndPersist 后段）。
  ParseAndPersistResult _abortedResult({
    required String displayContent,
    required ParsedDiagnosis? diagnosis,
    required TeacherResult? teacherResult,
    required List<GenUiComponent>? genuiComponents,
  }) {
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

  /// 步骤 11：诊断提交 + Teacher suggestion + GenUI 卡片。
  Future<void> commitDiagnosisAndSuggestions({
    required String sessionId,
    required ParsedDiagnosis? diagnosis,
    required String messageId,
    required ReferenceItem? primaryRef,
    required TeacherResult? teacherResult,
    required bool rapidFire,
    required bool flowBypassed,
    required List<GenUiComponent>? genuiComponents,
  }) async {
    // B-1：GenUI 卡片插入
    await _insertGenuiCardIfAny(sessionId, genuiComponents);

    // 11：诊断提交 + 阶段迁移 + 诊断结果卡 + 风格画像
    if (diagnosis != null) {
      await _commitDiagnosisWithCard(
        sessionId: sessionId,
        diagnosis: diagnosis,
        messageId: messageId,
        primaryRef: primaryRef,
      );
    }

    // Teacher suggestion 写入（两路径复用）
    if (teacherResult != null) {
      await _persistTeacherSuggestionIfAny(
        sessionId: sessionId,
        teacherResult: teacherResult,
        messageId: messageId,
        diagnosis: diagnosis,
        rapidFire: rapidFire,
        flowBypassed: flowBypassed,
      );
    }
  }

  /// 私有 helper：GenUI 卡片插入（失败不阻断）。
  Future<void> _insertGenuiCardIfAny(
    String sessionId,
    List<GenUiComponent>? genuiComponents,
  ) async {
    if (genuiComponents == null || genuiComponents.isEmpty) return;
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

  /// 私有 helper：诊断历史提交 + 阶段迁移 + 诊断结果卡。
  Future<void> _commitDiagnosisWithCard({
    required String sessionId,
    required ParsedDiagnosis diagnosis,
    required String messageId,
    required ReferenceItem? primaryRef,
  }) async {
    try {
      await _diagnosisService.commitDiagnosisWithHistory(
        _buildDiagnosisInput(
          sessionId: sessionId,
          messageId: messageId,
          diagnosis: diagnosis,
          primaryRef: primaryRef,
        ),
      );
      try {
        await _stateRepo.updateSubphase(sessionId, null);
      } catch (e) {
        debugPrint('[SafeRun] 诊断后重置子阶段失败: $e');
      }
      await _diagnosisCommitter.applyPhaseMigration(
        sessionId: sessionId,
        diagnosis: diagnosis,
      );
      await _insertDiagnosisResultCard(
        sessionId: sessionId,
        diagnosis: diagnosis,
        messageId: messageId,
      );
      await _persistStyleProfileIfAny(sessionId, diagnosis.styleProfile);
    } catch (e) {
      debugPrint('[SafeRun] 诊断写入失败不阻断消息存储: $e');
    }
  }

  /// 私有 helper：构造诊断落库输入（消除超长参数列表）。
  DiagnosisInput _buildDiagnosisInput({
    required String sessionId,
    required String messageId,
    required ParsedDiagnosis diagnosis,
    required ReferenceItem? primaryRef,
  }) {
    return DiagnosisInput(
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
    );
  }

  /// 私有 helper：风格画像落库（失败不阻断）。
  Future<void> _persistStyleProfileIfAny(
    String sessionId,
    WritingStyleProfile? styleProfile,
  ) async {
    if (styleProfile == null) return;
    try {
      await _studentModelRepo.updateStyleProfile(sessionId, styleProfile);
    } catch (e) {
      debugPrint('[SafeRun] 风格画像落库失败不阻断主流程: $e');
    }
  }

  /// 私有 helper：Teacher suggestion 落库 + 卡片。
  Future<void> _persistTeacherSuggestionIfAny({
    required String sessionId,
    required TeacherResult teacherResult,
    required String messageId,
    required ParsedDiagnosis? diagnosis,
    required bool rapidFire,
    required bool flowBypassed,
  }) async {
    try {
      final suggestionId = await persistTeacherSuggestion(
        _teacherSuggestionRepo,
        teacherResult,
        sessionId,
        messageId,
        'diagnosis',
        isRapidFire: rapidFire,
      );
      if (suggestionId != null && !flowBypassed) {
        await _insertTeacherSuggestionCard(
          sessionId: sessionId,
          teacherResult: teacherResult,
          suggestionId: suggestionId,
          diagnosis: diagnosis,
        );
      }
    } catch (e) {
      debugPrint('[SafeRun] Teacher suggestion 落库失败: $e');
    }
  }

  /// 私有 helper：插入诊断结果卡（保持 commitDiagnosisAndSuggestions ≤ 50 行）。
  Future<void> _insertDiagnosisResultCard({
    required String sessionId,
    required ParsedDiagnosis diagnosis,
    required String messageId,
  }) async {
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
  }

  /// 私有 helper：插入 Teacher 建议卡片（保持 ≤ 50 行）。
  Future<void> _insertTeacherSuggestionCard({
    required String sessionId,
    required TeacherResult teacherResult,
    required String suggestionId,
    required ParsedDiagnosis? diagnosis,
  }) async {
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

  /// 步骤 11（FEEDBACK）：训练结果解析 + teaching_history 写入 +
  /// 训练后 FSM 重评估 + 达标卡插入 + training_results 持久化。
  Future<void> handleTrainingResult({
    required String sessionId,
    required TeachingSubphase? currentSubphase,
    required String displayContent,
    required String userContent,
    required String? trainingSyndromeId,
    required List<ActiveProblemView> activeProblems,
    required SendMessageCallbacks callbacks,
  }) async {
    if (currentSubphase != TeachingSubphase.feedback) return;

    final trainingResult = _diagnosis.parseTrainingResult(displayContent);
    if (trainingResult == null) return;

    await _recordTrainingFeedback(
      sessionId: sessionId,
      trainingSyndromeId: trainingSyndromeId,
      activeProblems: activeProblems,
      userContent: userContent,
      displayContent: displayContent,
      trainingResult: trainingResult,
    );
    // 防 feedback 残留
    try {
      await _stateRepo.updateSubphase(sessionId, null);
    } catch (e) {
      debugPrint('[SafeRun] 训练轮终结重置子阶段失败: $e');
    }
    callbacks.onTrainingResult?.call(trainingResult);
  }

  /// 私有 helper：训练反馈写入（teaching_history + FSM 重评估 + results 落库）。
  Future<void> _recordTrainingFeedback({
    required String sessionId,
    required String? trainingSyndromeId,
    required List<ActiveProblemView> activeProblems,
    required String userContent,
    required String displayContent,
    required TrainingResult trainingResult,
  }) async {
    try {
      if (trainingSyndromeId != null) {
        await _studentModelRepo.appendTeachingHistory(sessionId, {
          'type': 'training',
          'syndromeId': trainingSyndromeId,
          'result': trainingResult.value,
          'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'sessionId': sessionId,
        });
        // T3 修复：FSM 重评估
        await _reevaluateTeachingState(
          sessionId: sessionId,
          trainingSyndromeId: trainingSyndromeId,
          activeProblems: activeProblems,
        );
      }
      // X-041c：training_results 落库
      if (_trainingResultRepo != null && trainingSyndromeId != null) {
        await _persistTrainingResult(
          sessionId: sessionId,
          trainingSyndromeId: trainingSyndromeId,
          userContent: userContent,
          displayContent: displayContent,
          trainingResult: trainingResult,
        );
      }
    } catch (e) {
      debugPrint('[SafeRun] 训练记录写入失败: $e');
    }
  }

  /// 私有 helper：FSM 重评估 + 达标分支插入阶段总结卡。
  Future<void> _reevaluateTeachingState({
    required String sessionId,
    required String trainingSyndromeId,
    required List<ActiveProblemView> activeProblems,
  }) async {
    try {
      final problem = activeProblems
          .where((p) => p.syndromeId == trainingSyndromeId)
          .firstOrNull;
      if (problem == null) return;
      final reEvalInput = await buildTrainingInputForActiveSyndrome(
        _studentModelRepo,
        sessionId,
        trainingSyndromeId,
        ActiveProblemMeta(
          currentSeverity: Severity.fromString(problem.severity) ?? Severity.l2,
        ),
        diagnosisRepo: _diagnosisRepo,
      );
      if (reEvalInput == null) return;
      final reEvalSummary = buildEvaluationSummary(
        trainingSyndromeId,
        reEvalInput,
      );
      if (reEvalSummary.teachingState == reEvalInput.teachingState) return;
      await _diagnosisRepo.updateTeachingState(
        sessionId,
        trainingSyndromeId,
        reEvalSummary.teachingState.value,
      );
      if (reEvalSummary.teachingState != TeachingState.mastered) return;
      try {
        await _diagnosisRepo.resolveSyndromesBatch(sessionId, [
          trainingSyndromeId,
        ]);
      } catch (e) {
        debugPrint('[SafeRun] 重评估resolveSyndromesBatch: $e');
      }
      await _messageInjector.insertPhaseSummaryOnMastered(
        sessionId,
        trainingSyndromeId,
        problem.syndromeName,
        reEvalInput.passRateInput.totalCount,
      );
    } catch (e) {
      debugPrint('[SafeRun] 重评估失败不阻断主流程: $e');
    }
  }

  /// 私有 helper：training_results 持久化（带 suggestion 追溯）。
  Future<void> _persistTrainingResult({
    required String sessionId,
    required String trainingSyndromeId,
    required String userContent,
    required String displayContent,
    required TrainingResult trainingResult,
  }) async {
    String? tracedSuggestionId;
    String tracedTaskType = 'rewrite';
    try {
      final latestSuggestion = await _teacherSuggestionRepo
          .getLatestActiveBySyndrome(sessionId, trainingSyndromeId);
      if (latestSuggestion != null) {
        tracedSuggestionId = latestSuggestion.id;
        tracedTaskType = latestSuggestion.taskType;
      }
    } catch (e) {
      debugPrint('[SafeRun] suggestion 追溯失败 fallback: $e');
    }
    try {
      await _trainingResultRepo!.insertTrainingResult(
        InsertTrainingResultParams(
          sessionId: sessionId,
          syndromeId: trainingSyndromeId,
          suggestionId: tracedSuggestionId,
          taskType: tracedTaskType,
          userContent: userContent,
          result: trainingResult.value,
          feedback: {'displayContent': displayContent},
        ),
      );
    } catch (e) {
      debugPrint('[SafeRun] training_results 持久化失败: $e');
    }
  }

  // K-9 公开 API 仅 commitDiagnosisFromContent 由 widget 端调用
  // （lib/widgets/chat_teaching.dart L53）；ChatService 内部消费 parseAndPersist
  // / commitDiagnosisAndSuggestions / handleTrainingResult 三步走。
  @visibleForTesting
  Type get k9Surface => DiagnosisFlowHandler;
}

/// K-9 公开门面：解决 PhaseSummaryCardPayload 引用 + 类型导入，
/// 保持 ChatService 端只需 import 'diagnosis_flow_handler.dart'。
typedef K9PhaseSummaryCard = PhaseSummaryCardPayload;
