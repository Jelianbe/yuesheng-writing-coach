/**
 * 训练 Store — 阅读前置 Action
 *
 * ⚠️ 本文件由 training.actions.ts 拆分而来。
 */

import { useChatStore } from './chat.store';
import { getInvoke } from '../utils/ipc';
import { TrainingApi } from '../../shared/api-contracts/training.contract';
import { ConfigApi } from '../../shared/api-contracts/config.contract';
import { READING_STEPS } from './training.types';
import type { TrainingState } from './training.types';
import type { TrainingRecord } from '../shared/types';

type SetStateFn = (partial: Partial<TrainingState> | ((state: TrainingState) => Partial<TrainingState>), replace?: boolean) => void;
type GetStateFn = () => TrainingState;

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

      const assignResult = await getInvoke()(TrainingApi.assign.channel, {
        sessionId,
        challengeId: `reading-${syndromeId}`,
      }) as { error?: string; record?: TrainingRecord };

      if (assignResult.error) throw new Error(assignResult.error);

      const readingResult = await getInvoke()(ConfigApi.getReadingEntry.channel, { syndromeId }) as { entries: Array<{ id: string; title: string; excerpt: string; analysisPrompt: string }> };
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
