/**
 * 教学领域入口
 *
 * 对外接口：ITeachingDomain — 供 ChatOrchestrator 等外部模块使用
 * 内部实现：TeachingStateService, TeachingStrategyService, ProblemPrioritizer,
 *           DisputeTrackerService, ReflectionGateService, StrategyInstructionBuilder
 */

import type { AttitudeLevel, DiagnosisAnalysis } from '../../../shared/types/index';

/** 反思问题结构 */
export interface TeachingReflectionQuestion {
  question: string;
  syndromeId: string;
  syndromeName: string;
}

export interface ITeachingDomain {
  /* 辩驳检测 */
  checkMessage(sessionId: string, message: string, isReflectionPhase: boolean): void;
  getEffectiveAttitude(sessionId: string, userAttitude: AttitudeLevel, isReflectionPhase: boolean): AttitudeLevel;

  /* 反思门控 */
  shouldTriggerReflection(diagnosis: DiagnosisAnalysis): { shouldReflect: boolean; question?: TeachingReflectionQuestion };
  buildReflectionPrompt(question: TeachingReflectionQuestion, attitude: AttitudeLevel): string;

  /* 策略指令 */
  buildStrategyInstruction(diagnosis: DiagnosisAnalysis | null, attitude: AttitudeLevel): string | null;
}

export { TeachingStateService } from './teaching-state.service';
export { TeachingStateStore } from './state/teaching-state.store';
export { TeachingState } from './state/teaching-state.types';
// Sprint 24 A-1/A-2: ActiveTraining 完整状态机
export { ActiveTrainingStore } from './state/active-training.store';
export { ActiveTrainingService } from './state/active-training.service';
export type {
  ActiveTraining,
  ActiveTrainingRow,
  CreateActiveTrainingInput,
  UpdateActiveTrainingInput,
  ActiveTrainingStatus,
  TrainingStep,
  TrainingFlow,
  TrainingFlowStep,
  SubmissionResultSnapshot,
} from './state/active-training.types';
export { DisputeTrackerService } from './dispute-tracker.service';
export { ReflectionGateService } from './reflection-gate.service';
export { StrategyInstructionBuilder } from './strategy-instruction-builder';
export { TeachingStrategyService } from '../02-prescription/strategy/service';
export { TeachingStrategyRouter } from '../02-prescription/strategy/router';
export { ProblemPrioritizer } from '../02-prescription/problem-prioritizer.service';
export { loadTransitionPromptConfig, getTransitionPrompt, setResourcesRoot } from './transition-prompt-loader';
