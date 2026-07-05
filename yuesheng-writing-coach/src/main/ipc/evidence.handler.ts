/**
 * 证据管理 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('evidence:getByDisease' | 'evidence:getByAbility' | 'evidence:getChain' | 'evidence:create' | 'evidence:getBySyndrome', ...)`
 *
 * 保留 validatePayload + apiSuccess/apiError 包装(短期内重写性价比低)
 */

import type { EvidenceRecord} from '../../shared/types/index';
import { apiSuccess, apiError } from '../../shared/types/index';
import type { EvidenceService } from '../domains/01-diagnosis/evidence/evidence.service';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';

export interface EvidenceHandlerDeps {
  evidenceService: EvidenceService;
}

let deps: EvidenceHandlerDeps | null = null;

export function initEvidenceHandlers(d: EvidenceHandlerDeps): void {
  deps = d;
}

export function registerEvidenceHandlers(): void {
  if (!deps) throw new Error('EvidenceHandler deps not injected');
  const d = deps;

  registerMethod('evidence:getByDisease', async (args) => {
    try {
      const validation = validatePayload<{ diseaseId: string; novelId: string; minLevel?: number }>(args, { required: ['diseaseId', 'novelId'], types: { diseaseId: 'string', novelId: 'string', minLevel: 'number' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      return apiSuccess(d.evidenceService.getByDisease(validation.data.diseaseId, validation.data.novelId, validation.data.minLevel));
    } catch (error) {
      console.error('[EvidenceHandler] evidence:getByDisease Error:', error);
      return apiError(String(error));
    }
  });

  registerMethod('evidence:getByAbility', async (args) => {
    try {
      const validation = validatePayload<{ abilityId: string; authorId: string; fromDate?: string; toDate?: string }>(args, { required: ['abilityId', 'authorId'], types: { abilityId: 'string', authorId: 'string', fromDate: 'string', toDate: 'string' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      return apiSuccess(d.evidenceService.getByAbility(validation.data.abilityId, validation.data.authorId, validation.data.fromDate, validation.data.toDate));
    } catch (error) {
      console.error('[EvidenceHandler] evidence:getByAbility Error:', error);
      return apiError(String(error));
    }
  });

  registerMethod('evidence:getChain', async (args) => {
    try {
      const validation = validatePayload<{ diagnosisId: string }>(args, { required: ['diagnosisId'], types: { diagnosisId: 'string' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      return apiSuccess(d.evidenceService.getChainForDiagnosis(validation.data.diagnosisId));
    } catch (error) {
      console.error('[EvidenceHandler] evidence:getChain Error:', error);
      return apiError(String(error));
    }
  });

  registerMethod('evidence:create', async (args) => {
    try {
      const validation = validatePayload<{ evidence: { type: string; level: number; novelId: string; contentJson: string | object; relatedDisease?: string; relatedAbility?: string; extractedBy: string } }>(args, { required: ['evidence'], types: { evidence: 'object' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      const ev = validation.data.evidence;
      const record: EvidenceRecord = {
        evidenceId: `EVD-${String(Date.now()).padStart(6, '0')}`,
        type: ev.type as EvidenceRecord['type'],
        level: ev.level as EvidenceRecord['level'],
        novelId: ev.novelId,
        contentJson: typeof ev.contentJson === 'string'
          ? ev.contentJson
          : JSON.stringify(ev.contentJson),
        relatedDisease: ev.relatedDisease ?? '',
        relatedAbility: ev.relatedAbility ?? '',
        extractedBy: ev.extractedBy,
        createdAt: new Date().toISOString(),
      };
      d.evidenceService.save(record);
      return apiSuccess({ evidenceId: record.evidenceId });
    } catch (error) {
      return apiError(String(error));
    }
  });

  registerMethod('evidence:getBySyndrome', async (args) => {
    try {
      const validation = validatePayload<{ syndromeId: string; sessionId: string }>(args, { required: ['syndromeId', 'sessionId'], types: { syndromeId: 'string', sessionId: 'string' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      return apiSuccess(d.evidenceService.getBySyndrome(validation.data.syndromeId, validation.data.sessionId));
    } catch (error) {
      console.error('[EvidenceHandler] evidence:getBySyndrome Error:', error);
      return apiError(String(error));
    }
  });
}
