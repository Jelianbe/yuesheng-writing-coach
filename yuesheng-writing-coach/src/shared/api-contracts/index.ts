// ─── API Contracts 统一导出 ───

// 基础类型
export type { ApiSuccess, ApiError, ApiResponse, ApiEndpoint, ApiEvent } from './base';

// 聊天域
export type {
  ChatSendRequest, ChatStopRequest,
  ChatSendResponse, ChatStopResponse,
  ChatStreamDataEvent, ChatStreamEndEvent, ChatToolExecutingEvent,
} from './chat.contract';
export { ChatApi } from './chat.contract';
export type { ChatInvokeChannels, ChatEventChannels } from './chat.contract';

// 诊断域
export type {
  SeverityLevel, SyndromeResult, DiagnosisEntry,
  DiagnosisUpdateRequest, DiagnosisQueryRequest,
  DiagnosisSubmitRewriteRequest, DiagnosisGetComparisonRequest,
  DiagnosisUpdateResponse, DiagnosisQueryResponse,
  DiagnosisRewriteEvaluation, DiagnosisComparisonResult,
  DiagnosisUpdateEvent,
} from './diagnosis.contract';
export { DiagnosisApi } from './diagnosis.contract';
export type { DiagnosisInvokeChannels, DiagnosisEventChannels } from './diagnosis.contract';

// 教学状态域
export type {
  TeachingState,
  TeachingStateGetRequest, TeachingStateUpdateRequest,
  TeachingStateConfirmRequest, TeachingStateGetPromptRequest,
  TeachingStateUpdateSummaryRequest,
  TeachingStateGetResponse, TeachingStateConfirmResponse,
  TeachingStateGetPromptResponse,
  TeachingStateUpdatedEvent,
} from './teaching-state.contract';
export { TeachingStateApi } from './teaching-state.contract';
export type { TeachingStateInvokeChannels, TeachingStateEventChannels } from './teaching-state.contract';

// 训练域
export type {
  TrainingRecommendRequest, TrainingAssignRequest,
  TrainingCompleteRequest, TrainingSkipRequest,
  TrainingHistoryRequest, TrainingSubmitRequest,
  TrainingEvaluateRequest, TrainingDeriveBehaviorRequest,
  TrainingRecommendResponse, TrainingAssignResponse,
  TrainingCompleteResponse, TrainingHistoryResponse,
  TrainingSubmitResponse, TrainingEvaluateResponse,
  TrainingDeriveBehaviorResponse,
} from './training.contract';
export { TrainingApi } from './training.contract';
export type { TrainingInvokeChannels } from './training.contract';

// 会话域
export type {
  SessionInfo, SessionMessage,
  SessionListRequest, SessionCreateRequest, SessionDeleteRequest,
  SessionRenameRequest, SessionGetMessagesRequest,
  SessionGetMessagesPagedRequest, SessionListWithMetaRequest,
  SessionUpdateTitleRequest, SessionSearchMessagesRequest,
  SessionIsNewUserRequest,
  SessionListResponse, SessionCreateResponse,
  SessionGetMessagesResponse, SessionGetMessagesPagedResponse,
  SessionListWithMetaResponse, SessionUpdateTitleResponse,
  SessionSearchMessagesResponse, SessionIsNewUserResponse,
} from './session.contract';
export { SessionApi } from './session.contract';
export type { SessionInvokeChannels } from './session.contract';

// 配置域
export type {
  ConfigGetRequest, ConfigSetRequest, ConfigTestConnectionRequest,
  ConfigGetResponse, ConfigSetResponse, ConfigTestConnectionResponse,
} from './config.contract';
export { ConfigApi } from './config.contract';
export type { ConfigInvokeChannels } from './config.contract';

// 证据域
export type {
  EvidenceRecord,
  EvidenceGetBySyndromeRequest, EvidenceGetByDiseaseRequest,
  EvidenceGetByAbilityRequest, EvidenceGetChainRequest,
  EvidenceCreateRequest,
  EvidenceGetResponse, EvidenceGetChainResponse, EvidenceCreateResponse,
} from './evidence.contract';
export { EvidenceApi } from './evidence.contract';
export type { EvidenceInvokeChannels } from './evidence.contract';

// 作品域
export type {
  ManuscriptInfo, ChapterInfo,
  ManuscriptListRequest, ManuscriptGetRequest,
  ManuscriptCreateRequest, ManuscriptUpdateRequest,
  ManuscriptDeleteRequest,
  ChapterListRequest, ChapterGetRequest,
  ChapterCreateRequest, ChapterDeleteRequest,
  ChapterUpdateContentRequest,
  ManuscriptListResponse, ManuscriptGetResponse,
  ManuscriptCreateResponse, ChapterListResponse,
  ChapterGetResponse, ChapterCreateResponse,
  ChapterUpdateContentResponse,
} from './manuscript.contract';
export { ManuscriptApi, ChapterApi } from './manuscript.contract';
export type { ManuscriptInvokeChannels, ChapterInvokeChannels } from './manuscript.contract';

// 能力画像域
export type {
  SyndromesAbility, AbilityProfile,
  AbilityGetProfileRequest, AbilityGetProfileResponse,
} from './ability.contract';
export { AbilityApi } from './ability.contract';
export type { AbilityInvokeChannels } from './ability.contract';

// 成长域
export type {
  GrowthTrendPoint, GrowthTrend,
  GrowthGetTrendsRequest, GrowthGetGlobalTrendsRequest,
  GrowthGetTrendsResponse, GrowthGetGlobalTrendsResponse,
} from './growth.contract';
export { GrowthApi } from './growth.contract';
export type { GrowthInvokeChannels } from './growth.contract';

// 新用户引导域
export type {
  OnboardingAnalyzeRequest, OnboardingAnalyzeResponse,
} from './onboarding.contract';
export { OnboardingApi } from './onboarding.contract';
export type { OnboardingInvokeChannels } from './onboarding.contract';

// 事件通道映射
export type {
  EventChannelMap, EventChannel, EventPayload,
} from './event-map';
