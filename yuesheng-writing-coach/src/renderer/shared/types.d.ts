/** 态度档位类型 */
export type AttitudeLevel = 'doubao' | 'yuesheng';
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
 * 所有 handler 统一使用此格式返回
 */
export interface ApiResponse<T = unknown> {
  /** 操作是否成功 */
  success: boolean;
  /** 成功时返回的数据 */
  data?: T;
  /** 失败时的错误信息 */
  error?: string;
}

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
/** 病症 ID（运行时常量见 constants.js） */
export type SyndromeId = string;
/** 教学动作 ID（运行时常量见 constants.js） */
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
    /** 病症 ID */
    id: SyndromeId;
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
/** IPC 通道字符串字面量类型 */
export type IPCChannel = string;
/** 教学阶段（运行时常量见 constants.js） */
export type TeachingPhase = string;
/** 教学子阶段（运行时常量见 constants.js） */
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
/** IPC 请求类型映射（invoke 通道 → 请求参数类型） */
export interface IPCRequestMap {
    [IPC_CHANNELS.CONFIG_GET]: {
        key: keyof ApiConfig;
    };
    [IPC_CHANNELS.CONFIG_SET]: {
        key: keyof ApiConfig;
        value: ApiConfig[keyof ApiConfig];
    };
    [IPC_CHANNELS.CONFIG_TEST_CONNECTION]: {
        apiKey: string;
        baseUrl: string;
    };
    [IPC_CHANNELS.DIAGNOSIS_QUERY]: {
        sessionId: string;
    };
    [IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE]: {
        sessionId: string;
        messageId: string;
        syndromeId: SyndromeId;
        originalText: string;
        rewrittenText: string;
        syndromeName?: string;
        syndromeDesc?: string;
    };
    [IPC_CHANNELS.DIAGNOSIS_GET_COMPARISON]: {
        sessionId: string;
    };
    [IPC_CHANNELS.TEACHING_STATE_GET]: {
        sessionId: string;
    };
    [IPC_CHANNELS.TEACHING_STATE_UPDATE]: {
        sessionId: string;
        updates: Partial<Omit<TeachingState, 'sessionId' | 'updatedAt'>>;
    };
    [IPC_CHANNELS.TEACHING_STATE_CONFIRM]: {
        sessionId: string;
    };
    [IPC_CHANNELS.TEACHING_STATE_GET_PROMPT]: {
        sessionId: string;
    };
    [IPC_CHANNELS.TEACHING_STATE_UPDATE_SUMMARY]: {
        sessionId: string;
        newContent: string;
    };
    [IPC_CHANNELS.ABILITY_GET_PROFILE]: {
        sessionId: string;
    };
    [IPC_CHANNELS.EVIDENCE_GET_BY_DISEASE]: {
        diseaseId: string;
        novelId: string;
        minLevel?: number;
    };
    [IPC_CHANNELS.EVIDENCE_GET_BY_ABILITY]: {
        abilityId: string;
        authorId: string;
        fromDate?: string;
        toDate?: string;
    };
    [IPC_CHANNELS.EVIDENCE_GET_CHAIN]: {
        diagnosisId: string;
    };
    [IPC_CHANNELS.EVIDENCE_CREATE]: {
        evidence: EvidenceRecord;
    };
    [IPC_CHANNELS.CHAT_SEND]: {
        message: string;
        sessionId: string;
        history?: {
            role: string;
            content: string;
        }[];
        attitudeLevel?: AttitudeLevel;
        studentContext?: string;
    };
    [IPC_CHANNELS.SESSION_LIST]: Record<string, never>;
    [IPC_CHANNELS.SESSION_CREATE]: Record<string, never>;
    [IPC_CHANNELS.SESSION_DELETE]: {
        sessionId: string;
    };
    [IPC_CHANNELS.SESSION_RENAME]: {
        sessionId: string;
        title: string;
    };
    [IPC_CHANNELS.SESSION_GET_MESSAGES]: {
        sessionId: string;
    };
}
/** IPC 响应类型映射（invoke 通道 → 响应类型） */
export interface IPCResponseMap {
    [IPC_CHANNELS.CONFIG_GET]: ApiConfig[keyof ApiConfig];
    [IPC_CHANNELS.CONFIG_SET]: void;
    [IPC_CHANNELS.CONFIG_TEST_CONNECTION]: ConnectionTestResult;
    [IPC_CHANNELS.DIAGNOSIS_QUERY]: ActiveProblem[] | null;
    [IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE]: {
        success: boolean;
        evaluation?: RewriteEvaluation;
        error?: string;
    };
    [IPC_CHANNELS.DIAGNOSIS_GET_COMPARISON]: {
        hasHistory: boolean;
        comparison?: string;
    };
    [IPC_CHANNELS.TEACHING_STATE_GET]: TeachingState & {
        phaseName: string;
        subphaseName: string;
        phaseProgress: number;
    };
    [IPC_CHANNELS.TEACHING_STATE_UPDATE]: TeachingState | null;
    [IPC_CHANNELS.TEACHING_STATE_CONFIRM]: {
        oldState: TeachingState;
        newState: TeachingState;
    } | null;
    [IPC_CHANNELS.TEACHING_STATE_GET_PROMPT]: string;
    [IPC_CHANNELS.TEACHING_STATE_UPDATE_SUMMARY]: TeachingState | null;
    [IPC_CHANNELS.ABILITY_GET_PROFILE]: AbilityProfile | null;
    [IPC_CHANNELS.EVIDENCE_GET_BY_DISEASE]: EvidenceRecord[];
    [IPC_CHANNELS.EVIDENCE_GET_BY_ABILITY]: EvidenceRecord[];
    [IPC_CHANNELS.EVIDENCE_GET_CHAIN]: EvidenceChain | null;
    [IPC_CHANNELS.EVIDENCE_CREATE]: {
        success: boolean;
        evidenceId?: string;
        error?: string;
    };
    [IPC_CHANNELS.CHAT_SEND]: {
        success: boolean;
        messageId?: string;
        error?: string;
    };
    [IPC_CHANNELS.SESSION_LIST]: Session[];
    [IPC_CHANNELS.SESSION_CREATE]: Session;
    [IPC_CHANNELS.SESSION_DELETE]: void;
    [IPC_CHANNELS.SESSION_RENAME]: void;
    [IPC_CHANNELS.SESSION_GET_MESSAGES]: MessageRow[];
}
/** IPC 事件推送类型映射（事件通道 → 推送数据类型） */
export interface IPCEventMap {
    [IPC_CHANNELS.DIAGNOSIS_UPDATE]: DiagnosisEntry;
    [IPC_CHANNELS.TEACHING_STATE_UPDATED]: TeachingState & {
        phaseName: string;
        subphaseName: string;
        phaseProgress: number;
    };
    [IPC_CHANNELS.CHAT_STREAM_DATA]: {
        sessionId: string;
        chunk: string;
    };
    [IPC_CHANNELS.CHAT_STREAM_END]: {
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
}
/** 诊断 Agent 的结构化输出 */
export interface DiagnosisAnalysis {
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
}
