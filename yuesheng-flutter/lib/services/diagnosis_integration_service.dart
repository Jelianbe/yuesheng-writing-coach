// ─────────────────────────────────────────────────────────────
// diagnosis_integration_service — 诊断整合与决策层 · 阶段一（W-21）
//
// 设计稿：docs/designs/2026-10-15-W21-诊断整合与决策层-阶段一-最小整合层与数据契约-设计稿.md
// 舰长已批（2026-10-15）。A 批 = 四数据契约 + A1 分组 + A4 未决收口；
// B 批 = A2 全局假设 + A3 焦点候选 + commit 旁路接线。
//
// 铁律（设计稿 §四「能用代码保证的不交给模型」）：
//   - 本服务**零 LLM 调用**：全部输出是既有诊断数据的确定性变换；
//   - 只读观察者：不新增表、不改 commit 链路、不接教学闸门；
//   - 纯函数：不改输入；旁路纪律（未来接线时失败静默不阻断主流程）。
// ─────────────────────────────────────────────────────────────

import '../types/teaching_types.dart';
import 'diagnosis_validator.dart' show kMutexSyndromePairs;
import 'merge_convergence.dart' show evidenceJaccard, kEvidenceJaccardThreshold;
import 'syndrome_registry.dart' show QuantityTag, quantityTagOf;

/// A2 系统性判定初值（设计稿 §六：拍初值，待 W-23 用 10–15 案例标定）。
const int kSystematicChapterThreshold = 3;

// ── 输入契约：诊断条目引用（来自 diagnosis_results 行，不复制原文）──

/// 单条诊断条目的引用视图（A1 分组输入）。
class DiagnosisEntryRef {
  final String rowId; // diagnosis_results 行主键
  final int entryIndex; // 行内 syndromes[] 下标
  final String syndromeId;
  final Severity severity;
  final List<String> evidence;
  final String chapterId; // 诊断发生时正在写的章节（跨章分组依据）
  final int createdAtSec; // epoch 秒（台账时间口径）

  /// W-19-A 干预价值档位（'high'/'medium'/'low'/null），A3 评分消费。
  final String? interventionValue;

  const DiagnosisEntryRef({
    required this.rowId,
    required this.entryIndex,
    required this.syndromeId,
    required this.severity,
    required this.evidence,
    required this.chapterId,
    required this.createdAtSec,
    this.interventionValue,
  });

  String get ref => '$rowId#$entryIndex';
}

// ── 输出契约（四结构，设计稿 §三）──

/// A1 产物：症候组（同 syndrome_id 为分组主键）。
class DiagnosisGroup {
  final String groupId;
  final String syndromeId;

  /// 全部成员条目引用（含被归并的同章重复——不丢任何引用）。
  final List<String> memberRefs;

  final int firstSeenSec;
  final int lastSeenSec;

  /// 独立出现过的章节（同章重复条目不重复计数，见 [kEvidenceJaccardThreshold] 用法）。
  final List<String> chapterSpan;

  final Severity severityMax;
  final List<String> evidencePool; // 去重并集

  /// 独立出现次数（= chapterSpan.length；系统性判定 N 的分母，A2/B 批消费）。
  int get chapterCount => chapterSpan.length;

  /// 同章高重叠被归并的条目数（归并不删引用，仅不重复计数章节）。
  final int duplicateMergedCount;

  /// 组内出现过的最高干预价值档位（null = 组内全部未评定；A3 评分消费）。
  final String? interventionValueMax;

  const DiagnosisGroup({
    required this.groupId,
    required this.syndromeId,
    required this.memberRefs,
    required this.firstSeenSec,
    required this.lastSeenSec,
    required this.chapterSpan,
    required this.severityMax,
    required this.evidencePool,
    required this.duplicateMergedCount,
    this.interventionValueMax,
  });
}

/// A2 产物（B 批实现，本批仅契约占位）。
class GlobalHypothesis {
  final String hypothesisId;
  final String kind; // 'systematic' | 'structural'
  final String statement; // 代码模板生成，非 LLM
  final List<String> sourceGroupIds;
  final String ruleId;
  final String status; // active | confirmed | rejected

  const GlobalHypothesis({
    required this.hypothesisId,
    required this.kind,
    required this.statement,
    required this.sourceGroupIds,
    required this.ruleId,
    required this.status,
  });
}

/// A3 产物（B 批实现，本批仅契约占位）。
class TeachingFocusCandidate {
  final String candidateId;
  final String syndromeId;
  final String groupId;
  final Map<String, num> scoreBreakdown; // 各分量独立可解释
  final String rationale; // 代码拼接，非 LLM
  final String status; // proposed（决定权在用户/阶段二）

  const TeachingFocusCandidate({
    required this.candidateId,
    required this.syndromeId,
    required this.groupId,
    required this.scoreBreakdown,
    required this.rationale,
    required this.status,
  });
}

/// A4 产物：未决问题（三类显式收口，禁止静默丢弃）。
class UnresolvedQuestion {
  static const kindPendingContext = 'pending_context';
  static const kindInsufficientEvidence = 'insufficient_evidence';
  static const kindNeedsHuman = 'needs_human';

  final String questionId;
  final String kind;
  final String statement; // 代码模板生成
  final List<String> blockingRefs;
  final int createdAtSec;
  final int? resolvedAt; // null = 未决

  const UnresolvedQuestion({
    required this.questionId,
    required this.kind,
    required this.statement,
    required this.blockingRefs,
    required this.createdAtSec,
    this.resolvedAt,
  });
}

/// 整合快照（四契约容器；hypotheses/candidates 由 B 批填充）。
class IntegrationSnapshot {
  final List<DiagnosisGroup> groups;
  final List<GlobalHypothesis> hypotheses; // B 批：恒空
  final List<TeachingFocusCandidate> candidates; // B 批：恒空
  final List<UnresolvedQuestion> questions;

  const IntegrationSnapshot({
    required this.groups,
    required this.hypotheses,
    required this.candidates,
    required this.questions,
  });
}

/// 档 A 探针摘要（W-21 接线清偿，2026-10-16）：把快照的 A2/A4 产物压成
/// 一行调试摘要，使「全局假设/未决问题」不流成**静默丢弃**（设计稿 A4
/// 原则明文禁止）。零持久化、零自动行为；两罐皆空 ⇒ 空串（调用方不打日志）。
/// 产品面消费（UI / prompt）属阶段三范围，prompt 向涉 R-027 须报批。
String formatIntegrationProbeSummary(IntegrationSnapshot snapshot) {
  final h = snapshot.hypotheses.length;
  final q = snapshot.questions.length;
  if (h == 0 && q == 0) return '';
  final buf = StringBuffer('[整合层探针] 假设 $h · 未决 $q');
  for (final e in snapshot.questions.take(3)) {
    final st = e.statement.length <= 60
        ? e.statement
        : '${e.statement.substring(0, 60)}…';
    buf.write(' | ${e.kind}：$st');
  }
  return buf.toString();
}

// ── A4 输入：外部未决源（pending_context 由 W-15-B 产出；人裁冲突由调用方给）──

/// 未决源条目（pending_context / needs_human 共用形态）。
class UnresolvedSource {
  final String statement;
  final List<String> blockingRefs;

  const UnresolvedSource(this.statement, this.blockingRefs);
}

// ── A1：分组（纯代码）──

/// 按 syndrome_id 分组；组内「同章 + 证据重叠 ≥ 阈值」的条目归并
/// （章节不重复计数，但引用全保留——不丢任何落库痕迹）。
List<DiagnosisGroup> buildDiagnosisGroups(List<DiagnosisEntryRef> entries) {
  final byId = <String, List<DiagnosisEntryRef>>{};
  for (final e in entries) {
    byId.putIfAbsent(e.syndromeId, () => []).add(e);
  }
  final groups = <DiagnosisGroup>[];
  for (final id in byId.keys.toList()..sort()) {
    groups.add(_buildGroup(id, byId[id]!));
  }
  return groups;
}

DiagnosisGroup _buildGroup(String syndromeId, List<DiagnosisEntryRef> members) {
  final sorted = List<DiagnosisEntryRef>.of(members)
    ..sort((a, b) => a.createdAtSec.compareTo(b.createdAtSec));
  final chapterClusters = <String, List<DiagnosisEntryRef>>{}; // 章 → 簇首条目组
  var duplicateMerged = 0;
  for (final e in sorted) {
    final prior = chapterClusters[e.chapterId];
    final isDup =
        prior != null &&
        prior.any(
          (p) =>
              evidenceJaccard(p.evidence, e.evidence) >=
              kEvidenceJaccardThreshold,
        );
    if (isDup) {
      duplicateMerged++;
    } else {
      chapterClusters.putIfAbsent(e.chapterId, () => []).add(e);
    }
  }
  final evidencePool = <String>{};
  for (final e in sorted) {
    evidencePool.addAll(e.evidence.where((x) => x.trim().isNotEmpty));
  }
  return DiagnosisGroup(
    groupId: 'dg-$syndromeId',
    syndromeId: syndromeId,
    memberRefs: sorted.map((e) => e.ref).toList(),
    firstSeenSec: sorted.first.createdAtSec,
    lastSeenSec: sorted.last.createdAtSec,
    chapterSpan: chapterClusters.keys.toList()..sort(),
    severityMax: sorted
        .reduce((a, b) => a.severity.index >= b.severity.index ? a : b)
        .severity,
    evidencePool: evidencePool.toList()..sort(),
    duplicateMergedCount: duplicateMerged,
    interventionValueMax: _maxInterventionValue(sorted),
  );
}

/// 组内最高干预价值档位（W-19-A rank 口径；全 null → null）。
String? _maxInterventionValue(List<DiagnosisEntryRef> entries) {
  String? best;
  var bestRank = -1;
  for (final e in entries) {
    final r = interventionValueRank(e.interventionValue);
    if (r > bestRank) {
      bestRank = r;
      best = e.interventionValue;
    }
  }
  return best;
}

// ── A4：未决问题（显式收口）──

/// 三源收口：① pending_context（W-15-B 产出，未施工前为空）
/// ② 证据不足（证据池为空的组——「报了条目但拿不出证据」）
/// ③ 需人裁决（调用方显式传入的规则冲突/人工挂起项）。
List<UnresolvedQuestion> collectUnresolvedQuestions(
  List<DiagnosisGroup> groups, {
  List<UnresolvedSource> pendingContexts = const [],
  List<UnresolvedSource> humanConflicts = const [],
  required int nowSec,
}) {
  final out = <UnresolvedQuestion>[];
  var i = 0;
  for (final p in pendingContexts) {
    out.add(
      UnresolvedQuestion(
        questionId: 'uq-pending-$nowSec-$i',
        kind: UnresolvedQuestion.kindPendingContext,
        statement: p.statement,
        blockingRefs: p.blockingRefs,
        createdAtSec: nowSec,
      ),
    );
    i++;
  }
  for (final g in groups) {
    if (g.evidencePool.isEmpty) {
      out.add(
        UnresolvedQuestion(
          questionId: 'uq-evidence-$nowSec-${g.syndromeId}',
          kind: UnresolvedQuestion.kindInsufficientEvidence,
          statement:
              '症候 ${g.syndromeId} 共 ${g.memberRefs.length} 条诊断'
              '，但证据池为空——无法追溯，待补充原文证据或人工复核',
          blockingRefs: g.memberRefs,
          createdAtSec: nowSec,
        ),
      );
    }
  }
  for (final c in humanConflicts) {
    out.add(
      UnresolvedQuestion(
        questionId: 'uq-human-$nowSec-$i',
        kind: UnresolvedQuestion.kindNeedsHuman,
        statement: c.statement,
        blockingRefs: c.blockingRefs,
        createdAtSec: nowSec,
      ),
    );
    i++;
  }
  return out;
}

/// A4 ①类输入合成（W-21 接线清偿，2026-10-16）：调用方把 W-15-B 产出的
/// `Syndrome.pendingContext` 标记转成未决源。仅 `pendingContext == true`
/// 的症候产源；阻塞引用 = 该症候本轮诊断条目定位（`messageId#index`，
/// 与 `DiagnosisEntryRef.ref` 同格式）。
List<UnresolvedSource> buildPendingContextSources({
  required List<Syndrome> syndromes,
  required String messageId,
}) {
  final out = <UnresolvedSource>[];
  for (var i = 0; i < syndromes.length; i++) {
    final s = syndromes[i];
    if (s.pendingContext != true) continue;
    out.add(
      UnresolvedSource(
        '症候 ${s.syndromeId} 的判定带跨块因果缺口标记（pending_context）'
        '——因果链证据待补，未收敛为确定性结论',
        <String>['$messageId#$i'],
      ),
    );
  }
  return out;
}

/// A4 ③类输入：单症候的人裁状态快照（T-20261016-05）。
///
/// 调用方从两个既有仓储读出后转置（本服务不依赖 data 层类型，与
/// [DiagnosisEntryRef] 同层——保持纯函数可测、零 DB 依赖）：
///   - `confirmationStatus` = `active_problem.confirmation_status` 当前态；
///   - `occurrenceCount` = 同章节会话内正式诊断次数（G15 口径，
///     `DiagnosisRepository.countConfirmedDiagnosesBySyndrome`）。
class HumanAdjudication {
  final String syndromeId;
  final String syndromeName;
  final String confirmationStatus;
  final int occurrenceCount;

  const HumanAdjudication({
    required this.syndromeId,
    required this.syndromeName,
    required this.confirmationStatus,
    required this.occurrenceCount,
  });
}

/// A4 ③类输入合成（T-20261016-05，口径 `DECISIONS §4-201` 项 4）：
/// 人裁冲突 = 症候当前裁决态为 **rejected** 且同章节会话内正式诊断
/// **再现 ≥ 2 次** ⇒ 未决源（落 kindNeedsHuman，由
/// [collectUnresolvedQuestions] 登记）。**ignored 不计**（无主动信号）；
/// suspected / confirmed 非冲突态同样不计。输出保序（调用方供数序）。
///
/// 判据精度如实登记（R-009 同源纪律：不伪装可观测性）——当前 schema
/// **无裁决历史表**（active_problem 单行/(会话,症候)，无 rejectedAt、
/// 无裁决事件流水）⇒ 口径中「学员再次拒绝」事件**不可逐次观测**。
/// 本判据取**可观测近似**：「驳回过 + 会话内再现 ≥ 2」；误报方向 =
/// 偏多（「驳回后对再现不作反应」也计入）——A4 暂无产品消费方（档 A
/// 探针期）风险可接受。精确判据（≥ 2 次 rejected 事件）须裁决历史表
/// ⇒ 另行立项，不在本批（零持久化边界）。
List<UnresolvedSource> buildHumanConflictSources({
  required List<HumanAdjudication> adjudications,
  required String sessionId,
}) {
  final out = <UnresolvedSource>[];
  for (final a in adjudications) {
    if (a.confirmationStatus != 'rejected') continue;
    if (a.occurrenceCount < 2) continue; // 无会话内再现 ⇒ 单次驳回非冲突
    final namePart = a.syndromeName.isEmpty ? '' : '（${a.syndromeName}）';
    out.add(
      UnresolvedSource(
        '症候 ${a.syndromeId}$namePart 已被学员驳回，'
        '同章节会话内正式诊断再现 ${a.occurrenceCount} 次仍维持驳回态'
        '——人裁冲突信号（系统复现 vs 学员驳回），待人工裁决',
        <String>['$sessionId#${a.syndromeId}'],
      ),
    );
  }
  return out;
}

// ── A2：全局假设（规则触发；statement 模板生成；无置信度小数——设计稿 §二）──

/// 系统性：组独立出现章节数 ≥ 阈值；结构性：互斥对两组同时存在
/// （复用 validator 的互斥表真源，只引用不复制）。
List<GlobalHypothesis> buildGlobalHypotheses(
  List<DiagnosisGroup> groups, {
  required int nowSec,
}) {
  final out = <GlobalHypothesis>[];
  for (final g in groups) {
    if (g.chapterCount < kSystematicChapterThreshold) continue;
    out.add(
      GlobalHypothesis(
        hypothesisId: 'gh-sys-${g.syndromeId}-$nowSec',
        kind: 'systematic',
        statement:
            '症候 ${g.syndromeId} 已在 ${g.chapterCount} 个章节独立出现'
            '（严重度峰值 ${g.severityMax.value}）——疑似系统性习惯',
        sourceGroupIds: [g.groupId],
        ruleId: 'R-A2-systematic-n$kSystematicChapterThreshold',
        status: 'active',
      ),
    );
  }
  out.addAll(_structuralHypotheses(groups, nowSec));
  return out;
}

List<GlobalHypothesis> _structuralHypotheses(
  List<DiagnosisGroup> groups,
  int nowSec,
) {
  final idSet = groups.map((g) => g.syndromeId).toSet();
  final out = <GlobalHypothesis>[];
  for (final pair in kMutexSyndromePairs) {
    if (!(idSet.contains(pair[0]) && idSet.contains(pair[1]))) continue;
    out.add(
      GlobalHypothesis(
        hypothesisId: 'gh-mx-${pair[0]}-${pair[1]}-$nowSec',
        kind: 'structural',
        statement:
            '互斥症候 ${pair[0]}/${pair[1]} 同时命中'
            '——疑似结构性张力，需人裁决取舍',
        sourceGroupIds: ['dg-${pair[0]}', 'dg-${pair[1]}'],
        ruleId: 'R-A2-structural-mutex',
        status: 'active',
      ),
    );
  }
  return out;
}

// ── A3：教学焦点候选（评分分解，只出候选不决定——决定权在用户/阶段二）──

/// 等权起步（设计稿 §六：权重表待 W-23 实验调参）。
/// 分量：severity(L1=1..L3=3) + intervention_value(null=0..high=3)
///      + recurrence(独立章节数，封顶 = 系统性阈值)。
List<TeachingFocusCandidate> buildTeachingFocusCandidates(
  List<DiagnosisGroup> groups, {
  required int nowSec,
}) {
  final cands = groups.map(_candidateFor).toList();
  cands.sort((a, b) {
    final byTotal = (b.scoreBreakdown['total'] ?? 0).compareTo(
      a.scoreBreakdown['total'] ?? 0,
    );
    if (byTotal != 0) return byTotal;
    return a.syndromeId.compareTo(b.syndromeId);
  });
  return cands;
}

/// iv 断供格的注册表先验值（T-20261018-04 第一批 · 设计批 2026-10-18 已批）。
///
/// 经既有 [quantityTagOf] 派生（零新映射表，ADR-0008 负面清单 4）：
///   - `wordChoice`（客观可验证的用词错误——基础语病/翻译腔）= 2，
///     与 ADR-0008 §2.1 资格闸档 A 同一判断的另一处应用；
///   - 其余（`overwritten` / `underwritten` / 无标签）= 1（不区分，
///     最小语义增量——满映射 2/1/0 备选舰长未选，见设计批 §五待裁 1）。
///
/// 先验**不是** LLM 评定：呈现层 rationale 以「注册表先验」字样标注
/// （R-009 同源纪律：不伪装数据来源）。
int quantityPrior(String syndromeId) {
  return quantityTagOf(syndromeId) == QuantityTag.wordChoice ? 2 : 1;
}

TeachingFocusCandidate _candidateFor(DiagnosisGroup g) {
  final severityScore = g.severityMax.index + 1;
  // A3 intervention_value 分量断供修复（T-20261018-04 第一批 · 设计批
  // 2026-10-18 舰长「都批」）：单次链输出规范明文不产出 intervention_value
  // （syndrome_kb_content.dart:62）⇒ 240/240 格 iv 全 null ⇒ 旧口径
  // valueScore 恒 0、total = severity + 1 恒等（W-23 全库 1068 候选复算，
  // ADR-0008 证据 4/6）。iv 为 null 时改由注册表既有 QuantityTag 派生先验
  // （quantityTagOf，零新映射表，ADR-0008 负面清单 4）：wordChoice = 2
  // ——与 ADR-0008 §2.1 资格闸档 A 同一判断的另一处应用；其余
  // （overwritten/underwritten/无标签）= 1（最小语义增量）。iv 非空路径
  // （merge 链产出）原样不动，一次只改一个变量（§4-192 范式）。
  final iv = g.interventionValueMax;
  final int valueScore;
  final String valueLabel;
  if (iv != null) {
    valueScore = interventionValueRank(iv) + 1;
    valueLabel = iv;
  } else {
    valueScore = quantityPrior(g.syndromeId) + 1;
    valueLabel = '注册表先验';
  }
  final recurrenceScore = g.chapterCount.clamp(0, kSystematicChapterThreshold);
  final total = severityScore + valueScore + recurrenceScore;
  return TeachingFocusCandidate(
    candidateId: 'tfc-${g.syndromeId}',
    syndromeId: g.syndromeId,
    groupId: g.groupId,
    scoreBreakdown: {
      'severity': severityScore,
      'intervention_value': valueScore,
      'recurrence': recurrenceScore,
      'total': total,
    },
    rationale:
        '${g.syndromeId}：严重度 ${g.severityMax.value}($severityScore)'
        ' · 干预价值 $valueLabel($valueScore)'
        ' · 跨 ${g.chapterCount} 章独立出现($recurrenceScore) ⇒ $total',
    status: 'proposed',
  );
}

// ── 快照组装（四契约全部就位）──

IntegrationSnapshot buildIntegrationSnapshot({
  required List<DiagnosisEntryRef> entries,
  required int nowSec,
  List<UnresolvedSource> pendingContexts = const [],
  List<UnresolvedSource> humanConflicts = const [],
}) {
  final groups = buildDiagnosisGroups(entries);
  final questions = collectUnresolvedQuestions(
    groups,
    pendingContexts: pendingContexts,
    humanConflicts: humanConflicts,
    nowSec: nowSec,
  );
  return IntegrationSnapshot(
    groups: groups,
    hypotheses: buildGlobalHypotheses(groups, nowSec: nowSec),
    candidates: buildTeachingFocusCandidates(groups, nowSec: nowSec),
    questions: questions,
  );
}
