/**
 * 教学状态机常量
 * 阶段/子阶段名称映射、子阶段序列、聚焦方向配置
 */

import { TeachingPhase, TeachingSubphase } from '../../shared/constants';
import type { FocusAreaValue } from '../../renderer/shared/types';

/**
 * 聚焦方向对应的世界观子阶段序列
 * character 模式跳过部分子阶段，只走确定主角
 */
export const FOCUS_AREA_WORLD_SUBPHASES: Record<FocusAreaValue, string[]> = {
  worldbuilding: [
    TeachingSubphase.WORLD_NATURAL_LAW,
    TeachingSubphase.WORLD_PROTAGONIST,
    TeachingSubphase.WORLD_SOCIAL_STRUCT,
    TeachingSubphase.WORLD_FIRST_SCENE,
    TeachingSubphase.WORLD_DAILY_DETAIL,
  ],
  character: [
    TeachingSubphase.WORLD_PROTAGONIST,
  ],
  general: [
    TeachingSubphase.WORLD_NATURAL_LAW,
    TeachingSubphase.WORLD_PROTAGONIST,
    TeachingSubphase.WORLD_SOCIAL_STRUCT,
    TeachingSubphase.WORLD_FIRST_SCENE,
    TeachingSubphase.WORLD_DAILY_DETAIL,
  ],
};

/** 阶段名称映射 */
export const PHASE_NAMES: Record<string, string> = {
  [TeachingPhase.INIT]: '初次见面',
  [TeachingPhase.ENGAGE]: '投入建立',
  [TeachingPhase.WORLD]: '世界观搭建',
  [TeachingPhase.PRACTICE_LOOP]: '诊断与训练',
  [TeachingPhase.REVIEW]: '复盘总结',
};

/** 子阶段名称映射 */
export const SUBPHASE_NAMES: Record<string, string> = {
  [TeachingSubphase.ENGAGE_CONFIRM]: '确认投入',
  [TeachingSubphase.WORLD_NATURAL_LAW]: '自然法则',
  [TeachingSubphase.WORLD_PROTAGONIST]: '确定主角',
  [TeachingSubphase.WORLD_SOCIAL_STRUCT]: '社会结构',
  [TeachingSubphase.WORLD_FIRST_SCENE]: '缩小到第一个场景',
  [TeachingSubphase.WORLD_DAILY_DETAIL]: '日常细节',
  [TeachingSubphase.PRACTICE_IDENTIFY]: '识别问题',
  [TeachingSubphase.PRACTICE_REFLECTION]: '反思引导',
  [TeachingSubphase.PRACTICE_TEACHING]: '教学建议',
  [TeachingSubphase.PRACTICE_ASSIGN]: '布置任务',
  [TeachingSubphase.PRACTICE_REVIEW]: '评估练习',
  [TeachingSubphase.REVIEW_SUMMARY]: '总结复盘',
};

/** 每个阶段的子阶段序列 */
export const PHASE_SUBPHASES: Record<string, string[]> = {
  [TeachingPhase.INIT]: [],
  [TeachingPhase.ENGAGE]: [
    TeachingSubphase.ENGAGE_CONFIRM,
  ],
  [TeachingPhase.WORLD]: [
    TeachingSubphase.WORLD_NATURAL_LAW,
    TeachingSubphase.WORLD_PROTAGONIST,
    TeachingSubphase.WORLD_SOCIAL_STRUCT,
    TeachingSubphase.WORLD_FIRST_SCENE,
    TeachingSubphase.WORLD_DAILY_DETAIL,
  ],
  [TeachingPhase.PRACTICE_LOOP]: [
    TeachingSubphase.PRACTICE_IDENTIFY,
    TeachingSubphase.PRACTICE_REFLECTION,
    TeachingSubphase.PRACTICE_TEACHING,
    TeachingSubphase.PRACTICE_ASSIGN,
    TeachingSubphase.PRACTICE_REVIEW,
  ],
  [TeachingPhase.REVIEW]: [TeachingSubphase.REVIEW_SUMMARY],
};

/**
 * 过渡邀请话术已从硬编码迁移到外部配置
 * @see resources/config/transition-prompts.json
 * @see transition-prompt-loader.ts
 */
export { getTransitionPrompt } from './transition-prompt-loader';
