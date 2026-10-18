// ─────────────────────────────────────────────────────────────
// SessionHarvestAssembler — 会话收口卡装配器（T-20261018-02 · A 议题）
//
// 职责：诊断完成后（handleComplete 汇聚点）判定触发条件 + 装配
// [SessionHarvestPayload] + 插卡。**只装配事实，零 LLM、零评价**
// （R-009 红线：卡片无「进步/变好/达成」类语——见 SessionHarvestCard 头注）。
//
// 触发口径（设计批 §一，先写死）——三选一即出卡：
//   ① 会话累计诊断次数 >= 2（首次诊断不收口：单次无「对比」可陈述）；
//   ② 本会话 M4 完成候选在场（成稿事实，最高优先）；
//   ③ 本会话存在训练记录。
//   三路全空 ⇒ 不出卡（不造死卡）。
//
// ★ 口径登记（舰长 2026-10-18「批」同批裁定：按登记接受，不改行为）：
//   设计批 §一.2 原文为「候选**新出现**（本次诊断期间产生）」，本实现按
//   「在场」判定。二者行为等价——§二 成稿节本就「在场才出」，且触发①
//   （诊断>=2 次）已覆盖全部复诊场景；差异仅在措辞层，不改变任何产品
//   语义。变量名 hasCandidate 即此口径（勿改名回 hasNewCandidate——那会
//   暗示未实现的「新出现」语义）。
//
// C 子件（M4 接线）：成稿节消费 ChapterCompletionQuerier.queryBySession ——
// 该查询器的第一个消费方（活性审查 T-20261018-01 断桥修复第一件）。
//
// 独立类纪律（R-010）：不改 handleComplete 本体签名——由 runner 在
// handleComplete 尾部 await 一次 [assembleAndInsert]；失败静默留痕
// 不阻断主流程（对齐候选区失败静默先例）。
// ─────────────────────────────────────────────────────────────

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/database/database.dart' show DiagnosisRow, TrainingResultRow;
import '../data/repositories/diagnosis_repository.dart';
import '../data/repositories/session_repository.dart';
import '../data/repositories/training_result_repository.dart';
import 'chapter_completion_querier.dart';
import 'chapter_completion_aggregator.dart';
import 'message_card_service.dart';
import 'syndrome_registry.dart' show syndromeNameOf;

class SessionHarvestAssembler {
  final DiagnosisRepository diagRepo;
  final TrainingResultRepository trainingRepo;
  final ChapterCompletionQuerier completionQuerier;
  final SessionRepository sessionRepo;

  const SessionHarvestAssembler({
    required this.diagRepo,
    required this.trainingRepo,
    required this.completionQuerier,
    required this.sessionRepo,
  });

  /// 诊断完成后的收口入口（handleComplete 尾部调用一次）。
  ///
  /// [currentSyndromes] 本次诊断的症候集（id, severity——由诊断链完成时
  /// 在场的数据直传，避免二次解析）；[nextFocusId] 本轮焦点（可空）。
  /// 失败静默（留痕 debugPrint，不阻断诊断主流程）。
  Future<void> assembleAndInsert({
    required String sessionId,
    required List<({String id, String severity})> currentSyndromes,
    String? nextFocusId,
  }) async {
    try {
      final payload = await _buildPayload(
        sessionId: sessionId,
        currentSyndromes: currentSyndromes,
        nextFocusId: nextFocusId,
      );
      if (payload == null) return; // 触发条件全不满足：不出卡
      await insertSessionHarvestCard(sessionRepo, sessionId, payload);
    } catch (e) {
      debugPrint('[SessionHarvest] 装配失败，不阻断诊断主流程: $e');
    }
  }

  /// 装配 payload；三条件全不满足返回 null。
  Future<SessionHarvestPayload?> _buildPayload({
    required String sessionId,
    required List<({String id, String severity})> currentSyndromes,
    String? nextFocusId,
  }) async {
    final history = await diagRepo.listDiagnosisHistory(sessionId);
    final diagnosisCount = history.length;
    final training = await trainingRepo.queryBySession(sessionId);
    final completion = await completionQuerier.queryBySession(sessionId);

    // 触发判定（三选一）
    final hasCandidate = completion.candidates.isNotEmpty;
    final shouldEmit =
        diagnosisCount >= 2 || hasCandidate || training.isNotEmpty;
    if (!shouldEmit) return null;

    final counts = _severityCountsOf(currentSyndromes);
    return SessionHarvestPayload(
      diagnosisCount: diagnosisCount,
      l1Count: counts.$1,
      l2Count: counts.$2,
      l3Count: counts.$3,
      diff: _buildDiff(history, currentSyndromes),
      training: _buildTraining(training),
      completion: _buildCompletion(completion),
      nextFocusName: nextFocusId == null ? null : syndromeNameOf(nextFocusId),
    );
  }

  /// severity 计数 → (L1, L2, L3)。
  (int, int, int) _severityCountsOf(
    List<({String id, String severity})> syndromes,
  ) {
    var l1 = 0, l2 = 0, l3 = 0;
    for (final s in syndromes) {
      switch (s.severity) {
        case 'L1':
          l1++;
        case 'L2':
          l2++;
        default:
          l3++;
      }
    }
    return (l1, l2, l3);
  }

  /// 对比节：与上一次诊断（history[1]——history[0] 是本次）；无历史 = null。
  HarvestDiff? _buildDiff(
    List<DiagnosisRow> history,
    List<({String id, String severity})> currentSyndromes,
  ) {
    if (history.length < 2) return null;
    final prev = _parseSyndromeIds(history[1].syndromes);
    final cur = currentSyndromes.map((s) => s.id).toSet();
    return HarvestDiff(
      added: cur.difference(prev).length,
      removed: prev.difference(cur).length,
      recurring: cur.intersection(prev).length,
    );
  }

  /// 训练节：无训练记录 = null。
  HarvestTraining? _buildTraining(List<TrainingResultRow> training) {
    if (training.isEmpty) return null;
    return HarvestTraining(
      attempts: training.length,
      passed: training.where((t) => t.result == 'passed').length,
    );
  }

  /// 成稿节（C 子件 / M4）：最新候选事实快照——只报数字，无成败语。
  HarvestCompletion? _buildCompletion(ChapterCompletionReport completion) {
    if (completion.candidates.isEmpty) return null;
    final latest = completion.candidates.last;
    return HarvestCompletion(
      goalWords: latest.goalWords,
      wordCount: latest.wordCount,
    );
  }

  /// 解析历史诊断行的症候 id 集（防 JSON 损坏——空集降级，不抛错）。
  Set<String> _parseSyndromeIds(String raw) {
    if (raw.isEmpty) return const <String>{};
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map(
            (e) =>
                e is Map<String, dynamic> ? e['syndrome_id'] as String? : null,
          )
          .whereType<String>()
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }
}
