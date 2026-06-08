// 运行时常量定义（ESM 格式）
// 与 src/shared/constants.ts 保持值一致
// 此文件作为 Vite 8 OxC 编译器的 workaround（避免 as const 对象被转为 CJS）
// v2: 修复 ESM 导出格式

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
};
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
};
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
};
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
    PRACTICE_REFLECTION: 'S2_REFLECTION',
    PRACTICE_TEACHING: 'S2_TEACHING',
    PRACTICE_ASSIGN_TASK: 'S2_ASSIGN_TASK',
    PRACTICE_REVIEW_TASK: 'S2_REVIEW_TASK',
    // P4_REVIEW 子阶段
    REVIEW_SUMMARY: 'S4_SUMMARY',
};
/** 默认显示/查询的最大诊断历史条数 */
export const MAX_DIAGNOSIS_HISTORY = 3;
/** 改善判定阈值（分数差大于此值视为明显改善/加重） */
export const IMPROVEMENT_THRESHOLD = 1;
/** IPC 通道常量 */
export const IPC_CHANNELS = {
    // === 配置 ===
    CONFIG_GET: 'config:get',
    CONFIG_SET: 'config:set',
    CONFIG_TEST_CONNECTION: 'config:testConnection',
    // === 诊断 ===
    DIAGNOSIS_UPDATE: 'diagnosis:update',
    DIAGNOSIS_QUERY: 'diagnosis:query',
    DIAGNOSIS_SUBMIT_REWRITE: 'diagnosis:submitRewrite',
    DIAGNOSIS_GET_COMPARISON: 'diagnosis:getComparison',
    GROWTH_GET_TRENDS: 'growth:getTrends',
    GROWTH_GET_GLOBAL_TRENDS: 'growth:getGlobalTrends',
    // === 教学状态 ===
    TEACHING_STATE_GET_CONTEXT: 'teachingState:getContext',
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
    TRAINING_DERIVE_BEHAVIOR: 'training:derive-behavior',
    // === 聊天 ===
    CHAT_SEND: 'chat:send',
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
    // === 作品管理 ===
    MANUSCRIPT_LIST: 'manuscript:list',
    MANUSCRIPT_GET: 'manuscript:get',
    MANUSCRIPT_CREATE: 'manuscript:create',
    MANUSCRIPT_UPDATE: 'manuscript:update',
    CHAPTER_LIST: 'chapter:list',
    CHAPTER_GET: 'chapter:get',
    CHAPTER_CREATE: 'chapter:create',
    CHAPTER_UPDATE_CONTENT: 'chapter:updateContent',
};
