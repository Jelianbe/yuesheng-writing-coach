/**
 * 诊断编排服务
 *
 * 职责：管理诊断分析流程，包括调用诊断 Agent、转换诊断数据、保存结果并推送到前端
 * 从 chat-orchestrator.service.ts 提取，减少主文件职责
 *
 * DI 注册名：'diagnosisOrchestratorService'
 */

import type { BrowserWindow } from 'electron';
import type { ApiProxy } from '../../../api-proxy';
import { IPC_CHANNELS, MAX_DIAGNOSIS_HISTORY } from '../../../../shared/constants';
import type { DiagnosisAnalysis, DiagnosisEntry, SyndromeResult, SeverityLevel } from '../../../../shared/types/index';
import type { SyndromeId } from '../../../../shared/constants';
import { markDiagnosisPushed } from '../../../ipc/utils/diagnosis-dedup';
import { SYNDROME_META, getActionsForSyndrome } from '../../../../shared/mappings';
import type { IDiagnosisDomain } from '../../01-diagnosis';
import type { TechniquePoolService} from '../../02-prescription/technique-pool.service';
import { type TechniqueFilter } from '../../02-prescription/technique-pool.service';
import { groupPassagesBySyndrome, getEvidenceForSyndrome } from '../evidence/evidence-grouping';
import * as path from 'path';
import { promises as fsPromises } from 'fs';

export class DiagnosisOrchestratorService {
  private mainWindow: BrowserWindow | null;

  constructor(
    private techniquePool: TechniquePoolService,
    private diagnosisDomain: IDiagnosisDomain,
    mainWindow: BrowserWindow | null,
  ) {
    this.mainWindow = mainWindow;
  }

  /** 设置主窗口（在窗口创建后调用） */
  setMainWindow(win: BrowserWindow | null): void {
    this.mainWindow = win;
  }

  /**
   * 执行诊断分析完整流程：
   * 1. 调用诊断 Agent
   * 2. 保存诊断结果
   * 3. 转换为前端格式并推送 DIAGNOSIS_UPDATED 事件
   */
  async analyze(
    apiProxy: ApiProxy,
    message: string,
    activeSessionId: string,
    options?: { syndromeIds?: string[] },
  ): Promise<{ analysis: DiagnosisAnalysis | null; isNarrative: boolean }> {
    if (!this.mainWindow) return { analysis: null, isNarrative: true };

    // S16 BL-02: 把 options.syndromeIds 映射为 TechniqueFilter，按活跃症候过滤技法池
    const filter: TechniqueFilter | undefined = options?.syndromeIds?.length
      ? { syndromeIds: options.syndromeIds }
      : undefined;
    const analysis = await this.callDiagnosisAgent(apiProxy, message, filter);
    const isNarrative = analysis?.contentType !== 'non-narrative';

    if (analysis && isNarrative) {
      const tempMessageId = this.generateId();
      const diagId = this.diagnosisDomain.save({
        sessionId: activeSessionId,
        messageId: tempMessageId,
        syndromes: [],
        suggestedActions: [],
        confidence: analysis.confidence ?? 0,
        timestamp: new Date().toISOString(),
      });
      this.diagnosisDomain.saveAnalysis(analysis, diagId);
      const entry = this.analysisToDiagnosisEntry(analysis, activeSessionId, tempMessageId);
      this.mainWindow.webContents.send(IPC_CHANNELS.DIAGNOSIS_UPDATED, { sessionId: activeSessionId, entry });
      markDiagnosisPushed(activeSessionId);
    }

    return { analysis, isNarrative };
  }

  /**
   * 从历史诊断中提取活跃的 syndromeIds
   */
  extractSyndromeIds(sessionId: string): string[] | undefined {
    const recentDiagnoses = this.diagnosisDomain.getRecentBySession(sessionId, 3);
    const syndromeIdsSet = new Set<string>();
    for (const diag of recentDiagnoses) {
      for (const syndrome of diag.syndromes) {
        syndromeIdsSet.add(syndrome.id);
      }
    }
    return syndromeIdsSet.size > 0 ? Array.from(syndromeIdsSet) : undefined;
  }

  // ─── 私有方法 ───

  private async callDiagnosisAgent(
    proxy: ApiProxy,
    userText: string,
    filter?: TechniqueFilter,
    onChunk?: (chunk: string) => void,
  ): Promise<DiagnosisAnalysis | null> {
    try {
      const promptPath = path.join(__dirname, '../../../resources/prompts/diagnosis-agent-prompt-v1.md');
      let diagnosisPrompt: string;
      try {
        diagnosisPrompt = await fsPromises.readFile(promptPath, 'utf-8');
        diagnosisPrompt = this.techniquePool.injectIntoPrompt(diagnosisPrompt, filter);
      } catch {
        console.warn('[DiagnosisAgent] Prompt file not found, using fallback');
        diagnosisPrompt = '分析以下文本的写作问题，以JSON格式输出结构化的诊断结果。';
      }

      const messages = [
        { role: 'system' as const, content: diagnosisPrompt },
        { role: 'user' as const, content: userText },
      ];

      let fullResponse = '';
      for await (const chunk of proxy.chatStream(messages)) {
        fullResponse += chunk;
        if (onChunk) onChunk(chunk);
      }

      const jsonMatch = fullResponse.match(/\{[\s\S]*\}/);
      if (!jsonMatch) {
        console.warn('[DiagnosisAgent] No JSON found in response');
        return null;
      }

      try {
        return JSON.parse(jsonMatch[0]) as DiagnosisAnalysis;
      } catch (parseErr) {
        console.error('[DiagnosisAgent] Failed to parse JSON:', parseErr);
        return null;
      }
    } catch (err) {
      console.error('[DiagnosisAgent] Failed to analyze:', err);
      return null;
    }
  }

  private analysisToDiagnosisEntry(
    analysis: DiagnosisAnalysis,
    sessionId: string,
    messageId: string,
  ): DiagnosisEntry {
    const allSuggestedActions: string[] = [];

    const keyPassages = analysis.keyPassages ?? [];
    const passagesBySyndrome = groupPassagesBySyndrome(keyPassages);
    const sharedFallback = keyPassages.slice(0, MAX_DIAGNOSIS_HISTORY).map(kp => kp.text);

    const syndromes: SyndromeResult[] = analysis.syndromeRef.map((ref) => {
      const meta = SYNDROME_META[ref as SyndromeId] ?? { name: ref, severity: 'L1' as SeverityLevel };
      const actions = getActionsForSyndrome(ref);
      allSuggestedActions.push(...actions);

      const evidence = getEvidenceForSyndrome(passagesBySyndrome, ref, sharedFallback);

      return {
        id: ref,
        name: meta.name,
        severity: meta.severity,
        evidence,
        score: analysis.confidence,
        suggestedActions: actions,
      };
    });

    const severityOrder = { L3: 0, L2: 1, L1: 2 };
    syndromes.sort((a, b) => severityOrder[a.severity] - severityOrder[b.severity]);

    const uniqueActions = [...new Set(allSuggestedActions)];

    return {
      sessionId,
      messageId,
      syndromes,
      suggestedActions: uniqueActions,
      timestamp: new Date().toISOString(),
      confidence: analysis.confidence,
    };
  }

  private generateId(): string {
    return `msg_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
  }
}
