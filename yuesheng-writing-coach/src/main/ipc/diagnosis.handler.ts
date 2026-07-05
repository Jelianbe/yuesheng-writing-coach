/**
 * 诊断 — Sprint 26 阶段 3.5 方案 4a bridge 注册
 *
 * 原 IPC handler 已废弃,改为 registerMethod 走单端点 bridge:invoke。
 * 调用方:`serviceBridge.invoke('diagnosis:query' | 'diagnosis:getComparison' | 'diagnosis:submitRewrite', ...)`
 *
 * 依赖: DiagnosisService, EvidenceService, SessionService, GrowthTrendService,
 *       TeachingStateService, DiagnosisMerger, ConfigService, mainWindow
 *
 * 保留 export 函数(外部调用):
 * - processDiagnosisFromAI: chat orchestrator 调用
 * - severityToNumber / mergeSyndromesIntoState: re-export 供 merger 使用
 *
 * Sprint 21 E-1: 载荷脱敏保留
 */

import type { BrowserWindow } from 'electron';
import type { DiagnosisService } from '../domains/01-diagnosis/diagnosis.service';
import type { EvidenceService } from '../domains/01-diagnosis/evidence/evidence.service';
import { IPC_CHANNELS, IMPROVEMENT_THRESHOLD } from '../../shared/constants';
import { wasDiagnosisPushed } from './utils/diagnosis-dedup';
import { validatePayload } from './utils/validate-payload';
import { registerMethod } from '../core/service-bridge';
import { ApiProxy } from '../api-proxy';
import type { ConfigService } from '../shared/services/config.service';
import type { SessionService } from '../../shared/services/session.service';
import type { DiagnosisMerger } from '../domains/01-diagnosis/diagnosis-merger';
import type { TeachingStateService } from '../domains/03-teaching/teaching-state.service';
import type { GrowthTrendService } from '../domains/02-prescription/student/growth-trend.service';
import { processAIResponse } from '../domains/01-diagnosis/diagnosis-processor';
import type { PayloadSanitizer } from '../core/payload-sanitizer.service';

export { severityToNumber, mergeSyndromesIntoState } from '../domains/01-diagnosis/diagnosis-merger-utils';

export interface DiagnosisHandlerDeps {
  configService: ConfigService;
  diagnosisService: DiagnosisService;
  evidenceService: EvidenceService;
  sessionService: SessionService;
  growthTrendService: GrowthTrendService;
  teachingStateService: TeachingStateService;
  diagnosisMerger: DiagnosisMerger;
  mainWindow: BrowserWindow | null;
}

let deps: DiagnosisHandlerDeps | null = null;
let sanitizerInstance: PayloadSanitizer | null = null;

export function initDiagnosisHandlers(d: DiagnosisHandlerDeps): void {
  deps = d;
}

export function setDiagnosisSanitizer(s: PayloadSanitizer): void {
  sanitizerInstance = s;
}

export function registerDiagnosisHandlers(): void {
  if (!deps) throw new Error('DiagnosisHandler deps not injected');
  const d = deps;

  registerMethod('diagnosis:query', async (args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const state = d.teachingStateService.getBySession(validation.data.sessionId);
    return sanitizerInstance?.sanitize('diagnosis', state?.activeProblems ?? null) ?? null;
  });

  registerMethod('diagnosis:getComparison', async (args) => {
    const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
    if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
    const recent = d.diagnosisService.getRecentBySession(validation.data.sessionId, 2);
    if (recent.length < 2) return { hasHistory: false };

    const prev = recent[0];
    const curr = recent[1];

    const parts: string[] = [];

    for (const currSyndrome of curr.syndromes) {
      const prevSyndrome = prev.syndromes.find(s => s.id === currSyndrome.id);
      if (!prevSyndrome) {
        parts.push(`${currSyndrome.name}是新出现的症候`);
        continue;
      }

      const prevScore = prevSyndrome.score ?? 0;
      const currScore = currSyndrome.score ?? 0;
      const diff = prevScore - currScore;

      if (diff > IMPROVEMENT_THRESHOLD) {
        parts.push(`${currSyndrome.name}从 ${prevScore.toFixed(0)} 分降到 ${currScore.toFixed(0)} 分，改善明显`);
      } else if (diff > 0) {
        parts.push(`${currSyndrome.name}略有改善（${prevScore.toFixed(0)}→${currScore.toFixed(0)}分）`);
      } else if (diff < -IMPROVEMENT_THRESHOLD) {
        parts.push(`${currSyndrome.name}加重了（${prevScore.toFixed(0)}→${currScore.toFixed(0)}分），建议加强练习`);
      } else if (diff < 0) {
        parts.push(`${currSyndrome.name}略有加重（${prevScore.toFixed(0)}→${currScore.toFixed(0)}分）`);
      } else {
        parts.push(`${currSyndrome.name}保持稳定`);
      }
    }

    for (const prevSyndrome of prev.syndromes) {
      const stillPresent = curr.syndromes.find(s => s.id === prevSyndrome.id);
      if (!stillPresent) {
        parts.push(`${prevSyndrome.name}已不在本次诊断中出现`);
      }
    }

    const comparison = parts.join('；');
    return { hasHistory: true, comparison };
  });

  registerMethod('diagnosis:submitRewrite', async (args) => {
    const { sessionId, syndromeId, originalText, rewrittenText, syndromeName, syndromeDesc } = args as {
      sessionId: string;
      messageId: string;
      syndromeId: string;
      originalText: string;
      rewrittenText: string;
      syndromeName?: string;
      syndromeDesc?: string;
    };
    d.sessionService.saveMessage(sessionId, 'system',
      `[修改原文] 症候: ${syndromeId}\n原文: "${originalText}"\n修改后: "${rewrittenText}"`);

    const config = d.configService.getConfig();
    if (config.apiKey) {
      const apiProxy = new ApiProxy(config);
      const evaluation = await apiProxy.evaluateRewrite({
        originalText,
        rewrittenText,
        syndromeName: syndromeName || syndromeId,
        syndromeDesc: syndromeDesc || '',
      });
      return { evaluation };
    }

    return undefined;
  });
}

export function processDiagnosisFromAI(
  fullResponse: string,
  sessionId: string,
  messageId: string,
): void {
  if (!deps) {
    console.error('[DiagnosisHandler] deps not initialized in processDiagnosisFromAI');
    return;
  }
  const d = deps;

  const result = processAIResponse(fullResponse, sessionId, messageId, {
    diagnosisService: d.diagnosisService,
    evidenceService: d.evidenceService,
    diagnosisMerger: d.diagnosisMerger,
  });

  if (!result) {
    console.warn('[DiagnosisHandler] No diagnosis table in AI response');
    return;
  }

  if (d.mainWindow) {
    try {
      const updatedState = d.teachingStateService.getBySession(sessionId);
      if (updatedState) {
        d.mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_UPDATED, {
          ...updatedState,
          phaseName: d.teachingStateService.getPhaseName(updatedState.currentPhase ?? ''),
          subphaseName: d.teachingStateService.getSubphaseName(updatedState.currentSubphase ?? ''),
          phaseProgress: d.teachingStateService.calculatePhaseProgress(updatedState.currentPhase ?? '', updatedState.currentSubphase ?? ''),
        });
      }
    } catch (e) {
      console.warn('[DiagnosisHandler] Failed to push TeachingState update:', e);
    }
  }

  if (d.mainWindow && !wasDiagnosisPushed(sessionId)) {
    d.mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATED, result.diagnosis);
  }
}
