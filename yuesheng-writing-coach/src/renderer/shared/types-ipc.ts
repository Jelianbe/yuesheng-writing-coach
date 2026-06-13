// IPC 类型系统
import type { ApiConfig, ConnectionTestResult, AttitudeLevel, ApiResponse } from './types-config';
import type { SyndromeId, RewriteEvaluation, EvidenceRecord, EvidenceChain } from './types-diagnosis';
import type { TeachingState, ActiveProblem } from './types-teaching';
import type { AbilityProfile } from './types-growth';
import type { Session, MessageRow, SessionMeta } from './types-chat';
import type { Manuscript, Chapter } from './types-manuscript';
import type { DiagnosisUpdateEvent } from '../../shared/api-contracts/diagnosis.contract';

/** IPC 通道字符串字面量类型 */
export type IPCChannel =
  | 'config:get' | 'config:set' | 'config:testConnection'
  | 'diagnosis:update' | 'diagnosis:query' | 'diagnosis:submitRewrite' | 'diagnosis:getComparison'
  | 'growth:getTrends' | 'growth:getGlobalTrends'
  | 'teachingState:get' | 'teachingState:update' | 'teachingState:confirm'
  | 'teachingState:getPrompt' | 'teachingState:updateSummary' | 'teachingState:updated'
  | 'ability:getProfile'
  | 'evidence:getByDisease' | 'evidence:getByAbility' | 'evidence:getChain' | 'evidence:create'
  | 'evidence:getBySyndrome'
  | 'training:recommend' | 'training:assign' | 'training:complete' | 'training:skip'
  | 'training:history' | 'training:submit' | 'training:evaluate' | 'training:deriveBehavior'
  | 'chat:send' | 'chat:stop' | 'chat:stream:data' | 'chat:stream:end'
  | 'session:list' | 'session:create' | 'session:delete' | 'session:rename' | 'session:getMessages'
  | 'session:getMessagesPaged' | 'session:listWithMeta' | 'session:updateTitle' | 'session:searchMessages' | 'session:isNewUser'
  | 'onboarding:analyze'
  | 'manuscript:list' | 'manuscript:get' | 'manuscript:create' | 'manuscript:update'
  | 'chapter:list' | 'chapter:get' | 'chapter:create' | 'chapter:delete' | 'chapter:updateContent'
  | 'manuscript:delete';

/** IPC 请求类型映射 */
export interface IPCRequestMap {
  'config:get': { key: keyof ApiConfig };
  'config:set': { key: keyof ApiConfig; value: ApiConfig[keyof ApiConfig] };
  'config:testConnection': { apiKey: string; baseUrl: string };
  'diagnosis:query': { sessionId: string };
  'diagnosis:submitRewrite': { sessionId: string; messageId: string; syndromeId: SyndromeId; originalText: string; rewrittenText: string; syndromeName?: string; syndromeDesc?: string };
  'diagnosis:getComparison': { sessionId: string };
  'growth:getTrends': { sessionId: string };
  'growth:getGlobalTrends': Record<string, never>;
  'teachingState:get': { sessionId: string };
  'teachingState:update': { sessionId: string; updates: Partial<Omit<TeachingState, 'sessionId' | 'updatedAt'>> };
  'teachingState:confirm': { sessionId: string };
  'teachingState:getPrompt': { sessionId: string };
  'teachingState:updateSummary': { sessionId: string; newContent: string };
  'ability:getProfile': { sessionId: string };
  'evidence:getByDisease': { diseaseId: string; novelId: string; minLevel?: number };
  'evidence:getByAbility': { abilityId: string; authorId: string; fromDate?: string; toDate?: string };
  'evidence:getChain': { diagnosisId: string };
  'evidence:create': { evidence: EvidenceRecord };
  'evidence:getBySyndrome': { syndromeId: string; sessionId: string };
  'chat:send': { message: string; sessionId: string; history?: { role: string; content: string }[]; attitudeLevel?: AttitudeLevel };
  'chat:stop': { sessionId: string };
  'session:list': Record<string, never>;
  'session:create': Record<string, never>;
  'session:delete': { sessionId: string };
  'session:rename': { sessionId: string; title: string };
  'session:getMessages': { sessionId: string };
  'session:getMessagesPaged': { sessionId: string; offset: number; limit: number };
  'session:listWithMeta': { limit?: number; offset?: number };
  'session:updateTitle': { id: string; title: string };
  'session:isNewUser': Record<string, never>;
  'manuscript:list': Record<string, never>;
  'manuscript:get': { id: string };
  'manuscript:create': { title: string; description?: string; genre?: string };
  'manuscript:update': { id: string; title?: string; description?: string; genre?: string; status?: 'active' | 'archived' };
  'chapter:list': { manuscriptId: string };
  'chapter:get': { id: string };
  'chapter:create': { manuscriptId: string; title: string };
  'chapter:delete': { id: string };
  'chapter:updateContent': { id: string; content: string };
  'manuscript:delete': { id: string };
}

/** IPC 响应类型映射（ER5：全部统一为 ApiResponse<T>） */
export interface IPCResponseMap {
  'config:get': ApiResponse<ApiConfig[keyof ApiConfig]>;
  'config:set': ApiResponse<void>;
  'config:testConnection': ApiResponse<ConnectionTestResult>;
  'diagnosis:query': ApiResponse<ActiveProblem[] | null>;
  'diagnosis:submitRewrite': ApiResponse<{ evaluation: RewriteEvaluation } | void>;
  'diagnosis:getComparison': ApiResponse<{ hasHistory: boolean; comparison?: string }>;
  'teachingState:get': ApiResponse<TeachingState & { phaseName: string; subphaseName: string; phaseProgress: number }>;
  'teachingState:update': ApiResponse<TeachingState>;
  'teachingState:confirm': ApiResponse<{ oldState: TeachingState; newState: TeachingState }>;
  'teachingState:getPrompt': ApiResponse<string>;
  'teachingState:updateSummary': ApiResponse<TeachingState>;
  'ability:getProfile': ApiResponse<AbilityProfile | null>;
  'evidence:getByDisease': ApiResponse<EvidenceRecord[]>;
  'evidence:getByAbility': ApiResponse<EvidenceRecord[]>;
  'evidence:getChain': ApiResponse<EvidenceChain | null>;
  'evidence:create': ApiResponse<{ evidenceId: string }>;
  'evidence:getBySyndrome': ApiResponse<EvidenceRecord[]>;
  'chat:send': ApiResponse<{ messageId: string }>;
  'chat:stop': ApiResponse<void>;
  'session:list': ApiResponse<Session[]>;
  'session:create': ApiResponse<Session>;
  'session:delete': ApiResponse<void>;
  'session:rename': ApiResponse<void>;
  'session:getMessages': ApiResponse<MessageRow[]>;
  'session:getMessagesPaged': ApiResponse<{ messages: MessageRow[]; total: number; hasMore: boolean }>;
  'session:listWithMeta': ApiResponse<SessionMeta[]>;
  'session:updateTitle': ApiResponse<void>;
  'session:isNewUser': ApiResponse<boolean>;
  'session:searchMessages': ApiResponse<{ messages: MessageRow[]; total: number }>;
  'onboarding:analyze': ApiResponse<{ summary: string }>;
  'training:recommend': ApiResponse<unknown>;
  'training:assign': ApiResponse<unknown>;
  'training:complete': ApiResponse<unknown>;
  'training:skip': ApiResponse<unknown>;
  'training:history': ApiResponse<unknown>;
  'training:submit': ApiResponse<unknown>;
  'training:evaluate': ApiResponse<unknown>;
  'training:deriveBehavior': ApiResponse<unknown>;
  'manuscript:list': ApiResponse<Manuscript[]>;
  'manuscript:get': ApiResponse<Manuscript | null>;
  'manuscript:create': ApiResponse<Manuscript>;
  'manuscript:update': ApiResponse<Manuscript>;
  'chapter:list': ApiResponse<Chapter[]>;
  'chapter:get': ApiResponse<Chapter | null>;
  'chapter:create': ApiResponse<Chapter>;
  'chapter:delete': ApiResponse<{ deleted: boolean }>;
  'chapter:updateContent': ApiResponse<{ wordCount: number }>;
  'manuscript:delete': ApiResponse<{ deleted: boolean }>;
}

/** IPC 事件推送类型映射 */
export interface IPCEventMap {
  'diagnosis:update': DiagnosisUpdateEvent;
  'teachingState:updated': TeachingState & { phaseName: string; subphaseName: string; phaseProgress: number };
  'chat:stream:data': { sessionId: string; chunk: string };
  'chat:stream:end': { sessionId: string; fullResponse: string; messageId: string; error?: string };
}
