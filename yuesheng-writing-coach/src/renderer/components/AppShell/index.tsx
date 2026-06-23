import React, { useCallback } from 'react';
import { Plus, Settings, Maximize2, Minus, Square, X } from 'lucide-react';
import { LeftPanel } from '../left/LeftPanel';
import { CenterPanel } from '../center/CenterPanel';
import { RightPanel } from '../right/RightPanel';
import { useRightToolsStore } from '../../stores/right-tools.store';
import { usePanelBusBridge } from '../../bus/panel-bus-bridge';
import styles from './index.module.css';

export const AppShell: React.FC = () => {
  // X-01: 挂载全局 panel-bus 路由
  usePanelBusBridge();

  const [collapsedLeft, setCollapsedLeft] = React.useState(false);
  const [collapsedRight, setCollapsedRight] = React.useState(false);
  const [leftWidth, setLeftWidth] = React.useState(220);
  const [rightWidth, setRightWidth] = React.useState(360);
  const [dragging, setDragging] = React.useState<'left' | 'right' | null>(null);

  const handleMouseDown = (side: 'left' | 'right') => (_e: React.MouseEvent) => {
    // 注：React 17+ mousedown 事件在 document 级别会被标记为 passive，
    // 此处调用 preventDefault 会触发 "Unable to preventDefault inside passive event listener" 警告。
    // 由于 mousedown 不需要阻止默认行为（不会触发滚动/缩放），直接省略。
    setDragging(side);
  };

  React.useEffect(() => {
    if (!dragging) return;
    const handleMove = (e: MouseEvent) => {
      if (dragging === 'left') {
        setLeftWidth(Math.max(160, Math.min(400, e.clientX)));
      } else {
        setRightWidth(Math.max(260, Math.min(600, window.innerWidth - e.clientX)));
      }
    };
    const handleUp = () => setDragging(null);
    window.addEventListener('mousemove', handleMove);
    window.addEventListener('mouseup', handleUp);
    return () => {
      window.removeEventListener('mousemove', handleMove);
      window.removeEventListener('mouseup', handleUp);
    };
  }, [dragging]);

  const rootClasses = [
    styles.root,
    dragging ? styles.dragging : '',
  ].filter(Boolean).join(' ');

  // ── collapsed bar 按钮 ──
  const openTool = useRightToolsStore(s => s.openTool);
  const handleExpand = useCallback(() => setCollapsedRight(false), []);
  const handleAdd = useCallback(() => setCollapsedRight(false), []);
  const handleSettings = useCallback(() => {
    setCollapsedRight(false);
    openTool('__settings__');
  }, [openTool]);

  return (
    <div className={rootClasses}>
      {/* ── Left Panel ── */}
      <aside
        className={styles.panelTrans}
        style={{
          width: collapsedLeft ? 0 : leftWidth,
          minWidth: collapsedLeft ? 0 : 160,
          overflow: 'hidden',
          flexShrink: 0,
        }}
      >
        {!collapsedLeft && <LeftPanel collapsed={collapsedLeft} setCollapsed={setCollapsedLeft} />}
      </aside>

      {!collapsedLeft && (
        <div
          className={styles.resizeHandle}
          data-side="left"
          onMouseDown={handleMouseDown('left')}
          title="拖拽调整左栏宽度"
        />
      )}

      {/* ── Center Panel ── */}
      <main className={`flex-1 flex flex-col min-w-0 ${styles.centerPanel}`}>
        <CenterPanel
          collapsedLeft={collapsedLeft}
          setCollapsedLeft={setCollapsedLeft}
        />
      </main>

      {/* ── Collapsed right bar ── */}
      {collapsedRight && (
        <div className={styles.collapsedBar}>
          <button className={styles.collapsedBarBtn} title="新建标签" onClick={handleAdd} aria-label="新建标签"><Plus size={16} /></button>
          <button className={styles.collapsedBarBtn} title="设置" onClick={handleSettings} aria-label="设置"><Settings size={16} /></button>
          <div className={styles.collapsedBarSep} />
          <button className={styles.collapsedBarBtn} title="展开面板" onClick={handleExpand} aria-label="展开面板"><Maximize2 size={16} /></button>
          <button className={styles.collapsedBarBtn} title="最小化" onClick={() => window.electronAPI?.send('window:minimize')} aria-label="最小化"><Minus size={16} /></button>
          <button className={styles.collapsedBarBtn} title="缩放" onClick={() => window.electronAPI?.send('window:maximize')} aria-label="缩放"><Square size={16} /></button>
          <button className={`${styles.collapsedBarBtn} ${styles.collapsedBarBtnDanger}`} title="关闭" onClick={() => window.electronAPI?.send('window:close')} aria-label="关闭"><X size={16} /></button>
        </div>
      )}

      {/* ── Right Panel ── */}
      <div
        className={styles.resizeHandle}
        data-side="right"
        onMouseDown={collapsedRight ? undefined : handleMouseDown('right')}
        title={collapsedRight ? '' : '拖拽调整右栏宽度'}
        style={collapsedRight ? { display: 'none' } : undefined}
      />

      <aside
        className={styles.panelTrans}
        style={{
          width: collapsedRight ? 0 : rightWidth,
          minWidth: collapsedRight ? 0 : 260,
          overflow: 'hidden',
          flexShrink: 0,
          borderLeft: collapsedRight ? 'transparent' : '1px solid #D6CEC0',
        }}
      >
        <RightPanel setCollapsedRight={setCollapsedRight} />
      </aside>
    </div>
  );
};
