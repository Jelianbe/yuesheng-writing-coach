import { ipcMain } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { EvidenceRecord, apiSuccess, apiError } from '../../renderer/shared/types';
import { EvidenceService } from '../services/evidence.service';

export interface EvidenceHandlerDeps {
  evidenceService: EvidenceService;
}

let deps: EvidenceHandlerDeps | null = null;

export function initEvidenceHandlers(d: EvidenceHandlerDeps): void {
  deps = d;
}

export function registerEvidenceHandlers(): void {
  if (!deps) throw new Error('EvidenceHandler deps not injected');

  ipcMain.handle(IPC_CHANNELS.EVIDENCE_GET_BY_DISEASE, (_event, args: { diseaseId: string; novelId: string; minLevel?: number }) => {
    try {
      return apiSuccess(deps!.evidenceService.getByDisease(args.diseaseId, args.novelId, args.minLevel));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_BY_DISEASE Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.EVIDENCE_GET_BY_ABILITY, (_event, args: { abilityId: string; authorId: string; fromDate?: string; toDate?: string }) => {
    try {
      return apiSuccess(deps!.evidenceService.getByAbility(args.abilityId, args.authorId, args.fromDate, args.toDate));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_BY_ABILITY Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.EVIDENCE_GET_CHAIN, (_event, args: { diagnosisId: string }) => {
    try {
      return apiSuccess(deps!.evidenceService.getChainForDiagnosis(args.diagnosisId));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_CHAIN Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.EVIDENCE_CREATE, (_event, args: { evidence: { type: string; level: number; novelId: string; contentJson: string | object; relatedDisease?: string; relatedAbility?: string; extractedBy: string } }) => {
    try {
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
      return apiSuccess({ evidenceId: record.evidenceId });
    } catch (error) {
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.EVIDENCE_GET_BY_SYNDROME, (_event, args: { syndromeId: string; sessionId: string }) => {
    try {
      return apiSuccess(deps!.evidenceService.getBySyndrome(args.syndromeId, args.sessionId));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_BY_SYNDROME Error:', error);
      return apiError(String(error));
    }
  });
}
