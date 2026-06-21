import React, { useCallback, useRef } from 'react';
import styles from './index.module.css';

export interface SubTabItem {
  id: string;
  label: string;
}

interface SubTabsProps {
  items: SubTabItem[];
  activeId: string | null;
  onSelect: (id: string) => void;
  onClose: (id: string) => void;
  emptyHint?: string;
  showAddBtn?: boolean;
  addBtnTitle?: string;
  onAddBtnClick?: () => void;
}

export const SubTabs: React.FC<SubTabsProps> = ({
  items,
  activeId,
  onSelect,
  onClose,
  emptyHint = '',
  showAddBtn = false,
  addBtnTitle = '',
  onAddBtnClick,
}) => {
  const containerRef = useRef<HTMLDivElement>(null);

  const handleWheel = useCallback((e: React.WheelEvent<HTMLDivElement>) => {
    if (e.deltaX !== 0) return;
    e.currentTarget.scrollLeft += e.deltaY;
    e.preventDefault();
  }, []);

  return (
    <div className={styles.rightSubHdr} id="rightSubHdr">
      <div
        ref={containerRef}
        className={styles.subTabs}
        id="subTabs"
        onWheel={handleWheel}
      >
        {items.length > 0 ? (
          items.map(item => {
            const isActive = activeId === item.id;
            return (
              <span
                key={item.id}
                className={`${styles.subTab} ${isActive ? styles.subTabActive : ''}`}
                onClick={() => onSelect(item.id)}
              >
                <span className={styles.subTabLabel}>{item.label}</span>
                <span
                  className={styles.subTabClose}
                  onClick={(e) => { e.stopPropagation(); onClose(item.id); }}
                >✕</span>
              </span>
            );
          })
        ) : (
          <span className={styles.subEmptyHint}>{emptyHint}</span>
        )}
      </div>
      {showAddBtn && onAddBtnClick && (
        <button className={styles.subAddBtn} id="subAddBtn" title={addBtnTitle} onClick={onAddBtnClick}>＋</button>
      )}
    </div>
  );
};
