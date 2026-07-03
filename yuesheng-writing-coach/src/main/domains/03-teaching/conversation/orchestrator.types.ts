/**
 * ConversationOrchestrator — 会话编排接口(Sprint 20 Issue 20-1 A-1)
 *
 * 设计目标:
 * - 解耦 ChatPage / TeachingStateMachine 与底层 ChatOrchestratorService
 * - 把"读 prompt + 加载 skill + 发请求 + 解析流"封装在 handleTurn()
 * - 对外暴露 AsyncIterable<OrchestratorEvent>,不暴露底层 stream
 *
 * 关系链:
 *   ChatPage / TeachingStateMachine
 *      ↓ handleTurn()
 *   ConversationOrchestrator (本接口)
 *      ↓ 委托
 *   ChatOrchestratorService (既有实现,在 03-teaching/chat/)
 *      ↓ proxy.chatStream()
 *   DeepSeek API
 *
 * 不在 A-1 范围(后续任务):
 * - A-2: 把 SkillDispatcher 从 renderer 抽到主进程
 * - A-3: TeachingStateMachine 改订阅事件
 * - A-4: ChatPage 改为订阅模式
 *
 * 依据: dev-docs/tasks/sprint-20-plan.md §A-1
 */

import type { AttitudeLevel } from '../../../../shared/types/index';

/** 会话阶段(对应 v5.0.0 提示词 phase 0-4) */
export type ConversationPhase =
  | 'trust_building'      // v5.0.0 新增:建立信任联系
  | 'requirement'         // 明确用户需求
  | 'diagnosis'           // 诊断分析
  | 'training'            // 训练执行
  | 'reflection';         // 反思复盘

/** 用户意图(从 AI 输出中提取,供状态机决策) */
export type ConversationIntent =
  | { type: 'clarify'; question: string }
  | { type: 'diagnose'; syndromeHints: string[] }
  | { type: 'train'; syndromeId: string; techniqueId?: string }
  | { type: 'close'; summary: string }
  | { type: 'none' };

/** 训练触发事件 */
export interface TrainingTriggeredEvent {
  sessionId: string;
  syndromeId: string;
  techniqueId?: string;
  /** 触发原因,用于回放/审计 */
  reason: 'diagnosis_result' | 'user_request' | 'prescription';
}

/** 症候证据(从 AI 输出归一化提取) */
export interface SyndromeEvidence {
  syndromeId: string;
  severity: 'L1' | 'L2' | 'L3' | null;
  /** 原文证据片段(用于溯源) */
  evidenceQuote: string;
  /** 用户问题 ID(用于关联到 ActiveProblem) */
  problemId?: string;
}

/** 阶段切换事件 */
export interface PhaseTransitionEvent {
  from: ConversationPhase;
  to: ConversationPhase;
  reason: string;
}

/** 错误事件 */
export interface OrchestratorError {
  code: 'API_ERROR' | 'PARSE_ERROR' | 'PHASE_INVALID' | 'CONTEXT_MISSING' | 'TIMEOUT';
  message: string;
  retryable: boolean;
}

/** 标准化事件流 — 所有消费者只订阅这些类型,不解 raw stream */
export type OrchestratorEvent =
  | { type: 'token'; content: string }
  | { type: 'intent'; payload: ConversationIntent }
  | { type: 'phase_transition'; payload: PhaseTransitionEvent }
  | { type: 'training_triggered'; payload: TrainingTriggeredEvent }
  | { type: 'diagnosis_extracted'; payload: SyndromeEvidence }
  | { type: 'done' }
  | { type: 'error'; payload: OrchestratorError };

/** Skill 引用(Sprint 20 A-2 准备:目前为声明,A-2 落地主进程加载) */
export interface SkillRef {
  id: string;
  /** 估算 token,用于控制 prompt 大小 */
  estimatedTokens: number;
  /** 加载阶段 */
  phases: ConversationPhase[];
}

/** 提示词元数据(R-025 治理入口) */
export interface PromptVersion {
  version: string;
  /** 回滚目标 */
  rollbackTo?: string;
  /** 变更日志 */
  changelog: string;
}

/** handleTurn 入参 */
export interface HandleTurnInput {
  /** 用户消息 */
  userMessage: string;
  /** 当前 phase(状态机注入) */
  phase: ConversationPhase;
  /** 会话 ID(必填,R-006 教训) */
  sessionId: string;
  /** 关联的活跃问题(可选) */
  activeProblemId?: string;
  /** 关联的活跃训练(可选) */
  activeTrainingSessionId?: string;
  /** 态度档位 */
  attitudeLevel?: AttitudeLevel;
  /** 学生上下文(可选,如章节引用解析结果) */
  studentContext?: string;
  /** 历史消息(已渲染的消息列表) */
  history?: Array<{ role: 'user' | 'assistant'; content: string }>;
}

/** 编排器接口 */
export interface ConversationOrchestrator {
  /**
   * 核心入口:处理一轮用户消息,产出标准化事件流
   * 调用方通过 for-await-of 消费事件
   */
  handleTurn(input: HandleTurnInput): AsyncIterable<OrchestratorEvent>;

  /**
   * 当前加载的提示词版本(R-025 治理接口)
   * 用于运行时切换 / 回滚通道验证
   */
  promptVersion(): PromptVersion;

  /**
   * 当前 phase 应加载的 skill 清单
   * A-2 落地主进程加载,目前返回声明
   */
  skillManifest(phase: ConversationPhase): SkillRef[];

  /**
   * 停止当前生成
   * 委托给底层 streamHandler
   */
  stopGeneration(): { stopped: boolean };
}

/** 标记事件类型守卫 */
export const isTokenEvent = (e: OrchestratorEvent): e is { type: 'token'; content: string } =>
  e.type === 'token';

export const isIntentEvent = (e: OrchestratorEvent): e is { type: 'intent'; payload: ConversationIntent } =>
  e.type === 'intent';

export const isPhaseTransitionEvent = (e: OrchestratorEvent): e is { type: 'phase_transition'; payload: PhaseTransitionEvent } =>
  e.type === 'phase_transition';

export const isTrainingTriggeredEvent = (e: OrchestratorEvent): e is { type: 'training_triggered'; payload: TrainingTriggeredEvent } =>
  e.type === 'training_triggered';

export const isDiagnosisEvent = (e: OrchestratorEvent): e is { type: 'diagnosis_extracted'; payload: SyndromeEvidence } =>
  e.type === 'diagnosis_extracted';

export const isErrorEvent = (e: OrchestratorEvent): e is { type: 'error'; payload: OrchestratorError } =>
  e.type === 'error';
