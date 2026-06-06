/**
 * 教学进度面板组件
 * 负责：展示当前教学进度、已完成动作、建议下一步
 * 依赖：Zustand teaching-state.store、Tailwind CSS、electronAPI
 * 设计原则：
 *   1. 纯展示组件，通过 Zustand store 订阅数据
 *   2. 无教学状态时显示空状态
 *   3. 提供"我懂了"按钮用于推进教学进度
 */

import React, { useEffect, useState, useCallback } from 'react';
import { useTeachingStateStore, selectProgressDisplay } from '../stores/teaching-state.store';
import { IPC_CHANNELS } from '../../shared/constants';
import { TeachingState, ApiResponse } from '../shared/types';

/**
 * 空状态组件
 */
function EmptyState(): React.ReactElement {
  return (
    <div className="flex flex-col items-center justify-center py-8 text-center">
      <div className="text-3xl mb-3 opacity-40">📚</div>
      <div className="text-sm text-slate-300 mb-1">暂无教学进度</div>
      <div className="text-xs text-slate-500 max-w-[200px]">
        开始对话后，月笙会自动记录教学进度
      </div>
    </div>
  );
}

/**
 * 确认对话框组件
 */
function ConfirmDialog({
  onConfirm,
  onCancel,
}: {
  onConfirm: () => void;
  onCancel: () => void;
}): React.ReactElement {
  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
      <div className="bg-slate-800 rounded-lg p-6 max-w-sm mx-4 border border-slate-700">
        <h3 className="text-lg font-semibold text-slate-200 mb-3">确认进度推进</h3>
        <p className="text-sm text-slate-400 mb-4">
          确认已完成当前教学步骤？确认后将继续下一阶段的教学。
        </p>
        <div className="flex gap-3 justify-end">
          <button
            onClick={onCancel}
            className="px-4 py-2 text-sm text-slate-400 hover:text-slate-200 transition-colors"
          >
            取消
          </button>
          <button
            onClick={onConfirm}
            className="px-4 py-2 text-sm bg-blue-600 hover:bg-blue-500 text-white rounded transition-colors"
          >
            确认，继续
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * 教学进度面板主组件
 */
export function TeachingProgressPanel({ sessionId }: { sessionId: string }): React.ReactElement {
  const progress = useTeachingStateStore(selectProgressDisplay);
  const setCurrentState = useTeachingStateStore((s) => s.setCurrentState);
  const setLoading = useTeachingStateStore((s) => s.setLoading);
  const [showConfirm, setShowConfirm] = useState(false);

  /** 加载教学状态 */
  useEffect(() => {
    if (!sessionId) return;

    const electronAPI = window.electronAPI;
    if (!electronAPI) return;

    setLoading(true);
    electronAPI.invoke(IPC_CHANNELS.TEACHING_STATE_GET, { sessionId })
      .then((response: unknown) => {
        const apiResponse = response as ApiResponse<TeachingState>;
        if (apiResponse.success && apiResponse.data) {
          setCurrentState(apiResponse.data);
        }
      })
      .catch((err: unknown) => {
        console.error('[TeachingProgressPanel] Failed to load teaching state:', err);
      })
      .finally(() => {
        setLoading(false);
      });

    /** 监听主进程推送的状态更新 */
    const cleanup = electronAPI.on(IPC_CHANNELS.TEACHING_STATE_UPDATED, (data: unknown) => {
      setCurrentState(data as TeachingState);
    });

    return cleanup;
  }, [sessionId, setCurrentState, setLoading]);

  /** 处理确认推进 */
  const handleConfirm = useCallback(() => {
    setShowConfirm(false);

    const electronAPI = (window as Window & {
      electronAPI?: {
        invoke: (channel: string, args: unknown) => Promise<unknown>;
      };
    }).electronAPI;

    if (!electronAPI || !sessionId) return;

    electronAPI.invoke(IPC_CHANNELS.TEACHING_STATE_CONFIRM, { sessionId })
      .then((response: unknown) => {
        const apiResponse = response as ApiResponse<{ oldState: TeachingState; newState: TeachingState }>;
        if (apiResponse.success && apiResponse.data) {
          setCurrentState(apiResponse.data.newState);
        }
      })
      .catch((err: unknown) => {
        console.error('[TeachingProgressPanel] Failed to confirm phase:', err);
      });
  }, [sessionId, setCurrentState]);

  if (!progress) {
    return (
      <aside
        className="w-72 bg-slate-900 border-l border-slate-700 overflow-y-auto flex-shrink-0"
        role="region"
        aria-label="教学进度"
      >
        <div className="p-4 border-b border-slate-700">
          <h2 className="text-sm font-semibold text-slate-200">📚 教学进度</h2>
        </div>
        <EmptyState />
      </aside>
    );
  }

  return (
    <>
      <aside
        className="w-72 bg-slate-900 border-l border-slate-700 overflow-y-auto flex-shrink-0"
        role="region"
        aria-label="教学进度"
      >
        {/* 面板标题 */}
        <div className="p-4 border-b border-slate-700">
          <h2 className="text-sm font-semibold text-slate-200">📚 教学进度</h2>
        </div>

        {/* 当前阶段 */}
        <div className="p-4 border-b border-slate-700">
          <h3 className="text-xs text-slate-500 uppercase tracking-wider mb-2">当前阶段</h3>
          <div className="text-sm font-medium text-slate-200">{progress.phaseName}</div>
          <div className="text-xs text-slate-400 mt-1">{progress.subphaseName}</div>

          {/* 进度条 */}
          <div className="mt-3 h-1.5 bg-slate-700 rounded-full overflow-hidden">
            <div
              className="h-full bg-gradient-to-r from-blue-500 to-emerald-500 rounded-full transition-all duration-500"
              style={{ width: `${progress.phaseProgress * 100}%` }}
            />
          </div>
          <div className="text-xs text-slate-500 mt-1 text-right">
            {Math.round(progress.phaseProgress * 100)}%
          </div>
        </div>

        {/* 已完成动作 */}
        {progress.completedActions.length > 0 && (
          <div className="p-4 border-b border-slate-700">
            <h3 className="text-xs text-slate-500 uppercase tracking-wider mb-2">已完成</h3>
            <div className="flex flex-col gap-1">
              {progress.completedActions.map((action) => (
                <div key={action.id} className="flex items-center gap-2 py-1">
                  <span className="text-emerald-400 text-xs">✓</span>
                  <span className="text-xs text-slate-400">
                    {action.id} {action.name}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* 建议下一步 */}
        {progress.nextActions.length > 0 && (
          <div className="p-4 border-b border-slate-700">
            <h3 className="text-xs text-slate-500 uppercase tracking-wider mb-2">建议下一步</h3>
            <div className="flex flex-col gap-1">
              {progress.nextActions.map((action) => (
                <div key={action.id} className="flex items-center gap-2 py-1">
                  <span className="text-blue-400 text-xs">→</span>
                  <span className="text-xs text-slate-300 font-medium">
                    {action.id} {action.name}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* 活跃问题 */}
        {progress.activeProblems.length > 0 && (
          <div className="p-4 border-b border-slate-700">
            <h3 className="text-xs text-slate-500 uppercase tracking-wider mb-2">当前问题</h3>
            <div className="flex flex-col gap-1">
              {progress.activeProblems.map((problem) => (
                <div key={problem.id} className="flex items-center gap-2 py-1">
                  <span
                    className={`w-2 h-2 rounded-full ${
                      problem.status === 'improving' ? 'bg-amber-400' : 'bg-red-400'
                    }`}
                  />
                  <span className="text-xs text-slate-400">
                    {problem.id} {problem.status === 'improving' ? '(改善中)' : '(活跃)'}
                  </span>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* "我懂了"按钮 */}
        <div className="p-4">
          <button
            onClick={() => setShowConfirm(true)}
            className="w-full py-2.5 bg-gradient-to-r from-blue-600 to-blue-500 hover:from-blue-500 hover:to-blue-400 text-white text-sm font-medium rounded-lg transition-all duration-200 shadow-lg shadow-blue-500/20"
          >
            我懂了，继续 →
          </button>
        </div>
      </aside>

      {/* 确认对话框 */}
      {showConfirm && (
        <ConfirmDialog
          onConfirm={handleConfirm}
          onCancel={() => setShowConfirm(false)}
        />
      )}
    </>
  );
}
