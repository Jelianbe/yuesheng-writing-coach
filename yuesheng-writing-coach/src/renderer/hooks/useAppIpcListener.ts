import { useEffect } from 'react';
import { IPC_CHANNELS } from '../../shared/constants';
import { useDiagStore } from '../stores/diag.store';
import { useChatStore } from '../stores/chat.store';
import { useTeachingStateStore } from '../stores/teaching-state.store';
import { useStudentContextStore } from '../stores/student-context.store';
import { useTrainingStore } from '../stores/training.store';
import type { TeachingState } from '../shared/types';

/**
 * 应用级 IPC 事件监听器 Hook
 *
 * 在 App 根组件初始化时注册所有 IPC 事件监听器，
 * 组件卸载时自动清理。
 *
 * 当前监听的通道：
 *   - DIAGNOSIS_UPDATE: 诊断结果推送
 *   - CHAT_STREAM_DATA: 流式响应数据
 *   - CHAT_STREAM_END: 流式响应结束
 *   - TEACHING_STATE_UPDATED: 教学状态更新
 */
export function useAppIpcListener(
  fetchGrowthSummary: () => void,
): void {
  useEffect(() => {
    if (!window.electronAPI) return;

    const cleanups = [
      window.electronAPI.on(IPC_CHANNELS.DIAGNOSIS_UPDATE, (_data: unknown) => {
        const entry = _data as import('../shared/types').DiagnosisEntry;
        const { setCurrentDiagnosis, addToHistory } = useDiagStore.getState();
        setCurrentDiagnosis(entry);
        addToHistory(entry.sessionId, entry);
        if (entry.syndromes.length > 0) {
          useStudentContextStore.getState().updateFromDiagnosis(entry.syndromes);
          void useTrainingStore.getState().refreshFromDiagnosis();
        }
      }),

      window.electronAPI.on(IPC_CHANNELS.CHAT_STREAM_DATA, (_data: unknown) => {
        const { chunk } = _data as { sessionId: string; chunk: string };
        useChatStore.getState().appendToLastAssistant(chunk);
      }),

      window.electronAPI.on(IPC_CHANNELS.CHAT_STREAM_END, (_data: unknown) => {
        const result = _data as { sessionId: string; fullResponse: string; messageId: string; error?: string };
        const { setLoading, setError: setChatError } = useChatStore.getState();
        if (result.error) setChatError(result.error);
        setLoading(false);
        if (result.fullResponse && result.fullResponse.length > 0) {
          useStudentContextStore.getState().updateFromInteraction('partial');
        }
        fetchGrowthSummary();
        // 面板组件（AbilityProfilePanel / GrowthPanel）通过 useSessionStore 自动获取 sessionId
        // 组件重新挂载时（如切换标签后重新打开面板）会自动刷新数据
      }),

      window.electronAPI.on(IPC_CHANNELS.TEACHING_STATE_UPDATED, (_data: unknown) => {
        const teaching = _data as TeachingState & { phaseName: string; subphaseName: string; phaseProgress: number };
        const { setCurrentState } = useTeachingStateStore.getState();
        const { phaseName: _pn, subphaseName: _sn, phaseProgress: _pp, ...rest } = teaching;
        setCurrentState(rest as unknown as TeachingState);
      }),
    ];

    return () => { cleanups.forEach((fn) => fn()); };
  }, [fetchGrowthSummary]);
}
