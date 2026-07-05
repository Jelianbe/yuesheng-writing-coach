/**
 * 训练 Store — 阅读前置 Action
 *
 * ⚠️ 本文件由 training.actions.ts 拆分而来。
 * Sprint 26 阶段 3.6: 调用方迁移到 service-bridge 单端点
 */

import { useChatStore } from './chat.store';
import { serviceBridge } from '../services/service-bridge';
import { READING_STEPS } from './training.types';
import type { TrainingState } from './training.types';
import type { TrainingRecord } from '../shared/types';

type SetStateFn = (partial: Partial<TrainingState> | ((state: TrainingState) => Partial<TrainingState>), replace?: boolean) => void;
type GetStateFn = () => TrainingState;

interface ReadingEntry {
  id: string;
  title: string;
  excerpt: string;
  analysisPrompt: string;
}

/**
 * startReading — 开始阅读前置任务
 * 当 readingDecision.required 时调用，加载 reading-library 条目
 * 并创建 mode: 'reading_task' 的活跃会话。
 */
export function createStartReadingAction(set: SetStateFn, get: GetStateFn) {
  return async (challengeId: string): Promise<void> => {
    set({ isLoading: true, error: null });
    try {
      const sessionId = useChatStore.getState().currentSessionId;
      if (!sessionId) throw new Error('No active session');

      const match = get().recommendations.find(r => r.challengeId === challengeId);
      const fallbackSyndromeId = get().errorCards[0]?.syndromeId ?? 'unknown';
      const syndromeId = match?.syndromeId ?? fallbackSyndromeId;

      const assignResult = await serviceBridge.invoke<
        { sessionId: string; challengeId: string },
        { error?: string; record?: TrainingRecord }
      >('training:assign', {
        sessionId,
        challengeId: `reading-${syndromeId}`,
      });
      if (!assignResult) throw new Error('training:assign returned null');
      if (assignResult.error) throw new Error(assignResult.error);

      const readingResult = await serviceBridge.invoke<
        { syndromeId: string },
        { entries: ReadingEntry[] }
      >('config:getReadingEntry', { syndromeId });
      if (!readingResult) throw new Error('config:getReadingEntry returned null');
      const entry = readingResult.entries[0];

      const readingContent = entry
        ? `${entry.excerpt}\n\n【分析引导】\n${entry.analysisPrompt}`
        : `请仔细阅读你的文本，关注本次训练涉及的写作问题（${syndromeId}）。在下一步中写下你的分析和观察。`;

      const session = {
        challengeId: `reading-${syndromeId}`,
        challengeName: entry?.title ?? `阅读分析 · ${syndromeId}`,
        challengeDescription: readingContent,
        mode: 'reading_task' as const,
        steps: READING_STEPS.map((s, i) => ({
          ...s,
          status: i === 0 ? 'active' as const : 'pending' as const,
        })),
        currentStepIndex: 0,
        originalQuote: '',
        constraint: '',
        userDraft: '',
        recordId: assignResult.record?.id,
        syndromeId,
        targetSyndrome: match?.syndromeName,
      };

      set({ activeTraining: session, isLoading: false, submissionResult: null, evaluationResult: null });
    } catch (error) {
      console.error('[TrainingStore] startReading failed:', error);
      set({ error: String(error), isLoading: false });
    }
  };
}
