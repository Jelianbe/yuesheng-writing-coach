import React from 'react';
import { Minus, Square, X, PanelRightClose, PanelRightOpen, Plus, Settings } from 'lucide-react';
import { useDrawerStore } from '../../stores/drawer.store';
import { useSessionStore } from '../../stores/session.store';
import { useRightPanelStore } from '../../stores';
import styles from './WindowControls.module.css';

/**
 * WindowControls — 窗口控制按钮（[＋][⚙][⤢][─][□][✕]）
 *
 * 设计文档要求：
 * - position: fixed 最高层级
 * - 始终显示在窗口右上角
 * - 按钮序列：[＋][⚙][][─][□][✕]
 */
export const WindowControls: React.FC = React.memo(() => {
  const collapsed = useDrawerStore(s => s.collapsed);
  const activePanel = useDrawerStore(s => s.activePanel);
  const toggleCollapsed = useDrawerStore(s => s.toggleCollapsed);
  const isRightExpanded = !collapsed && activePanel !== null;

  const handleTogglePanel = () => {
    toggleCollapsed();
  };

  const handleNewChat = async () => {
    const s = await useSessionStore.getState().createSession();
    if (s) await useSessionStore.getState().switchSession(s.id);
  };

  const handleOpenSettings = () => {
    useRightPanelStore.getState().switchTo('__settings__');
  };

  const handleMinimize = () => {
    window.electronAPI?.send('window:minimize');
  };

  const handleMaximize = () => {
    window.electronAPI?.send('window:maximize');
  };

  const handleClose = () => {
    window.electronAPI?.send('window:close');
  };

  return (
    <div
      className={styles.container}
      data-expanded={isRightExpanded}
      role="group"
      aria-label="窗口控制"
    >
      {/* [＋] 新建对话 */}
      <button
        onClick={handleNewChat}
        className={styles.btn}
        title="新建对话"
        aria-label="新建对话"
      >
        <Plus size={14} strokeWidth={1.5} />
      </button>

      {/* [] 设置 */}
      <button
        onClick={handleOpenSettings}
        className={styles.btn}
        title="打开设置"
        aria-label="打开设置"
      >
        <Settings size={14} strokeWidth={1.5} />
      </button>

      {/* [] 右侧栏缩放按钮 */}
      <button
        onClick={handleTogglePanel}
        className={styles.btn}
        aria-label={isRightExpanded ? '收起面板' : '展开面板'}
      >
        {isRightExpanded
          ? <PanelRightClose size={14} strokeWidth={1.5} />
          : <PanelRightOpen size={14} strokeWidth={1.5} />
        }
      </button>

      {/* [─] 最小化 */}
      <button
        onClick={handleMinimize}
        className={styles.btn}
        aria-label="最小化"
      >
        <Minus size={12} strokeWidth={1.5} />
      </button>

      {/* [□] 最大化 */}
      <button
        onClick={handleMaximize}
        className={styles.btn}
        aria-label="最大化"
      >
        <Square size={12} strokeWidth={1.5} />
      </button>

      {/* [✕] 关闭 */}
      <button
        onClick={handleClose}
        className={`${styles.btn} ${styles.closeBtn}`}
        aria-label="关闭"
      >
        <X size={12} strokeWidth={1.5} />
      </button>
    </div>
  );
});

WindowControls.displayName = 'WindowControls';
