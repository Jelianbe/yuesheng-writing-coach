/**
 * InputToolbar — 输入框上方工具栏 (RWR-P1-3)
 *
 * 规格 DoD: 按钮从左到右 [模板] [工具] [+] [][⤢] [─]
 * 6 个按钮,中间 2 个为占位(空按钮)
 *
 * 设计:
 * - 与输入框平齐的横向工具栏
 * - 各按钮独立 click handler
 * - 占位按钮渲染为不可点击的 spacer
 */

import React, { useCallback } from 'react';
import { FileText, Wrench, Plus, Maximize2, Minus } from 'lucide-react';
import styles from '../../styles/InputToolbar.module.css';

export interface InputToolbarProps {
  /** 点击"模板"按钮 */
  onTemplate?: () => void;
  /** 点击"工具"按钮 */
  onTool?: () => void;
  /** 点击"+"按钮(添加附件/上传) */
  onAdd?: () => void;
  /** 点击"⤢"按钮(全屏输入区) */
  onMaximize?: () => void;
  /** 点击"─"按钮(收起输入区) */
  onCollapse?: () => void;
}

export const InputToolbar: React.FC<InputToolbarProps> = ({
  onTemplate,
  onTool,
  onAdd,
  onMaximize,
  onCollapse,
}) => {
  return (
    <div className={styles.toolbar} role="toolbar" aria-label="输入区工具栏">
      <ToolbarButton icon={<FileText size={13} strokeWidth={1.6} />} label="模板" onClick={onTemplate} />
      <ToolbarButton icon={<Wrench size={13} strokeWidth={1.6} />} label="工具" onClick={onTool} />
      <ToolbarButton icon={<Plus size={13} strokeWidth={1.8} />} label="添加" onClick={onAdd} />
      {/* 占位: 第 4 个按钮位置预留 */}
      <div className={styles.spacer} aria-hidden="true" />
      <ToolbarButton icon={<Maximize2 size={13} strokeWidth={1.6} />} label="全屏" onClick={onMaximize} />
      <ToolbarButton icon={<Minus size={13} strokeWidth={1.6} />} label="收起" onClick={onCollapse} />
    </div>
  );
};

/** 单个工具栏按钮 */
const ToolbarButton: React.FC<{
  icon: React.ReactNode;
  label: string;
  onClick?: () => void;
}> = ({ icon, label, onClick }) => {
  const handleClick = useCallback(() => {
    onClick?.();
  }, [onClick]);

  return (
    <button
      type="button"
      onClick={handleClick}
      className={styles.btn}
      aria-label={label}
      title={label}
    >
      {icon}
    </button>
  );
};
