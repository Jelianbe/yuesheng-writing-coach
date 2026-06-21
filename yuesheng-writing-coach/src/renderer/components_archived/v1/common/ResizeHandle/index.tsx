/**
 * ResizeHandle — 可拖拽的面板分隔条
 *
 * 在左栏/中栏（side='left'）或中栏/右栏（side='right'）之间放置。
 * 内部使用 useUiLayoutStore 实现拖拽调整宽度。
 *
 * 用法:
 * ```tsx
 * <ResizeHandle side="left" />
 * <ResizeHandle side="right" />
 * ```
 */
import { useCallback, useRef } from 'react';
import { useUiLayoutStore } from '@/stores/ui-layout.store';
import styles from './index.module.css';

interface ResizeHandleProps {
  side: 'left' | 'right';
}

export function ResizeHandle({ side }: ResizeHandleProps): JSX.Element {
  const startResize = useUiLayoutStore((s) => s.startResize);
  const endResize = useUiLayoutStore((s) => s.endResize);
  const resizing = useUiLayoutStore((s) => s.resizing);
  const setSidebarWidth = useUiLayoutStore((s) => s.setSidebarWidth);
  const setRightPanelWidth = useUiLayoutStore((s) => s.setRightPanelWidth);
  const targetRef = useRef<HTMLDivElement>(null);

  const target = side === 'left' ? 'sidebar' : 'rightPanel';
  const isActive = resizing === target;

  const handleMouseDown = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    startResize(target);

    const startX = e.clientX;
    const startWidth = side === 'left'
      ? useUiLayoutStore.getState().sidebarWidth
      : useUiLayoutStore.getState().rightPanelWidth;

    const handleMouseMove = (ev: MouseEvent): void => {
      const delta = ev.clientX - startX;
      const newWidth = side === 'left'
        ? startWidth + delta
        : startWidth - delta;
      if (side === 'left') {
        setSidebarWidth(newWidth);
      } else {
        setRightPanelWidth(newWidth);
      }
    };

    const handleMouseUp = (): void => {
      endResize();
      document.removeEventListener('mousemove', handleMouseMove);
      document.removeEventListener('mouseup', handleMouseUp);
      document.body.style.cursor = '';
      document.body.style.userSelect = '';
    };

    document.addEventListener('mousemove', handleMouseMove);
    document.addEventListener('mouseup', handleMouseUp);
    document.body.style.cursor = 'col-resize';
    document.body.style.userSelect = 'none';
  }, [side, target, startResize, endResize, setSidebarWidth, setRightPanelWidth]);

  return (
    <div
      ref={targetRef}
      className={`${styles.handle} ${side === 'left' ? styles.handleLeft : styles.handleRight} ${isActive ? styles.handleActive : ''}`}
      onMouseDown={handleMouseDown}
      role="separator"
      aria-orientation="vertical"
      aria-label={`调整${side === 'left' ? '左侧' : '右侧'}面板宽度`}
    />
  );
}
