/// training-input-builder
///
/// 为指定活跃症候构建 training-evaluator 的输入参数。
///
/// 数据源（teaching_history JSON）：
/// - DiagnosisRecord（type='diagnosis'）→ severityInput + occurrenceCount + gapDays + consecutiveLowSeverity
/// - ConfirmationRecord（type='confirmation'）→ wasResolvedToL1 + studentAbandoned
/// - TrainingRecord（type='training'）→ passRateInput + consecutiveFailures + consecutivePasses + trainingCount
/// - active_problem 表（外部传入）→ currentSeverity
///
/// 仍为占位的字段：
/// - fsrsStability: null（FSRS 未启用，延后到 FSRS 任务）
/// - stateTransitionInput.fsrsIntervalDays: 0（FSRS 未启用，但 consolidating → mastered
///   已有非 FSRS 降级路径：consolidationObservations≥5 + consecutiveLowSeverity≥3 +
///   consecutivePasses≥3，见 training_evaluator.transitionTeachingState）
///
/// 真源：yuesheng-android/src/services/training-input-builder.ts
/// 批次 44 偏差（Flutter 侧增强）：teachingState 起点不再硬编码 identified，
/// 改用画像同源推断（inferTeachingState）从诊断历史推出当前教学状态，
/// 使 FSM 能从真实状态迁移（in_progress→consolidating 可达），
/// 对齐记忆约束「评估面板需显示真实教学状态迁移」。RN 真源仍硬编码 identified。
library;

import 'package:writingcoach/data/repositories/diagnosis_repository.dart';
import 'package:writingcoach/data/repositories/student_model_repository.dart';
import 'package:writingcoach/services/student_profile_compute.dart';
import 'package:writingcoach/services/syndrome_registry.dart';
import 'package:writingcoach/services/training_evaluator.dart';
import 'package:writingcoach/types/teaching_types.dart';

/// 数据不足阈值：少于 2 条诊断无法判断趋势（无 previousSeverity 可比对）
const int _kMinDiagnosisCountForTrend = 2;

/// 一天的秒数（teaching_history 时间戳为秒级）
const int _kSecondsPerDay = 86400;

/// 批次60：统计指定症候的已训练次数（type='training' 记录数）。
///
/// 独立于 buildTrainingInputForActiveSyndrome（后者在诊断数 < 2 时返回 null），
/// 供介入级别（I do/We do/You do）推导使用。解析失败返回 0。
Future<int> countTrainingForSyndrome(
  StudentModelRepository studentModelRepo,
  String sessionId,
  String syndromeId,
) async {
  try {
    final history = await studentModelRepo.getTeachingHistory(sessionId);
    return history
        .where((r) =>
            r['type'] == 'training' &&
            r['syndromeId'] is String &&
            effectiveSyndromeId(r['syndromeId'] as String) == syndromeId)
        .length;
  } catch (_) {
    return 0;
  }
}

/// 表现感知输入（7.2 performance_gate）。
///
/// 统计口径对齐 FSM / 毕业复核：
///   - [passRate] = passed 数 / 总数（partial 不计入通过）
///   - [consecutivePasses] / [consecutiveFails]：从最新记录倒序连续通过/未达标
///     （partial 两者都不计，遇 partial 即中断连续段）
class TrainingPerformance {
  final double passRate;
  final int consecutivePasses;
  final int consecutiveFails;

  /// 训练记录数（= trainingCount，冗余携带避免调用方二次查询）
  final int totalCount;

  const TrainingPerformance({
    required this.passRate,
    required this.consecutivePasses,
    required this.consecutiveFails,
    required this.totalCount,
  });
}

/// 统计指定症候的训练表现（7.2）。
///
/// 一次拉取 teaching_history，同时提供训练次数（totalCount）与表现指标，
/// 供介入级别推导使用，避免「次数 + 表现」两次重复查询。
/// 无训练记录 / 解析失败 → null（调用方降级为纯次数分级）。
Future<TrainingPerformance?> computeTrainingPerformance(
  StudentModelRepository studentModelRepo,
  String sessionId,
  String syndromeId,
) async {
  try {
    final history = await studentModelRepo.getTeachingHistory(sessionId);
    final records = history
        .where((r) =>
            r['type'] == 'training' &&
            r['syndromeId'] is String &&
            effectiveSyndromeId(r['syndromeId'] as String) == syndromeId)
        .toList()
      ..sort((a, b) {
        final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
        final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
        return ta.compareTo(tb); // ASC（与训练输入构建器一致）
      });
    if (records.isEmpty) return null;

    final passCount = records.where((r) => r['result'] == 'passed').length;
    int consecutivePasses = 0;
    for (int i = records.length - 1; i >= 0; i--) {
      if (records[i]['result'] != 'passed') break;
      consecutivePasses++;
    }
    int consecutiveFails = 0;
    for (int i = records.length - 1; i >= 0; i--) {
      if (records[i]['result'] != 'failed') break;
      consecutiveFails++;
    }

    return TrainingPerformance(
      passRate: passCount / records.length,
      consecutivePasses: consecutivePasses,
      consecutiveFails: consecutiveFails,
      totalCount: records.length,
    );
  } catch (_) {
    return null;
  }
}

/// 活跃症候的元信息（外部传入，来自 active_problem 表）
class ActiveProblemMeta {
  final Severity currentSeverity;

  /// active_problem.created_at；listActiveProblems 当前不返回该字段，可选
  final int? createdAt;

  const ActiveProblemMeta({required this.currentSeverity, this.createdAt});
}

/// 构建活跃症候的 training-evaluator 输入。
///
/// 从 [studentModelRepo] 读取 teaching_history，按 [syndromeId] 筛选相关记录，
/// 聚合计算各项输入参数。
///
/// 返回 null 的情况：
/// - teaching_history 解析失败
/// - diagnosisCount < 2（数据不足，无法判断趋势）
///
/// 真源：training-input-builder.ts buildTrainingInputForActiveSyndrome
Future<EvaluationSummaryInput?> buildTrainingInputForActiveSyndrome(
  StudentModelRepository studentModelRepo,
  String sessionId,
  String syndromeId,
  ActiveProblemMeta activeProblemMeta, {
  // v19 教学状态机持久化：优先从 DB 读起点，null 时 fallback 到历史推断
  DiagnosisRepository? diagnosisRepo,
}) async {
  try {
    final history = await studentModelRepo.getTeachingHistory(sessionId);

    // ─── 筛选 DiagnosisRecord（含目标症候，按时间倒序）───
    final diagnosisRecords =
        history.where((r) => r['type'] == 'diagnosis').where((r) {
          final syndromes = r['syndromes'];
          if (syndromes is! List) return false;
          return syndromes.any((id) =>
              id is String && effectiveSyndromeId(id) == syndromeId);
        }).toList()..sort((a, b) {
          final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
          final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
          return tb.compareTo(ta); // DESC
        });

    final diagnosisCount = diagnosisRecords.length;

    // ─── 筛选 TrainingRecord（目标症候，按时间正序）───
    final trainingRecords =
        history
            .where(
              (r) =>
                  r['type'] == 'training' &&
                  r['syndromeId'] is String &&
                  effectiveSyndromeId(r['syndromeId'] as String) ==
                      syndromeId,
            )
            .toList()
          ..sort((a, b) {
            final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
            final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
            return ta.compareTo(tb); // ASC
          });

    // ─── 计算连续失败次数（从末尾倒序）───
    int consecutiveFailures = 0;
    for (int i = trainingRecords.length - 1; i >= 0; i--) {
      if (trainingRecords[i]['result'] == 'failed') {
        consecutiveFailures++;
      } else {
        break;
      }
    }

    // ─── 计算连续通过次数（从末尾倒序）───
    int consecutivePasses = 0;
    for (int i = trainingRecords.length - 1; i >= 0; i--) {
      if (trainingRecords[i]['result'] == 'passed') {
        consecutivePasses++;
      } else {
        break;
      }
    }

    final passCount = trainingRecords
        .where((r) => r['result'] == 'passed')
        .length;
    final totalCount = trainingRecords.length;

    // ─── 数据不足时跳过注入（diagnosisCount < 2）───
    if (diagnosisCount < _kMinDiagnosisCountForTrend) {
      return null;
    }

    // ─── previousSeverity：取倒数第二条 DiagnosisRecord.maxSeverity ───
    // 真源说明：DiagnosisRecord 不存储 per-syndrome severity，maxSeverity 为
    // 该次诊断中所有症候的最大严重度。作为 previousSeverity 的代理值。
    final previousRecord = diagnosisRecords[1];
    final previousSeverityStr =
        (previousRecord['maxSeverity'] as String?) ?? 'L2';
    final previousSeverity =
        Severity.fromString(previousSeverityStr) ?? Severity.l2;

    // ─── occurrenceCount：含该 syndromeId 的诊断记录数 ───
    final occurrenceCount = diagnosisCount;

    // ─── gapDays：最近两次诊断时间戳差值 / 86400 ───
    final latestTs = (diagnosisRecords[0]['timestamp'] as num?)?.toInt() ?? 0;
    final prevTs = (previousRecord['timestamp'] as num?)?.toInt() ?? 0;
    final gapDays = ((latestTs - prevTs) / _kSecondsPerDay).floor();

    // ─── 批次1（O2）毕业复核输入：距最后一次观察（诊断/训练）的天数 ───
    // 学员改好后不再出现在诊断 → 无新观察数据 → 该值持续增大，
    // 与「gapDays（两次诊断间隔）」语义不同，不可混用。
    final latestTrainingTs = trainingRecords.isNotEmpty
        ? (trainingRecords.last['timestamp'] as num?)?.toInt() ?? 0
        : 0;
    final lastObservationTs = latestTrainingTs > latestTs
        ? latestTrainingTs
        : latestTs;
    final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final daysSinceLastObservation = lastObservationTs > 0
        ? ((nowTs - lastObservationTs) / _kSecondsPerDay).floor()
        : 0;
    // 历史训练达标率（毕业复核用）
    final passRate = totalCount > 0 ? passCount / totalCount : 0.0;

    // ─── wasResolvedToL1：存在 action='confirmed' 且 severity='L1' 的 ConfirmationRecord ───
    final wasResolvedToL1 = history
        .where((r) => r['type'] == 'confirmation')
        .any((r) {
          if (r['action'] != 'confirmed') return false;
          if (r['severity'] != 'L1') return false;
          final syndromes = r['syndromes'];
          return syndromes is List && syndromes.contains(syndromeId);
        });

    // ─── consecutiveLowSeverity：从最近一次诊断往前数，连续 maxSeverity='L1' 的次数 ───
    int consecutiveLowSeverity = 0;
    for (final r in diagnosisRecords) {
      if (r['maxSeverity'] == 'L1') {
        consecutiveLowSeverity++;
      } else {
        break;
      }
    }

    // ─── stateTransitionInput 字段计算 ───
    // 真源: training-evaluator.ts transitionTeachingState
    final trainingStarted = trainingRecords.isNotEmpty;
    final consolidationObservations = trainingRecords.length; // 保守代理值（FSRS 未启用）
    final relapseDetected =
        previousSeverity == Severity.l1 &&
        (activeProblemMeta.currentSeverity == Severity.l2 ||
            activeProblemMeta.currentSeverity == Severity.l3);
    final studentAbandoned = history
        .where((r) => r['type'] == 'confirmation')
        .any((r) {
          // D3 修复：disputeDiagnosis 现在写入 action='disputed'，
          // 与 evaluation_service 的 disputedCount 消费者对齐。
          if (r['action'] != 'disputed') return false;
          final syndromes = r['syndromes'];
          return syndromes is List && syndromes.contains(syndromeId);
        });

    // ─── 教学状态起点：v19 DB持久化优先，fallback 到画像同源推断 ───
    //
    // 优先级：
    //  1. DB active_problem.teaching_state（FSM 输出累积，状态不回退）
    //  2. 批次44原有逻辑：inferTeachingState 从诊断历史画像推断（兼容存量无教学状态的症候）
    //
    // 历史背景：
    // - 最早硬编码 TeachingState.identified：每次评估从0起步，状态无法累积
    // - 批次44改推断：从画像推断，能与学员画像页一致，但随历史推断摆动，
    //   FSM「一次评估」的短周期内可能被推断推到前一状态，状态非单调。
    // - v19改持久化：评估服务每轮把 FSM 输出写回 teaching_state，下一轮直接读，
    //   实现单调累积，正向迁移可完整走 identified→in_progress→consolidating→mastered。
    TeachingState startingTeachingState;
    if (diagnosisRepo != null) {
      final activeRow = await diagnosisRepo.getActiveProblem(sessionId, syndromeId);
      final persisted = activeRow?.teachingState;
      if (persisted != null && persisted.isNotEmpty) {
        final parsed = TeachingState.fromString(persisted);
        if (parsed != null) {
          startingTeachingState = parsed;
        } else {
          // DB值非法：fallback 到画像推断，避免异常起步
          startingTeachingState = _inferStartingState(
            diagnosisCount,
            diagnosisRecords,
          );
        }
      } else {
        // 存量数据（v18→v19迁移后 teaching_state 为 NULL）：走历史推断
        startingTeachingState = _inferStartingState(
          diagnosisCount,
          diagnosisRecords,
        );
      }
    } else {
      // 调用者未传 DiagnosisRepo（纯训练模拟/测试）：走历史推断
      startingTeachingState = _inferStartingState(
        diagnosisCount,
        diagnosisRecords,
      );
    }

    return EvaluationSummaryInput(
      severityInput: SeverityTrendInput(
        currentSeverity: activeProblemMeta.currentSeverity,
        previousSeverity: previousSeverity,
        occurrenceCount: occurrenceCount,
      ),
      passRateInput: PassRateInput(
        passCount: passCount,
        totalCount: totalCount,
      ),
      fsrsStability: null, // FSRS 未启用
      deteriorationInput: DeteriorationCheckInput(
        syndromeId: syndromeId,
        currentSeverity: activeProblemMeta.currentSeverity,
        previousSeverity: previousSeverity,
        wasResolvedToL1: wasResolvedToL1,
        consecutiveFailures: consecutiveFailures,
        reboundPattern: false, // 保守值，不主动计算（§4.2）
        gapDays: gapDays,
        newConcurrentSyndromes: 0, // 保守值，不主动计算（§4.2）
      ),
      teachingState: startingTeachingState, // 批次 44：画像同源推断起点（原硬编码 identified）
      stateTransitionInput: StateTransitionInput(
        trainingStarted: trainingStarted,
        consecutiveLowSeverity: consecutiveLowSeverity,
        consecutivePasses: consecutivePasses,
        fsrsIntervalDays: 0, // FSRS 未启用；consolidating → mastered 走代理/毕业复核路径
        consolidationObservations: consolidationObservations,
        relapseDetected: relapseDetected,
        studentAbandoned: studentAbandoned,
        // 批次1（O2）：毕业复核输入（长时间无新观察 + 历史达标率达标 → mastered）
        daysSinceLastObservation: daysSinceLastObservation,
        passRate: passRate,
      ),
      minDataInput: MinDataCheckInput(
        diagnosisCount: diagnosisCount,
        trainingCount: trainingRecords.length,
        consolidationObservations: consolidationObservations,
      ),
    );
  } catch (_) {
    // JSON 解析失败或其他异常 → 返回 null（容错，§5.2 D1 用例）
    return null;
  }
}

/// 批次44原有推断逻辑：从诊断历史推断 per-syndrome 教学状态起点
/// 供 diagnosisRepo 不可用 / teaching_state 为空 / DB值非法 时 fallback
TeachingState _inferStartingState(
  int diagnosisCount,
  List<Map<String, dynamic>> diagnosisRecords, // 按时间 DESC
) {
  // diagnosisRecords 按时间 DESC（最新在前），inferTeachingState 期望正序（旧→新）
  final severityHistory = diagnosisRecords.reversed.map((r) {
    final s = (r['maxSeverity'] as String?) ?? 'L2';
    return Severity.fromString(s) ?? Severity.l2;
  }).toList();
  return inferTeachingState(
    diagnosisCount,
    severityHistory,
    computeTrend(severityHistory),
    severityHistory.isNotEmpty ? severityHistory.last : Severity.l2,
  );
}
