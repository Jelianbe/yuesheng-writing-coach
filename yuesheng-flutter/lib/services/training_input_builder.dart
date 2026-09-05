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

/// 训练输入派生字段（R-019 拆出，供 _loadTrainingFields / _assembleSummary 共享）。
typedef _TrainingFields = ({
  int passCount,
  int totalCount,
  int consecutiveFailures,
  int consecutivePasses,
  Severity previousSeverity,
  int occurrenceCount,
  int gapDays,
  int daysSinceLastObservation,
  double passRate,
  bool wasResolvedToL1,
  bool trainingStarted,
  int consecutiveLowSeverity,
  bool relapseDetected,
  bool studentAbandoned,
});

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
        .where(
          (r) =>
              r['type'] == 'training' &&
              r['syndromeId'] is String &&
              effectiveSyndromeId(r['syndromeId'] as String) == syndromeId,
        )
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
    final records =
        history
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
    return await _buildInput(
      studentModelRepo,
      sessionId,
      syndromeId,
      activeProblemMeta,
      diagnosisRepo,
    );
  } catch (_) {
    // JSON 解析失败或其他异常 → 返回 null（容错，§5.2 D1 用例）
    return null;
  }
}

/// 构建 training-evaluator 输入（数据准备 + 组装，R-019 二次拆）。
Future<EvaluationSummaryInput?> _buildInput(
  StudentModelRepository studentModelRepo,
  String sessionId,
  String syndromeId,
  ActiveProblemMeta activeProblemMeta,
  DiagnosisRepository? diagnosisRepo,
) async {
  final history = await studentModelRepo.getTeachingHistory(sessionId);
  final diagnosisRecords = _filterDiagnosisRecords(history, syndromeId);
  final diagnosisCount = diagnosisRecords.length;
  final trainingRecords = _filterTrainingRecords(history, syndromeId);
  if (diagnosisCount < _kMinDiagnosisCountForTrend) return null;

  final f = _loadTrainingFields(
    history,
    trainingRecords,
    diagnosisRecords,
    syndromeId,
    activeProblemMeta,
  );
  final startingTeachingState = await _resolveStartingState(
    diagnosisRepo,
    sessionId,
    syndromeId,
    diagnosisCount,
    diagnosisRecords,
  );

  return _assembleSummary(
    f,
    activeProblemMeta,
    syndromeId,
    startingTeachingState,
    diagnosisCount,
  );
}

/// EvaluationSummaryInput 组装（R-019 拆出）。
EvaluationSummaryInput _assembleSummary(
  _TrainingFields f,
  ActiveProblemMeta activeProblemMeta,
  String syndromeId,
  TeachingState startingTeachingState,
  int diagnosisCount,
) {
  return EvaluationSummaryInput(
    severityInput: _buildSeverityInput(
      activeProblemMeta,
      f.previousSeverity,
      f.occurrenceCount,
    ),
    passRateInput: PassRateInput(
      passCount: f.passCount,
      totalCount: f.totalCount,
    ),
    fsrsStability: null, // FSRS 未启用
    deteriorationInput: _buildDeteriorationInput(
      syndromeId,
      activeProblemMeta,
      f.previousSeverity,
      f.wasResolvedToL1,
      f.consecutiveFailures,
      f.gapDays,
    ),
    teachingState: startingTeachingState, // 批次 44：画像同源推断起点（原硬编码 identified）
    stateTransitionInput: _buildStateTransitionInput(
      f.trainingStarted,
      f.consecutiveLowSeverity,
      f.consecutivePasses,
      f.totalCount,
      f.relapseDetected,
      f.studentAbandoned,
      f.daysSinceLastObservation,
      f.passRate,
    ),
    minDataInput: MinDataCheckInput(
      diagnosisCount: diagnosisCount,
      trainingCount: f.totalCount,
      consolidationObservations: f.totalCount,
    ),
  );
}

/// 派生字段聚合（诊断/训练计数 + 趋势/状态标志，R-019 拆出）。
({
  int passCount,
  int totalCount,
  int consecutiveFailures,
  int consecutivePasses,
  Severity previousSeverity,
  int occurrenceCount,
  int gapDays,
  int daysSinceLastObservation,
  double passRate,
  bool wasResolvedToL1,
  bool trainingStarted,
  int consecutiveLowSeverity,
  bool relapseDetected,
  bool studentAbandoned,
})
_loadTrainingFields(
  List<Map<String, dynamic>> history,
  List<Map<String, dynamic>> trainingRecords,
  List<Map<String, dynamic>> diagnosisRecords,
  String syndromeId,
  ActiveProblemMeta activeProblemMeta,
) {
  final totalCount = trainingRecords.length;
  final passCount = trainingRecords
      .where((r) => r['result'] == 'passed')
      .length;
  final consecutiveFailures = _countTrailingOutcome(trainingRecords, 'failed');
  final consecutivePasses = _countTrailingOutcome(trainingRecords, 'passed');
  final previousSeverity = _resolvePreviousSeverity(diagnosisRecords[1]);
  final occurrenceCount = diagnosisRecords.length;
  final gapDays = _computeGapDays(diagnosisRecords, diagnosisRecords[1]);
  final daysSinceLastObservation = _computeDaysSinceLastObservation(
    trainingRecords,
    diagnosisRecords,
  );
  final flags = _deriveStateFlags(
    history,
    syndromeId,
    previousSeverity,
    activeProblemMeta,
    diagnosisRecords,
  );
  return (
    passCount: passCount,
    totalCount: totalCount,
    consecutiveFailures: consecutiveFailures,
    consecutivePasses: consecutivePasses,
    previousSeverity: previousSeverity,
    occurrenceCount: occurrenceCount,
    gapDays: gapDays,
    daysSinceLastObservation: daysSinceLastObservation,
    passRate: totalCount > 0 ? passCount / totalCount : 0.0,
    wasResolvedToL1: flags.wasResolvedToL1,
    trainingStarted: trainingRecords.isNotEmpty,
    consecutiveLowSeverity: flags.consecutiveLowSeverity,
    relapseDetected: flags.relapseDetected,
    studentAbandoned: flags.studentAbandoned,
  );
}

/// previousSeverity：取倒数第二条 DiagnosisRecord.maxSeverity（代理值，R-019 拆出）。
Severity _resolvePreviousSeverity(Map<String, dynamic> previousRecord) {
  return Severity.fromString(
        (previousRecord['maxSeverity'] as String?) ?? 'L2',
      ) ??
      Severity.l2;
}

/// stateTransition 相关状态标志聚合（R-019 拆出）。
({
  bool wasResolvedToL1,
  bool relapseDetected,
  bool studentAbandoned,
  int consecutiveLowSeverity,
})
_deriveStateFlags(
  List<Map<String, dynamic>> history,
  String syndromeId,
  Severity previousSeverity,
  ActiveProblemMeta activeProblemMeta,
  List<Map<String, dynamic>> diagnosisRecords,
) {
  return (
    wasResolvedToL1: _hasConfirmation(history, syndromeId, 'confirmed', 'L1'),
    relapseDetected: _isRelapseDetected(previousSeverity, activeProblemMeta),
    studentAbandoned: _hasConfirmation(history, syndromeId, 'disputed', null),
    consecutiveLowSeverity: _countConsecutiveLowSeverity(diagnosisRecords),
  );
}

/// 筛选含目标症候的诊断记录（按时间倒序）（R-019 拆出）。
List<Map<String, dynamic>> _filterDiagnosisRecords(
  List<Map<String, dynamic>> history,
  String syndromeId,
) {
  return history.where((r) => r['type'] == 'diagnosis').where((r) {
    final syndromes = r['syndromes'];
    if (syndromes is! List) return false;
    return syndromes.any(
      (id) => id is String && effectiveSyndromeId(id) == syndromeId,
    );
  }).toList()..sort((a, b) {
    final ta = (a['timestamp'] as num?)?.toInt() ?? 0;
    final tb = (b['timestamp'] as num?)?.toInt() ?? 0;
    return tb.compareTo(ta); // DESC
  });
}

/// 筛选目标症候训练记录（按时间正序）（R-019 拆出）。
List<Map<String, dynamic>> _filterTrainingRecords(
  List<Map<String, dynamic>> history,
  String syndromeId,
) {
  return history
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
      return ta.compareTo(tb); // ASC
    });
}

/// 从末尾倒序统计连续同结果训练次数（R-019 拆出）。
int _countTrailingOutcome(
  List<Map<String, dynamic>> trainingRecords,
  String result,
) {
  var count = 0;
  for (int i = trainingRecords.length - 1; i >= 0; i--) {
    if (trainingRecords[i]['result'] == result) {
      count++;
    } else {
      break;
    }
  }
  return count;
}

/// 最近两次诊断的时间间隔天数（R-019 拆出）。
int _computeGapDays(
  List<Map<String, dynamic>> diagnosisRecords,
  Map<String, dynamic> previousRecord,
) {
  final latestTs = (diagnosisRecords[0]['timestamp'] as num?)?.toInt() ?? 0;
  final prevTs = (previousRecord['timestamp'] as num?)?.toInt() ?? 0;
  return ((latestTs - prevTs) / _kSecondsPerDay).floor();
}

/// 距最后一次观察（诊断/训练）的天数（毕业复核用，R-019 拆出）。
/// 与 gapDays（两次诊断间隔）语义不同，不可混用。
int _computeDaysSinceLastObservation(
  List<Map<String, dynamic>> trainingRecords,
  List<Map<String, dynamic>> diagnosisRecords,
) {
  final latestTs = (diagnosisRecords[0]['timestamp'] as num?)?.toInt() ?? 0;
  final latestTrainingTs = trainingRecords.isNotEmpty
      ? (trainingRecords.last['timestamp'] as num?)?.toInt() ?? 0
      : 0;
  final lastObservationTs = latestTrainingTs > latestTs
      ? latestTrainingTs
      : latestTs;
  final nowTs = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return lastObservationTs > 0
      ? ((nowTs - lastObservationTs) / _kSecondsPerDay).floor()
      : 0;
}

/// 是否存在满足 action（可选 severity）的 ConfirmationRecord（R-019 拆出）。
bool _hasConfirmation(
  List<Map<String, dynamic>> history,
  String syndromeId,
  String action,
  String? severity,
) {
  return history.where((r) => r['type'] == 'confirmation').any((r) {
    if (r['action'] != action) return false;
    if (severity != null && r['severity'] != severity) return false;
    final syndromes = r['syndromes'];
    return syndromes is List && syndromes.contains(syndromeId);
  });
}

/// 从最近一次诊断往前数连续 L1 次数（R-019 拆出）。
int _countConsecutiveLowSeverity(List<Map<String, dynamic>> diagnosisRecords) {
  var count = 0;
  for (final r in diagnosisRecords) {
    if (r['maxSeverity'] == 'L1') {
      count++;
    } else {
      break;
    }
  }
  return count;
}

/// 复发检测：上次 L1 且当前 L2/L3（R-019 拆出）。
bool _isRelapseDetected(
  Severity previousSeverity,
  ActiveProblemMeta activeProblemMeta,
) {
  return previousSeverity == Severity.l1 &&
      (activeProblemMeta.currentSeverity == Severity.l2 ||
          activeProblemMeta.currentSeverity == Severity.l3);
}

/// 教学状态起点：v19 DB 持久化优先，fallback 到画像同源推断（R-019 拆出）。
/// 优先级：1. DB active_problem.teaching_state（FSM 输出累积，状态不回退）
///         2. inferTeachingState 从诊断历史画像推断（兼容存量无教学状态的症候）
Future<TeachingState> _resolveStartingState(
  DiagnosisRepository? diagnosisRepo,
  String sessionId,
  String syndromeId,
  int diagnosisCount,
  List<Map<String, dynamic>> diagnosisRecords,
) async {
  if (diagnosisRepo == null) {
    return _inferStartingState(diagnosisCount, diagnosisRecords);
  }
  final activeRow = await diagnosisRepo.getActiveProblem(sessionId, syndromeId);
  final persisted = activeRow?.teachingState;
  if (persisted == null || persisted.isEmpty) {
    // 存量数据（v18→v19 迁移后 teaching_state 为 NULL）：走历史推断
    return _inferStartingState(diagnosisCount, diagnosisRecords);
  }
  final parsed = TeachingState.fromString(persisted);
  return parsed ?? _inferStartingState(diagnosisCount, diagnosisRecords);
}

/// severityInput 组装（R-019 拆出）。
SeverityTrendInput _buildSeverityInput(
  ActiveProblemMeta activeProblemMeta,
  Severity previousSeverity,
  int occurrenceCount,
) {
  return SeverityTrendInput(
    currentSeverity: activeProblemMeta.currentSeverity,
    previousSeverity: previousSeverity,
    occurrenceCount: occurrenceCount,
  );
}

/// deteriorationInput 组装（R-019 拆出）。
DeteriorationCheckInput _buildDeteriorationInput(
  String syndromeId,
  ActiveProblemMeta activeProblemMeta,
  Severity previousSeverity,
  bool wasResolvedToL1,
  int consecutiveFailures,
  int gapDays,
) {
  return DeteriorationCheckInput(
    syndromeId: syndromeId,
    currentSeverity: activeProblemMeta.currentSeverity,
    previousSeverity: previousSeverity,
    wasResolvedToL1: wasResolvedToL1,
    consecutiveFailures: consecutiveFailures,
    reboundPattern: false, // 保守值，不主动计算（§4.2）
    gapDays: gapDays,
    newConcurrentSyndromes: 0, // 保守值，不主动计算（§4.2）
  );
}

/// stateTransitionInput 组装（R-019 拆出）。
StateTransitionInput _buildStateTransitionInput(
  bool trainingStarted,
  int consecutiveLowSeverity,
  int consecutivePasses,
  int consolidationObservations,
  bool relapseDetected,
  bool studentAbandoned,
  int daysSinceLastObservation,
  double passRate,
) {
  return StateTransitionInput(
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
  );
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
