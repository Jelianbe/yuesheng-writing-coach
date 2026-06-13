/**
 * 诊断领域入口
 *
 * 对外接口：IDiagnosisDomain — 供 ChatOrchestrator 等外部模块使用
 * 内部实现：DiagnosisService, EvidenceService 等
 */

import type { DiagnosisAnalysis, DiagnosisEntry } from '../../../renderer/shared/types';

export interface IDiagnosisDomain {
  save(data: {
    sessionId: string;
    messageId: string;
    syndromes: unknown[];
    suggestedActions: string[];
    confidence: number;
    timestamp: string;
  }): string;

  saveAnalysis(analysis: DiagnosisAnalysis, diagId: string): void;

  getRecentBySession(sessionId: string, limit: number): DiagnosisEntry[];

  /** 处理 AI 回复中的诊断数据（解析 → 持久化 → 证据 → 合并），不含 IPC 推送 */
  processAIResponse(fullResponse: string, sessionId: string, messageId: string): { diagnosisId: string; diagnosis: DiagnosisEntry } | undefined;
}

export { DiagnosisService } from './diagnosis.service';
export { DiagnosisMerger } from './diagnosis-merger';
export { parseDiagnosisFromAIResponse } from './diagnosis-parser';
export { severityToNumber, mergeSyndromesIntoState } from './diagnosis-merger-utils';
export { processAIResponse, type DiagnosisProcessorDeps } from './diagnosis-processor';
