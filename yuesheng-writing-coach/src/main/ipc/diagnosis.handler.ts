/**
 * 诊断 IPC 处理器
 * 负责：解析 AI 回复中的诊断表，合并到 TeachingState，推送到渲染进程
 * 依赖：electron.ipcMain, diagnosis-parser, DiagnosisMerger
 * 安全：仅允许白名单中的通道
 *
 * 新架构：
 *   AI 回复 → diagnosis-parser 解析 → 转换为 ActiveProblem → 通过 DiagnosisMerger 合并到 TeachingState → IPC 推送
 */

import { ipcMain, BrowserWindow } from 'electron';
import { parseDiagnosisFromAIResponse } from '../services/diagnosis-parser';
import { DiagnosisService } from '../services/diagnosis.service';
import { EvidenceService } from '../services/evidence.service';
import { getAbilitiesForSyndrome } from '../../shared/mappings';
import { IPC_CHANNELS, IMPROVEMENT_THRESHOLD } from '../../shared/constants';
import { apiSuccess, apiError } from '../../renderer/shared/types';
import { validatePayload } from './utils/validate-payload';
import { ApiProxy } from '../api-proxy';
import { ConfigService } from '../services/config.service';
import { SessionService } from '../services/session.service';
import { DiagnosisMerger } from '../services/diagnosis-merger';
import { GrowthTrendService } from '../services/growth-trend.service';
import { SYNDROME_NAMES } from '../../shared/mappings';

// Re-export merge functions for use by diagnosis-merger service
export { severityToNumber, mergeSyndromesIntoState } from '../services/diagnosis-merger-utils';

export interface DiagnosisHandlerDeps {
  configService: ConfigService;
  diagnosisService: DiagnosisService;
  evidenceService: EvidenceService;
  sessionService: SessionService;
  growthTrendService: GrowthTrendService;
  getTeachingStateBySession: (sessionId: string) => { activeProblems: unknown[] } | null;
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
  ipcMain.handle(
    IPC_CHANNELS.DIAGNOSIS_QUERY,
    (_event, args) => {
      const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      try {
        const state = deps!.getTeachingStateBySession(validation.data.sessionId);
        return apiSuccess(state?.activeProblems ?? null);
      } catch (error) {
        console.error('[DiagnosisHandler] 查询诊断结果失败:', error);
        return apiError(String(error));
      }
    },
  );

  /**
   * 获取历史诊断对比
   */
  ipcMain.handle(
    IPC_CHANNELS.DIAGNOSIS_GET_COMPARISON,
    (_event, args) => {
      const validation = validatePayload<{ sessionId: string }>(args, { required: ['sessionId'], types: { sessionId: 'string' } });
      if (!validation.valid) return apiError(`INVALID_PAYLOAD: ${validation.error.message}`);
      try {
        const recent = deps!.diagnosisService.getRecentBySession(validation.data.sessionId, 2);
        if (recent.length < 2) return apiSuccess({ hasHistory: false });

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
        return apiSuccess({ hasHistory: true, comparison });
      } catch (error) {
        console.error('[DiagnosisHandler] 生成对比失败:', error);
        return apiError(String(error));
      }
    },
  );

  /**
   * 获取成长趋势数据
   */
  ipcMain.handle(
    IPC_CHANNELS.GROWTH_GET_TRENDS,
    (_event, args: { sessionId: string }) => {
      try {
        const summary = deps!.growthTrendService.getGrowthSummary(
          args.sessionId,
          (id) => SYNDROME_NAMES[id] || id,
        );
        return apiSuccess(summary);
      } catch (error) {
        console.error('[GrowthTrend] 获取成长趋势失败:', error);
        return apiError(String(error));
      }
    },
  );

  /**
   * 获取全局成长趋势
   */
  ipcMain.handle(
    IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS,
    () => {
      try {
        const summary = deps!.growthTrendService.getGrowthSummary(
          undefined,
          (id) => SYNDROME_NAMES[id] || id,
        );
        return apiSuccess(summary);
      } catch (error) {
        console.error('[GrowthTrend] 获取全局成长趋势失败:', error);
        return apiError(String(error));
      }
    },
  );

  /**
   * 提交修改原文
   */
  ipcMain.handle(
    IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE,
    async (_event, args: { sessionId: string; messageId: string; syndromeId: string; originalText: string; rewrittenText: string; syndromeName?: string; syndromeDesc?: string }) => {
      try {
        const { sessionId, syndromeId, originalText, rewrittenText, syndromeName, syndromeDesc } = args;
        console.log(`[Rewrite] 用户修改原文: session=${sessionId}, syndrome=${syndromeId}`);

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

          console.log(`[Rewrite] 评估结果: ${evaluation.improvement}`);
          return apiSuccess({ evaluation });
        }

        return apiSuccess(undefined);
      } catch (error) {
        const errorMessage = error instanceof Error ? error.message : '未知错误';
        console.error('[Rewrite] 提交修改失败:', errorMessage);
        return apiError(errorMessage);
      }
    },
  );
}

/**
 * 解析 AI 回复中的诊断表，合并到 TeachingState，推送到渲染进程
 *
 * 在 AI 回复流结束后调用
 */
export function processDiagnosisFromAI(
  fullResponse: string,
  sessionId: string,
  messageId: string,
): void {
  const { cleanResponse: _cleanResponse, diagnosis } = parseDiagnosisFromAIResponse(
    fullResponse,
    sessionId,
    messageId,
  );

  if (!diagnosis) {
    console.log('[DiagnosisHandler] No diagnosis table in AI response');
    return;
  }

  // 2. 持久化诊断结果（返回新生成的 UUID 主键）
  let diagnosisId = '';
  try {
    diagnosisId = deps!.diagnosisService.save(diagnosis);
  } catch (err) {
    console.error('[DiagnosisHandler] Failed to persist diagnosis:', err);
  }

  // 3. 创建 Evidence 记录并关联到诊断
  try {
    const now = new Date().toISOString();

    for (const syndrome of diagnosis.syndromes) {
      const abilities = getAbilitiesForSyndrome(syndrome.id);

      for (const [idx, evText] of syndrome.evidence.entries()) {
        const evidenceId = `EVD-${Date.now().toString(36)}${idx}`;
        const record = {
          evidenceId,
          type: 'text' as const,
          level: 1 as const,
          novelId: diagnosis.sessionId,
          contentJson: JSON.stringify({ text: evText }),
          relatedDisease: syndrome.id,
          relatedAbility: abilities[0] ?? '',
          extractedBy: 'diagnosis-parser',
          createdAt: now,
        };
        deps!.evidenceService.save(record);
        deps!.evidenceService.linkToDiagnosis(diagnosisId, evidenceId, idx === 0 ? 'primary' : 'supporting');
      }
    }
  } catch (err) {
    console.error('[DiagnosisHandler] Failed to create evidence:', err);
  }

  // 4. 将诊断结果合并到 TeachingState
  deps!.diagnosisMerger.merge(diagnosis);

  // 5. 推送到渲染进程
  if (deps!.mainWindow) {
    deps!.mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATE, diagnosis);
  }
}
