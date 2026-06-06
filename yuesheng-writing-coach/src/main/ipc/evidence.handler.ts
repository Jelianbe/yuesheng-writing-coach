import { ipcMain } from 'electron';
import { IPC_CHANNELS } from '../../shared/constants';
import { EvidenceRecord, apiSuccess, apiError } from '../../renderer/shared/types';
import { EvidenceService } from '../services/evidence.service';

let service: EvidenceService | null = null;

export function setEvidenceService(s: EvidenceService): void {
  service = s;
}

export function registerEvidenceHandlers(): void {
  ipcMain.handle(IPC_CHANNELS.EVIDENCE_GET_BY_DISEASE, (_event, args: { diseaseId: string; novelId: string; minLevel?: number }) => {
    try {
      if (!service) return apiError('EvidenceService not initialized');
      return apiSuccess(service.getByDisease(args.diseaseId, args.novelId, args.minLevel));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_BY_DISEASE Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.EVIDENCE_GET_BY_ABILITY, (_event, args: { abilityId: string; authorId: string; fromDate?: string; toDate?: string }) => {
    try {
      if (!service) return apiError('EvidenceService not initialized');
      return apiSuccess(service.getByAbility(args.abilityId, args.authorId, args.fromDate, args.toDate));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_BY_ABILITY Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.EVIDENCE_GET_CHAIN, (_event, args: { diagnosisId: string }) => {
    try {
      if (!service) return apiError('EvidenceService not initialized');
      return apiSuccess(service.getChainForDiagnosis(args.diagnosisId));
    } catch (error) {
      console.error('[EvidenceHandler] EVIDENCE_GET_CHAIN Error:', error);
      return apiError(String(error));
    }
  });

  ipcMain.handle(IPC_CHANNELS.EVIDENCE_CREATE, (_event, args: { evidence: { type: string; level: number; novelId: string; contentJson: string | object; relatedDisease?: string; relatedAbility?: string; extractedBy: string } }) => {
    if (!service) return apiError('EvidenceService not initialized');
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
      service.save(record);
      return apiSuccess({ evidenceId: record.evidenceId });
    } catch (error) {
      return apiError(String(error));
    }
  });
}
