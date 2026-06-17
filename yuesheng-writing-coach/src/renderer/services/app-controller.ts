/**
 * 应用级编排器
 *
 * 职责：注册 IPC 事件监听，将推送事件桥接到对应的 Zustand store action。
 * 替代原本分散在 App.tsx / useAppIpcListener.ts 中的 IPC 监听注册逻辑。
 *
 * 生命周期：
 *   1. initialize()  — 应用启动时调用，注册所有监听 + 初始化 store 数据
 *   2. destroy()     — 应用卸载时调用，清理所有监听
 */

import { useChatStore } from '../stores/chat.store';
import { useDiagStore } from '../stores/diag.store';
import { useTeachingStateStore } from '../stores/teaching-state.store';
import { useStudentContextStore } from '../stores/student-context.store';
import { useTrainingStore } from '../stores/training.store';
import { usePanelSessionStore } from '../stores/panel-session.store';
import { useProgressStore } from '../stores/progress.store';
import { chatService } from './chat.service';
import { diagnosisService } from './diagnosis.service';
import { teachingStateService } from './teaching-state.service';
import type { DiagnosisEntry as RendererDiagnosisEntry } from '../shared/types-diagnosis';
import type { TeachingState as RendererTeachingState } from '../shared/types-teaching';
import { TeachingSubphase } from '../../shared/constants';

export interface AppControllerCallbacks {
  /** 流式结束时触发（用于刷新成长汇总等后处理） */
  onStreamEnd?: () => void;
}

export interface AppController {
  /** 注册所有 IPC 事件监听 + 初始化 store 数据 */
  initialize(callbacks?: AppControllerCallbacks): void;
  /** 清理所有 IPC 事件监听 */
  destroy(): void;
}

/**
 * 创建应用级编排器
 *
 * 通过闭包维护 cleanup 函数列表，destroy() 时统一移除。
 */
export function createAppController(): AppController {
  const cleanups: Array<() => void> = [];

  return {
    initialize(callbacks?: AppControllerCallbacks): void {
      // 0. 初始化 store 数据（替代 App.tsx 中分散的 init useEffect）
      useStudentContextStore.getState().load();

      // 1. 诊断更新 → diag.store + studentContext + training + progress (B-2)
      // 注: contract 类型较瘦，renderer 类型有额外字段，做类型断言桥接。
      cleanups.push(
        diagnosisService.onDiagnosisUpdate((data) => {
          const { sessionId, entry } = data;
          const rendererEntry = entry as unknown as RendererDiagnosisEntry;
          useDiagStore.getState().setCurrentDiagnosis(rendererEntry);
          if (sessionId) {
            useDiagStore.getState().addToHistory(sessionId, rendererEntry);
          }
          // 同步更新学生上下文和训练面板
          if (rendererEntry.syndromes && rendererEntry.syndromes.length > 0) {
            useStudentContextStore.getState().updateFromDiagnosis(rendererEntry.syndromes);
            useTrainingStore.getState().refreshFromDiagnosis();
            // RWR-P1-6 (B-2): 诊断产生后自动更新 progress.store
            // contract 的 SyndromeResult.syndromeId 是真实 ID,description 作为 label
            useProgressStore.getState().appendIssues(
              sessionId,
              entry.syndromes.map((s) => ({
                syndromeId: s.syndromeId,
                label: s.description,
              })),
            );
          }
        }),
      );

      // 2. 流式数据 → chat.store
      cleanups.push(
        chatService.onStreamData((data) => {
          useChatStore.getState().appendToLastAssistant(data.chunk);
        }),
      );

      // 3. 流式结束 → chat.store + studentContext + 外部回调
      cleanups.push(
        chatService.onStreamEnd((data) => {
          if (data.aborted) {
            // 用户主动中断
            useChatStore.getState().abortStream();
          } else {
            useChatStore.getState().finalizeLastMessage();
          }
          useChatStore.getState().setLoading(false);
          if (data.error) {
            useChatStore.getState().setError(data.error);
          }
          // 非中断且有回复时更新学生上下文
          if (!data.aborted && data.fullResponse && data.fullResponse.length > 0) {
            useStudentContextStore.getState().updateFromInteraction('partial');
          }
          // 外部回调（如 fetchGrowthSummary）
          callbacks?.onStreamEnd?.();
        }),
      );

      // 4. 工具调用状态 — 目前仅用于调试跟踪
      cleanups.push(
        chatService.onToolExecuting((data) => {
          if (data.status === 'error') {
            // eslint-disable-next-line no-console
            console.debug('[AppController] tool error:', data.toolName);
          }
        }),
      );

      // 5. 教学状态更新 → teaching-state.store + panel-session.store (F-03)
      // 注: contract 的 TeachingStateUpdatedEvent 与 renderer 的 TeachingState 字段不同，
      //     此处做类型断言桥接。Phase 4 统一类型定义后可移除。
      cleanups.push(
        teachingStateService.onUpdated((data) => {
          const teachingState = data as unknown as RendererTeachingState;
          useTeachingStateStore.getState().setCurrentState(teachingState);

          // F-03: 根据教学子阶段更新 sidebarPhase 和训练卡状态
          const subphase = teachingState.currentSubphase;
          if (subphase === TeachingSubphase.PRACTICE_TEACHING) {
            // TEACHING 完成 → 解锁训练卡但不自动展开
            usePanelSessionStore.getState().setSidebarPhase('training');
            usePanelSessionStore.getState().setTrainingUnlocked(true);
            usePanelSessionStore.getState().setTrainingExpanded(false);
          } else if (subphase === TeachingSubphase.PRACTICE_ASSIGN) {
            // ASSIGN_TASK → 训练卡自动展开
            usePanelSessionStore.getState().setSidebarPhase('training');
            usePanelSessionStore.getState().setTrainingUnlocked(true);
            usePanelSessionStore.getState().setTrainingExpanded(true);
          } else if (subphase === TeachingSubphase.PRACTICE_GUIDE) {
            // 引导发现阶段
            usePanelSessionStore.getState().setSidebarPhase('guide');
          }
        }),
      );
    },

    destroy(): void {
      for (const cleanup of cleanups) {
        cleanup();
      }
      cleanups.length = 0;
    },
  };
}
