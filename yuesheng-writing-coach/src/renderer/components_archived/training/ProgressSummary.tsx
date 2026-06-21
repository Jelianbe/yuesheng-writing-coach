/**
 * ProgressSummary — 右侧栏"进步摘要"卡片(C-2 / RWR-P1-8)
 *
 * 依据 spec §4.9 + §十五.4.2:
 *   - 包装 TeachingProgressBar,在精通确认时刻(进度条跳 1/N)短暂高亮
 *   - 右侧栏规则:从不主动打开;已开+标签栏中时自动切换内容
 *   - 高亮由数据驱动(消费 progress.store 现有 currentProgress.resolvedIssues)
 *
 * 约束:
 *   - R-021 隐性诊断:不展示症候 name/description(只展示 resolved/total)
 *   - R-019 单文件 ≤300 行
 *   - 不造 IPC(消费 progress.store 即可)
 *   - 不接 BeatCheckChart(spec 范围不要求,提示词"弱项对比"已删除)
 *
 * 高亮逻辑:
 *   1. 监听 currentProgress.resolvedIssues 变化
 *   2. 200ms 延迟后激活高亮类名,3000ms 后关闭
 *   3. session 切换时清空高亮状态,避免误触
 */

import React, { useEffect, useRef, useState } from 'react';
import { useProgressStore } from '../../stores/progress.store';
import { TeachingProgressBar } from './TeachingProgressBar';
import styles from './ProgressSummary.module.css';

/** 高亮激活延迟(spec §4.9 "卡片短暂高亮" UX 反馈) */
const HIGHLIGHT_ACTIVATION_DELAY_MS = 200;
/** 高亮持续时间(UX 反馈窗口) */
const HIGHLIGHT_DURATION_MS = 3000;

export const ProgressSummary: React.FC = () => {
  const currentProgress = useProgressStore((s) => s.currentProgress);
  const [highlighted, setHighlighted] = useState(false);
  const prevResolvedRef = useRef<number>(0);
  const prevSessionIdRef = useRef<string | null>(null);
  const timersRef = useRef<number[]>([]);

  useEffect(() => {
    // 清空旧 timer(避免快速连击时计时器堆叠)
    timersRef.current.forEach((id) => window.clearTimeout(id));
    timersRef.current = [];

    if (!currentProgress) {
      prevSessionIdRef.current = null;
      prevResolvedRef.current = 0;
      setHighlighted(false);
      return undefined;
    }

    // session 切换:清空高亮 + 重置基线
    if (currentProgress.sessionId !== prevSessionIdRef.current) {
      prevSessionIdRef.current = currentProgress.sessionId;
      prevResolvedRef.current = currentProgress.resolvedIssues;
      setHighlighted(false);
      return undefined;
    }

    // resolved 增长:触发高亮(spec §4.9 "进度条跳 1/N → 卡片短暂高亮")
    if (currentProgress.resolvedIssues > prevResolvedRef.current) {
      prevResolvedRef.current = currentProgress.resolvedIssues;
      const onTimer = window.setTimeout(
        () => setHighlighted(true),
        HIGHLIGHT_ACTIVATION_DELAY_MS,
      );
      const offTimer = window.setTimeout(
        () => setHighlighted(false),
        HIGHLIGHT_ACTIVATION_DELAY_MS + HIGHLIGHT_DURATION_MS,
      );
      timersRef.current.push(onTimer, offTimer);
    }

    return () => {
      timersRef.current.forEach((id) => window.clearTimeout(id));
      timersRef.current = [];
    };
  }, [currentProgress?.sessionId, currentProgress?.resolvedIssues]);

  return (
    <div
      className={
        highlighted
          ? `${styles.summary} ${styles.summaryHighlighted}`
          : styles.summary
      }
      data-testid="progress-summary"
      data-highlighted={highlighted ? 'true' : 'false'}
    >
      <TeachingProgressBar />
    </div>
  );
};
