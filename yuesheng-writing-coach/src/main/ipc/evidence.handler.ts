import { IPC_CHANNELS } from '../../shared/constants';
import { EvidenceRecord, apiSuccess, apiError } from '../../renderer/shared/types';
import { EvidenceService } from '../services/evidence.service';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';

export interface EvidenceHandlerDeps {
  evidenceService: EvidenceService;
}

let deps: EvidenceHandlerDeps | null = null;

export function initEvidenceHandlers(d: EvidenceHandlerDeps): void {
  deps = d;
}

export function registerEvidenceHandlers(): void {
  if (!deps) throw new Error('EvidenceHandler deps not injected');

  createHandler(IPC_CHANNELS.EVIDENCE_GET_BY_DISEASE, (_event, args) => {
    try {
      const validation = validatePayload<{ diseaseId: string; novelId: string; minLevel?: number }>(args, { required: ['diseaseId', 'novelId'], types: { diseaseId: 'string', novelId: 'string', minLevel: 'number' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      return apiSuccess(deps!.evidenceService.getByDisease(validation.data.diseaseId, validation.data.novelId, validation.data.minLevel));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_BY_DISEASE Error:', error);
      return apiError(String(error));
    }
  });

  createHandler(IPC_CHANNELS.EVIDENCE_GET_BY_ABILITY, (_event, args) => {
    try {
      const validation = validatePayload<{ abilityId: string; authorId: string; fromDate?: string; toDate?: string }>(args, { required: ['abilityId', 'authorId'], types: { abilityId: 'string', authorId: 'string', fromDate: 'string', toDate: 'string' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      return apiSuccess(deps!.evidenceService.getByAbility(validation.data.abilityId, validation.data.authorId, validation.data.fromDate, validation.data.toDate));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_BY_ABILITY Error:', error);
      return apiError(String(error));
    }
  });

  createHandler(IPC_CHANNELS.EVIDENCE_GET_CHAIN, (_event, args) => {
    try {
      const validation = validatePayload<{ diagnosisId: string }>(args, { required: ['diagnosisId'], types: { diagnosisId: 'string' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      return apiSuccess(deps!.evidenceService.getChainForDiagnosis(validation.data.diagnosisId));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_CHAIN Error:', error);
      return apiError(String(error));
    }
  });

  createHandler(IPC_CHANNELS.EVIDENCE_CREATE, (_event, args) => {
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
      deps!.evidenceService.save(record);
      return apiSuccess({ evidenceId: record.evidenceId });
    } catch (error) {
      return apiError(String(error));
    }
  });

  createHandler(IPC_CHANNELS.EVIDENCE_GET_BY_SYNDROME, (_event, args) => {
    try {
      const validation = validatePayload<{ syndromeId: string; sessionId: string }>(args, { required: ['syndromeId', 'sessionId'], types: { syndromeId: 'string', sessionId: 'string' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      return apiSuccess(deps!.evidenceService.getBySyndrome(validation.data.syndromeId, validation.data.sessionId));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_BY_SYNDROME Error:', error);
      return apiError(String(error));
    }
  });
}
