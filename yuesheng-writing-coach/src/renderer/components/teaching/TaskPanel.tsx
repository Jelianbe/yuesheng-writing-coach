/**
 * TaskPanel — 教学任务面板（V2-020）
 *
 * 功能：
 * - 从 TeachingState 读取教学动作，按进行中/已完成分组展示
 * - 支持标记动作完成或恢复为进行中（通过 IPC teachingState:update）
 * - 空状态处理（无教学状态时提示）
 */

import React, { useCallback } from 'react';
import { CheckCircle, Circle, ClipboardList, Target } from 'lucide-react';
import { useTeachingStateStore } from '../../stores/teaching-state.store';
import { ACTION_NAMES } from '../../../shared/mappings';
import { getInvoke } from '../../utils/ipc';

const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

/** 教学动作完整列表（静态列表，用于展示所有可用动作） */
const ALL_ACTIONS: { id: string; name: string }[] = Object.entries(ACTION_NAMES).map(([id, name]) => ({
  id,
  name: name as string,
}));

/** 单条任务行 */
const TaskItem: React.FC<{
  actionId: string;
  actionName: string;
  completed: boolean;
  onToggle: (actionId: string, currentCompleted: boolean) => void;
}> = ({ actionId, actionName, completed, onToggle }) => (
  <div
    style={{
      display: 'flex',
      alignItems: 'center',
      gap: 10,
      padding: '8px 10px',
      borderRadius: 'var(--radius-sm)',
      transition: `all 200ms ${EASE_OUT_QUART}`,
      opacity: completed ? 0.65 : 1,
    }}
    onMouseEnter={e => { (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)'; }}
    onMouseLeave={e => { (e.currentTarget as HTMLElement).style.background = 'transparent'; }}
  >
    <button
      onClick={() => onToggle(actionId, completed)}
      style={{
        border: 'none',
        background: 'transparent',
        cursor: 'pointer',
        padding: 0,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        color: completed ? 'var(--accent)' : 'var(--text-tertiary)',
        transition: `color 200ms ${EASE_OUT_QUART}`,
        flexShrink: 0,
      }}
      aria-label={completed ? `标记 ${actionName} 为进行中` : `标记 ${actionName} 为已完成`}
      title={completed ? '标记为进行中' : '标记为已完成'}
    >
      {completed ? (
        <CheckCircle size={18} strokeWidth={1.8} />
      ) : (
        <Circle size={18} strokeWidth={1.4} />
      )}
    </button>
    <span
      style={{
        fontSize: '0.82rem',
        color: completed ? 'var(--text-tertiary)' : 'var(--text-primary)',
        textDecoration: completed ? 'line-through' : 'none',
        lineHeight: 1.4,
        flex: 1,
        minWidth: 0,
        overflow: 'hidden',
        textOverflow: 'ellipsis',
        whiteSpace: 'nowrap',
      }}
    >
      {actionName}
    </span>
  </div>
);

/** 任务面板主体 */
const TaskPanel: React.FC = () => {
  const currentState = useTeachingStateStore(s => s.currentState);
  const setCurrentState = useTeachingStateStore(s => s.setCurrentState);

  // ── 切换任务完成状态 ──
  const handleToggle = useCallback(async (actionId: string, currentCompleted: boolean) => {
    if (!currentState) return;

    const newCompleted = !currentCompleted;
    let updatedCompletedActions: string[];

    if (newCompleted) {
      // 标记完成
      updatedCompletedActions = currentState.completedActions.includes(actionId)
        ? currentState.completedActions
        : [...currentState.completedActions, actionId];
    } else {
      // 取消完成
      updatedCompletedActions = currentState.completedActions.filter(id => id !== actionId);
    }

    // 乐观更新 UI
    setCurrentState({
      ...currentState,
      completedActions: updatedCompletedActions,
    });

    // 同步到后端
    try {
      const invoke = getInvoke();
      await invoke('teachingState:update', {
        sessionId: currentState.sessionId,
        updates: { completedActions: updatedCompletedActions },
      });
    } catch {
      // 静默回退
      setCurrentState(currentState);
    }
  }, [currentState, setCurrentState]);

  if (!currentState) {
    return (
      <div
        style={{
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '40px 20px',
          color: 'var(--text-tertiary)',
          gap: 12,
          textAlign: 'center',
        }}
      >
        <ClipboardList size={36} strokeWidth={1.4} opacity={0.3} />
        <span style={{ fontSize: '0.85rem' }}>暂无教学任务</span>
        <span style={{ fontSize: '0.72rem' }}>开始对话后将自动生成教学任务</span>
      </div>
    );
  }

  // 按完成状态分组
  const completedIds = new Set(currentState.completedActions);
  const suggestedIds = new Set(currentState.nextSuggestedActions);

  const completedTasks = ALL_ACTIONS.filter(a => completedIds.has(a.id));
  const inProgressTasks = ALL_ACTIONS.filter(a => suggestedIds.has(a.id) && !completedIds.has(a.id));

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* 当前阶段指示 */}
      <div
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: 8,
          padding: '0 2px',
          fontSize: '0.72rem',
          color: 'var(--text-tertiary)',
        }}
      >
        <Target size={14} strokeWidth={1.6} />
        <span>{currentState.currentPhase} · {currentState.currentSubphase}</span>
      </div>

      {/* 进行中任务 */}
      <div>
        <div
          style={{
            fontSize: '0.72rem',
            fontWeight: 600,
            color: 'var(--text-secondary)',
            letterSpacing: '0.03em',
            padding: '0 2px 4px',
            display: 'flex',
            alignItems: 'center',
            gap: 6,
          }}
        >
          <span>进行中</span>
          <span style={{ fontSize: '0.68rem', color: 'var(--text-tertiary)', fontWeight: 400 }}>
            ({inProgressTasks.length})
          </span>
        </div>
        {inProgressTasks.length > 0 ? (
          <div
            style={{
              border: '1px solid var(--border-light)',
              borderRadius: 'var(--radius-md)',
              overflow: 'hidden',
            }}
          >
            {inProgressTasks.map(task => (
              <TaskItem
                key={task.id}
                actionId={task.id}
                actionName={task.name}
                completed={false}
                onToggle={handleToggle}
              />
            ))}
          </div>
        ) : (
          <div
            style={{
              fontSize: '0.78rem',
              color: 'var(--text-tertiary)',
              padding: '12px 10px',
              textAlign: 'center',
              border: '1px dashed var(--border-light)',
              borderRadius: 'var(--radius-md)',
            }}
          >
            暂无进行中的任务
          </div>
        )}
      </div>

      {/* 已完成任务 */}
      {completedTasks.length > 0 && (
        <div>
          <div
            style={{
              fontSize: '0.72rem',
              fontWeight: 600,
              color: 'var(--text-tertiary)',
              letterSpacing: '0.03em',
              padding: '0 2px 4px',
              display: 'flex',
              alignItems: 'center',
              gap: 6,
            }}
          >
            <span>已完成</span>
            <span style={{ fontSize: '0.68rem', color: 'var(--text-tertiary)', fontWeight: 400 }}>
              ({completedTasks.length})
            </span>
          </div>
          <div
            style={{
              border: '1px solid var(--border-light)',
              borderRadius: 'var(--radius-md)',
              overflow: 'hidden',
            }}
          >
            {completedTasks.map(task => (
              <TaskItem
                key={task.id}
                actionId={task.id}
                actionName={task.name}
                completed={true}
                onToggle={handleToggle}
              />
            ))}
          </div>
        </div>
      )}
    </div>
  );
};

export default TaskPanel;
