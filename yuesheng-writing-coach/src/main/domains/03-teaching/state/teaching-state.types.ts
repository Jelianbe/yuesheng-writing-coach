/**
 * 教学状态类型定义（主进程专用）
 * 公共类型从 shared/types.ts 导入，此处仅保留数据库相关类型
 */

export {
  TeachingPhase,
  TeachingSubphase,
  SyndromeId,
  ActionId,
} from '../../../../shared/constants';

export type {
  ProblemStatus,
  ActiveProblem,
  AIStateSuggestion,
  TeachingState,
  TeachingProgressDisplay,
  SeverityLevel,
} from '../../../../shared/types/index';

import type { TeachingPhase, TeachingSubphase } from '../../../../shared/constants';

/** 教学状态数据库行格式 */
export interface TeachingStateRow {
  id: number;
  session_id: string;
  current_phase: string;
  current_subphase: string | null;
  completed_actions: string;
  completed_tasks: string;
  active_problems: string;
  next_suggested_actions: string;
  current_task_id: string | null;
  diagnosis_summary: string;
  last_user_confirmation: string | null;
  focus_area: string | null;
  transition_offered: number;
  locked_syndromes: string;
  updated_at: string;
}

/** 教学状态创建输入 */
export interface CreateTeachingStateInput {
  sessionId: string;
  currentPhase?: TeachingPhase;
  currentSubphase?: TeachingSubphase;
}
