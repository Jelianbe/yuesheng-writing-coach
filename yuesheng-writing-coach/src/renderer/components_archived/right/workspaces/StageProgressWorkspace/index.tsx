/**
 * StageProgressWorkspace — S8 发展路径进度工具
 *
 * 展示用户在七阶段发展路径中的当前位置和进度。
 * 数据来源：prescription:getStageProgress + getAllStages IPC
 */

import React, { useEffect, useState, useCallback } from 'react';
import { getInvoke } from '../../../../utils/ipc';
import { IPC_CHANNELS } from '../../../../../shared/constants';
import { registerWorkspace } from '../../../../registry/workspace-registry';
import type { StageProgress, DevelopmentStageInfo } from '../../../../shared/types';
import styles from './index.module.css';

interface StageDisplay {
  stageId: string;
  name: string;
  order: number;
  active: boolean;
  completed: boolean;
  locked: boolean;
}

export const StageProgressWorkspace: React.FC = () => {
  const [stageProgress, setStageProgress] = useState<StageProgress | null>(null);
  const [allStages, setAllStages] = useState<DevelopmentStageInfo[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { useChatStore } = await import('../../../../stores/chat.store');
      const sid = useChatStore.getState().currentSessionId;

      const [stagesResult, progress] = await Promise.all([
        getInvoke()(IPC_CHANNELS.PRESCRIPTION_GET_ALL_STAGES) as Promise<{ stages: DevelopmentStageInfo[] }>,
        sid
          ? getInvoke()(IPC_CHANNELS.PRESCRIPTION_GET_STAGE_PROGRESS, { sessionId: sid }) as Promise<StageProgress>
          : Promise.resolve(null),
      ]);

      setAllStages(stagesResult.stages ?? []);
      if (progress) setStageProgress(progress);
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();

    // 切换到该工具时重新加载
    window.addEventListener('focus', loadData);
    return () => window.removeEventListener('focus', loadData);
  }, [loadData]);

  // 构建阶段列表展示
  const stageDisplays: StageDisplay[] = allStages.map((stage) => {
    const currentOrder = stageProgress?.currentStage.order ?? 1;
    const isCurrent = stageProgress?.currentStage.stageId === stage.stageId;
    const isCompleted = stage.order < currentOrder;

    return {
      stageId: stage.stageId,
      name: stage.name,
      order: stage.order,
      active: isCurrent,
      completed: isCompleted,
      locked: !isCurrent && !isCompleted,
    };
  });

  if (loading) {
    return <div className={styles.container}><div className={styles.loading}>加载中...</div></div>;
  }

  if (error) {
    return <div className={styles.container}><div className={styles.error}>{error}</div></div>;
  }

  if (allStages.length === 0) {
    return <div className={styles.container}><div className={styles.empty}>暂无发展路径数据</div></div>;
  }

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <h3 className={styles.title}>写作发展路径</h3>
        {stageProgress && (
          <div className={styles.subtitle}>
            当前阶段：{stageProgress.currentStage.name}
            <span className={styles.coreQuestion}>（{stageProgress.currentStage.coreQuestion}）</span>
          </div>
        )}
      </div>

      <div className={styles.timeline}>
        {stageDisplays.map((stage) => (
          <div
            key={stage.stageId}
            className={`${styles.stageItem} ${
              stage.active ? styles.active : stage.completed ? styles.completed : styles.locked
            }`}
          >
            <div className={styles.stageDot}>
              {stage.completed ? '✓' : stage.order}
            </div>
            <div className={styles.stageContent}>
              <div className={styles.stageName}>{stage.name}</div>
              {stage.active && stageProgress && (
                <>
                  <div className={styles.progressBar}>
                    <div
                      className={styles.progressFill}
                      style={{ width: `${stageProgress.progress}%` }}
                    />
                  </div>
                  <div className={styles.statusText}>
                    进度 {stageProgress.progress}%
                    {stageProgress.blockingSyndromes && stageProgress.blockingSyndromes.length > 0 && (
                      <span className={styles.blocking}>
                        （{stageProgress.blockingSyndromes.length} 个症候待改善）
                      </span>
                    )}
                  </div>
                </>
              )}
              {stage.completed && <div className={styles.statusText}>已完成</div>}
              {stage.locked && <div className={styles.statusText}>未解锁</div>}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

// ADR-002: 自注册
registerWorkspace({
  id: 'stage',
  name: '发展路径',
  icon: '◈',
  defaultOpen: true,
  component: () => import('./index').then(m => ({ default: m.StageProgressWorkspace })),
});
