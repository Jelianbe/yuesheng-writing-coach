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
import { DiagnosisEntry, apiSuccess, apiError } from '../../renderer/shared/types';
import { ApiProxy } from '../api-proxy';
import { ConfigService } from '../services/config.service';
import { SessionService } from '../services/session.service';
import { DiagnosisMerger } from '../services/diagnosis-merger';
import { GrowthTrendService } from '../services/growth-trend.service';
import { SYNDROME_NAMES } from '../../shared/mappings';

// Re-export merge functions for use by diagnosis-merger service
export { severityToNumber, mergeSyndromesIntoState } from '../services/diagnosis-merger-utils';

let diagnosisMerger: DiagnosisMerger | null = null;
let diagnosisService: DiagnosisService | null = null;
let evidenceService: EvidenceService | null = null;
let sessionService: SessionService | null = null;
let mainWindow: BrowserWindow | null = null;
let growthTrendService: GrowthTrendService | null = null;
let configService: ConfigService | null = null;

export function setConfigService(svc: ConfigService): void {
  configService = svc;
}

/** 只读 getter 用于 DIAGNOSIS_QUERY（替代直接持有 Store） */
let getTeachingStateBySession: ((sessionId: string) => { activeProblems: unknown[] } | null) | null = null;

export function setTeachingStateGetter(getter: (sessionId: string) => { activeProblems: unknown[] } | null): void {
  getTeachingStateBySession = getter;
}

/**
 * 设置诊断合并服务
 * @param merger - 诊断合并服务实例
 */
export function setDiagnosisMerger(merger: DiagnosisMerger): void {
  diagnosisMerger = merger;
}

/**
 * 设置诊断持久化服务
 */
export function setDiagnosisService(service: DiagnosisService): void {
  diagnosisService = service;
}

export function setEvidenceService(service: EvidenceService): void {
  evidenceService = service;
}

export function setSessionService(svc: SessionService): void {
  sessionService = svc;
}

export function setGrowthTrendService(svc: GrowthTrendService): void {
  growthTrendService = svc;
}

export function setMainWindow(win: BrowserWindow): void {
  mainWindow = win;
}

/**
 * 注册诊断相关的 IPC 处理器
 */
export function registerDiagnosisHandlers(): void {
  /**
   * 查询诊断结果
   */
  ipcMain.handle(
    IPC_CHANNELS.DIAGNOSIS_QUERY,
    (_event, args: { sessionId: string }) => {
      try {
        if (!getTeachingStateBySession) return apiSuccess(null);
        const state = getTeachingStateBySession(args.sessionId);
        return apiSuccess(state?.activeProblems ?? null);
      } catch (error) {
        console.error('[DiagnosisHandler] 查询诊断结果失败:', error);
        return apiError(String(error));
      }
    },
  );

  /**
   * 获取历史诊断对比
   * 对比上次诊断和本次诊断，生成一句话成长记录
   */
  ipcMain.handle(
    IPC_CHANNELS.DIAGNOSIS_GET_COMPARISON,
    (_event, args: { sessionId: string }) => {
      try {
        if (!diagnosisService) return apiSuccess({ hasHistory: false });

        const recent = diagnosisService.getRecentBySession(args.sessionId, 2);
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

        // 检查哪些症候在本次诊断中已消失
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
   * 获取成长趋势数据（右侧栏能力成长可视化）
   */
  ipcMain.handle(
    IPC_CHANNELS.GROWTH_GET_TRENDS,
    (_event, args: { sessionId: string }) => {
      try {
        if (!growthTrendService) return apiSuccess({ trends: [], masteredCount: 0, improvingCount: 0, needsAttentionCount: 0 });

        const summary = growthTrendService.getGrowthSummary(
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
   * 获取全局成长趋势（跨所有会话的长期进步）
   */
  ipcMain.handle(
    IPC_CHANNELS.GROWTH_GET_GLOBAL_TRENDS,
    () => {
      try {
        if (!growthTrendService) return apiSuccess({ trends: [], masteredCount: 0, improvingCount: 0, needsAttentionCount: 0 });

        // 不传 sessionId = 聚合所有会话
        const summary = growthTrendService.getGrowthSummary(
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
   * 渲染进程 -> 主进程: { sessionId, messageId, syndromeId, originalText, rewrittenText }
   * 主进程 -> 渲染进程: ApiResponse<{ evaluation: RewriteEvaluation } | void>
   *
   * M-2: 记录用户的修改原文操作
   * M-3: 调用 AI 评估接口，返回修改效果评估
   */
  ipcMain.handle(
    IPC_CHANNELS.DIAGNOSIS_SUBMIT_REWRITE,
    async (_event, args: { sessionId: string; messageId: string; syndromeId: string; originalText: string; rewrittenText: string; syndromeName?: string; syndromeDesc?: string }) => {
      try {
        const { sessionId, syndromeId, originalText, rewrittenText, syndromeName, syndromeDesc } = args;
        console.log(`[Rewrite] 用户修改原文: session=${sessionId}, syndrome=${syndromeId}`);

        // 记录到 session 消息中（作为系统内部记录）
        if (sessionService) {
          sessionService.saveMessage(sessionId, 'system',
            `[修改原文] 症候: ${syndromeId}\n原文: "${originalText}"\n修改后: "${rewrittenText}"`);
        }

        // 调用 AI 评估
        const config = configService!.getConfig();
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

        // 没有 API Key 时，返回无评估状态
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
 *
 * @param fullResponse - AI 完整回复（可能包含诊断表 JSON）
 * @param sessionId - 会话 ID
 * @param messageId - 消息 ID
 */
export function processDiagnosisFromAI(
  fullResponse: string,
  sessionId: string,
  messageId: string,
): void {
  // 1. 解析 AI 回复中的诊断表
  const { cleanResponse: _cleanResponse, diagnosis } = parseDiagnosisFromAIResponse(
    fullResponse,
    sessionId,
    messageId,
  );

  if (!diagnosis) {
    console.log('[DiagnosisHandler] No diagnosis table in AI response');
    return;
  }

  const diagnosisId = diagnosis.sessionId + '_' + diagnosis.messageId;

  // 2. 持久化诊断结果
  if (diagnosisService) {
    try {
      diagnosisService.save(diagnosis);
    } catch (err) {
      console.error('[DiagnosisHandler] Failed to persist diagnosis:', err);
    }
  }

  // 3. 创建 Evidence 记录并关联到诊断
  if (evidenceService) {
    try {
      const now = new Date().toISOString();
      const syndromeEvidenceMap: Array<{
        id: string;
        evidenceIds: string[];
        severity: string;
        sampleText?: string;
      }> = [];

      for (const syndrome of diagnosis.syndromes) {
        const abilities = getAbilitiesForSyndrome(syndrome.id);
        const syndromeEvidenceIds: string[] = [];

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
          evidenceService.save(record);
          evidenceService.linkToDiagnosis(diagnosisId, evidenceId, idx === 0 ? 'primary' : 'supporting');
          syndromeEvidenceIds.push(evidenceId);
        }

        syndromeEvidenceMap.push({
            id: syndrome.id,
            evidenceIds: syndromeEvidenceIds,
          severity: syndrome.severity,
          sampleText: syndrome.evidence[0],
        });
      }
    } catch (err) {
      console.error('[DiagnosisHandler] Failed to create evidence:', err);
    }
  }

  // 4. 将诊断结果合并到 TeachingState
  if (diagnosisMerger) {
    diagnosisMerger.merge(diagnosis);
  } else {
    console.warn('[DiagnosisHandler] DiagnosisMerger not initialized');
  }

  // 5. 推送到渲染进程
  if (mainWindow) {
    mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATE, diagnosis);
  }
}
