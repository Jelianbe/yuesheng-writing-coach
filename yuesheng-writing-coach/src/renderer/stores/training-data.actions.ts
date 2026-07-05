/**
 * 训练 Store — 数据加载 Actions
 *
 * ⚠️ 本文件由 training.actions.ts 拆分而来。
 *
 * Sprint 26 阶段 3.6: 调用方迁移到 service-bridge 单端点
 */

import { useChatStore } from './chat.store';
import { useDiagStore } from './diag.store';
import { useConfigStore } from './config.store';
import { serviceBridge } from '../services/service-bridge';
import type { TrainingHistoryResponse } from '../../shared/api-contracts/training.contract';
import { SYNDROME_NAMES } from '../../shared/mappings';
import type {
  ErrorCard,
  TrainingRecord,
  TrainingRecommendation,
} from '../shared/types';
import type { TrainingState } from './training.types';

type SetStateFn = (partial: Partial<TrainingState> | ((state: TrainingState) => Partial<TrainingState>), replace?: boolean) => void;
type GetStateFn = () => TrainingState;

// ===== 数据加载 Actions =====

export function createLoadHistoryAction(set: SetStateFn, _get: GetStateFn) {
  return async (sessionId: string): Promise<void> => {
    set({ isLoading: true, error: null });
    try {
      const data = await serviceBridge.invoke<{ sessionId: string }, TrainingHistoryResponse>(
        'training:history',
        { sessionId },
      );

      if (!data) {
        throw new Error('loadHistory returned null');
      }

      const records: TrainingRecord[] = (data.records ?? []).map((r) => ({
        id: r.recordId,
        sessionId,
        challengeId: r.syndromeId,
        challengeName: SYNDROME_NAMES[r.syndromeId] ?? r.title ?? '未知训练',
        status: 'completed' as const,
        score: r.score,
        assignedAt: r.completedAt ? new Date(r.completedAt).toISOString() : '',
      }));

      set({ history: records, isLoading: false });
    } catch (error) {
      console.error('[TrainingStore] loadHistory failed:', error);
      set({ error: String(error), isLoading: false });
    }
  };
}

export function createRefreshFromDiagnosisAction(set: SetStateFn, _get: GetStateFn) {
  return async (): Promise<void> => {
    set({ isLoading: true, error: null });
    try {
      const sessionId = useChatStore.getState().currentSessionId;
      if (!sessionId) {
        set({ errorCards: [], recommendations: [], isLoading: false });
        return;
      }

      // 1. 从 diag.store 聚合 ErrorCards
      const diagHistory = useDiagStore.getState().getHistoryBySession(sessionId);
      const syndromeMap = new Map<string, {
        syndromeId: string;
        syndromeName: string;
        severity: string;
        diagnosisCount: number;
        lastQuote: string;
        lastDiagnosedAt: string;
      }>();

      const severityOrder: Record<string, number> = { L3: 3, L2: 2, L1: 1 };

      for (const entry of diagHistory) {
        for (const syndrome of entry.syndromes) {
          const existing = syndromeMap.get(syndrome.id);
          if (!existing || new Date(entry.timestamp) > new Date(existing.lastDiagnosedAt)) {
            syndromeMap.set(syndrome.id, {
              syndromeId: syndrome.id,
              syndromeName: syndrome.name,
              severity: syndrome.severity,
              diagnosisCount: (existing?.diagnosisCount ?? 0) + 1,
              lastQuote: syndrome.evidence[0] ?? '',
              lastDiagnosedAt: entry.timestamp,
            });
          } else if (existing) {
            existing.diagnosisCount += 1;
          }
        }
      }

      const errorCards: ErrorCard[] = Array.from(syndromeMap.values())
        .sort((a, b) => (severityOrder[b.severity] ?? 0) - (severityOrder[a.severity] ?? 0))
        .map(c => ({
          syndromeId: c.syndromeId,
          syndromeName: c.syndromeName,
          severity: c.severity as ErrorCard['severity'],
          diagnosisCount: c.diagnosisCount,
          lastQuote: c.lastQuote,
          lastDiagnosedAt: c.lastDiagnosedAt,
        }));

      // 1.5 B-02：阅读前置决策
      const attitude = useConfigStore.getState().attitudeLevel;
      let readingDecision = null;
      try {
        const result = await serviceBridge.invoke<
          { attitude: string },
          { required: boolean; recommended: boolean; label: string; reason?: string }
        >('training:decideReading', { attitude });
        readingDecision = result;
      } catch (e) {
        console.warn('[training.actions] decideReading failed, falling back to null:', e);
      }
      set({ readingDecision: readingDecision ?? null });

      // 2. 调用 training:recommend 获取推荐
      // 注: contract TrainingRecommendResponse 字段名 tasks 与 handler 实际返回 recommendations 不一致,
      //     此处用业务实际类型(避免迁移时改 handler 触发更大改动)
      const recData = await serviceBridge.invoke<
        { sessionId: string },
        { recommendations: TrainingRecommendation[] }
      >('training:recommend', { sessionId });
      const recommendations: TrainingRecommendation[] = recData?.recommendations ?? [];

      // 3. 关联匹配的 challengeId 到 errorCards
      if (recommendations.length > 0) {
        for (const card of errorCards) {
          const match = recommendations.find(r => r.syndromeId === card.syndromeId);
          if (match) {
            card.matchedChallengeId = match.challengeId;
          }
        }
      }

      set({ errorCards, recommendations, isLoading: false });

      // 自动设置桥接卡片推荐
      if (recommendations.length > 0) {
        set({ bridgeRecommendation: recommendations[0] });
      } else {
        set({ bridgeRecommendation: null });
      }
    } catch (error) {
      console.error('[TrainingStore] refreshFromDiagnosis failed:', error);
      set({ error: String(error), isLoading: false });
    }
  };
}
