import React, { useRef, useEffect } from 'react';
import { X, Plus, Minimize2, Minus, Maximize } from 'lucide-react';
import { getAllWorkspaces, type WorkspaceId } from '../../../registry/workspace-registry';
import styles from './index.module.css';

interface ToolTabsProps {
  openTools: WorkspaceId[];
  activeToolId: WorkspaceId | null;
  onSetActive: (id: WorkspaceId) => void;
  onCloseTool: (id: WorkspaceId) => void;
  onAddTool: () => void;
  onCollapse: () => void;
  addBtnRef: React.RefObject<HTMLButtonElement | null>;
}

export const ToolTabs: React.FC<ToolTabsProps> = ({
  openTools,
  activeToolId,
  onSetActive,
  onCloseTool,
  onAddTool,
  onCollapse,
  addBtnRef,
}) => {
  const toolTabsRef = useRef<HTMLDivElement>(null);
  const allTools = getAllWorkspaces();

  // 非 passive wheel handler（避免 preventDefault 警告）
  useEffect(() => {
    const el = toolTabsRef.current;
    if (!el) return;
    const onWheel = (e: WheelEvent) => {
      if (e.deltaX !== 0) return;
      el.scrollLeft += e.deltaY;
      e.preventDefault();
    };
    el.addEventListener('wheel', onWheel, { passive: false });
    return () => el.removeEventListener('wheel', onWheel);
  }, []);

  return (
    <div className={styles.rightHdr}>
      <div
        ref={toolTabsRef}
        className={styles.toolTabs}
        id="toolTabs"
      >
        {openTools.length > 0 ? (
          openTools.map(tId => {
            const tool = allTools.find(x => x.id === tId);
            const active = tId === activeToolId;
            return (
              <div
                key={tId}
                className={`${styles.tab} ${active ? styles.tabActive : ''}`}
                onClick={() => onSetActive(tId)}
              >
                <span className={styles.tabLabel}>{tool?.name ?? tId}</span>
                <span
                  className={styles.tabCloseBtn}
                  onClick={e => { e.stopPropagation(); onCloseTool(tId); }}
                ><X size={10} /></span>
              </div>
            );
          })
        ) : (
          <span className={styles.emptyHint}>从下方打开工具</span>
        )}
      </div>

      <div className={styles.rightActions}>
        <button ref={addBtnRef as React.Ref<HTMLButtonElement>} className={styles.actionBtn} aria-label="添加工具" onClick={onAddTool}><Plus size={14} /></button>
        <button className={styles.actionBtn} aria-label="收起面板" onClick={onCollapse}><Minimize2 size={14} /></button>
        <button className={styles.actionBtn} aria-label="最小化"><Minus size={14} /></button>
        <button className={styles.actionBtn} aria-label="缩放"><Maximize size={14} /></button>
        <button className={`${styles.actionBtn} ${styles.actionBtnDanger}`} aria-label="关闭"><X size={14} /></button>
      </div>
    </div>
  );
};
