/// P3-1 训练评估引擎
///
/// 将 training-evaluation skill 中的确定性规则从 LLM prompt 迁移到代码。
/// LLM 保留自然语言生成能力，决策逻辑由本模块完成。
///
/// 真源：yuesheng-android/src/services/training-evaluator.ts
///
/// 提供：
///   1. 严重度趋势 (A) — 数值比较
///   2. 达标率计算 (B) — 纯算术
///   3. FSRS 稳定性 (C) — 数值比较
///   4. 综合判断 — 三维度整合
///   5. 恶化检测 — 信号检测
///   6. 教学状态迁移 — FSM
///   7. 最小数据量检查
library;

import 'package:writingcoach/types/teaching_types.dart';

part 'training_evaluator_dimension.dart';
part 'training_evaluator_deterioration.dart';
part 'training_evaluator_state.dart';
part 'training_evaluator_summary.dart';
