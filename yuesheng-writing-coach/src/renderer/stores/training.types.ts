/**
 * 训练 Store 类型定义与常量
 */

import type {
  CenterMode,
  ErrorCard,
  TrainingRecommendation,
  ActiveTrainingSession,
  TrainingStep,
  TrainingRecord,
  EvaluationResult,
} from '../shared/types';

// ===== 类型定义 =====

export interface TrainingSubmissionResult {
  passed: boolean;
  feedback: string;
  score?: number;
  improved?: boolean;
  nextStep?: string;
}

export interface TrainingState {
  /** 中心面板模式：'chat' = 对话流，'training' = 训练工坊 */
  centerMode: CenterMode;

  /** 错误卡片数据（由历史诊断聚合生成） */
  errorCards: ErrorCard[];

  /** 推荐训练任务 */
  recommendations: TrainingRecommendation[];

  /** 阅读前置决策结果（B-02） */
  readingDecision: {
    required: boolean;
    recommended: boolean;
    label: string;
    reason?: string;
  } | null;

  /** M4: 阅读已完成标记（用于展示过渡横幅） */
  readingComplete: boolean;

  /** 当前活跃的训练会话（null = 未在进行训练） */
  activeTraining: ActiveTrainingSession | null;

  /** 训练历史记录 */
  history: TrainingRecord[];

  /** AI 提交评估结果（null = 未提交或已清除） */
  submissionResult: TrainingSubmissionResult | null;

  /** 训练评分结果（Evaluator Agent 输出，null = 未评估） */
  evaluationResult: EvaluationResult | null;

  /** 加载中 */
  isLoading: boolean;

  /** 加载错误 */
  error: string | null;

  /** 桥接卡片推荐（null = 无推荐或已关闭） */
  bridgeRecommendation: TrainingRecommendation | null;

  // ===== A3: 自荐阅读框架 =====

  /** A3: 最近一次训练的评估分数（用于判断是否推荐阅读） */
  lastEvaluationScore: number | null;

  /** A3: 最近训练对应的症候 ID（用于匹配阅读材料） */
  lastSyndromeId: string | null;

  // ===== C2: BehaviorDerivationTool 状态 =====

  /** 推导加载中 */
  derivationLoading: boolean;

  /** 推导结果 */
  derivationResult: {
    derivedBehavior: string;
    analysis: string;
    consistencyCheck: string;
  } | null;

  /** 推导错误 */
  derivationError: string | null;

  // ===== F-03: 复盘总结 =====

  /** 复盘总结数据（null = 未加载） */
  retroSummary: {
    totalTrainingCount: number;
    syndromeCount: number;
    syndromeSummaries: Array<{
      syndromeId: string;
      syndromeName: string;
      trainingCount: number;
      initialScore: number | null;
      currentScore: number | null;
      improvement: number | null;
      mastered: boolean;
    }>;
    overallImprovement: number;
    masteredTechniques: string[];
    recommendedFocus: string[];
    summary: string;
  } | null;

  /** 复盘加载中 */
  retroLoading: boolean;

  /** 进入复盘阶段（通过 IPC 生成复盘总结，切换 centerMode 为 retro） */
  enterRetro: (sessionId: string) => Promise<void>;

  // ===== 模式切换 =====

  /** 进入训练工坊（切换 centerMode 为 training） */
  enterWorkshop: () => Promise<void>;

  /** 返回对话流（切换 centerMode 为 chat） */
  backToChat: () => void;

  /** 进入编辑器（切换 centerMode 为 editor） */
  enterEditor: () => void;

  // ===== 训练操作 =====

  /** 开始训练任务 */
  startTraining: (challengeId: string) => Promise<void>;

  /** B-02: 开始阅读前置任务（加载 reading-library 条目，创建 mode: reading_task 会话） */
  startReading: (challengeId: string) => Promise<void>;

  /** 更新草稿 */
  updateDraft: (content: string) => void;

  /** 提交练习步骤 */
  submitStep: () => Promise<void>;

  /** 跳过/放弃训练 */
  skipTraining: () => Promise<void>;

  /** M4: 关闭阅读完成横幅 */
  dismissReadingComplete: () => void;

  /** 加载训练历史 */
  loadHistory: (sessionId: string) => Promise<void>;

  /** 刷新训练工坊数据（从诊断数据聚合 + IPC 推荐） */
  refreshFromDiagnosis: () => Promise<void>;

  /** 设置桥接卡片推荐（诊断后自动调用） */
  setBridgeRecommendation: (rec: TrainingRecommendation | null) => void;

  /** 关闭桥接卡片 */
  dismissBridge: () => void;

  /** 评估训练（调用 Evaluator Agent 获取评分） */
  evaluateTraining: () => Promise<void>;

  /** C2: 推导角色行为 */
  deriveBehavior: (params: {
    characterName: string;
    sceneDescription: string;
    question1: string;
    question2: string;
    question3: string;
  }) => Promise<void>;

  /** 重置推导状态 */
  resetDerivation: () => void;

  /** X-02: 将训练稿写入编辑器（当前章节） */
  sendToEditor: () => void;
}

// ===== 通用三步框架 =====

export const DEFAULT_STEPS: Omit<TrainingStep, 'status'>[] = [
  { id: 'review', title: '阅读你的原始文本', description: '回顾你这段写作中暴露的问题' },
  { id: 'rewrite', title: '约束改写', description: '在给定的约束条件下改写这段内容' },
  { id: 'submit', title: '提交评估', description: '提交修改稿并接收 AI 评估反馈' },
];

/** A3: 阅读任务的三步框架 — 分析观察而非约束改写 */
export const READING_STEPS: Omit<TrainingStep, 'status'>[] = [
  { id: 'read_guide', title: '阅读指导', description: '了解本次需要关注的阅读分析方向' },
  { id: 'analyze', title: '写下分析', description: '根据指导写下你的阅读分析或观察' },
  { id: 'submit', title: '提交评估', description: '提交分析结果并接收 AI 评估反馈' },
];
