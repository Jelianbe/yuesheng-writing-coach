/**
 * 教学状态机 — 引导发现（GUIDE）过渡逻辑
 * 负责：根据症候 discoverable 字段决定是否进入 GUIDE、处理 GUIDE 阶段内响应、退出条件检测
 *
 * GUIDE 内部状态机：discover → try → reflect → confirm
 * - discover: 用户自己尝试发现问题
 * - try: 用户尝试修改
 * - reflect: 反思效果
 * - confirm: 确认理解
 */

import syndromeActionMap from '../../../../../resources/config/syndrome-action-map.json';
import { TeachingSubphase } from '../../../../shared/constants';
import type { TeachingState } from './teaching-state.types';
import { calculateNextActions } from './teaching-state-machine.navigation';

// ======================== 类型定义 ========================

/** GUIDE 内部子阶段 */
export type GuideSubState = 'discover' | 'try' | 'reflect' | 'confirm';

/** GUIDE 输入上下文 */
export interface GuideContext {
  /** 当前处理的症候 ID */
  syndromeId: string;
  /** 当前内部子阶段 */
  currentSubState: GuideSubState;
  /** 已对话轮次 */
  dialogueRound: number;
  /** 连续敷衍回应次数 */
  consecutiveShallowCount: number;
  /** 用户是否已要求跳过 */
  userRequestedSkip: boolean;
  /** 诊断置信度（1-10），partial 判定用 */
  confidence?: number;
  /** 用户能力水平，partial 判定用 */
  userLevel?: 'beginner' | 'intermediate' | 'advanced';
}

/** GUIDE 进入/操作结果 */
export interface GuideResult {
  /** 是否成功进入/继续 */
  entered: boolean;
  /** 原因说明 */
  reason: string;
  /** 下一个内部子阶段（entered=true 时有效） */
  nextSubState?: GuideSubState;
}

/** 退出原因 */
export type ExitReason = 'normal_complete' | 'shallow_three' | 'timeout_5_rounds' | 'user_skip';

/** 用户响应类型 */
export type GuideUserAction = 'meaningful' | 'shallow' | 'skip';

// ======================== JSON 配置加载 ========================

interface SyndromeMapping {
  syndromeId: string;
  discoverable: boolean | 'partial';
  [key: string]: unknown;
}

const DISCOVERABLE_MAP = new Map<string, boolean | 'partial'>();

function initDiscoverableMap(): void {
  if (DISCOVERABLE_MAP.size > 0) return;
  const data = syndromeActionMap as { mappings: SyndromeMapping[] };
  for (const m of data.mappings) {
    DISCOVERABLE_MAP.set(m.syndromeId, m.discoverable);
  }
}

function getDiscoverable(syndromeId: string): boolean | 'partial' {
  initDiscoverableMap();
  return DISCOVERABLE_MAP.get(syndromeId) ?? false;
}

// ======================== 核心函数 ========================

/**
 * 判断是否应进入 GUIDE 子阶段
 *
 * 规则：
 * - discoverable=true → 进入 GUIDE
 * - discoverable=false → 跳过 GUIDE，直接进入 TEACHING
 * - discoverable=partial → 按 confidence 和用户能力决定
 *
 * @param context - GUIDE 输入上下文
 * @returns 进入判定结果
 */
export function enterGuide(context: GuideContext): GuideResult {
  const discoverable = getDiscoverable(context.syndromeId);

  if (discoverable === true) {
    return { entered: true, reason: 'discoverable=true', nextSubState: 'discover' };
  }

  if (discoverable === false) {
    return { entered: false, reason: 'discoverable=false' };
  }

  // discoverable === 'partial': 综合判定
  const hasHighConfidence = context.confidence !== undefined && context.confidence >= 7;
  const isBeginner = context.userLevel === 'beginner';

  if (hasHighConfidence || isBeginner) {
    return { entered: true, reason: 'partial:high_confidence_or_beginner', nextSubState: 'discover' };
  }

  return { entered: false, reason: 'partial:low_confidence_or_skilled' };
}

/**
 * 处理 GUIDE 阶段内的用户响应，推进内部状态机
 *
 * @param context - 当前 GUIDE 上下文
 * @param action - 用户响应类型
 * @returns 处理结果，包含下一个内部子阶段
 */
export function handleGuideAction(context: GuideContext, action: GuideUserAction): GuideResult {
  // skip → 直接跳到 confirm，快速退出
  if (action === 'skip') {
    return {
      entered: true,
      reason: 'user_skip_to_confirm',
      nextSubState: 'confirm',
    };
  }

  // shallow → 停留在当前子阶段，让用户再试
  if (action === 'shallow') {
    return {
      entered: true,
      reason: 'shallow_response_stay',
      nextSubState: context.currentSubState,
    };
  }

  // meaningful → 推进内部状态机
  // discover → try → reflect → confirm
  const nextStateMap: Record<GuideSubState, GuideSubState> = {
    discover: 'try',
    try: 'reflect',
    reflect: 'confirm',
    confirm: 'confirm',
  };

  return {
    entered: true,
    reason: 'advance_substate',
    nextSubState: nextStateMap[context.currentSubState],
  };
}

/**
 * 退出条件检测
 *
 * @param context - 当前 GUIDE 上下文
 * @returns 退出原因（应退出）或 null（继续）
 */
export function shouldExitGuide(context: GuideContext): ExitReason | null {
  // 用户明确要求跳过
  if (context.userRequestedSkip) {
    return 'user_skip';
  }

  // 连续 3 次敷衍回应
  if (context.consecutiveShallowCount >= 3) {
    return 'shallow_three';
  }

  // 总对话轮次 >= 5
  if (context.dialogueRound >= 5) {
    return 'timeout_5_rounds';
  }

  // 用户成功发现并确认（已到达 confirm）
  if (context.currentSubState === 'confirm') {
    return 'normal_complete';
  }

  return null;
}

// ======================== 状态集成函数 ========================

/**
 * 尝试进入 GUIDE 子阶段
 * 类似 enterReflectionIfTriggered 的调用模式：接收 TeachingState，返回更新后的状态
 *
 * @param state - 当前教学状态
 * @param context - GUIDE 上下文
 * @returns 更新后的教学状态（如果进入则为 S2_GUIDE，否则保持原状态）
 */
export function transitionToGuide(state: TeachingState, context: GuideContext): TeachingState {
  const result = enterGuide(context);
  if (!result.entered) {
    return state;
  }

  const now = new Date().toISOString();
  return {
    ...state,
    currentSubphase: TeachingSubphase.PRACTICE_GUIDE,
    nextSuggestedActions: calculateNextActions(state.currentPhase, TeachingSubphase.PRACTICE_GUIDE),
    updatedAt: now,
  };
}

/**
 * 退出 GUIDE 子阶段
 *
 * @param state - 当前教学状态
 * @param reason - 退出原因
 * @returns 更新后的教学状态（推进到下一个子阶段）
 */
export function exitGuide(state: TeachingState, _reason: ExitReason): TeachingState {
  const now = new Date().toISOString();

  // 根据退出原因决定下一个子阶段
  // normal_complete → 正常推进到 TEACHING
  // 其他 → 也推进到 TEACHING（但调用方可酌情调整为 REFLECTION）
  const nextSubphase = TeachingSubphase.PRACTICE_TEACHING;

  return {
    ...state,
    currentSubphase: nextSubphase,
    nextSuggestedActions: calculateNextActions(state.currentPhase, nextSubphase),
    updatedAt: now,
  };
}
