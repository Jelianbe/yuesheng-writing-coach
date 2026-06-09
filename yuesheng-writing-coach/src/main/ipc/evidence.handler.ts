import { IPC_CHANNELS } from '../../shared/constants';
import { EvidenceRecord } from '../../renderer/shared/types';
import { EvidenceService } from '../services/evidence.service';
import { createHandler } from './utils/create-handler';
import { validatePayload } from './utils/validate-payload';

export interface EvidenceHandlerDeps {
  evidenceService: EvidenceService;
}

let deps: EvidenceHandlerDeps | null = null;

export function initEvidenceHandlers(d: EvidenceHandlerDeps): void {
  deps = d;
}

export function registerEvidenceHandlers(): void {
  if (!deps) throw new Error('EvidenceHandler deps not injected');

  createHandler<{ diseaseId: string; novelId: string; minLevel?: number }, ReturnType<EvidenceService['getByDisease']>>(
    IPC_CHANNELS.EVIDENCE_GET_BY_DISEASE,
    (_event, args) => {
      const validation = validatePayload<{ diseaseId: string; novelId: string; minLevel?: number }>(args, { required: ['diseaseId', 'novelId'], types: { diseaseId: 'string', novelId: 'string', minLevel: 'number' } });
      if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
      return deps!.evidenceService.getByDisease(validation.data.diseaseId, validation.data.novelId, validation.data.minLevel);
    },
  );

  createHandler<{ abilityId: string; authorId: string; fromDate?: string; toDate?: string }, ReturnType<EvidenceService['getByAbility']>>(
    IPC_CHANNELS.EVIDENCE_GET_BY_ABILITY,
    (_event, args) => {
      const validation = validatePayload<{ abilityId: string; authorId: string; fromDate?: string; toDate?: string }>(args, { required: ['abilityId', 'authorId'], types: { abilityId: 'string', authorId: 'string', fromDate: 'string', toDate: 'string' } });
      if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
      return deps!.evidenceService.getByAbility(validation.data.abilityId, validation.data.authorId, validation.data.fromDate, validation.data.toDate);
    },
  );

  createHandler<{ diagnosisId: string }, ReturnType<EvidenceService['getChainForDiagnosis']>>(
    IPC_CHANNELS.EVIDENCE_GET_CHAIN,
    (_event, args) => {
      const validation = validatePayload<{ diagnosisId: string }>(args, { required: ['diagnosisId'], types: { diagnosisId: 'string' } });
      if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
      return deps!.evidenceService.getChainForDiagnosis(validation.data.diagnosisId);
    },
  );

  createHandler<{ evidence: { type: string; level: number; novelId: string; contentJson: string | object; relatedDisease?: string; relatedAbility?: string; extractedBy: string } }, { evidenceId: string }>(
    IPC_CHANNELS.EVIDENCE_CREATE,
    (_event, args) => {
      const validation = validatePayload<{ evidence: Record<string, unknown> }>(args, { required: ['evidence'], types: { evidence: 'object' } });
      if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
      const record: EvidenceRecord = {
        evidenceId: `EVD-${String(Date.now()).padStart(6, '0')}`,
        type: args.evidence.type as EvidenceRecord['type'],
        level: args.evidence.level as EvidenceRecord['level'],
        novelId: args.evidence.novelId,
        contentJson: typeof args.evidence.contentJson === 'string'
          ? args.evidence.contentJson
          : JSON.stringify(args.evidence.contentJson),
        relatedDisease: args.evidence.relatedDisease ?? '',
        relatedAbility: args.evidence.relatedAbility ?? '',
        extractedBy: args.evidence.extractedBy,
        createdAt: new Date().toISOString(),
      };
      deps!.evidenceService.save(record);
      return { evidenceId: record.evidenceId };
    },
  );

  createHandler<{ syndromeId: string; sessionId: string }, ReturnType<EvidenceService['getBySyndrome']>>(
    IPC_CHANNELS.EVIDENCE_GET_BY_SYNDROME,
    (_event, args) => {
      const validation = validatePayload<{ syndromeId: string; sessionId: string }>(args, { required: ['syndromeId', 'sessionId'], types: { syndromeId: 'string', sessionId: 'string' } });
      if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
      return deps!.evidenceService.getBySyndrome(validation.data.syndromeId, validation.data.sessionId);
    },
  );
}
