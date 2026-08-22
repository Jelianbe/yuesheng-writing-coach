// ─────────────────────────────────────────────────────────────
// training_input_builder 拆分：training_input_builder_count.dart（R-019 ≤300 行）
// 训练统计：countTrainingForSyndrome/TrainingPerformance/computeTrainingPerformance。迁移自 training_input_builder.dart，行为零变更。
// ─────────────────────────────────────────────────────────────
part of 'training_input_builder.dart';

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
