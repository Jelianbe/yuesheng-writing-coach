import React, { useCallback, useRef } from 'react';
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

  const handleWheel = useCallback((e: React.WheelEvent<HTMLDivElement>) => {
    if (e.deltaX !== 0) return;
    e.currentTarget.scrollLeft += e.deltaY;
    e.preventDefault();
  }, []);

  return (
    <div className={styles.rightHdr}>
      <div
        ref={toolTabsRef}
        className={styles.toolTabs}
        id="toolTabs"
        onWheel={handleWheel}
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
                >✕</span>
              </div>
            );
          })
        ) : (
          <span className={styles.emptyHint}>从下方打开工具</span>
        )}
      </div>

      <div className={styles.rightActions}>
        <button ref={addBtnRef as React.Ref<HTMLButtonElement>} className={styles.actionBtn} title="添加工具" onClick={onAddTool}>＋</button>
        <button className={styles.actionBtn} title="收起面板" onClick={onCollapse}>⤢</button>
        <button className={styles.actionBtn} title="最小化">─</button>
        <button className={styles.actionBtn} title="缩放">□</button>
        <button className={`${styles.actionBtn} ${styles.actionBtnDanger}`} title="关闭">✕</button>
      </div>
    </div>
  );
};
