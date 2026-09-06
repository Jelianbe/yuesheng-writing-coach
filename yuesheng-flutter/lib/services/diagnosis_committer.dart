// ─────────────────────────────────────────────────────────────
// DiagnosisCommitter — 诊断提交编排器（独立类）
//
// ADR-C74 拆分重构的产物（批次 K）。从 ChatService 抽出诊断提交链路的所有
// 副作用（解析/落库/卡片/阶段迁移），自身无状态（除 B1 连续失败计数），
// 依赖通过构造函数注入——沿用 ADR-capability-contracts §3.2 「独立类 +
// 显式接口 + DI」三步法样板。
//
// 实施节奏（K-1 ~ K-5）：
//   K-1：本文件——仅类骨架（字段+构造），方法体待 K-2 ~ K-5 逐步迁入
//   K-2：迁 _applyPhaseMigration
//   K-3：迁 _parseAndPersist + _commitDiagnosisAndSuggestions
//   K-4：迁 _injectDiagnosisLock + _buildFactProtocolContext + _buildDriftHintContext
//   K-5：迁 commitDiagnosisFromContent 公开委派 + 落库辅助方法
//
// 关键不变量（K-1 阶段）：
//   - chatServiceProvider 注入本类实例，但 ChatService 不消费——
//     行为零变化，仅证明「独立类 + DI」路径可行（X-025-ARCH 教训复盘）
//   - sendMessage / _sendMessageCore 必须留 ChatService 薄壳，
//     避免 _FakeChatService @override 契约断裂
// ─────────────────────────────────────────────────────────────

// 私有字段（_xxx）+ 公开命名参数（xxx）模式无法用 initializing formal
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:writingcoach/contracts/diagnosis_capability.dart';
import 'package:writingcoach/contracts/genui_capability.dart';
import 'package:writingcoach/contracts/material_capability.dart';
import 'package:writingcoach/contracts/teaching_capability.dart';
import 'package:writingcoach/data/database/database.dart';
import 'package:writingcoach/data/repositories/chapter_repository.dart';
import 'package:writingcoach/data/repositories/character_fact_repository.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/event_fact_repository.dart';
import 'package:writingcoach/data/repositories/outline_repository.dart';
import 'package:writingcoach/data/repositories/reference_repository.dart';
import 'package:writingcoach/data/repositories/session_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/data/repositories/subplot_fact_repository.dart';
import 'package:writingcoach/data/repositories/teaching_state_repository.dart';
import 'package:writingcoach/services/diagnosis_service.dart';
import 'package:writingcoach/services/evaluation_service.dart';
import 'package:writingcoach/services/fact_parser.dart';
import 'package:writingcoach/services/fact_stale_service.dart';
import 'package:writingcoach/services/message_card_service.dart';
import 'package:writingcoach/services/outline_parser.dart';
import 'package:writingcoach/services/outline_service.dart';
import 'package:writingcoach/services/chat_context_builder.dart'
    show ReferenceItem;
import 'package:writingcoach/services/phase_mapper_resolver.dart';
import 'package:writingcoach/services/phase_transition.dart';
import 'package:writingcoach/data/database/utils.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 诊断提交编排器
///
/// 负责 AI 回复中 [YS_DIAGNOSIS] 块的解析、校验、落库、卡片生成、阶段迁移
/// 等所有副作用。sendMessage 与 commitDiagnosisFromContent 两条诊断路径的
/// 共用行为——通过本类保证一致（ADR-C74 §3.1，X-025-ARCH 复盘实证）。
///
/// 字段/依赖建模原则：
///   - 必备依赖（required）：6 个仓储 + 1 个 service + 4 个 capability
///   - 可选依赖（X-041c 模式）：4 个 nullable 仓储，不装配则跳过对应落库
///   - 内部状态：B1 连续失败计数（按 session 隔离，`Map<String, int>`）
///
/// K-1 阶段无任何方法体——仅类骨架，用于验证构造签名可编译、Provider 装配
/// 可实例化，且 ChatService 加 `final DiagnosisCommitter? _diagnosisCommitter`
/// 字段后六道门禁全绿（行为零变化护栏）。
class DiagnosisCommitter {
  // ─── 必备依赖（K-2 阶段升级为 nullable，K-3 ~ K-5 阶段随方法迁入
  //    按需收紧为 required）───
  //
  // 升级策略：
  //   K-2：仅 _applyPhaseMigration 迁入，用 4 仓储即可
  //   K-3：迁 _parseAndPersist / _commitDiagnosisAndSuggestions → 升 diagnosis 为 required
  //   K-4：迁 _injectDiagnosisLock + 协议块字符串构造 → 升 diagnosis 为 required
  //   K-5：迁 commitDiagnosisFromContent 委派 + 落库辅助 → 升 genUi/material/teaching 为 required
  //
  // 设计原则：nullable 是「演进中间态」，每一次收紧都靠 commit 落地——避免 K-1
  // 那种「字段预留但长期不用」的 unused_field 摊大饼。DiagnosisService 同理。
  final SessionRepository _sessionRepo;
  final TeachingStateRepository _stateRepo;
  final DiagnosisRepository _diagnosisRepo;
  final StudentModelRepository _studentModelRepo;

  // K-4 阶段新增：实体/事实落库辅助依赖
  final ReferenceRepository _referenceRepo;
  final ChapterRepository _chapterRepo;

  // ─── 可选依赖（X-041c 模式：nullable，不装配则跳过对应落库）───
  // C78 批次2a：db 仅用于构造 FactStaleService（事实 stale 标记）。未装配
  // → 跳过 stale 标记，落库行为与本批前完全一致（保护既有构造点）。
  final AppDatabase? _db;
  final OutlineRepository? _outlineRepo;
  final CharacterFactRepository? _characterFactRepo;
  final EventFactRepository? _eventFactRepo;
  final SubplotFactRepository? _subplotFactRepo;

  /// K-4 阶段：懒加载 outline service 缓存（与 ChatService._ensureOutlineService 同语义）。
  /// 装配了 outlineRepo → 首次使用即构建并缓存；未装配 → 永为 null。
  OutlineService? _outlineService;

  DiagnosisCommitter({
    required SessionRepository sessionRepo,
    required TeachingStateRepository stateRepo,
    required DiagnosisRepository diagnosisRepo,
    required StudentModelRepository studentModelRepo,
    // K-4 阶段新增 required：实体/事实落库辅助需要
    required ReferenceRepository referenceRepo,
    required ChapterRepository chapterRepo,
    // K-3 ~ K-5 阶段预留 capability/service 参数（K-9 收尾：字段已删，
    // 参数保留以维持构造签名向后兼容；lint 未启用参数 unused 检查）
    DiagnosisService? diagnosisService,
    GenUiCapability? genUi,
    MaterialCapability? material,
    TeachingCapability? teaching,
    DiagnosisCapability? diagnosis,
    // C78 批次2a：事实 stale 标记需要 AppDatabase（仅依赖链最底层，无环）
    AppDatabase? db,
    OutlineRepository? outlineRepo,
    CharacterFactRepository? characterFactRepo,
    EventFactRepository? eventFactRepo,
    SubplotFactRepository? subplotFactRepo,
  }) : _sessionRepo = sessionRepo,
       _stateRepo = stateRepo,
       _diagnosisRepo = diagnosisRepo,
       _studentModelRepo = studentModelRepo,
       _referenceRepo = referenceRepo,
       _chapterRepo = chapterRepo,
       _outlineRepo = outlineRepo,
       _characterFactRepo = characterFactRepo,
       _eventFactRepo = eventFactRepo,
       _subplotFactRepo = subplotFactRepo,
       _db = db;

  /// C78 批次2a：懒构建事实 stale 服务（未装配 db → null，跳过 stale 标记）。
  FactStaleService? get _factStale =>
      _db == null ? null : FactStaleService(_db);

  /// K-4：懒加载大纲服务（批次7 O2 模式，与 ChatService 同语义）。
  OutlineService? _ensureOutlineService() {
    _outlineService ??= _outlineRepo != null
        ? OutlineService(_outlineRepo)
        : null;
    return _outlineService;
  }

  // ─────────────────────────────────────────────────────────────
  // K-2：applyPhaseMigration 阶段迁移统一处理
  //
  // 由 ChatService._sendMessageCore (L2480) 与 commitDiagnosisFromContent
  // (L731) 两条路径调用——保证两条诊断路径的阶段迁移行为一致。
  //
  // 内部三步：
  //   1. AI 驱动路径（路径 1）：diagnosis 输出 suggestedPhase/Level → resolver
  //   2. M4-B validatePhaseTransition 校验 + 相邻降级（clampEarlyPhaseSkip）
  //   3. M4-A 自动迁移（路径 2）：所有活跃症候 resolved + 达标率 ≥ phasePassRate
  //
  // 公开 + @visibleForTesting：迁出后允许专项测试直接覆盖本方法，弥补
  // sendMessage 私有路径无法单元测试的局限（X-025-ARCH 教训复盘）。
  // ─────────────────────────────────────────────────────────────

  /// 阶段迁移统一处理（批次6 D1）——AI 驱动 resolver + M4-A 自动迁移 + M4-C 达标率校验
  ///
  /// 供 [commitDiagnosisFromContent] 与 sendMessage 复用，保证两条诊断路径行为一致：
  ///   - sendMessage：单次诊断（≤4000 字）
  ///   - commitDiagnosisFromContent：超长分块诊断（>4000 字，progressive 路径）
  ///
  /// 内部职责（均 try/catch 包裹，失败不阻断主流程）：
  ///   1. diagnosis 输出 suggestedPhase/suggestedBeginnerLevel 时 → phase-mapper resolver
  ///   2. effectivePhase → M4-B validatePhaseTransition 校验 → updatePhase + 子阶段重置 + 升级卡片
  ///   3. effectiveBeginnerLevel → updateBeginnerLevel
  ///   4. 所有活跃症候已 resolved → M4-A 自动迁移（M4-C 达标率 ≥ phasePassRate 才放行）
  Future<void> applyPhaseMigration({
    required String sessionId,
    required ParsedDiagnosis? diagnosis,
  }) async {
    // 批次1（C5/H3）：路径1（AI 驱动）成功迁移后，路径2（M4-A 自动）不得
    // 再无条件继续，防止同轮链式双跳（如 P1→P2→P3）
    final path1Migrated = await _applyResolverMigration(sessionId, diagnosis);
    if (path1Migrated) return;

    // ── 2. 自动迁移路径：M4-A + M4-C 达标率校验 ──
    await _applyAutomaticMigration(sessionId);
  }

  /// 路径1：AI 驱动迁移（phase-mapper resolver）。返回是否真实迁移。
  Future<bool> _applyResolverMigration(
    String sessionId,
    ParsedDiagnosis? diagnosis,
  ) async {
    final hasSignal =
        diagnosis != null &&
        (diagnosis.suggestedPhase != null ||
            diagnosis.suggestedBeginnerLevel != null);
    if (!hasSignal) {
      await _logN38MissingMigration(sessionId, diagnosis);
      return false;
    }
    final d = diagnosis;
    try {
      final currentState = await _stateRepo.getTeachingState(sessionId);
      final currentBeginnerLevel = BeginnerLevel.fromString(
        currentState?.beginnerLevel,
      );
      final consecutiveFailedTrainings =
          await _computeConsecutiveFailedTrainings(
            sessionId,
            currentBeginnerLevel,
            d,
          );
      return await _applyResolverResult(
        sessionId,
        currentState,
        d,
        consecutiveFailedTrainings,
      );
    } catch (e) {
      debugPrint('[SafeRun] resolver 失败不阻断主流程: $e');
      return false;
    }
  }

  /// 解析器结果应用：阶段 + 学员等级落库（R-019 二次拆）。
  Future<bool> _applyResolverResult(
    String sessionId,
    TeachingStateRow? currentState,
    ParsedDiagnosis d,
    int consecutiveFailedTrainings,
  ) async {
    final resolverResult = resolvePhaseMapper(
      PhaseMapperInput(
        currentPhase: TeachingPhase.fromString(currentState?.currentPhase),
        currentBeginnerLevel: BeginnerLevel.fromString(
          currentState?.beginnerLevel,
        ),
        suggestedPhase: d.suggestedPhase,
        suggestedBeginnerLevel: d.suggestedBeginnerLevel,
        consecutiveFailedTrainings: consecutiveFailedTrainings,
      ),
    );
    var migrated = false;
    if (resolverResult.effectivePhase != null) {
      migrated = await _applyResolvedPhase(
        sessionId,
        currentState?.currentPhase,
        resolverResult.effectivePhase!,
      );
    }
    if (resolverResult.effectiveBeginnerLevel != null) {
      await _stateRepo.updateBeginnerLevel(
        sessionId,
        resolverResult.effectiveBeginnerLevel!.value,
      );
    }
    return migrated;
  }

  /// 计算连续失败训练次数（仅 N3 触发降级检查时需要）。
  Future<int> _computeConsecutiveFailedTrainings(
    String sessionId,
    BeginnerLevel? currentBeginnerLevel,
    ParsedDiagnosis diagnosis,
  ) async {
    if (currentBeginnerLevel != BeginnerLevel.n3Diagnose) return 0;
    try {
      final allHistory = await _studentModelRepo.getTeachingHistory(sessionId);
      final activeProblems = await _diagnosisRepo.listActiveProblems(sessionId);
      final focusSyndromeId =
          diagnosis.currentTeachingFocusId ??
          activeProblems.firstOrNull?.syndromeId;
      if (focusSyndromeId == null) return 0;
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
      var consecutiveFailedTrainings = 0;
      for (int i = trainingRecords.length - 1; i >= 0; i--) {
        if (trainingRecords[i]['result'] == 'failed') {
          consecutiveFailedTrainings++;
        } else {
          break;
        }
      }
      return consecutiveFailedTrainings;
    } catch (e) {
      debugPrint('[SafeRun] resolver 训练记录读取失败: $e');
      return 0;
    }
  }

  /// M4-B 校验 + 阶段迁移（含 C54 clamp 降级）。返回是否真实迁移。
  Future<bool> _applyResolvedPhase(
    String sessionId,
    String? prevPhaseValue,
    TeachingPhase effectivePhase,
  ) async {
    final currentPhaseForValidation =
        TeachingPhase.fromString(prevPhaseValue) ?? TeachingPhase.p0Engage;
    if (validatePhaseTransition(currentPhaseForValidation, effectivePhase)) {
      await _stateRepo.updatePhase(sessionId, effectivePhase.value);
      // 批次9：阶段真实变化时插入 phase_upgrade 卡片（对齐 RN insertPhaseUpgradeCard）
      if (prevPhaseValue != effectivePhase.value) {
        // M4-D: 阶段迁移时重置子阶段，避免上一阶段子阶段残留
        await _stateRepo.updateSubphase(sessionId, null);
        await _insertUpgradeCard(
          sessionId,
          prevPhaseValue ?? TeachingPhase.p0Engage.value,
          effectivePhase.value,
        );
        return true;
      }
      return false;
    }
    // C54 方案 C（C-2，ADR-C54 §4-C-2）：早期跨一格的非法建议
    // 确定性降级为相邻递进，而非整轮丢弃——首诊双信号场景
    // （P0→P1 与 P1→P2 同时成立）不再依赖 AI 采样选择
    final fallback = clampEarlyPhaseSkip(
      currentPhaseForValidation,
      effectivePhase,
    );
    if (fallback == null) {
      debugPrint(
        '[SafeRun] M4-B: 阶段迁移非法已拦截 '
        '$currentPhaseForValidation → $effectivePhase',
      );
      return false;
    }
    await _stateRepo.updatePhase(sessionId, fallback.value);
    // M4-D: 阶段迁移时重置子阶段，避免上一阶段子阶段残留
    await _stateRepo.updateSubphase(sessionId, null);
    await _insertUpgradeCard(
      sessionId,
      prevPhaseValue ?? TeachingPhase.p0Engage.value,
      fallback.value,
    );
    return true;
  }

  /// 阶段迁移卡片插入（失败不影响迁移）。
  Future<void> _insertUpgradeCard(
    String sessionId,
    String from,
    String to,
  ) async {
    try {
      await insertPhaseUpgradeCard(
        _sessionRepo,
        sessionId,
        PhaseUpgradeCardPayload(from: from, to: to),
      );
    } catch (e) {
      debugPrint('[SafeRun] 卡片插入失败不影响阶段迁移: $e');
    }
  }

  /// N38 可观测性：诊断含症候但无 suggested_phase，仅 P0/P1 告警。
  Future<void> _logN38MissingMigration(
    String sessionId,
    ParsedDiagnosis? diagnosis,
  ) async {
    if (diagnosis == null || diagnosis.syndromes.isEmpty) return;
    // 此处只记录、不改行为——代码侧不代填迁移，避免越权改动教学状态机。
    try {
      final state = await _stateRepo.getTeachingState(sessionId);
      final phase = TeachingPhase.fromString(state?.currentPhase);
      if (phase == TeachingPhase.p0Engage || phase == TeachingPhase.p1World) {
        debugPrint(
          '[N38] ${phase!.value} 阶段诊断块含 ${diagnosis.syndromes.length} 个症候'
          '（迁移信号已成立）但无 suggested_phase → 本轮不发生阶段迁移',
        );
      }
    } catch (e) {
      debugPrint('[SafeRun] N38 可观测读取教学状态失败: $e');
    }
  }

  /// 路径2：M4-A 自动迁移（所有活跃症候 resolved + M4-C 达标率）。
  Future<void> _applyAutomaticMigration(String sessionId) async {
    // 守卫：仅在 P2 及以后触发（P0/P1 阶段迁移由 AI suggested_phase 驱动）
    // M4-C: passRate >= phasePassRate(0.7) 才允许迁移，避免手动标记完成跳过训练升阶
    try {
      final remaining = await _diagnosisRepo.listActiveProblems(sessionId);
      if (remaining.isEmpty) {
        await _tryAutomaticUpgrade(sessionId);
      }
    } catch (e) {
      debugPrint('[SafeRun] 自动迁移失败不阻断主流程: $e');
    }
  }

  /// M4-A 单次自动升阶评估。
  Future<void> _tryAutomaticUpgrade(String sessionId) async {
    final ts = await _stateRepo.getTeachingState(sessionId);
    final currentPhase =
        TeachingPhase.fromString(ts?.currentPhase) ?? TeachingPhase.p0Engage;
    if (currentPhase == TeachingPhase.p0Engage ||
        currentPhase == TeachingPhase.p1World) {
      return;
    }
    final evalService = EvaluationService(_diagnosisRepo, _studentModelRepo);
    final passRate = await evalService.computePassRateForPhaseMigration(
      sessionId,
    );
    if (passRate < EvaluationThresholds.phasePassRate) {
      debugPrint(
        '[SafeRun] M4-C: 达标率 $passRate < '
        '${EvaluationThresholds.phasePassRate}，阶段暂不迁移',
      );
      return;
    }
    final next = nextPhase(currentPhase);
    // M4-B: nextPhase 已保证相邻递进，validatePhaseTransition 双重校验
    if (next == null || !validatePhaseTransition(currentPhase, next)) return;
    await _stateRepo.updatePhase(sessionId, next.value);
    await _stateRepo.updateSubphase(sessionId, null);
    await _insertUpgradeCard(sessionId, currentPhase.value, next.value);
  }

  // ─────────────────────────────────────────────────────────────
  // K-3：协议块字符串构造器（纯字符串，无 IO 依赖）
  //
  // 原 ChatService.extension.ChatServiceDiagnosis._buildFactProtocolContext
  // + _buildDriftHintContext 迁出。零私有依赖，可独立测试。
  //
  // sendMessage 主链两处调用（L1574 / L1650）改为
  //   `_diagnosisCommitter?.buildXxx(...) ?? ''`
  // —— production 必装，nullable 仅为测试兼容 K-1 设计。
  // ─────────────────────────────────────────────────────────────

  /// 批次64（B62f）：声线漂移提示上下文——引导 AI 以提问方式温和指出其中一条
  String buildDriftHintContext(List<String> hints) {
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
  String buildFactProtocolContext() {
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
        '"chapter":3,"evidence":"原文摘录（≤30字）"}\n'
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
        'chapter 为该断言出现的章节序号。同一人物可多条断言。'
        'evidence 为该断言在正文中的原句摘录（非转述、非概括），供学员核对依据；'
        '无对应原文时省略该字段（不填空串）。\n'
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

  // ─────────────────────────────────────────────────────────────
  // K-4：实体/事实落库辅助——applyOutlineEntitiesFromContent + applyFactExtractionFromContent
  //
  // 原 ChatService.extension.ChatServiceDiagnosisApply 上两个方法迁出。
  // 两条诊断路径共用（commitDiagnosisFromContent + sendMessage._parseAndPersist），
  // 通过本类保证一致。
  // ─────────────────────────────────────────────────────────────

  /// 大纲实体提取 + 确认卡写入（批次72/73/74 D4-A 共用）
  ///
  /// 失败/未装配/无大纲块/非章节主引用 → 静默跳过不抛。
  /// 优先使用入参传入的 primaryRef（sendMessage 路径）；
  /// 若未传（commitDiagnosisFromContent 路径）则从 session 的当前引用取。
  Future<void> applyOutlineEntitiesFromContent({
    required String sessionId,
    required String fullContent,
    ReferenceItem? primaryRef,
  }) async {
    if (_ensureOutlineService() == null) return;
    final pRef = await _resolveChapterPrimaryRef(sessionId, primaryRef);
    if (pRef?.refType != 'chapter') return;
    try {
      await _persistOutlineExtraction(sessionId, fullContent, pRef!);
    } catch (e) {
      debugPrint('[SafeRun] commitOutlineChangeFromContent 大纲落库失败: $e');
    }
  }

  /// 解析主引用（R-019 拆出：applyOutlineEntitiesFromContent）。
  /// 入参未传（D4-A 路径）时从 session 引用装配；查询失败返回 null。
  Future<ReferenceItem?> _resolveChapterPrimaryRef(
    String sessionId,
    ReferenceItem? primaryRef,
  ) async {
    if (primaryRef != null) return primaryRef;
    try {
      final refs = await _referenceRepo.listReferences(sessionId);
      if (refs.isEmpty) return null;
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
      return items.firstWhere(
        (r) => r.isPrimary == 1,
        orElse: () => items.first,
      );
    } catch (e) {
      debugPrint('[SafeRun] commitOutlineChangeFromContent 引用查询失败: $e');
      return null;
    }
  }

  /// 大纲提取落库 + 确认卡写入（R-019 拆出：applyOutlineEntitiesFromContent）。
  Future<void> _persistOutlineExtraction(
    String sessionId,
    String fullContent,
    ReferenceItem pRef,
  ) async {
    final outlineExtraction = parseOutlineExtraction(fullContent);
    if (outlineExtraction == null || outlineExtraction.entities.isEmpty) {
      return;
    }
    final chapter = await _chapterRepo.getChapter(pRef.refId);
    if (chapter == null) return;
    final results = await _ensureOutlineService()!.applyOutlineExtraction(
      manuscriptId: chapter.manuscriptId,
      extraction: outlineExtraction,
      sourceChapterId: chapter.id,
      sourceChapterNo: chapter.sortOrder,
    );
    debugPrint(
      '[DiagnosisCommitter] 大纲提取落库 | 实体数=${outlineExtraction.entities.length}',
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
  }

  /// A6：事实提取落库（时序知识图谱写入路径）
  ///
  /// 从 AI 诊断回复中提取 [YS_FACT] 块，将人物/事件/支线事实
  /// upsert 到 character_fact/event_fact/subplot_fact 三表。
  /// 失败/未装配/无事实块/非章节 → 静默跳过不抛。
  /// 优先使用入参 primaryRef（sendMessage 路径）；
  /// 若未传（commitDiagnosisFromContent 路径）则从 session 引用取。
  /// C78 批次3（FR-10）：返回 `（本轮净新增人物断言条数, 作品ID）`——
  /// 诊断流经 onFactBatch 回调登记为消息尾部提示卡（内存态，ADR-C78 冲突 C）。
  /// 净新增 = 落库后断言数 − 落库前（AI 重抽同三元组被合并/替换不计入，
  /// 「沉淀 N 条」必须与角色页可见的新增一致，不夸大）。
  Future<({int count, String? manuscriptId})> applyFactExtractionFromContent({
    required String sessionId,
    required String fullContent,
    ReferenceItem? primaryRef,
  }) async {
    // 三表仓储至少一个未装配 → 跳过
    if (_characterFactRepo == null &&
        _eventFactRepo == null &&
        _subplotFactRepo == null) {
      return (count: 0, manuscriptId: null);
    }

    // 解析 primaryRef（同 _applyOutlineEntitiesFromContent 模式）
    final pRef = await _resolveFactPrimaryRef(primaryRef, sessionId);
    if (pRef == null || pRef.refType != 'chapter') {
      return (count: 0, manuscriptId: null);
    }

    try {
      final extraction = parseFactExtraction(fullContent);
      if (extraction == null || extraction.isEmpty) {
        return (count: 0, manuscriptId: null);
      }

      final chapter = await _chapterRepo.getChapter(pRef.refId);
      if (chapter == null) return (count: 0, manuscriptId: null);
      final added = await _commitFacts(chapter, extraction);

      debugPrint(
        '[DiagnosisCommitter] A6 事实提取落库 | 人物=${extraction.characters.length} '
        '事件=${extraction.events.length} 支线=${extraction.subplots.length} '
        '净新增断言=$added',
      );
      return (count: added, manuscriptId: chapter.manuscriptId);
    } catch (e) {
      debugPrint('[SafeRun] 事实提取三表落库失败: $e');
      return (count: 0, manuscriptId: null);
    }
  }

  /// 三表落库（R-019：由 [applyFactExtractionFromContent] 抽出）。
  ///
  /// C78 批次2a：[chapter] 已取到，正文指纹直接由 `chapter.content` 算出——
  /// 无需再按 ADR 设想用 getChapterByOrder 反查一次，省一次查询。
  /// C78 批次3：返回本轮**净新增**人物断言条数（FR-10 提示卡计数来源）。
  Future<int> _commitFacts(Chapter chapter, FactExtraction extraction) async {
    final manuscriptId = chapter.manuscriptId;
    final chapterNo = chapter.sortOrder;
    final now = nowSec();
    final content = chapter.content;
    final added = await _persistCharacterFacts(
      extraction,
      manuscriptId,
      chapterNo,
      now,
      chapterContent: content,
    );
    await _persistEventFacts(
      extraction,
      manuscriptId,
      chapterNo,
      chapterContent: content,
    );
    await _persistSubplotFacts(extraction, manuscriptId, chapterNo, now);
    return added;
  }

  /// 解析 primaryRef（同 _applyOutlineEntitiesFromContent 模式）（R-019 拆出）。
  Future<ReferenceItem?> _resolveFactPrimaryRef(
    ReferenceItem? primaryRef,
    String sessionId,
  ) async {
    if (primaryRef != null) return primaryRef;
    try {
      final refs = await _referenceRepo.listReferences(sessionId);
      if (refs.isEmpty) return null;
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
      return items.firstWhere(
        (r) => r.isPrimary == 1,
        orElse: () => items.first,
      );
    } catch (e) {
      debugPrint('[SafeRun] persistTeacherSuggestion 失败: $e');
      return null;
    }
  }

  /// 人物事实 → character_fact（R-019 拆出）。
  ///
  /// C78 批次2a：[chapterContent] 用于算当前指纹，填 hash / 标旧版 / 三元组
  /// 合并三件事全部委托 [FactStaleService.mergeAssertions]（在 upsertCharacter
  /// 内部调用——既有断言只有在那里才读得到）。
  /// C78 批次3：返回净新增断言数（落库前后逐角色对账；替换/去重不计）。
  Future<int> _persistCharacterFacts(
    FactExtraction extraction,
    String manuscriptId,
    int chapterNo,
    int now, {
    required String chapterContent,
  }) async {
    final repo = _characterFactRepo;
    if (repo == null) return 0;
    final currentHash = chapterFingerprint(chapterContent);
    var added = 0;
    for (final c in extraction.characters) {
      final before = await _countAssertions(repo, manuscriptId, c.name);
      await repo.upsertCharacter(
        manuscriptId: manuscriptId,
        name: c.name,
        firstSeenChapter: chapterNo,
        firstSeenAt: now,
        assertions: c.assertions,
        chapterHash: currentHash,
        chapterNo: chapterNo,
      );
      final after = await _countAssertions(repo, manuscriptId, c.name);
      added += after - before;
    }
    return added;
  }

  /// 该角色行当前的断言条数（净新增对账用；行不存在计 0）。
  Future<int> _countAssertions(
    CharacterFactRepository repo,
    String manuscriptId,
    String name,
  ) async {
    final row = await repo.getCharacter(manuscriptId, name);
    if (row == null) return 0;
    return CharacterFactRepository.parseAssertions(row.assertions).length;
  }

  /// 事件事实 → event_fact：两轮写入（upsert 全部 + 反查填因果边）（R-019 拆出）。
  Future<void> _persistEventFacts(
    FactExtraction extraction,
    String manuscriptId,
    int chapterNo, {
    required String chapterContent,
  }) async {
    final repo = _eventFactRepo;
    if (repo == null) return;
    final currentHash = chapterFingerprint(chapterContent);
    for (final e in extraction.events) {
      await repo.upsertEvent(
        manuscriptId: manuscriptId,
        name: e.name,
        eventType: e.eventType,
        chapter: e.chapter ?? chapterNo,
        participants: e.participants,
        description: e.description,
        chapterHash: currentHash,
      );
    }
    // C78 批次2a：本轮重新确认过的事件已被 upsert 刷成 currentHash，下面
    // 这条判据（chapterHash != currentHash）会自动跳过它们，只标真正的旧版。
    await _factStale?.markStaleEvents(
      manuscriptId: manuscriptId,
      chapterNo: chapterNo,
      chapterHash: currentHash,
    );
    // 第二轮：填因果边（causeEventName → causeEventId）
    for (final e in extraction.events) {
      final causeName = e.causeEventName;
      if (causeName == null) continue;
      final self = await repo.getEvent(manuscriptId, e.name);
      final cause = await repo.getEvent(manuscriptId, causeName);
      if (self != null && cause != null) {
        await repo.updateCauseEventId(self.id, cause.id);
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

  /// 支线事实 → subplot_fact（R-019 拆出）。
  Future<void> _persistSubplotFacts(
    FactExtraction extraction,
    String manuscriptId,
    int chapterNo,
    int now,
  ) async {
    final repo = _subplotFactRepo;
    if (repo == null) return;
    for (final s in extraction.subplots) {
      await repo.upsertSubplot(
        manuscriptId: manuscriptId,
        name: s.name,
        introducedChapter: s.introducedChapter ?? chapterNo,
        resolvedChapter: s.resolvedChapter,
        resolvedAt: s.resolvedChapter != null ? now : null,
        description: s.description,
      );
    }
  }
}
