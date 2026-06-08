/** 病症 ID 常量 */
export declare const SyndromeId: {
    readonly WorldviewBloat: "P001";
    readonly CharacterTool: "P002";
    readonly EmotionLabeling: "P003";
    readonly InfoDumping: "P004";
    readonly PerspectiveDrift: "P005";
    readonly PacingStagnation: "P006";
    readonly ReadingStructureSingle: "P007";
    readonly MotivationDeficit: "P009";
    readonly OCPlanarization: "P010";
    readonly HooklessOpening: "H001";
    readonly IdentityMissing: "H002";
    readonly EmotionalCurveIssue: "E001";
    readonly IntentContradictionNovice: "I001";
    readonly IntentContradictionTalent: "I002";
    readonly IntentContradictionWorldview: "I003";
    readonly IntentContradictionProtagonist: "I004";
    readonly IntentContradictionPacing: "I005";
    readonly IntentExecutionGap: "I006";
};
/** 病症 ID 类型 */
export type SyndromeId = (typeof SyndromeId)[keyof typeof SyndromeId];
/** 教学动作 ID 常量（以 syndrome-manual.md / action-library.md 为权威来源） */
export declare const ActionId: {
    readonly NarrowScope: "A001";
    readonly ReturnToProtagonist: "A002";
    readonly FiveQuestions: "A003";
    readonly GroundInReality: "A004";
    readonly StageSplit: "A005";
    readonly ContrastShow: "A006";
    readonly FlipPerspective: "A007";
    readonly ReadingAssignment: "A008";
    readonly ConfidenceConfirm: "A009";
    readonly BoundaryCalibration: "A010";
    readonly CrossContextTransfer: "A011";
    /** 意图校准：呈现矛盾而非下判断 */
    readonly IntentCalibration: "A012";
};
/** 教学动作 ID 类型 */
export type ActionId = (typeof ActionId)[keyof typeof ActionId];
/** 教学阶段常量 */
export declare const TeachingPhase: {
    /** 初次见面 */
    readonly INIT: "P0_INIT";
    /** 投入建立（V2.2 阶段一演进）—— 让用户愿意暴露 */
    readonly ENGAGE: "P0_ENGAGE";
    /** 世界观搭建 */
    readonly WORLD: "P1_WORLD";
    /** 诊断-训练循环：识别问题 → 推荐任务 → 练习 → 反馈 */
    readonly PRACTICE_LOOP: "P2_PRACTICE_LOOP";
    /** 复盘总结 */
    readonly REVIEW: "P4_REVIEW";
};
/** 教学阶段类型 */
export type TeachingPhase = (typeof TeachingPhase)[keyof typeof TeachingPhase];
/** 教学子阶段常量 */
export declare const TeachingSubphase: {
    readonly ENGAGE_CONFIRM: "S0_CONFIRM";
    readonly WORLD_NATURAL_LAW: "S1_NATURAL_LAW";
    readonly WORLD_PROTAGONIST: "S1_PROTAGONIST";
    readonly WORLD_SOCIAL_STRUCT: "S1_SOCIAL_STRUCT";
    readonly WORLD_FIRST_SCENE: "S1_FIRST_SCENE";
    readonly WORLD_DAILY_DETAIL: "S1_DAILY_DETAIL";
    readonly PRACTICE_IDENTIFY: "S2_IDENTIFY";
    readonly PRACTICE_REFLECTION: "S2_REFLECTION";
    readonly PRACTICE_TEACHING: "S2_TEACHING";
    readonly PRACTICE_ASSIGN: "S2_ASSIGN_TASK";
    readonly PRACTICE_REVIEW: "S2_REVIEW_TASK";
    readonly REVIEW_SUMMARY: "S4_SUMMARY";
};
/** 教学子阶段类型 */
export type TeachingSubphase = (typeof TeachingSubphase)[keyof typeof TeachingSubphase];
/** 默认显示/查询的最大诊断历史条数 */
export declare const MAX_DIAGNOSIS_HISTORY = 3;
/** 改善判定阈值（分数差大于此值视为明显改善/加重） */
export declare const IMPROVEMENT_THRESHOLD = 1;
/** IPC 通道常量 */
export declare const IPC_CHANNELS: {
    readonly CONFIG_GET: "config:get";
    readonly CONFIG_SET: "config:set";
    readonly CONFIG_TEST_CONNECTION: "config:testConnection";
    readonly DIAGNOSIS_UPDATE: "diagnosis:update";
    readonly DIAGNOSIS_QUERY: "diagnosis:query";
    readonly DIAGNOSIS_SUBMIT_REWRITE: "diagnosis:submitRewrite";
    readonly DIAGNOSIS_GET_COMPARISON: "diagnosis:getComparison";
    readonly GROWTH_GET_TRENDS: "growth:getTrends";
    readonly GROWTH_GET_GLOBAL_TRENDS: "growth:getGlobalTrends";
    readonly TEACHING_STATE_GET_CONTEXT: "teachingState:getContext";
    readonly TEACHING_STATE_GET: "teachingState:get";
    readonly TEACHING_STATE_UPDATE: "teachingState:update";
    readonly TEACHING_STATE_CONFIRM: "teachingState:confirm";
    readonly TEACHING_STATE_GET_PROMPT: "teachingState:getPrompt";
    readonly TEACHING_STATE_UPDATE_SUMMARY: "teachingState:updateSummary";
    readonly TEACHING_STATE_UPDATED: "teachingState:updated";
    readonly ABILITY_GET_PROFILE: "ability:getProfile";
    readonly EVIDENCE_GET_BY_DISEASE: "evidence:getByDisease";
    readonly EVIDENCE_GET_BY_ABILITY: "evidence:getByAbility";
    readonly EVIDENCE_GET_CHAIN: "evidence:getChain";
    readonly EVIDENCE_CREATE: "evidence:create";
    readonly EVIDENCE_GET_BY_SYNDROME: "evidence:getBySyndrome";
    readonly TRAINING_RECOMMEND: "training:recommend";
    readonly TRAINING_ASSIGN: "training:assign";
    readonly TRAINING_COMPLETE: "training:complete";
    readonly TRAINING_SKIP: "training:skip";
    readonly TRAINING_HISTORY: "training:history";
    readonly TRAINING_SUBMIT: "training:submit";
    readonly TRAINING_EVALUATE: "training:evaluate";
    readonly TRAINING_DERIVE_BEHAVIOR: "training:derive-behavior";
    readonly CHAT_SEND: "chat:send";
    readonly CHAT_STREAM_DATA: "chat:stream:data";
    readonly CHAT_STREAM_END: "chat:stream:end";
    readonly SESSION_LIST: "session:list";
    readonly SESSION_CREATE: "session:create";
    readonly SESSION_DELETE: "session:delete";
    readonly SESSION_RENAME: "session:rename";
    readonly SESSION_GET_MESSAGES: "session:getMessages";
    readonly SESSION_GET_MESSAGES_PAGED: "session:getMessagesPaged";
    readonly SESSION_LIST_WITH_META: "session:listWithMeta";
    readonly SESSION_UPDATE_TITLE: "session:updateTitle";
    readonly SESSION_SEARCH_MESSAGES: "session:searchMessages";
    readonly MANUSCRIPT_LIST: "manuscript:list";
    readonly MANUSCRIPT_GET: "manuscript:get";
    readonly MANUSCRIPT_CREATE: "manuscript:create";
    readonly MANUSCRIPT_UPDATE: "manuscript:update";
    readonly CHAPTER_LIST: "chapter:list";
    readonly CHAPTER_GET: "chapter:get";
    readonly CHAPTER_CREATE: "chapter:create";
    readonly CHAPTER_UPDATE_CONTENT: "chapter:updateContent";
};
