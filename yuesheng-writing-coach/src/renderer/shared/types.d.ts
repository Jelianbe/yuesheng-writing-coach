/** 态度档位类型（三态：温柔/月笙/尖锐） */
export type AttitudeLevel = 'doubao' | 'yuesheng' | 'direct';
/** API 配置数据 */
export interface ApiConfig {
    /** OpenAI 兼容 API 密钥 */
    apiKey: string;
    /** API 基础 URL */
    baseUrl: string;
    /** 模型名称 */
    modelName: string;
    /** 温度参数 (0-2) */
    temperature: number;
    /** 态度档位 */
    attitudeLevel: AttitudeLevel;
    /** 聊天流输出最大 token 数（默认 8192） */
    maxTokens: number;
}
/**
 * 统一 IPC 响应格式（ER5）
 * 所有 handler 统一使用此格式返回，确保渲染进程可用统一方式处理错误
 */
export interface ApiResponse<T = unknown> {
    /** 操作是否成功 */
    success: boolean;
    /** 成功时返回的数据 */
    data?: T;
    /** 失败时的错误信息 */
    error?: string;
}
/** 创建成功响应 */
export declare function apiSuccess<T>(data: T): ApiResponse<T>;
/** 创建错误响应 */
export declare function apiError(error: string): ApiResponse<never>;
/** API 配置校验结果 */
export interface ApiConfigValidation {
    /** 是否通过校验 */
    isValid: boolean;
    /** 校验错误消息（仅当 isValid=false 时存在） */
    errors: string[];
}
/** 连接测试结果 */
export interface ConnectionTestResult {
    /** 测试是否成功 */
    success: boolean;
    /** 错误消息（仅当 success=false 时存在） */
    error?: string;
    /** 响应时间（毫秒） */
    responseTime?: number;
}
/** 诊断严重度等级 */
export type SeverityLevel = 'L1' | 'L2' | 'L3';
/** 病症 ID（运行时常量见 constants.js → SyndromeId） */
export type SyndromeId = string;
/** 症候类型分类（V6.0新增，用于教育学规则匹配） */
export type SyndromeType = 'expressive_deficit' | 'structural_disorder' | 'motivation_deficit';
/** 教学动作 ID（运行时常量见 constants.js → ActionId） */
export type ActionId = string;
/** 触发信号（诊断引擎用，仅用于诊断解析器验证） */
export interface SyndromeSignal {
    /** 信号类型：关键词/正则/句式 */
    type: string;
    /** 匹配模式（关键词或正则表达式） */
    pattern: string;
    /** 权重分值 */
    weight: number;
    /** 是否匹配到文本前缀位置 */
    prefixMatch?: boolean;
    /** 匹配到的文本片段 */
    matchedText?: string;
}
/** 单个病症诊断结果（AI 输出格式） */
export interface SyndromeResult {
    /** 病症 ID（可能与 variant 编码在同一字符串中，如 "P001::setting_overload"） */
    id: SyndromeId;
    /** 变种标识（如 "setting_overload"），由 parser 从 id 中拆分 */
    variant?: string;
    /** 病症名称 */
    name: string;
    /** 严重度等级 */
    severity: SeverityLevel;
    /** 用户原文证据片段 */
    evidence: string[];
    /** 信号分（可选，用于排序） */
    score?: number;
    /** 建议教学动作 */
    suggestedActions: ActionId[];
    /** AI 提供的修改建议（可选，用于治疗模式） */
    rewriteSuggestion?: string;
}
/** AI 修改评估结果 */
export interface RewriteEvaluation {
    /** 改善程度 */
    improvement: '明显改善' | '略有改善' | '无明显改善';
    /** 具体分析 */
    analysis: string;
    /** 一句话建议 */
    suggestion: string;
}
/** 完整诊断条目（AI 输出格式） */
export interface DiagnosisEntry {
    /** 所属会话 ID */
    sessionId: string;
    /** 所属消息 ID */
    messageId: string;
    /** 识别到的病症列表（按严重度排序） */
    syndromes: SyndromeResult[];
    /** 合并后的建议动作列表（去重） */
    suggestedActions: ActionId[];
    /** 整体置信度（0-1） */
    confidence: number;
    /** 诊断时间戳（ISO 8601 格式） */
    timestamp: string;
    /** 下一步建议关注的病症 ID */
    nextFocus?: SyndromeId;
    /** SF-004: 节拍完整性检测结果（叙事节奏诊断用） */
    beatCheck?: Record<string, boolean>;
}
/** 聊天消息角色 */
export type MessageRole = 'user' | 'assistant' | 'system';
/** 单条消息 */
export interface ChatMessage {
    id: string;
    role: MessageRole;
    content: string;
    timestamp: number;
    diagnosis?: DiagnosisEntry;
}
/** 会话 */
export interface Session {
    id: string;
    title: string;
    createdAt: string;
    updatedAt: string;
    messages: ChatMessage[];
    lastMessage?: string;
}
/** 聊天发送请求 */
export interface ChatSendRequest {
    message: string;
    sessionId: string;
}
/** 流式数据块 */
export interface StreamChunk {
    sessionId: string;
    chunk: string;
}
/** 流式结束 */
export interface StreamEnd {
    sessionId: string;
    fullResponse: string;
    messageId: string;
}
/** 能力评分 */
export interface AbilityScore {
    abilityId: string;
    abilityName: string;
    score: number;
    relatedSyndromes: string[];
    severityHistory: number[];
    trend: 'up' | 'down' | 'stable';
    dataInsufficient: boolean;
}
/** 弱点标签 */
export interface WeakPoint {
    syndromeId: string;
    syndromeName: string;
    occurrenceCount: number;
    avgSeverity: number;
    lastOccurrence: string;
    trend: 'improving' | 'worsening' | 'stable';
}
/** 训练统计 */
export interface TrainingStats {
    totalAssigned: number;
    totalCompleted: number;
    completionRate: number;
    bySyndrome: Record<string, {
        assigned: number;
        completed: number;
    }>;
}
/** 诊断趋势 */
export interface DiagnosisTrend {
    totalDiagnoses: number;
    avgConfidence: number;
    syndromeFrequency: Record<string, number>;
}
/** 能力画像 */
export interface AbilityProfile {
    sessionId: string;
    abilities: AbilityScore[];
    weakPoints: WeakPoint[];
    trainingStats: TrainingStats;
    diagnosisTrend: DiagnosisTrend;
    computedAt: string;
}
/** 新用户引导基线数据 */
export interface OnboardingBaseline {
    /** 写作类型 */
    writingType: 'fantasy' | 'urban' | 'sci-fi' | 'realistic' | 'historical' | 'other' | 'unknown';
    /** 用户发送的示例文字（可选） */
    sampleText?: string;
    /** AI 分析回复摘要 */
    analysisSummary?: string;
    /** 用户选择的改进目标 */
    improvementGoal?: string;
    /** 记录时间戳 */
    capturedAt: number;
}
/** 教学阶段（运行时常量见 constants.js → TeachingPhase） */
export type TeachingPhase = string;
/** 教学子阶段（运行时常量见 constants.js → TeachingSubphase） */
export type TeachingSubphase = string;
/** 活跃病症状态 */
export type ProblemStatus = 'active' | 'improving' | 'resolved';
/** 活跃病症记录 */
export interface ActiveProblem {
    /** 病症 ID */
    id: SyndromeId;
    /** 病症名称 */
    name: string;
    /** 严重度 */
    severity: SeverityLevel;
    /** 用户原文证据片段 */
    evidence: string[];
    /** 信号分（可选，用于排序） */
    score?: number;
    /** 首次检测时间 */
    firstDetected: string;
    /** 当前状态 */
    status: ProblemStatus;
    /** 建议教学动作 */
    suggestedActions: ActionId[];
}
/** AI 状态更新建议 */
export interface AIStateSuggestion {
    /** 建议标记完成的动作 */
    completeAction?: ActionId;
    /** 建议新增的问题 */
    newProblem?: Omit<ActiveProblem, 'firstDetected' | 'status'>;
    /** 建议的下一步动作 */
    nextAction?: ActionId;
}
/** 聚焦方向值 */
export type FocusAreaValue = 'worldbuilding' | 'character' | 'general';
/** 聚焦方向（含未选择状态） */
export type FocusArea = FocusAreaValue | null;
/** 教学状态（数据库存储格式） */
export interface TeachingState {
    /** 所属会话 ID */
    sessionId: string;
    /** 当前大阶段 */
    currentPhase: TeachingPhase;
    /** 当前子阶段 */
    currentSubphase: TeachingSubphase;
    /** 已完成的教学动作 ID 列表 */
    completedActions: ActionId[];
    /** 已完成的训练任务 ID 列表 */
    completedTasks: string[];
    /** 当前活跃的病症问题 */
    activeProblems: ActiveProblem[];
    /** 建议的下一步动作 */
    nextSuggestedActions: ActionId[];
    /** 当前建议的任务 ID */
    currentTaskId: string | null;
    /** 诊断历史摘要（最近 3 轮简洁文本） */
    diagnosisSummary: string;
    /** 用户最后确认时间 */
    lastUserConfirmation: string | null;
    /** 当前聚焦方向 */
    focusArea: FocusArea;
    /** 是否已提供过过渡邀请（防止重复） */
    transitionOffered: boolean;
    /** 状态最后更新时间 */
    updatedAt: string;
    /** 锁定的症候 ID 列表（诊断后锁定，跨轮次保持，直到 resolved） */
    lockedSyndromes: string[];
}
/** 教学状态更新请求 */
export interface TeachingStateUpdateRequest {
    /** 要更新的字段（部分更新） */
    updates: Partial<Omit<TeachingState, 'sessionId' | 'updatedAt'>>;
}
/** 教学进度展示数据（前端用） */
export interface TeachingProgressDisplay {
    /** 当前阶段名称 */
    phaseName: string;
    /** 当前子阶段名称 */
    subphaseName: string;
    /** 阶段进度（0-1） */
    phaseProgress: number;
    /** 已完成动作列表（含名称） */
    completedActions: {
        id: ActionId;
        name: string;
    }[];
    /** 建议下一步动作列表（含名称） */
    nextActions: {
        id: ActionId;
        name: string;
    }[];
    /** 活跃问题列表 */
    activeProblems: ActiveProblem[];
}
/** 消息行（数据库行映射） */
export interface MessageRow {
    id: string;
    session_id: string;
    role: string;
    content: string;
    timestamp: number;
}
/** IPC 通道字符串字面量类型 */
export type IPCChannel = 'config:get' | 'config:set' | 'config:testConnection' | 'diagnosis:update' | 'diagnosis:query' | 'diagnosis:submitRewrite' | 'diagnosis:getComparison' | 'teachingState:get' | 'teachingState:update' | 'teachingState:confirm' | 'teachingState:getPrompt' | 'teachingState:updateSummary' | 'teachingState:updated' | 'ability:getProfile' | 'evidence:getByDisease' | 'evidence:getByAbility' | 'evidence:getChain' | 'evidence:create' | 'chat:send' | 'chat:stream:data' | 'chat:stream:end' | 'session:list' | 'session:create' | 'session:delete' | 'session:rename' | 'session:getMessages' | 'session:getMessagesPaged' | 'session:listWithMeta' | 'session:updateTitle' | 'session:isNewUser' | 'manuscript:list' | 'manuscript:get' | 'manuscript:create' | 'manuscript:update' | 'chapter:list' | 'chapter:get' | 'chapter:updateContent';
/** IPC 请求类型映射 */
export interface IPCRequestMap {
    'config:get': {
        key: keyof ApiConfig;
    };
    'config:set': {
        key: keyof ApiConfig;
        value: ApiConfig[keyof ApiConfig];
    };
    'config:testConnection': {
        apiKey: string;
        baseUrl: string;
    };
    'diagnosis:query': {
        sessionId: string;
    };
    'diagnosis:submitRewrite': {
        sessionId: string;
        messageId: string;
        syndromeId: SyndromeId;
        originalText: string;
        rewrittenText: string;
        syndromeName?: string;
        syndromeDesc?: string;
    };
    'diagnosis:getComparison': {
        sessionId: string;
    };
    'teachingState:get': {
        sessionId: string;
    };
    'teachingState:update': {
        sessionId: string;
        updates: Partial<Omit<TeachingState, 'sessionId' | 'updatedAt'>>;
    };
    'teachingState:confirm': {
        sessionId: string;
    };
    'teachingState:getPrompt': {
        sessionId: string;
    };
    'teachingState:updateSummary': {
        sessionId: string;
        newContent: string;
    };
    'ability:getProfile': {
        sessionId: string;
    };
    'evidence:getByDisease': {
        diseaseId: string;
        novelId: string;
        minLevel?: number;
    };
    'evidence:getByAbility': {
        abilityId: string;
        authorId: string;
        fromDate?: string;
        toDate?: string;
    };
    'evidence:getChain': {
        diagnosisId: string;
    };
    'evidence:create': {
        evidence: EvidenceRecord;
    };
    'chat:send': {
        message: string;
        sessionId: string;
        history?: {
            role: string;
            content: string;
        }[];
        attitudeLevel?: AttitudeLevel;
    };
    'session:list': Record<string, never>;
    'session:create': Record<string, never>;
    'session:delete': {
        sessionId: string;
    };
    'session:rename': {
        sessionId: string;
        title: string;
    };
    'session:getMessages': {
        sessionId: string;
    };
    'session:getMessagesPaged': {
        sessionId: string;
        offset: number;
        limit: number;
    };
    'session:listWithMeta': {
        limit?: number;
        offset?: number;
    };
    'session:updateTitle': {
        id: string;
        title: string;
    };
    'session:isNewUser': Record<string, never>;
    'manuscript:list': Record<string, never>;
    'manuscript:get': {
        id: string;
    };
    'manuscript:create': {
        title: string;
        description?: string;
        genre?: string;
    };
    'manuscript:update': {
        id: string;
        title?: string;
        description?: string;
        genre?: string;
        status?: 'active' | 'archived';
    };
    'chapter:list': {
        manuscriptId: string;
    };
    'chapter:get': {
        id: string;
    };
    'chapter:updateContent': {
        id: string;
        content: string;
    };
}
/** IPC 响应类型映射（ER5：全部统一为 ApiResponse<T>） */
export interface IPCResponseMap {
    'config:get': ApiResponse<ApiConfig[keyof ApiConfig]>;
    'config:set': ApiResponse<void>;
    'config:testConnection': ApiResponse<ConnectionTestResult>;
    'diagnosis:query': ApiResponse<ActiveProblem[] | null>;
    'diagnosis:submitRewrite': ApiResponse<{
        evaluation: RewriteEvaluation;
    } | void>;
    'diagnosis:getComparison': ApiResponse<{
        hasHistory: boolean;
        comparison?: string;
    }>;
    'teachingState:get': ApiResponse<TeachingState & {
        phaseName: string;
        subphaseName: string;
        phaseProgress: number;
    }>;
    'teachingState:update': ApiResponse<TeachingState>;
    'teachingState:confirm': ApiResponse<{
        oldState: TeachingState;
        newState: TeachingState;
    }>;
    'teachingState:getPrompt': ApiResponse<string>;
    'teachingState:updateSummary': ApiResponse<TeachingState>;
    'ability:getProfile': ApiResponse<AbilityProfile | null>;
    'evidence:getByDisease': ApiResponse<EvidenceRecord[]>;
    'evidence:getByAbility': ApiResponse<EvidenceRecord[]>;
    'evidence:getChain': ApiResponse<EvidenceChain | null>;
    'evidence:create': ApiResponse<{
        evidenceId: string;
    }>;
    'chat:send': ApiResponse<{
        messageId: string;
    }>;
    'session:list': ApiResponse<Session[]>;
    'session:create': ApiResponse<Session>;
    'session:delete': ApiResponse<void>;
    'session:rename': ApiResponse<void>;
    'session:getMessages': ApiResponse<MessageRow[]>;
    'session:getMessagesPaged': ApiResponse<{
        messages: MessageRow[];
        total: number;
        hasMore: boolean;
    }>;
    'session:listWithMeta': ApiResponse<SessionMeta[]>;
    'session:updateTitle': ApiResponse<void>;
    'session:isNewUser': ApiResponse<boolean>;
    'manuscript:list': ApiResponse<Manuscript[]>;
    'manuscript:get': ApiResponse<Manuscript | null>;
    'manuscript:create': ApiResponse<Manuscript>;
    'manuscript:update': ApiResponse<Manuscript>;
    'chapter:list': ApiResponse<Chapter[]>;
    'chapter:get': ApiResponse<Chapter | null>;
    'chapter:updateContent': ApiResponse<{
        wordCount: number;
    }>;
}
/** IPC 事件推送类型映射 */
export interface IPCEventMap {
    'diagnosis:update': DiagnosisEntry;
    'teachingState:updated': TeachingState & {
        phaseName: string;
        subphaseName: string;
        phaseProgress: number;
    };
    'chat:stream:data': {
        sessionId: string;
        chunk: string;
    };
    'chat:stream:end': {
        sessionId: string;
        fullResponse: string;
        messageId: string;
        error?: string;
    };
}
/** 单条证据记录 */
export interface EvidenceRecord {
    evidenceId: string;
    type: 'text' | 'pattern' | 'statistical' | 'comparison';
    level: 1 | 2 | 3 | 4;
    novelId: string;
    contentJson: string;
    relatedDisease: string;
    relatedAbility: string;
    extractedBy: string;
    createdAt: string;
}
/** 诊断证据链（含关联关系） */
export interface EvidenceChain {
    diagnosisId: string;
    primaryEvidence: EvidenceRecord[];
    supportingEvidence: EvidenceRecord[];
    statistics: EvidenceRecord[];
}
/** 能力轨迹点 */
export interface TrajectoryPoint {
    date: string;
    score: number;
    eventId: string;
}
/** 成长链事件 */
export interface GrowthEvent {
    eventType: 'diagnosis' | 'training' | 'evaluation';
    eventId: string;
    date: string;
    severity?: 'L1' | 'L2' | 'L3';
    snapshotId?: string;
    sampleText?: string;
    evidenceIds?: string[];
    exerciseId?: string;
    description?: string;
    score?: number;
}
/** 成长链 */
export interface GrowthChain {
    chainId: string;
    abilityId: string;
    syndromeId: string;
    status: 'active' | 'improving' | 'resolved' | 'recurred';
    timeline: GrowthEvent[];
    improvement: string;
    scoreFrom: number;
    scoreTo: number;
}
/** 可视化数据 */
export interface VisualizationData {
    type: 'radar' | 'timeline' | 'comparison';
    data: Record<string, unknown>;
}
/** 执行模式（从文本中提取） */
export interface ExecutionPattern {
    /** 主角起点修为/地位 */
    protagonistStartingLevel: string;
    /** 危机类型 */
    crisisType: string;
    /** 叙事模式 */
    narrativePattern: string;
    /** 金手指类型 */
    advantageType?: string;
    /** 日常/经济/阶层描写密度 0-1 */
    dailyLifeDensity: number;
    /** 与意图的匹配度（规则引擎计算） */
    intentConsistencyScore: number;
    /** 检测到的矛盾点 */
    mismatches: ConsistencyGap[];
}
/** 一致性检测规则匹配结果 */
export interface ConsistencyGap {
    /** 规则 ID */
    ruleId: string;
    /** 意图描述 */
    intent: string;
    /** 实际操作 */
    execution: string;
    /** 矛盾说明 */
    gap: string;
    /** 严重程度 1-5 */
    severity: number;
    /** 关联症候 */
    relatedSyndrome?: string;
}
/** 意图阶段枚举 */
export type IntentPhase = 'unknown' | 'incubating' | 'emerging' | 'established';
/** 作者阶段（面对诊断时的认知状态） */
export type AuthorStage = 'defensive' | 'accepting' | 'patching' | 'attributing';
/** 技法池条目（Diagnosis Agent 输出用） */
export interface TechniqueRef {
    /** 技法名 */
    name: string;
    /** 来源作品 */
    source: string;
    /** 难度等级 */
    difficulty: 'beginner' | 'intermediate';
}
/** 关键段落引用（Diagnosis Agent 输出用） */
export interface KeyPassage {
    /** 原文片段（不超过 50 字） */
    text: string;
    /** 问题描述 */
    issue: string;
    /** 关联的症候 ID（可选，用于按症候分组证据） */
    syndromeRef?: string;
}
/** 诊断 Agent 的结构化输出 */
export interface DiagnosisAnalysis {
    /** 内容类型：narrative=叙事文本（执行完整诊断），non-narrative=非叙事（跳过症候诊断） */
    contentType?: 'narrative' | 'non-narrative';
    /** 根因：一句话概括（不超过 20 字） */
    rootCause: string;
    /** 意图阶段：0=未成形/1=模糊/2=明确但不一致 */
    intentPhase: number;
    /** 关联症候编号列表（内部使用） */
    syndromeRef: string[];
    /** 可选技法池（3-5条） */
    techniquePool: TechniqueRef[];
    /** 文本中的关键段落（供教学引用） */
    keyPassages: KeyPassage[];
    /** 置信度（0-1） */
    confidence: number;
    /** SF-003: 节拍完整性检测（激励事件/中点转折/高潮/结局/开篇钩子） */
    beatCheck?: Record<string, boolean>;
}
/** 中心面板模式 */
export type CenterMode = 'chat' | 'training';
/** 训练步骤 */
export interface TrainingStep {
    /** 步骤 ID */
    id: string;
    /** 步骤标题 */
    title: string;
    /** 步骤描述 */
    description: string;
    /** 步骤状态 */
    status: 'completed' | 'active' | 'pending';
}
/** 活跃训练会话 */
export interface ActiveTrainingSession {
    /** 挑战 ID */
    challengeId: string;
    /** 挑战名称 */
    challengeName: string;
    /** 挑战描述（训练任务说明） */
    challengeDescription: string;
    /** 交互模式（对应 challenge-templates.json 的 mode） */
    mode: string;
    /** 步骤列表 */
    steps: TrainingStep[];
    /** 当前步骤索引（0-based） */
    currentStepIndex: number;
    /** 原始文本引用 */
    originalQuote: string;
    /** 约束条件 */
    constraint: string;
    /** 用户草稿 */
    userDraft: string;
    /** 训练记录 ID（用于提交 complete） */
    recordId?: string;
    /** 对应的症候 ID */
    syndromeId?: string;
    /** 目标症候（SF-002 长期目标展示） */
    targetSyndrome?: string;
    /** 核心技法模式（SF-002 中期目标展示） */
    corePatterns?: string;
    /** AI 评估结果（用于 complete 提交） */
    submissionResult?: {
        passed: boolean;
        feedback: string;
    };
}
/** 错误卡片（训练工坊区块一） */
export interface ErrorCard {
    /** 症候 ID */
    syndromeId: string;
    /** 症候名称 */
    syndromeName: string;
    /** 严重度 */
    severity: SeverityLevel;
    /** 诊断次数 */
    diagnosisCount: number;
    /** 最近引用（原文片段） */
    lastQuote: string;
    /** 最后诊断时间 */
    lastDiagnosedAt: string;
    /** 匹配的挑战模板 ID */
    matchedChallengeId?: string;
}
/** 训练推荐 */
export interface TrainingRecommendation {
    /** 挑战 ID */
    challengeId: string;
    /** 挑战名称 */
    challengeName: string;
    /** 挑战描述 */
    description: string;
    /** 对应症候 ID */
    syndromeId: string;
    /** 症候类型（V6.0新增） */
    syndromeType?: SyndromeType | null;
    /** 严重度 */
    severity: SeverityLevel;
    /** 层级（structural/surface） */
    tier: string;
    /** 约束条件 */
    constraint: string;
    /** 预期结果 */
    expectedOutcome: string;
    /** 模式 */
    mode: string;
    /** 匹配的技法列表 */
    techniques?: TechniqueInfo[];
}
/** 技法信息（来自 technique-library.json） */
export interface TechniqueInfo {
    /** 技法 ID */
    id: string;
    /** 技法名称 */
    name: string;
    /** 来源（小说名/公开资源） */
    source: string;
    /** 来源作者 */
    sourceAuthor?: string;
    /** 来源类型（V6.0新增：public_teaching=公开教学资源） */
    sourceType?: string;
    /** 难度 */
    difficulty: string;
    /** 分类 */
    category: string;
    /** 适用症候 */
    applicableSyndromes?: string[];
    /** 核心一句话（V6.0新增，TE系列专用） */
    coreIdea?: string;
    /** 简述 */
    description: string;
    /** 教学逻辑（V6.0新增，TE系列的核心附加值——原作者是怎么教的） */
    teachingLogic?: string;
    /** 原文示例 */
    example: string;
    /** 练习建议 */
    exercise?: string;
    /** 核心模式标识（V6.0新增） */
    coreId?: string;
    /** 核心模式名称（V6.0新增） */
    coreName?: string;
    /** 难度顺序：1=beginner, 2=intermediate, 3=advanced（V6.0新增） */
    difficultyOrder?: number;
    /** 适用范围：通用/奇幻玄幻/推理悬疑等（V6.0新增） */
    genreScope?: string | string[];
}
/** 作品（manuscripts 表行映射） */
export interface Manuscript {
    id: string;
    title: string;
    description: string;
    genre: string;
    status: 'active' | 'archived';
    created_at: number;
    updated_at: number;
    sort_order: number;
}
/** 章节（chapters 表行映射） */
export interface Chapter {
    id: string;
    manuscript_id: string;
    title: string;
    content: string;
    word_count: number;
    sort_order: number;
    status: 'draft' | 'revising' | 'complete';
    created_at: number;
    updated_at: number;
}
/** 会话元数据（含 preview） */
export interface SessionMeta {
    id: string;
    title: string;
    preview: string;
    createdAt: string;
    updatedAt: string;
}
/** 训练记录（数据库行格式） */
export interface TrainingRecord {
    /** 记录 ID */
    id: string;
    /** 会话 ID */
    sessionId: string;
    /** 挑战 ID（challengeId） */
    taskId: string;
    /** 症候 ID */
    syndromeId: string;
    /** 用户响应 */
    userResponse: string;
    /** 状态（assigned/in_progress/completed/skipped） */
    status: string;
    /** 有效性评分（0-1） */
    effectiveness: number;
    /** AI 评估反馈 */
    aiFeedback: string;
    /** 分配时间 */
    assignedAt: string;
    /** 完成时间 */
    completedAt?: string;
    /** Evaluator Agent 评分（1-10） */
    score?: number | null;
}
/** 评估结果（Evaluator Agent 输出） */
export interface EvaluationResult {
    /** 评分 1-10 */
    score: number;
    /** 文字反馈 */
    feedback: string;
    /** 是否相比原文有改善 */
    improved: boolean;
    /** 下一步建议 */
    nextStep: string;
}
/** 教学模式 */
export type TeachingMode = 'scaffolding' | 'guiding' | 'challenging';
/** 教学策略类型 */
export type TeachingStrategy = 'case-driven' | 'analysis-driven' | 'reflection-driven';
/** 第一层：聚焦症候决策 */
export interface FocusDecision {
    /** 本次聚焦的症候 ID */
    targetSyndrome: string;
    /** 症候中文名 */
    targetSyndromeName: string;
    /** 为什么选这个 */
    rationale: string;
    /** 教育理论依据 */
    theoryReference: string[];
    /** 备选症候（非本次但不忽略） */
    alternativeSyndromes: string[];
}
/** 第二层：教学模式决策 */
export interface ModeDecision {
    /** 教学模式 */
    teachingMode: TeachingMode;
    /** 教学策略 */
    strategy: TeachingStrategy;
    /** 症候类型（expressive_deficit / structural_disorder / motivation_deficit） */
    syndromeType: string;
    /** 推荐入口（来自 syndrome-type-map） */
    recommendedEntry: string;
    /** 教育理论依据 */
    theoryReference: string[];
}
export interface ParameterDecision {
    /** 当前学习路径阶段 ID */
    phaseId: string;
    /** 核心技法模式列表 */
    corePatterns: string[];
    /** 步骤序列 */
    stepSequence: Array<{
        stepId: string;
        stepName: string;
        coachingTemplateRef: string;
        toneProfile: string;
    }>;
    /** 匹配的教练话术模板 ID（T-036 新增） */
    matchedTemplateId?: string;
    /** 练习类型 */
    practiceType: string;
}
/**
 * Persona 配置（PE-001 结构化，替换 attitude 硬编码）
 *
 * 定义 AI 教练的人格化特征，包括语气、挑战强度、知识范围等。
 */
export interface PersonaConfig {
    id: 'doubao' | 'yuesheng' | 'direct';
    label: string;
    tone: string;
    challengeSize: 'micro' | 'medium' | 'full';
    knowledgeScope: string;
    responseStyle: string;
}
/** Persona 预设映射 */
export declare const PERSONA_PRESETS: Record<string, PersonaConfig>;
/** Router 输入 */
export interface RouterInput {
    /** 用户 ID */
    userId: string;
    /** 用户水平 */
    userLevel: 'beginner' | 'intermediate' | 'advanced';
    /** 认知风格（来自学生模型） */
    cognitiveStyle?: string;
    /** 挫折指数（0-1） */
    frustrationIndex: number;
    /** 最频繁症候出现次数 */
    topSyndromeCount: number;
    /** 活跃症候列表 */
    activeSyndromes: Array<{
        id: string;
        severity: number;
        name: string;
    }>;
    /** 训练历史 */
    trainingHistory: Array<{
        syndromeId: string;
        score: number;
        completed: boolean;
    }>;
    /** 当前教学阶段（来自状态机） */
    currentPhase?: string;
    /** 用户态度档位 */
    attitude?: 'doubao' | 'yuesheng' | 'direct';
    /** Persona 配置（PE-001，若提供则优先使用） */
    persona?: PersonaConfig;
    /** 训练动机水平（用于 R-007 规则匹配） */
    trainingMotivation?: 'low' | 'normal' | 'high';
    /** 训练跳过率 0-1（用于 R-007 规则匹配） */
    trainingSkipRate?: number;
    /** 各症候出现次数映射（用于 R-009/R-010/R-014 规则匹配） */
    syndromeCountMap?: Record<string, number>;
    /** 处理中的教育规则 ID 列表（外部注入，用于条件匹配） */
    activeRuleIds?: string[];
}
/** Router 输出 */
export interface RouterOutput {
    /** 聚焦症候决策 */
    targetSyndrome: FocusDecision;
    /** 教学模式决策 */
    teachingMode: ModeDecision;
    /** 参数细化决策 */
    parameters: ParameterDecision;
    /** 向后兼容字段 */
    compatibleWithLegacy: {
        mode: TeachingMode;
        tone: string;
        format?: string;
    };
}
