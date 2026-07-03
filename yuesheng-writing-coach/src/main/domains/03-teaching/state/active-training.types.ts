/**
 * ActiveTrainingSession 持久化类型 — Sprint 24 A-1
 *
 * 数据流向:
 *   Renderer (ActiveTrainingSession) → IPC → Main (ActiveTraining) → SQLite (ActiveTrainingRow)
 *
 * 设计原则:
 *   - ActiveTrainingRow 是 SQLite 存储格式(下划线 + JSON 字符串字段)
 *   - ActiveTraining 是领域对象(camelCase + 反序列化 JSON)
 *   - ActiveTrainingStore 负责两者转换(R-014 配置外置:结构在类型层,DB 层只存 string)
 *
 * 状态机:
 *   - 'in_progress': 训练进行中
 *   - 'completed': 训练完成(recordId 已绑定)
 *   - 'aborted': 训练中止(用户主动取消或异常退出)
 *
 * 跨域引用(R-020):
 *   - TrainingStep / TrainingFlow 在主进程侧独立定义精简版
 *   - 不引用 renderer/shared/types-training(避免反向依赖)
 *   - IPC 边界做兼容性转换
 *
 * 依据: dev-docs/tasks/sprint-24-plan.md §A-1 + §2.2(状态机边界)
 */

/** 主进程侧独立定义的 TrainingStep(与 renderer 兼容) */
export interface TrainingStep {
  id: string;
  title: string;
  description: string;
  status: 'completed' | 'active' | 'pending';
}

/** 主进程侧独立定义的 TrainingFlowStep(与 renderer 兼容) */
export interface TrainingFlowStep {
  stepId: 1 | 2 | 3 | 4 | 5;
  name: string;
  instruction: string;
  userAction: string;
  estimatedMinutes: number;
  coachingHint?: string;
}

/** 主进程侧独立定义的 TrainingFlow(与 renderer 兼容) */
export interface TrainingFlow {
  syndromeId: string;
  techniqueName: string;
  category: string;
  steps: TrainingFlowStep[];
  estimatedTotalMinutes: number;
  abilityNodeIds?: string[];
}

/** 数据库存储状态字面量 */
export type ActiveTrainingStatus = 'in_progress' | 'completed' | 'aborted';

/** 评估结果(主进程侧简化版) */
export interface SubmissionResultSnapshot {
  passed: boolean;
  feedback: string;
  score?: number;
  evaluatedAt: string;
}

/** 领域对象: ActiveTraining (主进程侧) */
export interface ActiveTraining {
  /** 数据库行 ID(自增主键) */
  id: number;
  /** 所属会话 ID(UNIQUE 约束) */
  sessionId: string;
  /** 挑战 ID */
  challengeId: string;
  /** 挑战名称 */
  challengeName: string | null;
  /** 交互模式 */
  mode: string | null;
  /** 当前步骤索引(0-based) */
  currentStepIndex: number;
  /** 步骤列表 */
  steps: TrainingStep[];
  /** 用户草稿(训练核心内容) */
  userDraft: string;
  /** 流式类型 */
  flowType: 'flow5' | 'legacy' | null;
  /** 完整训练流(S8 通用流) */
  trainingFlow: TrainingFlow | null;
  /** 关联训练记录 ID */
  recordId: string | null;
  /** 关联症候 ID */
  syndromeId: string | null;
  /** 原始文本引用 */
  originalQuote: string | null;
  /** 约束条件 */
  constraint: string | null;
  /** 上次评估结果快照 */
  submissionResult: SubmissionResultSnapshot | null;
  /** 状态机状态 */
  status: ActiveTrainingStatus;
  /** 创建时间 */
  startedAt: string;
  /** 更新时间 */
  updatedAt: string;
  /** 完成时间(complete/abort 时写入) */
  completedAt: string | null;
}

/** 数据库行: ActiveTrainingRow (SQLite 存储格式) */
export interface ActiveTrainingRow {
  id: number;
  session_id: string;
  challenge_id: string;
  challenge_name: string | null;
  mode: string | null;
  current_step_index: number;
  steps_json: string;
  user_draft: string;
  flow_type: string | null;
  training_flow_json: string | null;
  record_id: string | null;
  syndrome_id: string | null;
  original_quote: string | null;
  constraint_text: string | null;
  submission_result_json: string | null;
  status: string;
  started_at: string;
  updated_at: string;
  completed_at: string | null;
}

/** 创建输入 */
export interface CreateActiveTrainingInput {
  sessionId: string;
  challengeId: string;
  challengeName?: string;
  mode?: string;
  steps: TrainingStep[];
  flowType?: 'flow5' | 'legacy';
  trainingFlow?: TrainingFlow;
  syndromeId?: string;
  originalQuote?: string;
  constraint?: string;
  /** 触发来源(对齐 TrainingTriggeredEvent.reason) */
  source: 'training_triggered' | 'user_request' | 'diagnosis_result' | 'prescription';
}

/** 更新输入(部分更新) */
export interface UpdateActiveTrainingInput {
  challengeName?: string;
  mode?: string;
  currentStepIndex?: number;
  steps?: TrainingStep[];
  userDraft?: string;
  flowType?: 'flow5' | 'legacy' | null;
  trainingFlow?: TrainingFlow | null;
  recordId?: string | null;
  syndromeId?: string | null;
  originalQuote?: string | null;
  constraint?: string | null;
  submissionResult?: SubmissionResultSnapshot | null;
  status?: ActiveTrainingStatus;
  completedAt?: string | null;
}

/** 类型守卫: 是否为有效状态 */
export function isValidActiveTrainingStatus(s: string): s is ActiveTrainingStatus {
  return s === 'in_progress' || s === 'completed' || s === 'aborted';
}
