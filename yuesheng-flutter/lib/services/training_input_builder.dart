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

part 'training_input_builder_count.dart';
part 'training_input_builder_build.dart';
/// 数据不足阈值：少于 2 条诊断无法判断趋势（无 previousSeverity 可比对）
const int _kMinDiagnosisCountForTrend = 2;

/// 一天的秒数（teaching_history 时间戳为秒级）
const int _kSecondsPerDay = 86400;

