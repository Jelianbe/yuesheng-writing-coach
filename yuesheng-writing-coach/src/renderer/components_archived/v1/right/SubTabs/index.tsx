/**
 * SubTabs — 子标签栏
 *
 * 显示 usePanelSessionStore.sessions 中当前面板类型对应的 session。
 * 当前激活 session 高亮，点击切换 session（调用 usePanelSessionStore.switchSession）。
 * 每个 tab 显示图标 + 标题 + 关闭按钮（×）。
 * 无 session 时不渲染。
 *
 * 用法:
 * ```tsx
 * <SubTabs />
 * ```
 */
import { useCallback } from 'react';
import { usePanelSessionStore } from '@/stores/panel-session.store';
import styles from './index.module.css';

export function SubTabs(): JSX.Element | null {
  const sessions = usePanelSessionStore((s) => s.sessions);
  const activeSessionId = usePanelSessionStore((s) => s.activeSessionId);
  const switchSession = usePanelSessionStore((s) => s.switchSession);
  const removeSession = usePanelSessionStore((s) => s.removeSession);

  const handleTabClick = useCallback(
    (id: string) => {
      switchSession(id);
    },
    [switchSession],
  );

  const handleClose = useCallback(
    (e: React.MouseEvent, id: string) => {
      e.stopPropagation();
      removeSession(id);
    },
    [removeSession],
  );

  if (sessions.length === 0) {
    return null;
  }

  return (
    <nav className={styles.bar} role="tablist" aria-label="会话子标签">
      {sessions.map((session) => {
        const isActive = session.id === activeSessionId;
        return (
          <button
            key={session.id}
            className={[
              styles.tab,
              isActive ? styles.tabActive : '',
            ]
              .filter(Boolean)
              .join(' ')}
            onClick={() => handleTabClick(session.id)}
            role="tab"
            aria-selected={isActive}
            type="button"
            title={session.title}
          >
            {session.icon ? (
              <span className={styles.tabIcon} aria-hidden="true">{session.icon}</span>
            ) : null}
            <span className={styles.tabTitle}>{session.title}</span>
            <button
              className={styles.closeBtn}
              onClick={(e) => handleClose(e, session.id)}
              type="button"
              aria-label={`关闭 ${session.title}`}
            >
              {'\u00D7'}
            </button>
          </button>
        );
      })}
    </nav>
  );
}
