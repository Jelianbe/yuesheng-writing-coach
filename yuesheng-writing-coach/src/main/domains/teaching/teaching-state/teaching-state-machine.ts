/**
 * 教学状态机核心逻辑（桶文件）
 *
 * 职责演变说明：
 * 为满足 R-019 单文件 ≤300 行的规范，原 teaching-state-machine.ts 已按功能拆分为以下子模块：
 *
 * - teaching-state-machine.constants.ts  阶段/子阶段名称映射、子阶段序列常量
 * - teaching-state-machine.navigation.ts 导航函数（阶段/子阶段推进、进度计算）
 * - teaching-state-machine.locking.ts    症候锁定/更新/解锁机制
 * - teaching-state-machine.reflection.ts 反思门控判定与严重度降级
 *
 * 所有外部导入路径保持不变。此文件作为桶文件重新导出所有公开函数。
 *
 * @see teaching-state-machine.constants
 * @see teaching-state-machine.navigation
 * @see teaching-state-machine.locking
 * @see teaching-state-machine.reflection
 */

// Constants
export { getTransitionPrompt } from './teaching-state-machine.constants';

// Navigation
export {
  getPhaseName,
  getSubphaseName,
  getNextPhase,
  getFirstSubphaseOf,
  getNextSubphase,
  calculatePhaseProgress,
  confirmPhaseComplete,
  shouldOfferTransition,
  calculateNextActions,
} from './teaching-state-machine.navigation';

// Locking
export {
  lockSyndromes,
  updateSyndromeStatus,
  autoLockConsistentSyndromes,
  unlockResolvedSyndromes,
  areAllSyndromesResolved,
} from './teaching-state-machine.locking';

// Reflection
export {
  shouldEnterReflection,
  enterReflectionIfTriggered,
  downgradeSyndromeSeverity,
} from './teaching-state-machine.reflection';

// Guide
export {
  enterGuide,
  handleGuideAction,
  shouldExitGuide,
  transitionToGuide,
  exitGuide,
} from './teaching-state-machine.guide';

export type {
  GuideSubState,
  GuideContext,
  GuideResult,
  ExitReason,
  GuideUserAction,
} from './teaching-state-machine.guide';

// MasteryGate
export {
  evaluateMastery,
} from './mastery-gate';

export type {
  MasteryDecision,
  MasteryContext,
} from './mastery-gate';
