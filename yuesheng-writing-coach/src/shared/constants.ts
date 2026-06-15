// 运行时常量定义（TypeScript 版本，供主进程编译使用）
// 与 src/renderer/shared/constants.js 保持值一致

/** 病症 ID 常量 */
export const SyndromeId = {
  WorldviewBloat: 'P001',
  CharacterTool: 'P002',
  EmotionLabeling: 'P003',
  InfoDumping: 'P004',
  PerspectiveDrift: 'P005',
  PacingStagnation: 'P006',
  ReadingStructureSingle: 'P007',
  WorldviewExposition: 'P008',
  MotivationDeficit: 'P009',
  OCPlanarization: 'P010',
  // 诊断维度标记（由 DiagnosisAgent 产出，非教学症候）
  HooklessOpening: 'H001',
  IdentityMissing: 'H002',
  EmotionalCurveIssue: 'E001',
  IntentContradictionNovice: 'I001',
  IntentContradictionTalent: 'I002',
  IntentContradictionWorldview: 'I003',
  IntentContradictionProtagonist: 'I004',
  IntentContradictionPacing: 'I005',
  IntentExecutionGap: 'I006',
} as const;

/** 病症 ID 类型 */
export type SyndromeId = (typeof SyndromeId)[keyof typeof SyndromeId];

/** 教学动作 ID 常量（以 syndrome-manual.md / action-library.md 为权威来源） */
export const ActionId = {
  NarrowScope: 'A001',
  ReturnToProtagonist: 'A002',
  FiveQuestions: 'A003',
  GroundInReality: 'A004',
  StageSplit: 'A005',
  ContrastShow: 'A006',
  FlipPerspective: 'A007',
  ReadingAssignment: 'A008',
  ConfidenceConfirm: 'A009',
  BoundaryCalibration: 'A010',
  CrossContextTransfer: 'A011',
  /** 意图校准：呈现矛盾而非下判断 */
  IntentCalibration: 'A012',
} as const;

/** 教学动作 ID 类型 */
export type ActionId = (typeof ActionId)[keyof typeof ActionId];

/** 教学阶段常量 */
export const TeachingPhase = {
  /** 初次见面 */
  INIT: 'P0_INIT',
  /** 投入建立（V2.2 阶段一演进）—— 让用户愿意暴露 */
  ENGAGE: 'P0_ENGAGE',
  /** 世界观搭建 */
  WORLD: 'P1_WORLD',
  /** 诊断-训练循环：识别问题 → 推荐任务 → 练习 → 反馈 */
  PRACTICE_LOOP: 'P2_PRACTICE_LOOP',
  /** 复盘总结 */
  REVIEW: 'P4_REVIEW',
} as const;

/** 教学阶段类型 */
export type TeachingPhase = (typeof TeachingPhase)[keyof typeof TeachingPhase];

/** 教学子阶段常量 */
export const TeachingSubphase = {
  // P0_ENGAGE 子阶段
  ENGAGE_CONFIRM: 'S0_CONFIRM',
  // P1_WORLD 子阶段
  WORLD_NATURAL_LAW: 'S1_NATURAL_LAW',
  WORLD_PROTAGONIST: 'S1_PROTAGONIST',
  WORLD_SOCIAL_STRUCT: 'S1_SOCIAL_STRUCT',
  WORLD_FIRST_SCENE: 'S1_FIRST_SCENE',
  WORLD_DAILY_DETAIL: 'S1_DAILY_DETAIL',
  // P2_PRACTICE_LOOP 子阶段
  PRACTICE_IDENTIFY: 'S2_IDENTIFY',
  PRACTICE_GUIDE: 'S2_GUIDE',
  PRACTICE_REFLECTION: 'S2_REFLECTION',
  PRACTICE_TEACHING: 'S2_TEACHING',
  PRACTICE_ASSIGN: 'S2_ASSIGN_TASK',
  PRACTICE_REVIEW: 'S2_REVIEW_TASK',
  // P4_REVIEW 子阶段
  REVIEW_SUMMARY: 'S4_SUMMARY',
} as const;

/** 教学子阶段类型 */
export type TeachingSubphase = (typeof TeachingSubphase)[keyof typeof TeachingSubphase];

/** S2 训练循环子阶段有序序列（B-01 状态机遍历用） */
export const S2_SUBPHASES: TeachingSubphase[] = [
  TeachingSubphase.PRACTICE_IDENTIFY,
  TeachingSubphase.PRACTICE_GUIDE,
  TeachingSubphase.PRACTICE_REFLECTION,
  TeachingSubphase.PRACTICE_TEACHING,
  TeachingSubphase.PRACTICE_ASSIGN,
  TeachingSubphase.PRACTICE_REVIEW,
];

/** 默认显示/查询的最大诊断历史条数 */
export const MAX_DIAGNOSIS_HISTORY = 3;

/** 改善判定阈值（分数差大于此值视为明显改善/加重） */
export const IMPROVEMENT_THRESHOLD = 1;

/**
 * IPC 通道常量
 * @deprecated 请使用 src/shared/api-contracts/ 下的类型化 API 合约替代。
 *             新代码应通过 API 合约的 invoke() 进行类型安全的 IPC 调用，
 *             不再直接引用 IPC_CHANNELS 的字符串通道名。
 */
export const IPC_CHANNELS = {
  // === 配置 ===
  CONFIG_GET: 'config:get',
  CONFIG_SET: 'config:set',
  CONFIG_TEST_CONNECTION: 'config:testConnection',
  CONFIG_GET_READING_ENTRY: 'config:getReadingEntry',
  // === 诊断 ===
  DIAGNOSIS_UPDATE: 'diagnosis:update',
  DIAGNOSIS_QUERY: 'diagnosis:query',
  DIAGNOSIS_SUBMIT_REWRITE: 'diagnosis:submitRewrite',
  DIAGNOSIS_GET_COMPARISON: 'diagnosis:getComparison',
  GROWTH_GET_TRENDS: 'growth:getTrends',
  GROWTH_GET_GLOBAL_TRENDS: 'growth:getGlobalTrends',
  // === 教学状态 ===
  TEACHING_STATE_GET: 'teachingState:get',
  TEACHING_STATE_UPDATE: 'teachingState:update',
  TEACHING_STATE_CONFIRM: 'teachingState:confirm',
  TEACHING_STATE_GET_PROMPT: 'teachingState:getPrompt',
  TEACHING_STATE_UPDATE_SUMMARY: 'teachingState:updateSummary',
  TEACHING_STATE_UPDATED: 'teachingState:updated',
  // === 能力画像 ===
  ABILITY_GET_PROFILE: 'ability:getProfile',
  // === 证据 ===
  EVIDENCE_GET_BY_DISEASE: 'evidence:getByDisease',
  EVIDENCE_GET_BY_ABILITY: 'evidence:getByAbility',
  EVIDENCE_GET_CHAIN: 'evidence:getChain',
  EVIDENCE_CREATE: 'evidence:create',
  EVIDENCE_GET_BY_SYNDROME: 'evidence:getBySyndrome',
  // === 训练 ===
  TRAINING_RECOMMEND: 'training:recommend',
  TRAINING_ASSIGN: 'training:assign',
  TRAINING_COMPLETE: 'training:complete',
  TRAINING_SKIP: 'training:skip',
  TRAINING_HISTORY: 'training:history',
  TRAINING_SUBMIT: 'training:submit',
  TRAINING_EVALUATE: 'training:evaluate',
  TRAINING_DECIDE_READING: 'training:decideReading',
  TRAINING_DERIVE_BEHAVIOR: 'training:deriveBehavior',
  // === 聊天 ===
  CHAT_SEND: 'chat:send',
  CHAT_STOP: 'chat:stop',
  CHAT_STREAM_DATA: 'chat:stream:data',
  CHAT_STREAM_END: 'chat:stream:end',
  // === 会话管理 ===
  SESSION_LIST: 'session:list',
  SESSION_CREATE: 'session:create',
  SESSION_DELETE: 'session:delete',
  SESSION_RENAME: 'session:rename',
  SESSION_GET_MESSAGES: 'session:getMessages',
  SESSION_GET_MESSAGES_PAGED: 'session:getMessagesPaged',
  SESSION_LIST_WITH_META: 'session:listWithMeta',
  SESSION_UPDATE_TITLE: 'session:updateTitle',
  SESSION_SEARCH_MESSAGES: 'session:searchMessages',
  // === 新用户引导 ===
  SESSION_IS_NEW_USER: 'session:isNewUser',
  ONBOARDING_ANALYZE: 'onboarding:analyze',
  // === 作品管理 ===
  MANUSCRIPT_LIST: 'manuscript:list',
  MANUSCRIPT_GET: 'manuscript:get',
  MANUSCRIPT_CREATE: 'manuscript:create',
  MANUSCRIPT_UPDATE: 'manuscript:update',
  CHAPTER_LIST: 'chapter:list',
  CHAPTER_GET: 'chapter:get',
  CHAPTER_CREATE: 'chapter:create',
  CHAPTER_DELETE: 'chapter:delete',
  CHAPTER_UPDATE_CONTENT: 'chapter:updateContent',
  MANUSCRIPT_DELETE: 'manuscript:delete',
  // === 工具调用 ===
  CHAT_TOOL_EXECUTING: 'chat:tool:executing',
} as const;

/** 允许渲染进程通过 invoke() 调用的 IPC 通道白名单 */
export const ALLOWED_INVOKE_CHANNELS: readonly string[] = [
  IPC_CHANNELS.CONFIG_GET,
  IPC_CHANNELS.CONFIG_SET,
  IPC_CHANNELS.CONFIG_TEST_CONNECTION,
  IPC_CHANNELS.CONFIG_GET_READING_ENTRY,
  IPC_CHANNELS.DIAGNOSIS_QUERY,
  IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE,
  IPC_CHANNELS.DIAGNOSIS_GET_COMPARISON,
  IPC_CHANNELS.GROWTH_GET_TRENDS,
  IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS,
  IPC_CHANNELS.TEACHING_STATE_GET,
  IPC_CHANNELS.TEACHING_STATE_UPDATE,
  IPC_CHANNELS.TEACHING_STATE_CONFIRM,
  IPC_CHANNELS.TEACHING_STATE_GET_PROMPT,
  IPC_CHANNELS.TEACHING_STATE_UPDATE_SUMMARY,
  IPC_CHANNELS.ABILITY_GET_PROFILE,
  IPC_CHANNELS.EVIDENCE_GET_BY_DISEASE,
  IPC_CHANNELS.EVIDENCE_GET_BY_ABILITY,
  IPC_CHANNELS.EVIDENCE_GET_CHAIN,
  IPC_CHANNELS.EVIDENCE_CREATE,
  IPC_CHANNELS.EVIDENCE_GET_BY_SYNDROME,
  IPC_CHANNELS.CHAT_SEND,
  IPC_CHANNELS.CHAT_STOP,
  IPC_CHANNELS.SESSION_LIST,
  IPC_CHANNELS.SESSION_CREATE,
  IPC_CHANNELS.SESSION_DELETE,
  IPC_CHANNELS.SESSION_RENAME,
  IPC_CHANNELS.SESSION_GET_MESSAGES,
  IPC_CHANNELS.SESSION_GET_MESSAGES_PAGED,
  IPC_CHANNELS.SESSION_LIST_WITH_META,
  IPC_CHANNELS.SESSION_UPDATE_TITLE,
  IPC_CHANNELS.SESSION_SEARCH_MESSAGES,
  IPC_CHANNELS.SESSION_IS_NEW_USER,
  IPC_CHANNELS.ONBOARDING_ANALYZE,
  IPC_CHANNELS.TRAINING_RECOMMEND,
  IPC_CHANNELS.TRAINING_ASSIGN,
  IPC_CHANNELS.TRAINING_COMPLETE,
  IPC_CHANNELS.TRAINING_SKIP,
  IPC_CHANNELS.TRAINING_HISTORY,
  IPC_CHANNELS.TRAINING_SUBMIT,
  IPC_CHANNELS.TRAINING_EVALUATE,
  IPC_CHANNELS.TRAINING_DECIDE_READING,
  IPC_CHANNELS.TRAINING_DERIVE_BEHAVIOR,
  IPC_CHANNELS.MANUSCRIPT_LIST,
  IPC_CHANNELS.MANUSCRIPT_GET,
  IPC_CHANNELS.MANUSCRIPT_CREATE,
  IPC_CHANNELS.MANUSCRIPT_UPDATE,
  IPC_CHANNELS.MANUSCRIPT_DELETE,
  IPC_CHANNELS.CHAPTER_LIST,
  IPC_CHANNELS.CHAPTER_GET,
  IPC_CHANNELS.CHAPTER_CREATE,
  IPC_CHANNELS.CHAPTER_DELETE,
  IPC_CHANNELS.CHAPTER_UPDATE_CONTENT,
];

/** 允许渲染进程通过 on() 订阅的 IPC 事件通道白名单 */
export const ALLOWED_EVENT_CHANNELS: readonly string[] = [
  IPC_CHANNELS.DIAGNOSIS_UPDATE,
  IPC_CHANNELS.TEACHING_STATE_UPDATED,
  IPC_CHANNELS.CHAT_STREAM_DATA,
  IPC_CHANNELS.CHAT_STREAM_END,
  IPC_CHANNELS.CHAT_TOOL_EXECUTING,
];
