/**
 * 诊断 IPC 处理器
 * 负责：解析 AI 回复中的诊断表，合并到 TeachingState，推送到渲染进程
 * 依赖：electron.ipcMain, diagnosis-parser, DiagnosisMerger
 * 安全：仅允许白名单中的通道
 *
 * 新架构：
 *   AI 回复 → diagnosis-parser 解析 → 转换为 ActiveProblem → 通过 DiagnosisMerger 合并到 TeachingState → IPC 推送
 */

import { BrowserWindow } from 'electron';
import { DiagnosisService } from '../domains/diagnosis/diagnosis.service';
import { EvidenceService } from '../domains/diagnosis/evidence/evidence.service';
import { IPC_CHANNELS, IMPROVEMENT_THRESHOLD } from '../../shared/constants';
import { wasDiagnosisPushed } from './utils/diagnosis-dedup';
import { validatePayload } from './utils/validate-payload';
import { createHandler } from './utils/create-handler';
import { ApiProxy } from '../api-proxy';
import { ConfigService } from '../shared/services/config.service';
import { SessionService } from '../shared/services/session.service';
import { DiagnosisMerger } from '../domains/diagnosis/diagnosis-merger';
import { TeachingStateService } from '../domains/teaching/teaching-state.service';
import { GrowthTrendService } from '../domains/student/growth-trend.service';
import { processAIResponse } from '../domains/diagnosis/diagnosis-processor';
import { SYNDROME_NAMES } from '../../shared/mappings';

// Re-export merge functions for use by diagnosis-merger service
export { severityToNumber, mergeSyndromesIntoState } from '../domains/diagnosis/diagnosis-merger-utils';

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

export function initDiagnosisHandlers(d: DiagnosisHandlerDeps): void {
  deps = d;
}

/**
 * 注册诊断相关的 IPC 处理器
 */
export function registerDiagnosisHandlers(): void {
  if (!deps) throw new Error('DiagnosisHandler deps not injected');

  /**
   * 查询诊断结果
   */
  createHandler(
    IPC_CHANNELS.DIAGNOSIS_QUERY,
    (_event, args) => {
      const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
      if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
      const state = deps!.teachingStateService.getBySession(validation.data.sessionId);
      return state?.activeProblems ?? null;
    },
  );

  /**
   * 获取历史诊断对比
   */
  createHandler(
    IPC_CHANNELS.DIAGNOSIS_GET_COMPARISON,
    (_event, args) => {
      const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
      if (!validation.valid) throw new Error(`INVALID_PAYLOAD: ${validation.error.message}`);
      const recent = deps!.diagnosisService.getRecentBySession(validation.data.sessionId, 2);
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
    },
  );

  /**
   * 获取成长趋势数据
   */
  createHandler(
    IPC_CHANNELS.GROWTH_GET_TRENDS,
    (_event, args: { sessionId: string }) => {
      const summary = deps!.growthTrendService.getGrowthSummary(
        args.sessionId,
        (id) => SYNDROME_NAMES[id] || id,
      );
      return summary;
    },
  );

  /**
   * 获取全局成长趋势
   */
  createHandler(
    IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS,
    () => {
      const summary = deps!.growthTrendService.getGrowthSummary(
        undefined,
        (id) => SYNDROME_NAMES[id] || id,
      );
      return summary;
    },
  );

  /**
   * 提交修改原文
   */
  createHandler(
    IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE,
    async (_event, args: { sessionId: string; messageId: string; syndromeId: string; originalText: string; rewrittenText: string; syndromeName?: string; syndromeDesc?: string }) => {
      const { sessionId, syndromeId, originalText, rewrittenText, syndromeName, syndromeDesc } = args;
      deps!.sessionService.saveMessage(sessionId, 'system',
        `[修改原文] 症候: ${syndromeId}\n原文: "${originalText}"\n修改后: "${rewrittenText}"`);

      const config = deps!.configService.getConfig();
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
    },
  );
}

/**
 * 解析 AI 回复中的诊断表，合并到 TeachingState，推送到渲染进程
 *
 * 在 AI 回复流结束后调用
 * 核心领域逻辑委托给 processAIResponse，本层只负责 IPC 推送
 */
export function processDiagnosisFromAI(
  fullResponse: string,
  sessionId: string,
  messageId: string,
): void {
  const result = processAIResponse(fullResponse, sessionId, messageId, {
    diagnosisService: deps!.diagnosisService,
    evidenceService: deps!.evidenceService,
    diagnosisMerger: deps!.diagnosisMerger,
  });

  if (!result) {
    console.warn('[DiagnosisHandler] No diagnosis table in AI response');
    return;
  }

  // 4.5 推送 TeachingState 更新到前端（诊断合并可能推进子阶段）
  if (deps!.mainWindow) {
    try {
      const updatedState = deps!.teachingStateService.getBySession(sessionId);
      if (updatedState) {
        deps!.mainWindow.webContents.send(IPC_CHANNELS.TEACHING_STATE_UPDATED, {
          ...updatedState,
          phaseName: deps!.teachingStateService.getPhaseName(updatedState.currentPhase ?? ''),
          subphaseName: deps!.teachingStateService.getSubphaseName(updatedState.currentSubphase ?? ''),
          phaseProgress: deps!.teachingStateService.calculatePhaseProgress(updatedState.currentPhase ?? '', updatedState.currentSubphase ?? ''),
        });
      }
    } catch (e) {
      console.warn('[DiagnosisHandler] Failed to push TeachingState update:', e);
    }
  }

  // 5. 推送到渲染进程（RP-02: 若 Pipe 1 已推送则跳过）
  if (deps!.mainWindow && !wasDiagnosisPushed(sessionId)) {
    deps!.mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATE, result.diagnosis);
  }
}
