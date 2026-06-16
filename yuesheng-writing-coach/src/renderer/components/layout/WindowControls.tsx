/**
 * WindowControls — 窗口级独立渲染的 [─][□][✕] 控件
 *
 * 设计要点：
 * - position: fixed; top: 0; right: 0 — 不嵌套在任何栏的 DOM 中
 * - 最高 z-index，始终可见
 * - 颜色通过监听 useUiLayoutStore 中右侧栏状态切换
 * - 窗口控制 IPC 通过 preload 的 send 通道发送
 */

import React, { useCallback } from 'react';
import { useUiLayoutStore } from '../../stores/ui-layout.store';
import { IPC_CHANNELS } from '../../../shared/constants';
import styles from './WindowControls.module.css';

export const WindowControls: React.FC = React.memo(() => {
  // 监听右侧栏收起状态来决定配色
  const rightSidebarCollapsed = useUiLayoutStore(s => s.rightSidebarCollapsed);

  // 右侧栏展开态 → 浅色背景+深色图标；收起态 → 深色背景+浅色图标
  const isExpanded = !rightSidebarCollapsed;

  const handleMinimize = useCallback(() => {
    window.electronAPI?.send(IPC_CHANNELS.WINDOW_MINIMIZE);
  }, []);

  const handleMaximize = useCallback(() => {
    window.electronAPI?.send(IPC_CHANNELS.WINDOW_MAXIMIZE);
  }, []);

  const handleClose = useCallback(() => {
    window.electronAPI?.send(IPC_CHANNELS.WINDOW_CLOSE);
  }, []);

  return (
    <div
      className={styles.container}
      data-expanded={isExpanded}
      aria-label="窗口控制"
    >
      <button
        className={styles.btn}
        onClick={handleMinimize}
        aria-label="最小化窗口"
        title="最小化"
      >
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
          <rect x="2" y="5.5" width="8" height="1" stroke="currentColor" strokeWidth="1.2" />
        </svg>
      </button>
      <button
        className={styles.btn}
        onClick={handleMaximize}
        aria-label="最大化/还原窗口"
        title="最大化"
      >
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
          <rect x="2" y="2" width="8" height="8" rx="1" stroke="currentColor" strokeWidth="1.2" />
        </svg>
      </button>
      <button
        className={`${styles.btn} ${styles.closeBtn}`}
        onClick={handleClose}
        aria-label="关闭窗口"
        title="关闭"
      >
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none">
          <path d="M3 3L9 9M9 3L3 9" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
        </svg>
      </button>
    </div>
  );
});

WindowControls.displayName = 'WindowControls';
