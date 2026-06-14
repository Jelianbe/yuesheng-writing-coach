/**
 * MasteryGate — 纯函数路由
 * 负责：根据训练评分、历史表现、用户状态决定教学路径
 *
 * 决策表：
 * | 条件 | 决策 |
 * |------|------|
 * | score > 9（> 90%） | fast_forward — 跳过下一次 GUIDE |
 * | score < 4（< 40%） | re_enter_guide — 重新进入 GUIDE |
 * | 3 次连续敷衍 | downgrade_attitude — 降档态度 |
 * | 其他 | normal_proceed — 正常推进 |
 */

/** MasteryGate 决策结果 */
export type MasteryDecision = 'fast_forward' | 're_enter_guide' | 'downgrade_attitude' | 'normal_proceed';

/** MasteryGate 输入上下文 */
export interface MasteryContext {
  /** 当前训练评分（1-10） */
  score: number;
  /** 历史评分列表 */
  historicalScores: number[];
  /** 当前态度档位 */
  attitude: 'doubao' | 'yuesheng' | 'sensei';
  /** 连续敷衍回应次数 */
  consecutiveShallowCount: number;
}

/**
 * 评估训练掌握度，返回教学路径决策
 *
 * @param context - 掌握度评估上下文
 * @returns 决策结果
 */
export function evaluateMastery(context: MasteryContext): MasteryDecision {
  // 归一化分数到 0-1
  const normalizedScore = context.score / 10;

  // score > 9（> 90%）→ 快速通过，跳过下次 GUIDE
  if (normalizedScore > 0.9) {
    return 'fast_forward';
  }

  // score < 4（< 40%）→ 重新进入 GUIDE
  if (normalizedScore < 0.4) {
    return 're_enter_guide';
  }

  // 3 次连续敷衍 → 降档态度
  if (context.consecutiveShallowCount >= 3) {
    return 'downgrade_attitude';
  }

  // 其他情况 → 正常推进
  return 'normal_proceed';
}
