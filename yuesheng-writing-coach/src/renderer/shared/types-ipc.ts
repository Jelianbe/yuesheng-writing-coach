// IPC 类型系统
import type { ApiConfig, ConnectionTestResult, AttitudeLevel, ApiResponse } from './types-config';
import type { SyndromeId, DiagnosisEntry, RewriteEvaluation, EvidenceRecord, EvidenceChain } from './types-diagnosis';
import type { TeachingState, ActiveProblem } from './types-teaching';
import type { AbilityProfile } from './types-growth';
import type { Session, MessageRow, SessionMeta } from './types-chat';
import type { Manuscript, Chapter } from './types-manuscript';

/** IPC 通道字符串字面量类型 */
export type IPCChannel =
  | 'config:get' | 'config:set' | 'config:testConnection'
  | 'diagnosis:update' | 'diagnosis:query' | 'diagnosis:submitRewrite' | 'diagnosis:getComparison'
  | 'teachingState:get' | 'teachingState:update' | 'teachingState:confirm'
  | 'teachingState:getPrompt' | 'teachingState:updateSummary' | 'teachingState:updated'
  | 'ability:getProfile'
  | 'evidence:getByDisease' | 'evidence:getByAbility' | 'evidence:getChain' | 'evidence:create'
  | 'chat:send' | 'chat:stream:data' | 'chat:stream:end'
  | 'session:list' | 'session:create' | 'session:delete' | 'session:rename' | 'session:getMessages'
  | 'session:getMessagesPaged' | 'session:listWithMeta' | 'session:updateTitle' | 'session:isNewUser'
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
  'chat:send': { message: string; sessionId: string; history?: { role: string; content: string }[]; attitudeLevel?: AttitudeLevel };
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
  'chat:send': ApiResponse<{ messageId: string }>;
  'session:list': ApiResponse<Session[]>;
  'session:create': ApiResponse<Session>;
  'session:delete': ApiResponse<void>;
  'session:rename': ApiResponse<void>;
  'session:getMessages': ApiResponse<MessageRow[]>;
  'session:getMessagesPaged': ApiResponse<{ messages: MessageRow[]; total: number; hasMore: boolean }>;
  'session:listWithMeta': ApiResponse<SessionMeta[]>;
  'session:updateTitle': ApiResponse<void>;
  'session:isNewUser': ApiResponse<boolean>;
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
  'diagnosis:update': DiagnosisEntry;
  'teachingState:updated': TeachingState & { phaseName: string; subphaseName: string; phaseProgress: number };
  'chat:stream:data': { sessionId: string; chunk: string };
  'chat:stream:end': { sessionId: string; fullResponse: string; messageId: string; error?: string };
}
