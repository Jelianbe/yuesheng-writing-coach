// ─────────────────────────────────────────────────────────────
// MessageInjector — system 消息注入编排器（独立类）
//
// ADR-C74 批次 K-7 拆分重构产物。从 ChatService 抽出 sendMessage
// 主流程中 5 个 system 消息注入方法（聚类 A，详见
// docs/recon-reports/RECON-K7-K8-K9-2026-09-04.md §4 聚类 A 共性）：
//   - 注入链副作用：messages.add(...) 或更新 sessionRepo
//   - 形参：markStage 闭包 + messages 列表
//   - 不直接调 LLM
//
// 字段依赖建模原则（同 DiagnosisCommitter K-1 样板）：
//   - 必备依赖（required）：6 个仓储 + 1 个编排器 + 1 个 capability
//   - 可选依赖（X-041c 模式）：5 个 nullable 仓储，不装配则跳过对应观察项
//   - 内部状态：4 个按 cycle 隔离的缓存
//   - 构造签名：`MessageInjector({required ..., nullable 5 仓储})`，
//     与 chat_service 已有 `diagnosisCommitter` 模式对称
//
// 实施节奏（K-7）：
//   K-7：迁 5 个 _inject* + 11 个跟随 helper + 1 个 _insertPhaseSummaryOnMastered
//        + 4 个缓存字段
//
// 关键不变量：
//   - chatServiceProvider 注入本类实例；ChatService 改为委派
//   - _FakeChatService 测试替身不触达 MessageInjector（private 委派链），
//     @override 契约保留（X-025-ARCH 教训复盘）
//   - K-8 合并：原 _preloadReferenceDetails 跟随 _injectReferences 迁入
//     本类（已被 _injectReferences 内部封装），三段批量查询逻辑
//     与原 chat_service 完全等价（chat_service_reference_preload_test.dart
//     守护契约）
// ─────────────────────────────────────────────────────────────

// 私有字段（_xxx）+ 公开命名参数（xxx）模式无法用 initializing formal
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import 'package:writingcoach/config/shared_constants.dart' show FocusSwitch;
import 'package:writingcoach/config/token_budget_table.dart';
import 'package:writingcoach/contracts/material_capability.dart';
import 'package:writingcoach/contracts/reference_capability.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/manuscript_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show
        ActiveFocusContext,
        ActiveSyndromeView,
        ChapterBrief,
        FocusSource,
        ManuscriptDetail,
        ReferenceItem,
        ReferenceResolvers,
        buildCausalityBreakContext,
        buildConflictObservationsContext,
        buildDialogueTagContext,
        buildGrammarLexicalContext,
        buildReferencesContext,
        buildStructuredSyndromeContext,
        buildSubplotClosureContext,
        findKeywordExcerpt;
import 'package:writingcoach/services/character_identity.dart';
// C78 批次2b：conflict_detector 的 import 已移除——本文件改走
// character_identity 的共享判据入口（detectConflictsForFacts / fillConflictExcerpts），
// 不再直接引用 detectCharacterConflicts，避免调用方自行组合导致判据分叉。
import 'package:writingcoach/services/diagnosis_committer.dart';
import 'package:writingcoach/services/dialogue_tag_detector.dart';
import 'package:writingcoach/services/event_causality_detector.dart';
import 'package:writingcoach/services/focus_resolver.dart' as focus;
import 'package:writingcoach/services/grammar_lexical_detector.dart';
import 'package:writingcoach/services/intent_classifier.dart';
import 'package:writingcoach/services/llm_client.dart' show ChatMessage;
import 'package:writingcoach/services/message_card_service.dart'
    show PhaseSummaryCardPayload, SyndromeChangeItem, insertPhaseSummaryCard;
import 'package:writingcoach/services/outline_service.dart';
import 'package:writingcoach/services/style_fingerprint.dart';
import 'package:writingcoach/services/style_technique_router.dart';
import 'package:writingcoach/services/student_profile.dart';
import 'package:writingcoach/services/subplot_closure_detector.dart';
import 'package:writingcoach/services/syndrome_skill_levels.dart';
import 'package:writingcoach/services/training_evaluator.dart';
import 'package:writingcoach/services/training_few_shot_library.dart';
import 'package:writingcoach/services/training_input_builder.dart';
import 'package:writingcoach/services/training_knowledge_base.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 系统消息注入编排器
///
/// sendMessage 主流程中 5 个 system 消息注入步骤（5.0 学员画像 / 5.1 引用 /
/// 5.1.x 章节观察 / 5.2 附属文件 / 6 诊断锁）的独立持有者。
/// 通过 markStage 闭包参数与 chat_service 主链解耦，
/// 维持 sendMessage 主流程的整体节拍不变。
class MessageInjector {
  // ─── 必备依赖（聚类 A 共性，见 RECON §4）───
  final SessionRepository _sessionRepo;
  final DiagnosisRepository _diagnosisRepo;
  final StudentModelRepository _studentModelRepo;
  final ReferenceCapability _referenceRepo;
  final ChapterRepository _chapterRepo;
  final ManuscriptRepository _manuscriptRepo;

  /// 协议块字符串构造（K-3 已迁 DiagnosisCommitter），通过 DI 复用
  final DiagnosisCommitter _diagnosisCommitter;

  /// 附属文件格式化（5.2 注入）
  final MaterialCapability _material;

  // ─── 可选依赖（X-041c 模式：nullable，不装配则跳过对应观察项）───
  final CharacterFactRepository? _characterFactRepo;
  final EventFactRepository? _eventFactRepo;
  final SubplotFactRepository? _subplotFactRepo;
  final OutlineRepository? _outlineRepo;

  // ─── 内部状态：4 个缓存，跟着方法一起搬 ───
  /// 引用详情预载缓存（每次 injectReferences 调用前预加载，调用后清空）
  /// A-3 N+1 消除的产物：单次 `WHERE id IN(...)` 批量取全，
  /// 因 buildReferencesContext 是同步函数需要同步缓存访问
  final Map<String, AttachedFileRow> _cachedAttachedFiles = {};
  final Map<String, ChapterBrief> _cachedChapters = {};
  final Map<String, ManuscriptDetail> _cachedManuscripts = {};

  /// 批次63（B62b）：L1 意图向量——每个 session 最近 3 次交互意图
  /// 随 _injectProfileAndIntents 迁入
  final Map<String, List<String>> _recentIntentsBySession = {};

  /// 懒加载大纲服务缓存
  ///（与 ChatService._ensureOutlineService / DiagnosisCommitter._ensureOutlineService 同语义）
  OutlineService? _outlineService;

  MessageInjector({
    required SessionRepository sessionRepo,
    required DiagnosisRepository diagnosisRepo,
    required StudentModelRepository studentModelRepo,
    required ReferenceCapability referenceRepo,
    required ChapterRepository chapterRepo,
    required ManuscriptRepository manuscriptRepo,
    required DiagnosisCommitter diagnosisCommitter,
    required MaterialCapability material,
    CharacterFactRepository? characterFactRepo,
    EventFactRepository? eventFactRepo,
    SubplotFactRepository? subplotFactRepo,
    OutlineRepository? outlineRepo,
  }) : _sessionRepo = sessionRepo,
       _diagnosisRepo = diagnosisRepo,
       _studentModelRepo = studentModelRepo,
       _referenceRepo = referenceRepo,
       _chapterRepo = chapterRepo,
       _manuscriptRepo = manuscriptRepo,
       _diagnosisCommitter = diagnosisCommitter,
       _material = material,
       _characterFactRepo = characterFactRepo,
       _eventFactRepo = eventFactRepo,
       _subplotFactRepo = subplotFactRepo,
       _outlineRepo = outlineRepo;

  /// 懒加载大纲服务（批次7 O2 模式）
  OutlineService? _ensureOutlineService() {
    _outlineService ??= _outlineRepo != null
        ? OutlineService(_outlineRepo)
        : null;
    return _outlineService;
  }

  // ════════════════════════════════════════════════════════════════
  // 公开 API：5 个注入入口（每个 ≤ 50 行 R-019 硬上限）
  // ════════════════════════════════════════════════════════════════

  /// 5.0 学员画像 + 教学计划延续 + 意图 + 颗粒度注入
  ///
  /// chat_service.dart 原 _injectProfileAndIntents L1112-L1184 = 73 行
  /// 按 R-019 已拆为 4 个 helper。
  Future<void> injectProfileAndIntents({
    required String sessionId,
    required String content,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    await _injectStudentProfile(
      sessionId: sessionId,
      messages: messages,
      markStage: markStage,
    );
    await _injectPreviousTeachingPlan(sessionId: sessionId, messages: messages);
    _injectUserIntentVector(
      sessionId: sessionId,
      content: content,
      messages: messages,
    );
    _injectReplyDetailGuidance(content: content, messages: messages);
  }

  /// 5.1 引用内容注入（含 K-8 合并的 _preloadReferenceDetails）。
  ///
  /// 返回 primaryRef（5.2 附属文件注入推导 manuscriptId）+ chapterContent
  /// chat_service.dart 原 _injectReferences L1186-L1250 = 65 行 +
  /// 原 _preloadReferenceDetails L1641-L1725 = 85 行（K-8 合并），
  /// 按 R-019 拆为 6 个 helper。
  Future<({ReferenceItem? primaryRef, String? chapterContent})>
  injectReferences({
    required String sessionId,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    final refs = await _loadReferencedItems(sessionId);
    if (refs.isEmpty) return (primaryRef: null, chapterContent: null);

    final referenceItems = refs.map(_toReferenceItem).toList();
    final primaryRef = _pickPrimaryRef(referenceItems);

    await _preloadReferenceDetails(refs: refs);
    final referencesContext = buildReferencesContext(
      referenceItems,
      resolvers: _buildReferenceResolvers(),
    );
    if (referencesContext.isNotEmpty) {
      markStage(BudgetStageNames.references);
      messages.add(ChatMessage(role: 'system', content: referencesContext));
    }
    _clearReferenceCaches();
    return (primaryRef: primaryRef, chapterContent: null);
  }

  /// 5.1.8 / 5.1.9 / 5.2：大纲实体 + 事实协议 + 附属文件注入
  ///
  /// chat_service.dart 原 _injectOutlineFactsAndFiles L1252-L1340 = 89 行，
  /// 按 R-019 拆为 3 个 helper。
  Future<void> injectOutlineFactsAndFiles({
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    if (await _injectEntityMemory(
      content: content,
      primaryRef: primaryRef,
      messages: messages,
    )) {
      await _injectEntityIndex(primaryRef: primaryRef, messages: messages);
    }
    _injectFactProtocol(primaryRef: primaryRef, messages: messages);
    await _injectAttachedFiles(
      primaryRef: primaryRef,
      messages: messages,
      markStage: markStage,
    );
  }

  /// 5.1.2 - 5.1.7：章节诊断观察项注入
  ///
  /// chat_service.dart 原 _injectChapterObservations L1344-L1579 = 236 行，
  /// 按 R-019 拆为 6 个 helper（每个观察项独立可降级注入）。
  Future<void> injectChapterObservations({
    required String sessionId,
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    await _injectVoiceDriftObservation(
      sessionId: sessionId,
      content: content,
      primaryRef: primaryRef,
      messages: messages,
    );
    await _injectConflictObservation(
      sessionId: sessionId,
      content: content,
      primaryRef: primaryRef,
      messages: messages,
    );
    await _injectCausalityObservation(
      sessionId: sessionId,
      content: content,
      primaryRef: primaryRef,
      messages: messages,
    );
    await _injectSubplotClosureObservation(
      sessionId: sessionId,
      content: content,
      primaryRef: primaryRef,
      messages: messages,
    );
    await _injectGrammarObservation(
      content: content,
      primaryRef: primaryRef,
      messages: messages,
    );
    await _injectDialogueTagObservation(
      content: content,
      primaryRef: primaryRef,
      messages: messages,
    );
  }

  /// 6. 跨轮次诊断锁定注入
  ///
  /// 返回 trainingSyndromeId（来源 focus-resolver，X-1-7-2 训练记录写入用）。
  /// chat_service.dart 原 _injectDiagnosisLock L841-L1108 = 268 行，
  /// 按 R-019 拆为 6 个 helper。
  Future<String?> injectDiagnosisLock({
    required String sessionId,
    required String content,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required BeginnerLevel? beginnerLevel,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    if (activeProblems.isEmpty) return null;
    final focusResult = await _resolveTrainingFocus(
      sessionId: sessionId,
      content: content,
      activeProblems: activeProblems,
      currentSubphase: currentSubphase,
      beginnerLevel: beginnerLevel,
    );
    _injectFocusRejectionContext(
      messages: messages,
      rejectReason: focusResult.rejectReason,
    );
    await _evaluateActiveFocusProblem(
      sessionId: sessionId,
      content: content,
      activeProblems: activeProblems,
      focusResult: focusResult,
      messages: messages,
      markStage: markStage,
    );
    await _injectStructuredSyndromeContext(
      activeProblems: activeProblems,
      focusResult: focusResult,
      messages: messages,
      markStage: markStage,
    );
    _injectStudentSkillLevelGuidance(
      beginnerLevel: beginnerLevel,
      messages: messages,
    );
    return focusResult.activatedFocusId;
  }

  /// 6 续：active focus problem 不为空时跑 §6.3 (介入 + 训练评估)
  Future<void> _evaluateActiveFocusProblem({
    required String sessionId,
    required String content,
    required List<ActiveProblemView> activeProblems,
    required _FocusResolveResult focusResult,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    final syndromeId =
        focusResult.activatedFocusId ??
        _pickFocusProblem(activeProblems, null)?.syndromeId;
    if (syndromeId == null) return;
    final focusProblem = _pickFocusProblem(
      activeProblems,
      focusResult.activatedFocusId,
    );
    if (focusProblem == null) return;
    await _injectInterventionLevel(
      sessionId: sessionId,
      focusSyndromeId: syndromeId,
      focusProblem: focusProblem,
      messages: messages,
    );
    await _injectTrainingEvaluationContext(
      sessionId: sessionId,
      focusSyndromeId: syndromeId,
      focusProblem: focusProblem,
      messages: messages,
      markStage: markStage,
    );
  }
  // ════════════════════════════════════════════════════════════════
  // injectProfileAndIntents helpers (4)
  // ════════════════════════════════════════════════════════════════

  /// 5.0：学员画像注入（跨会话上下文）
  Future<void> _injectStudentProfile({
    required String sessionId,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
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
  }

  /// 5.0.0b：注入上一轮教学焦点的 focus_reason + nextFocus
  Future<void> _injectPreviousTeachingPlan({
    required String sessionId,
    required List<ChatMessage> messages,
  }) async {
    try {
      final latestDiag = await _diagnosisRepo.getLatestDiagnosis(sessionId);
      if (latestDiag == null) return;
      final parts = <String>[];
      if (latestDiag.focusReason != null &&
          latestDiag.focusReason!.isNotEmpty) {
        parts.add('**上一轮教学焦点理由**：${latestDiag.focusReason}');
      }
      if (latestDiag.nextFocus != null && latestDiag.nextFocus!.isNotEmpty) {
        parts.add('**上轮设定的下一步方向**：${latestDiag.nextFocus}');
      }
      if (parts.isEmpty) return;
      messages.add(
        ChatMessage(
          role: 'system',
          content:
              '# 上一轮教学计划延续（系统注入）\n\n'
              '${parts.join('\n\n')}\n\n'
              '请保持教学连贯性，延续上轮设定的方向。',
        ),
      );
    } catch (e) {
      debugPrint('[SafeRun] 教学计划延续注入失败不阻断主流程: $e');
    }
  }

  /// 5.0.1：意图分类（最近 3 次向量）
  void _injectUserIntentVector({
    required String sessionId,
    required String content,
    required List<ChatMessage> messages,
  }) {
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
  }

  /// 5.0.2：颗粒度控制（长话短说/详细点时注入）
  void _injectReplyDetailGuidance({
    required String content,
    required List<ChatMessage> messages,
  }) {
    final detailNote = buildReplyDetailInstruction(detectReplyDetail(content));
    if (detailNote != null) {
      messages.add(ChatMessage(role: 'system', content: detailNote));
    }
  }

  // ════════════════════════════════════════════════════════════════
  // injectReferences helpers（K-8 合并 _preloadReferenceDetails）
  // ════════════════════════════════════════════════════════════════

  /// 5.1：加载会话引用原始记录
  Future<List<ReferencedItem>> _loadReferencedItems(String sessionId) async {
    try {
      final refs = await _referenceRepo.listReferences(sessionId);
      return refs;
    } catch (e) {
      debugPrint('[SafeRun] 引用列表加载失败不阻断主流程: $e');
      return const [];
    }
  }

  /// ReferencedItem → ReferenceItem（chat_context_builder 入参类型）
  ReferenceItem _toReferenceItem(ReferencedItem r) {
    return ReferenceItem(
      refType: r.refType,
      refId: r.refId,
      title: r.title,
      isPrimary: r.isPrimary,
      manuscriptId: r.manuscriptId,
      excerptRange: r.excerptRange,
    );
  }

  /// 主引用选择（isPrimary == 1 优先，回退首条）
  ReferenceItem? _pickPrimaryRef(List<ReferenceItem> items) {
    if (items.isEmpty) return null;
    return items.firstWhere((r) => r.isPrimary == 1, orElse: () => items.first);
  }

  /// 同步访问预载缓存的 resolver 三角
  ReferenceResolvers _buildReferenceResolvers() {
    return ReferenceResolvers(
      fileResolver: (fileId) => _cachedAttachedFiles[fileId],
      chapterResolver: (chapterId) => _cachedChapters[chapterId],
      manuscriptResolver: (manuscriptId) => _cachedManuscripts[manuscriptId],
    );
  }

  void _clearReferenceCaches() {
    _cachedAttachedFiles.clear();
    _cachedChapters.clear();
    _cachedManuscripts.clear();
  }

  /// A-3 N+1 消除：单次 `WHERE id IN(...)` 批量取全
  /// 按 refType 分 3 类，每类独立 try/catch 保留「单类失败不阻断」语义
  ///
  /// chat_service.dart 原 _preloadReferenceDetails L1641-L1725 = 85 行
  /// 按 R-019 拆为 1 个分发器 + 3 个查询段 helper。
  Future<void> _preloadReferenceDetails({
    required List<ReferencedItem> refs,
  }) async {
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
    await _preloadChapters(chapterIds);
    await _preloadAttachedFiles(fileIds);
    await _preloadManuscripts(manuscriptIds);
  }

  /// 章节引用：单次 `WHERE id IN(...)` 取全
  Future<void> _preloadChapters(List<String> chapterIds) async {
    if (chapterIds.isEmpty) return;
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

  /// 素材文件引用：单次 `WHERE id IN(...)` 取全
  Future<void> _preloadAttachedFiles(List<String> fileIds) async {
    if (fileIds.isEmpty) return;
    try {
      final files = await _referenceRepo.getAttachedFilesByIds(fileIds);
      for (final f in files) {
        _cachedAttachedFiles[f.id] = f;
      }
    } catch (e) {
      debugPrint('[SafeRun] 素材批量加载失败不阻断整体: $e');
    }
  }

  /// 作品引用：manuscripts + 其章节，2 查询替代 2N
  Future<void> _preloadManuscripts(List<String> manuscriptIds) async {
    if (manuscriptIds.isEmpty) return;
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

  // ════════════════════════════════════════════════════════════════
  // injectOutlineFactsAndFiles helpers (3)
  // ════════════════════════════════════════════════════════════════

  /// 5.1.8：大纲实体协议头注入（无条件——AI 从首轮即知晓 [YS_ENTITY] 协议）。
  /// 返回是否走 §5.1.8 条件命中，后续 _injectEntityIndex 据此判定。
  Future<bool> _injectEntityMemory({
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    if (!content.contains(_kDiagnosisRequestMarker)) return false;
    if (primaryRef?.refType != 'chapter') return false;
    final outlineService = _ensureOutlineService();
    if (outlineService == null) return false;
    try {
      messages.add(
        ChatMessage(
          role: 'system',
          content: outlineService.buildEntityProtocolContext(),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[SafeRun] 大纲记忆注入失败不阻断主流程: $e');
      return false;
    }
  }

  /// 5.1.8（接续）：实体索引上下文注入（有实体才注入）
  Future<void> _injectEntityIndex({
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    final outlineService = _ensureOutlineService();
    if (outlineService == null) return;
    final chapterId = primaryRef?.refId;
    if (chapterId == null) return;
    try {
      final chapter = await _chapterRepo.getChapter(chapterId);
      if (chapter == null) return;
      final ctx = await outlineService.buildEntityIndexContext(
        chapter.manuscriptId,
      );
      if (ctx != null) {
        messages.add(ChatMessage(role: 'system', content: ctx));
      }
    } catch (e) {
      debugPrint('[SafeRun] 大纲实体索引注入失败不阻断主流程: $e');
    }
  }

  /// 5.1.9：时序知识图谱事实提取协议注入
  void _injectFactProtocol({
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) {
    if (primaryRef?.refType != 'chapter') return;
    if (_characterFactRepo == null &&
        _eventFactRepo == null &&
        _subplotFactRepo == null) {
      return;
    }
    messages.add(
      ChatMessage(
        role: 'system',
        content: _diagnosisCommitter.buildFactProtocolContext(),
      ),
    );
  }

  /// 5.2：附属文件上下文注入（V3：AI 可读取书籍下所有文件）
  Future<void> _injectAttachedFiles({
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    try {
      final manuscriptId = await _deriveManuscriptId(primaryRef);
      if (manuscriptId == null) return;
      final files = await _referenceRepo.listAttachedFiles(manuscriptId);
      if (files.isEmpty) return;
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
    } catch (e) {
      debugPrint('[SafeRun] 附属文件注入失败不阻断主流程: $e');
    }
  }

  /// 5.2 helper：从 primaryRef 推 manuscriptId
  Future<String?> _deriveManuscriptId(ReferenceItem? primaryRef) async {
    if (primaryRef == null) return null;
    if (primaryRef.refType == 'manuscript') return primaryRef.refId;
    if (primaryRef.refType == 'chapter') {
      final chapter = await _chapterRepo.getChapter(primaryRef.refId);
      return chapter?.manuscriptId;
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════
  // injectChapterObservations helpers (6)
  // ════════════════════════════════════════════════════════════════

  /// §5.1.2：声线漂移检测 + 提示注入（L3 style_fingerprint → L1 实时提示）
  Future<void> _injectVoiceDriftObservation({
    required String sessionId,
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    if (!content.contains(_kDiagnosisRequestMarker)) return;
    if (primaryRef?.refType != 'chapter') return;
    try {
      final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
      if (chapter == null) return;
      final current = extractStyleFingerprint(chapter.content);
      if (current == null) return;
      final baseline = await _studentModelRepo.getStyleFingerprint(sessionId);
      final hints = (baseline == null || baseline.sentencesCount == 0)
          ? const <String>[]
          : detectVoiceDrift(baseline, current);
      if (hints.isEmpty) {
        await _studentModelRepo.updateStyleFingerprint(sessionId, current);
      } else {
        messages.add(
          ChatMessage(
            role: 'system',
            content: _diagnosisCommitter.buildDriftHintContext(hints),
          ),
        );
      }
    } catch (e) {
      debugPrint('[SafeRun] 漂移检测失败不阻断主流程: $e');
    }
  }

  /// §5.1.3：时序矛盾冲突观察（A6 首步）
  Future<void> _injectConflictObservation({
    required String sessionId,
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    if (!content.contains(_kDiagnosisRequestMarker)) return;
    if (primaryRef?.refType != 'chapter') return;
    if (_characterFactRepo == null) return;
    try {
      final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
      if (chapter == null) return;
      final facts = await _characterFactRepo.listCharacters(
        chapter.manuscriptId,
      );
      if (facts.isEmpty) return;
      // C78 批次2b（§5.3）：改走共享判据入口——先按身份合并（别名行不漏检），
      // 再检测；摘录仍在本地填（AI 侧用当前诊断章节正文，与判据刻意分离）。
      // 逐行等价于原 .map() 构造 inputs + detectCharacterConflicts + 填 excerpt，
      // 零行为变更，唯一差别是**先做了身份合并**（原逻辑漏掉的一环）。
      final raw = detectConflictsForFacts(facts);
      final observations = fillConflictExcerpts(raw, chapter.content);
      final ctx = buildConflictObservationsContext(observations);
      if (ctx != null) {
        messages.add(ChatMessage(role: 'system', content: ctx));
      }
    } catch (e) {
      debugPrint('[SafeRun] 冲突检测失败不阻断主流程: $e');
    }
  }

  /// §5.1.4：因果链断裂观察
  Future<void> _injectCausalityObservation({
    required String sessionId,
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    if (!content.contains(_kDiagnosisRequestMarker)) return;
    if (primaryRef?.refType != 'chapter') return;
    if (_eventFactRepo == null) return;
    try {
      final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
      if (chapter == null) return;
      final events = await _eventFactRepo.listEvents(chapter.manuscriptId);
      if (events.isEmpty) return;
      final inputs = events
          .map(
            (e) => (
              name: e.name,
              chapter: e.chapter,
              eventType: e.eventType,
              causeEventId: e.causeEventId,
              effectEventId: e.effectEventId,
              // C78 批次2b（§5.3）：EventFact.stale 是 **int**（SQLite 布尔惯例，
              // drift 生成为 `final int stale`），typedef 定的是 bool，故显式转换。
              stale: e.stale != 0,
            ),
          )
          .toList();
      final raw = detectCausalityBreaks(inputs);
      final chapterContent = chapter.content;
      final observations = raw
          .map(
            (o) => CausalityBreakObservation(
              name: o.name,
              chapter: o.chapter,
              eventType: o.eventType,
              description: o.description,
              excerpt: findKeywordExcerpt(chapterContent, o.name),
            ),
          )
          .toList();
      final ctx = buildCausalityBreakContext(observations);
      if (ctx != null) {
        messages.add(ChatMessage(role: 'system', content: ctx));
      }
    } catch (e) {
      debugPrint('[SafeRun] 因果链检测失败不阻断主流程: $e');
    }
  }

  /// §5.1.5：情节闭环观察
  Future<void> _injectSubplotClosureObservation({
    required String sessionId,
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    if (!content.contains(_kDiagnosisRequestMarker)) return;
    if (primaryRef?.refType != 'chapter') return;
    if (_subplotFactRepo == null) return;
    try {
      final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
      if (chapter == null) return;
      final subplots = await _subplotFactRepo.listSubplots(
        chapter.manuscriptId,
      );
      if (subplots.isEmpty) return;
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
      final chapterContent = chapter.content;
      final observations = raw
          .map(
            (o) => UnclosedSubplotObservation(
              name: o.name,
              introducedChapter: o.introducedChapter,
              currentChapter: o.currentChapter,
              description: o.description,
              excerpt: findKeywordExcerpt(chapterContent, o.name),
            ),
          )
          .toList();
      final ctx = buildSubplotClosureContext(observations);
      if (ctx != null) {
        messages.add(ChatMessage(role: 'system', content: ctx));
      }
    } catch (e) {
      debugPrint('[SafeRun] 情节闭环检测失败不阻断主流程: $e');
    }
  }

  /// §5.1.6：基础文法观察
  Future<void> _injectGrammarObservation({
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    if (!content.contains(_kDiagnosisRequestMarker)) return;
    if (primaryRef?.refType != 'chapter') return;
    try {
      final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
      if (chapter == null) return;
      final issues = detectGrammarLexicalIssues(chapter.content);
      final ctx = buildGrammarLexicalContext(issues);
      if (ctx != null) {
        messages.add(ChatMessage(role: 'system', content: ctx));
      }
    } catch (e) {
      debugPrint('[SafeRun] 基础文法检测失败不阻断主流程: $e');
    }
  }

  /// §5.1.7：对话标签观察
  Future<void> _injectDialogueTagObservation({
    required String content,
    required ReferenceItem? primaryRef,
    required List<ChatMessage> messages,
  }) async {
    if (!content.contains(_kDiagnosisRequestMarker)) return;
    if (primaryRef?.refType != 'chapter') return;
    try {
      final chapter = await _chapterRepo.getChapter(primaryRef!.refId);
      if (chapter == null) return;
      final issues = detectDialogueTagIssues(chapter.content);
      final ctx = buildDialogueTagContext(issues);
      if (ctx != null) {
        messages.add(ChatMessage(role: 'system', content: ctx));
      }
    } catch (e) {
      debugPrint('[SafeRun] 对话标签检测失败不阻断主流程: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════
  // injectDiagnosisLock helpers (6)
  // ════════════════════════════════════════════════════════════════

  /// 6.1 focus-resolver 6 项校验门控
  Future<_FocusResolveResult> _resolveTrainingFocus({
    required String sessionId,
    required String content,
    required List<ActiveProblemView> activeProblems,
    required TeachingSubphase? currentSubphase,
    required BeginnerLevel? beginnerLevel,
  }) async {
    final aiSuggestedFocusId = await _diagnosisRepo.getLatestTeachingFocus(
      sessionId,
    );
    final focusHistory = await _buildFocusHistory(sessionId);
    final userFocusOverride = _parseUserFocusFromMessage(
      content,
      activeProblems,
    );
    final focusProblems = _toFocusProblems(activeProblems);
    final focusHistoryEntries = focusHistory
        .map(
          (h) => focus.FocusHistoryEntry(
            focusId: h.focusId,
            timestamp: h.timestamp,
          ),
        )
        .toList();
    final focusInput = focus.ResolveFocusInput(
      problems: focusProblems,
      aiSuggestedFocusId: aiSuggestedFocusId,
      userFocusOverride: userFocusOverride,
      subphase: currentSubphase,
      focusHistory: focusHistoryEntries,
      // 批次60：学员当前技能层级
      studentSkillLevel: skillLevelForBeginner(beginnerLevel),
    );
    final result = focus.resolveTeachingFocus(focusInput);
    return _FocusResolveResult(
      activatedFocusId: result.activatedFocusId,
      source: result.source,
      reason: result.reason,
      rejectReason: result.rejectReason,
    );
  }

  /// ActiveProblemView → FocusProblem 转换（R-019 行数止血）
  List<FocusProblem> _toFocusProblems(List<ActiveProblemView> activeProblems) {
    return activeProblems
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
  }

  /// 6.2：focus 拒绝原因注入
  void _injectFocusRejectionContext({
    required List<ChatMessage> messages,
    required String? rejectReason,
  }) {
    if (rejectReason == null) return;
    messages.add(
      ChatMessage(role: 'system', content: '# Focus 切换提示\n\n$rejectReason'),
    );
  }

  /// 6.3 上半段：训练介入级别注入（D3 复发 + 7.2 表现感知）
  Future<void> _injectInterventionLevel({
    required String sessionId,
    required String focusSyndromeId,
    required ActiveProblemView focusProblem,
    required List<ChatMessage> messages,
  }) async {
    try {
      final performance = await computeTrainingPerformance(
        _studentModelRepo,
        sessionId,
        focusSyndromeId,
      );
      final trainingCount = performance?.totalCount ?? 0;
      final relapse = await _resolveRelapseSignal(focusSyndromeId);
      final currentSeverity =
          Severity.fromString(focusProblem.severity) ?? Severity.l2;
      final intervention = interventionLevelForTrainingCount(
        trainingCount,
        currentSeverity: currentSeverity,
        relapse: relapse,
        performance: performance,
      );
      final adjustmentNote = _buildInterventionAdjustmentNote(
        trainingCount: trainingCount,
        currentSeverity: currentSeverity,
        relapse: relapse,
        performance: performance,
      );
      messages.add(
        ChatMessage(
          role: 'system',
          content: _formatInterventionLevelMessage(
            trainingCount: trainingCount,
            intervention: intervention,
            adjustmentNote: adjustmentNote,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[SafeRun] 训练评估注入失败不阻断主流程: $e');
    }
  }

  /// 6.3 上半段 helper：复发信号查询失败降级 false
  Future<bool> _resolveRelapseSignal(String focusSyndromeId) async {
    try {
      return await _diagnosisRepo.hasResolvedHistory(focusSyndromeId);
    } catch (e) {
      debugPrint('[SafeRun] 复发信号查询失败降级 false: $e');
      return false;
    }
  }

  /// 6.3 上半段 helper：训练介入级别消息内容
  String _formatInterventionLevelMessage({
    required int trainingCount,
    required InterventionLevel intervention,
    required String adjustmentNote,
  }) {
    final adjLine = adjustmentNote.isEmpty ? '' : '$adjustmentNote\n';
    return '# 训练介入级别（逐步撤除脚手架）\n\n'
        '本症候已训练 $trainingCount 次，本轮采用介入级别：'
        '${intervention.value}（${intervention.label}）。'
        '$adjLine'
        '按级别组织训练：\n'
        '- I do：给完整示范参考 + 常见错误提醒 + 自查锚点，让学员先看懂\n'
        '- We do：常见错误提醒 + 自查锚点保留，示范改为引导方向，学员动手写为主\n'
        '- You do：只给自查锚点，不做示范，学员独立练习 + 你来点评\n'
        '（本注入是参考输入，具体执行由你按学员情况判断）';
  }

  /// 7.2（批次16）：介入级别修正原因说明（ADR-C74 K-7 由 chat_service 迁入）。
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
    if (relapse) return '（本轮因复发回退脚手架到 I do）';
    if (currentSeverity == Severity.l3) {
      return '（本轮因严重度 L3 回退脚手架到 I do）';
    }
    if (performance == null) return '';

    final base = trainingCount >= 4
        ? InterventionLevel.youDo
        : trainingCount >= 2
        ? InterventionLevel.weDo
        : InterventionLevel.iDo;

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

  /// 6.3 下半段：训练评估上下文（FSM 迁移 + 知识库 + few-shot）
  ///
  /// 调度器：try 包裹两个独立子任务（FSM+context + 知识库+few-shot），
  /// 任一失败不阻断另一。
  Future<void> _injectTrainingEvaluationContext({
    required String sessionId,
    required String focusSyndromeId,
    required ActiveProblemView focusProblem,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    try {
      await _injectTrainingFsmAndContext(
        sessionId: sessionId,
        focusSyndromeId: focusSyndromeId,
        focusProblem: focusProblem,
        messages: messages,
      );
    } catch (e) {
      debugPrint('[SafeRun] 训练上下文构建失败不阻断主流程: $e');
    }
    await _injectTrainingKnowledge(
      focusSyndromeId: focusSyndromeId,
      messages: messages,
      markStage: markStage,
    );
  }

  /// 6.3 子任务 A：buildTrainingInput + FSM 迁移写回 + contextInjection 注入
  Future<void> _injectTrainingFsmAndContext({
    required String sessionId,
    required String focusSyndromeId,
    required ActiveProblemView focusProblem,
    required List<ChatMessage> messages,
  }) async {
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
    if (trainingInput == null) return;
    final summary = buildEvaluationSummary(focusSyndromeId, trainingInput);
    await _persistFsmTransitionOnMastered(
      sessionId: sessionId,
      focusSyndromeId: focusSyndromeId,
      summary: summary,
      trainingInput: trainingInput,
      focusProblem: focusProblem,
    );
    if (summary.contextInjection.isNotEmpty) {
      messages.add(
        ChatMessage(role: 'system', content: summary.contextInjection),
      );
    }
  }

  /// 6.3 子任务 A 续：FSM 状态机迁移写回 DB（mastered → 立即解锁 + 总结卡）
  Future<void> _persistFsmTransitionOnMastered({
    required String sessionId,
    required String focusSyndromeId,
    required EvaluationSummary summary,
    required EvaluationSummaryInput trainingInput,
    required ActiveProblemView focusProblem,
  }) async {
    if (summary.teachingState == trainingInput.teachingState) return;
    try {
      await _diagnosisRepo.updateTeachingState(
        sessionId,
        focusSyndromeId,
        summary.teachingState.value,
      );
      if (summary.teachingState != TeachingState.mastered) return;
      try {
        await _diagnosisRepo.resolveSyndromesBatch(sessionId, [
          focusSyndromeId,
        ]);
      } catch (e) {
        debugPrint('[SafeRun] resolveSyndromesBatch 内层: $e');
      }
      // B1：达标→解锁同时插入阶段总结卡
      await insertPhaseSummaryOnMastered(
        sessionId,
        focusSyndromeId,
        focusProblem.syndromeName,
        trainingInput.passRateInput.totalCount,
      );
    } catch (e) {
      debugPrint('[SafeRun] FSM updateTeachingState 外层: $e');
    }
  }

  /// 6.3 子任务 B：注入训练教学知识 + few-shot 借鉴
  Future<void> _injectTrainingKnowledge({
    required String focusSyndromeId,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    try {
      final trainingKnowledge = getTrainingContent([focusSyndromeId]);
      if (trainingKnowledge.isNotEmpty) {
        markStage(BudgetStageNames.trainingKnowledge);
        messages.add(ChatMessage(role: 'system', content: trainingKnowledge));
      }
      final fewShot = getTrainingFewShot([focusSyndromeId]);
      if (fewShot.isNotEmpty) {
        messages.add(ChatMessage(role: 'system', content: fewShot));
      }
    } catch (e) {
      debugPrint('[SafeRun] 知识库注入失败不阻断主流程: $e');
    }
  }

  /// 6.4：L3 结构化症候详情（含文笔画像旁路路由）
  ///
  /// 内部仅 1 个 await（拉取 latestStyleProfile），其后 routeStyleTechniques /
  /// formatStyleTechniqueSection / buildStructuredSyndromeContext 全同步，
  /// 故函数本身是 async 但行为等价原 chat_service §6.4 同步语义。
  Future<void> _injectStructuredSyndromeContext({
    required List<ActiveProblemView> activeProblems,
    required _FocusResolveResult focusResult,
    required List<ChatMessage> messages,
    required void Function(String) markStage,
  }) async {
    final activeSyndromeViews = activeProblems
        .map(
          (p) => ActiveSyndromeView(
            syndromeId: p.syndromeId,
            syndromeName: p.syndromeName,
            severity: Severity.fromString(p.severity) ?? Severity.l2,
            confirmationStatus:
                ConfirmationStatus.fromString(p.confirmationStatus) ??
                ConfirmationStatus.suspected,
          ),
        )
        .toList();
    // 文笔画像旁路路由（fire-and-forget try/catch——失败不阻断主流程）
    String? styleTechniqueSection;
    try {
      final latestStyleProfile = await _studentModelRepo
          .getLatestStyleProfile();
      final suggestion = routeStyleTechniques(
        styleProfile: latestStyleProfile,
        activeProblems: activeSyndromeViews,
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
  }

  /// 6.5：学员技能层级软引导
  void _injectStudentSkillLevelGuidance({
    required BeginnerLevel? beginnerLevel,
    required List<ChatMessage> messages,
  }) {
    final studentSkillLevel = skillLevelForBeginner(beginnerLevel);
    if (studentSkillLevel == null) return;
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

  // ════════════════════════════════════════════════════════════════
  // injectDiagnosisLock focus 系列 helper (3)
  // ════════════════════════════════════════════════════════════════

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
      debugPrint('[SafeRun] buildFocusHistory 失败: $e');
      return [];
    }
  }

  /// 从用户消息解析 focus 切换意图（只解析 P\d+ 显式编码）
  String? _parseUserFocusFromMessage(
    String content,
    List<ActiveProblemView> activeProblems,
  ) {
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

  /// 选取焦点症候对应的 ActiveProblemView
  ActiveProblemView? _pickFocusProblem(
    List<ActiveProblemView> activeProblems,
    String? focusSyndromeId,
  ) {
    if (activeProblems.isEmpty) return null;
    final sid = focusSyndromeId ?? activeProblems.first.syndromeId;
    return activeProblems.where((p) => p.syndromeId == sid).firstOrNull;
  }

  // ════════════════════════════════════════════════════════════════
  // B1 阶段总结卡（公开 API，供 ChatService._handleTrainingResult 在 K-9 收尾前
  // 仍走本编排器；K-9 完成后改由 DiagnosisFlowHandler 注入此处）
  // ════════════════════════════════════════════════════════════════

  /// 阶段总结卡（B1）：某症候训练达标 mastered 时插入（公开，供外部诊断链路调用）
  ///
  /// 内部仍被 [_injectDiagnosisLock] 调用（聚类 A 跟随 helper），
  /// 同时供 ChatService._handleTrainingResult 暂用（K-9 收尾后改由
  /// DiagnosisFlowHandler 持此引用，本类不再被 ChatService 委派）。
  Future<void> insertPhaseSummaryOnMastered(
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
}

/// 内部 focus 历史条目
class _FocusHistoryItem {
  final String focusId;
  final int timestamp;
  const _FocusHistoryItem({required this.focusId, required this.timestamp});
}

/// 内部 focus 解析结果（focus-resolver → 主流程）
class _FocusResolveResult {
  final String? activatedFocusId;
  final focus.FocusSource source;
  final String reason;
  final String? rejectReason;
  const _FocusResolveResult({
    required this.activatedFocusId,
    required this.source,
    required this.reason,
    required this.rejectReason,
  });
}

/// 诊断请求标记（章节诊断 prompt 的特征子串，
/// 声线漂移 / 冲突观察等统一命中条件）
const String _kDiagnosisRequestMarker = '写作诊断分析';
