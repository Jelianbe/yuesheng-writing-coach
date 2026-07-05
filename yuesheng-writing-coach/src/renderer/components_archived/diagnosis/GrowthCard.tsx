import React from 'react';
import { TrendingUp } from 'lucide-react';
import styles from './GrowthCard.module.css';

interface GrowthCardProps {
  /** 一句话成长记录 */
  summary: string;
  /** 是否有历史记录 */
  hasHistory: boolean;
  /** 加载状态 */
  isLoading?: boolean;
}

/**
 * GrowthCard — 一句话成长记录（M-4）
 *
 * 出现在诊断/评估后，作为聊天的自然收尾。
 * 通过 IPC `diagnosis:getComparison` 获取对比数据。
 */
export const GrowthCard: React.FC<GrowthCardProps> = ({
  summary,
  hasHistory,
  isLoading = false,
}) => {
  if (isLoading) {
    return (
      <div className={`${styles.skeletonContainer} animate-fade-in`}>
        <div className={styles.skeletonRow}>
          <div className={`${styles.skeletonCircle} animate-pulse-custom`} />
          <div className={`${styles.skeletonBar} animate-pulse-custom`} />
        </div>
      </div>
    );
  }

  return (
    <div className={`${styles.container} animate-slide-up`}>
      <div className={styles.content}>
        <div className={styles.iconWrapper}>
          <TrendingUp className={styles.icon} />
        </div>
        <div className={styles.body}>
          <p className={styles.title}>
            成长记录
          </p>
          <p className={styles.summary}>
            {hasHistory ? summary : '这是你的第一次诊断，还没有对比数据。'}
          </p>
        </div>
      </div>
    </div>
  );
};
