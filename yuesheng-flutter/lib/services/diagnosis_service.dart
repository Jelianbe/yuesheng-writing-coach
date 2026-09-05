// ─────────────────────────────────────────────────────────────
// DiagnosisService — 诊断状态唯一 Owner
// 复刻 yuesheng-android/src/services/diagnosis-service.ts
//
// 职责：
//   1. 诊断锁定/解锁（shouldUnlock/autoCheckAndUnlock/unlockSyndromes）
//   2. 确认/质疑（confirmDiagnosis/disputeDiagnosis）
//   3. commitDiagnosisWithHistory：在 commitDiagnosis 基础上追加 teaching_history + 自动解锁
//
// 简化项（与 chat_service 一致）：
//   - loadSyndromeTeachingStates 未单独实现为服务函数——等价能力已由
//     diagnosis_card 内部直接实现（getAllDiagnoses + computeSyndromeProfile，
//     批次 45），按需加载避免每次会话初始化全量画像聚合
// ─────────────────────────────────────────────────────────────

// 私有字段（_xxx）+ 公开命名参数（xxx）模式无法用 initializing formal
// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:writingcoach/config/shared_constants.dart';
import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 解锁触发判断结果
class UnlockTrigger {
  final bool shouldUnlock;
  final String reason;
  final int consecutiveFailedTrainings;
  final int disputeCount;

  const UnlockTrigger({
    required this.shouldUnlock,
    required this.reason,
    required this.consecutiveFailedTrainings,
    required this.disputeCount,
  });
}

/// 诊断服务（诊断状态唯一 Owner）
class DiagnosisService {
  final DiagnosisRepository _diagnosisRepo;
  final StudentModelRepository _studentModelRepo;

  DiagnosisService({
    required DiagnosisRepository diagnosisRepo,
    required StudentModelRepository studentModelRepo,
  }) : _diagnosisRepo = diagnosisRepo,
       _studentModelRepo = studentModelRepo;

  // ════════════ 解锁触发条件 ════════════

  /// 判断症候是否应解锁。
  ///
  /// 触发条件（任一满足）：
  /// - 连续 CONSECUTIVE_FAIL_THRESHOLD 次训练评估为 failed
  /// - 该症候被质疑 ≥ DISPUTE_THRESHOLD 次
  ///
  /// 真源：diagnosis-service.ts shouldUnlockSyndrome
  Future<UnlockTrigger> shouldUnlockSyndrome(
    String sessionId,
    String syndromeId,
  ) async {
    final allHistory = await _studentModelRepo.getTeachingHistory(sessionId);

    final syndromeHistory = _filterSyndromeHistory(allHistory, syndromeId);
    final trainingRecords = _sortTrainingRecords(allHistory, syndromeId);
    final consecutiveFailedTrainings = _countConsecutiveFailures(
      trainingRecords,
    );
    final disputeCount = syndromeHistory
        .where((r) => r['action'] == 'disputed')
        .length;

    final shouldUnlock =
        consecutiveFailedTrainings >= DiagnosisLock.consecutiveFailThreshold ||
        disputeCount >= DiagnosisLock.disputeThreshold;

    final reasons = <String>[];
    if (consecutiveFailedTrainings >= DiagnosisLock.consecutiveFailThreshold) {
      reasons.add('连续 $consecutiveFailedTrainings 次训练无效');
    }
    if (disputeCount >= DiagnosisLock.disputeThreshold) {
      reasons.add('被质疑 $disputeCount 次');
    }

    return UnlockTrigger(
      shouldUnlock: shouldUnlock,
      reason: shouldUnlock ? reasons.join('；') : '不满足解锁条件',
      consecutiveFailedTrainings: consecutiveFailedTrainings,
      disputeCount: disputeCount,
    );
  }

  /// 筛选含目标症候的 ConfirmationRecord（R-019 拆出）。
  List<Map<String, dynamic>> _filterSyndromeHistory(
    List<Map<String, dynamic>> allHistory,
    String syndromeId,
  ) {
    return allHistory.where((r) {
      if (r['type'] != 'confirmation') return false;
      final syndromes = r['syndromes'];
      if (syndromes is! List) return false;
      return syndromes.any(
        (id) => id is String && effectiveSyndromeId(id) == syndromeId,
      );
    }).toList();
  }

  /// 筛选目标症候的 TrainingRecord（按时间正序；R-019 拆出）。
  List<Map<String, dynamic>> _sortTrainingRecords(
    List<Map<String, dynamic>> allHistory,
    String syndromeId,
  ) {
    return allHistory
        .where(
          (r) =>
              r['type'] == 'training' &&
              r['syndromeId'] is String &&
              effectiveSyndromeId(r['syndromeId'] as String) == syndromeId,
        )
        .toList()
      ..sort((a, b) {
        final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
        final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
        return ta.compareTo(tb);
      });
  }

  /// 计算连续失败次数（从末尾倒序；R-019 拆出）。
  int _countConsecutiveFailures(List<Map<String, dynamic>> trainingRecords) {
    var count = 0;
    for (int i = trainingRecords.length - 1; i >= 0; i--) {
      if (trainingRecords[i]['result'] == 'failed') {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// 批量解锁症候（将 active_problem status 设为 'resolved'）
  ///
  /// 真源：diagnosis-service.ts unlockSyndromes
  /// Wave 6 重构：调用 diagnosis-dao.resolveSyndromesBatch，消除 dual truth source
  Future<int> unlockSyndromes(
    String sessionId,
    List<String> syndromeIds,
  ) async {
    return _diagnosisRepo.resolveSyndromesBatch(sessionId, syndromeIds);
  }

  /// 在每次诊断提交后自动检测应解锁的症候并执行解锁。
  ///
  /// 真源：diagnosis-service.ts autoCheckAndUnlock
  /// 应在 commitDiagnosisWithHistory 调用后执行。
  Future<List<String>> autoCheckAndUnlock(String sessionId) async {
    final activeProblems = await _diagnosisRepo.listActiveProblems(sessionId);

    final toUnlock = <String>[];
    for (final p in activeProblems) {
      final trigger = await shouldUnlockSyndrome(sessionId, p.syndromeId);
      if (trigger.shouldUnlock) {
        toUnlock.add(p.syndromeId);
      }
    }

    if (toUnlock.isNotEmpty) {
      await unlockSyndromes(sessionId, toUnlock);
    }

    return toUnlock;
  }

  /// v19 正向达标路径：teaching_state=mastered → 解锁（status=resolved）
  ///
  /// 修复 E3：原 autoCheckAndUnlock 仅在「连续失败/被质疑」时解锁，
  /// 训练达标（FSM 迁移到 mastered）无法触发正向解锁，导致症候永远
  /// 留在 active_problem 里、无法进入迁移环节。
  ///
  /// 触发时机：
  ///  1. commitDiagnosisWithHistory 内（每次诊断提交后）
  ///  2. EvaluationService 持久化 teaching_state=mastered 时（直接调用 dao）
  ///
  /// 幂等：已 resolved 的症候 listActiveProblems 不再返回，不会重复解锁。
  Future<List<String>> checkAndResolveMastered(String sessionId) async {
    final activeProblems = await _diagnosisRepo.listActiveProblems(sessionId);
    final masteredSyndromes = activeProblems
        .where((p) => p.teachingState == 'mastered')
        .map((p) => p.syndromeId)
        .toList();
    if (masteredSyndromes.isNotEmpty) {
      await unlockSyndromes(sessionId, masteredSyndromes);
    }
    return masteredSyndromes;
  }

  // ════════════ 诊断业务编排 ════════════

  /// 确认诊断
  ///
  /// 真源：diagnosis-service.ts confirmDiagnosis
  /// D2/D6 修复：无论 level=confirmed 还是 partial，都追加 teaching_history，
  /// action 统一为 'confirmed'（消费者 evaluation_service / training_input_builder
  /// 均读 'confirmed'），partial 时额外加 'level':'partial' 区分。
  Future<void> confirmDiagnosis(
    String sessionId,
    String syndromeId,
    String syndromeName,
    Severity severity, {
    String level = 'confirmed',
  }) async {
    await _diagnosisRepo.confirmDiagnosis(
      sessionId,
      syndromeId,
      syndromeName,
      severity.value,
    );
    await _studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'confirmation',
      'syndromes': [syndromeId],
      'syndromeName': syndromeName,
      'severity': severity.value,
      'action': 'confirmed',
      'level': level, // 'confirmed' 或 'partial'，消费者按需读取
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'sessionId': sessionId,
    });
  }

  /// 质疑诊断
  ///
  /// 真源：diagnosis-service.ts disputeDiagnosis
  /// D3 修复：追加 teaching_history，action='disputed'，
  /// 解锁 shouldUnlockSyndrome 的"被质疑≥2次"反向解锁路径。
  Future<void> disputeDiagnosis(
    String sessionId,
    String syndromeId,
    String syndromeName,
  ) async {
    await _diagnosisRepo.disputeDiagnosis(sessionId, syndromeId, syndromeName);
    await _studentModelRepo.appendTeachingHistory(sessionId, {
      'type': 'confirmation',
      'syndromes': [syndromeId],
      'syndromeName': syndromeName,
      'action': 'disputed',
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'sessionId': sessionId,
    });
  }

  /// 计算诊断效果（improved / worsened）
  ///
  /// 真源：diagnosis-service.ts calculateEffectiveness
  /// 逻辑：对本次诊断的每个症候，在全部历史诊断（跨会话全表，对齐 RN
  /// `getAllDiagnoses()` 无参调用）中筛同症候记录，按时间倒序取最近两条
  /// 比较严重度（当前诊断刚落库，[0]=本次，[1]=上一次）：
  ///   - 更轻（L3→L2/L1，L2→L1）→ improved
  ///   - 更重（L1→L2/L3，L2→L3）→ worsened
  ///   - 无变化 → 不返回（维持 null，RN 不写 no_change）
  /// 仅在同症候历史 ≥ REPEAT_SYNDROME_THRESHOLD（2）时判定
  Future<String?> calculateEffectiveness(DiagnosisInput input) async {
    if (input.syndromes.isEmpty) return null;
    const order = {'L1': 1, 'L2': 2, 'L3': 3};
    String? effectiveness;

    final pastEntries = await _diagnosisRepo.getAllDiagnoses();
    final syndromeIds = input.syndromes
        .map((s) => s['syndrome_id'] as String? ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final sid in syndromeIds) {
      final sameSyndrome =
          pastEntries.where((e) => e.syndromeId == sid).toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      if (sameSyndrome.length >= DiagnosisLimits.repeatSyndromeThreshold) {
        final prev = sameSyndrome[1].severity;
        final curr = sameSyndrome[0].severity;
        if ((order[curr] ?? 0) < (order[prev] ?? 0)) {
          effectiveness = 'improved';
          break;
        }
        if ((order[curr] ?? 0) > (order[prev] ?? 0)) {
          effectiveness = 'worsened';
          break;
        }
      }
    }

    return effectiveness;
  }

  /// 提交诊断结果：分步落库，每步独立降级，失败可观测（批次2-D1）
  ///
  /// 步骤：commitDiagnosis → appendTeachingHistory → checkAndResolveMastered → autoCheckAndUnlock
  /// 核心步骤（commitDiagnosis）失败立即返回，避免后续步骤基于空诊断运行。
  Future<void> commitDiagnosisWithHistory(DiagnosisInput input) async {
    final maxSeverity = _resolveMaxSeverity(input.syndromes);

    // 1. 提交诊断结果（核心步骤，失败必须记录并立即返回）
    try {
      await _diagnosisRepo.commitDiagnosis(input);
    } catch (e) {
      debugPrint(
        '[Diagnosis] commitDiagnosis 失败 session=${input.sessionId}: $e',
      );
      return;
    }

    // 2. 追加 teaching_history
    try {
      final effectiveness = await calculateEffectiveness(input);
      final historyRecord = _buildHistoryRecord(input, maxSeverity);
      if (effectiveness != null) {
        historyRecord['effectiveness'] = effectiveness;
      }
      await _studentModelRepo.appendTeachingHistory(
        input.sessionId,
        historyRecord,
      );
    } catch (e) {
      debugPrint(
        '[Diagnosis] appendTeachingHistory 失败 session=${input.sessionId}: $e',
      );
    }

    // 3. 正向达标优先：teaching_state=mastered → 解锁（v19 E3修复）
    try {
      await checkAndResolveMastered(input.sessionId);
    } catch (e) {
      debugPrint(
        '[Diagnosis] checkAndResolveMastered 失败 session=${input.sessionId}: $e',
      );
    }

    // 4. 自动检测并解锁症候（原反向路径：连续失败/被质疑）
    try {
      await autoCheckAndUnlock(input.sessionId);
    } catch (e) {
      debugPrint(
        '[Diagnosis] autoCheckAndUnlock 失败 session=${input.sessionId}: $e',
      );
    }
  }

  /// 取症候最高严重度（R-019 拆出：commitDiagnosisWithHistory）。
  String _resolveMaxSeverity(List<Map<String, dynamic>> syndromes) {
    const severityOrder = {'L1': 1, 'L2': 2, 'L3': 3};
    String maxSeverity = 'L1';
    for (final s in syndromes) {
      final sev = s['severity'] as String? ?? 'L1';
      if ((severityOrder[sev] ?? 0) > (severityOrder[maxSeverity] ?? 0)) {
        maxSeverity = sev;
      }
    }
    return maxSeverity;
  }

  /// 构建 teaching_history 记录（R-019 拆出：commitDiagnosisWithHistory）。
  Map<String, dynamic> _buildHistoryRecord(
    DiagnosisInput input,
    String maxSeverity,
  ) {
    return <String, dynamic>{
      'type': 'diagnosis',
      'syndromes': input.syndromes
          .map((s) => s['syndrome_id'] as String)
          .toList(),
      'maxSeverity': maxSeverity,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'sessionId': input.sessionId,
      'teaching_mode': input.teachingMode ?? 'socratic',
    };
  }
}
