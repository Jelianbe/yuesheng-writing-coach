import React from 'react';

/** 会话项（扁平数据结构，不依赖 Session 类型） */
export interface SessionItem {
  id: string;
  title: string;
  tags: string[];
  timeAgo: string;
}

export interface AppSidebarProps {
  /** 会话列表 */
  sessions: SessionItem[];
  /** 当前激活的会话 ID */
  activeSessionId: string;
  /** 选择会话回调 */
  onSelectSession: (id: string) => void;
  /** 新建会话回调 */
  onNewSession: () => void;
  /** 进入训练工坊回调 */
  onEnterWorkshop?: () => void;
  /** 是否折叠 */
  collapsed: boolean;
  /** 折叠切换回调 */
  onToggleCollapse: () => void;
}

export const AppSidebar: React.FC<AppSidebarProps> = React.memo(({
  sessions,
  activeSessionId,
  onSelectSession,
  onNewSession,
  onEnterWorkshop,
  collapsed,
  onToggleCollapse,
}) => {
  return (
    <aside
      style={{
        flex: collapsed ? '0 0 56px' : '0 1 280px',
        width: collapsed ? '56px' : undefined,
        minWidth: collapsed ? '56px' : '180px',
        maxWidth: collapsed ? '56px' : '340px',
        background: 'var(--bg-sidebar)',
        borderRight: '1px solid var(--border)',
        display: 'flex',
        flexDirection: 'column',
        overflow: 'visible',
        transition: 'flex 0.4s cubic-bezier(0.34, 1.56, 0.64, 1), width 0.4s cubic-bezier(0.34, 1.56, 0.64, 1), min-width 0.4s cubic-bezier(0.34, 1.56, 0.64, 1), max-width 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)',
        position: 'relative',
        zIndex: 50,
      }}
      role="navigation"
      aria-label="Sidebar navigation"
    >
      {/* Toggle button */}
      <button
        onClick={onToggleCollapse}
        style={{
          position: 'absolute',
          right: -20,
          top: 80,
          width: 39,
          height: 39,
          background: 'var(--bg-card)',
          border: '1px solid var(--border)',
          borderRadius: '50%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          cursor: 'pointer',
          zIndex: 100,
          transition: 'all 0.4s cubic-bezier(0.34, 1.56, 0.64, 1)',
          color: 'var(--text-tertiary)',
          fontSize: '0.85rem',
          boxShadow: 'var(--shadow-md)',
          transform: collapsed ? 'rotate(180deg)' : 'rotate(0deg)',
        }}
        title={collapsed ? '展开侧边栏' : '折叠侧边栏'}
        aria-label={collapsed ? '展开侧边栏' : '折叠侧边栏'}
      >
        ▸
      </button>

      {/* Sidebar header: new session + training workshop buttons */}
      <div
        style={{
          padding: collapsed ? '16px 10px' : '16px 14px',
          borderBottom: '1px solid var(--border)',
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: collapsed ? 8 : 8,
        }}
      >
        <button
          onClick={onNewSession}
          style={{
            width: collapsed ? 36 : '100%',
            height: collapsed ? 36 : undefined,
            padding: collapsed ? 0 : '10px 16px',
            border: 'none',
            borderRadius: 'var(--radius-md)',
            background: 'var(--accent)',
            color: 'var(--text-on-accent)',
            fontFamily: 'var(--font-body)',
            fontSize: '0.85rem',
            fontWeight: 500,
            cursor: 'pointer',
            transition: 'all 0.2s ease',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            gap: 6,
            boxShadow: 'var(--shadow-md)',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
          }}
          title="新建会话"
          aria-label="新建会话"
        >
          {collapsed ? (
            <span style={{ fontSize: '1.2rem', fontWeight: 500 }}>+</span>
          ) : (
            <span>+ 新建会话</span>
          )}
        </button>
        {onEnterWorkshop && (
          <button
            onClick={onEnterWorkshop}
            style={{
              width: collapsed ? 36 : '100%',
              height: collapsed ? 36 : undefined,
              padding: collapsed ? 0 : '8px 16px',
              border: '1px solid var(--border)',
              borderRadius: 'var(--radius-md)',
              background: 'transparent',
              color: 'var(--text-primary)',
              fontFamily: 'var(--font-body)',
              fontSize: '0.82rem',
              fontWeight: 500,
              cursor: 'pointer',
              transition: 'all 0.2s ease',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'center',
              gap: 6,
              whiteSpace: 'nowrap',
              overflow: 'hidden',
            }}
            title="训练工坊"
            aria-label="训练工坊"
            onMouseEnter={(e) => {
              (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)';
            }}
            onMouseLeave={(e) => {
              (e.currentTarget as HTMLElement).style.background = 'transparent';
            }}
          >
            {collapsed ? (
              <span style={{ fontSize: '1rem' }}></span>
            ) : (
              <span>🎯 训练工坊</span>
            )}
          </button>
        )}
      </div>

      {/* Section label */}
      {!collapsed && (
        <div
          style={{
            padding: '12px 14px 6px',
            fontSize: '0.72rem',
            fontWeight: 600,
            textTransform: 'uppercase',
            letterSpacing: '0.5px',
            color: 'var(--text-tertiary)',
            whiteSpace: 'nowrap',
            overflow: 'hidden',
          }}
        >
          最近会话
        </div>
      )}

      {/* Session list */}
      <div
        style={{
          flex: 1,
          overflowY: collapsed ? 'hidden' : 'auto',
          padding: '4px 10px 10px',
        }}
        role="list"
        aria-label="Session list"
      >
        {sessions.length === 0 ? (
          !collapsed && (
            <div
              style={{
                padding: '20px 10px',
                textAlign: 'center',
                color: 'var(--text-tertiary)',
                fontSize: '0.8rem',
              }}
            >
              暂无会话
            </div>
          )
        ) : (
          sessions.map((session) => {
            const isActive = session.id === activeSessionId;

            return (
              <div
                key={session.id}
                onClick={() => onSelectSession(session.id)}
                role="button"
                tabIndex={0}
                aria-label={`Session: ${session.title}`}
                aria-current={isActive ? 'true' : undefined}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    onSelectSession(session.id);
                  }
                }}
                style={{
                  padding: collapsed ? '10px 4px' : '9px 10px',
                  borderRadius: 'var(--radius-md)',
                  cursor: 'pointer',
                  transition: 'all 0.15s ease',
                  marginBottom: 3,
                  display: 'flex',
                  alignItems: collapsed ? 'center' : 'flex-start',
                  justifyContent: collapsed ? 'center' : undefined,
                  gap: collapsed ? undefined : 8,
                  background: isActive ? 'var(--bg-active)' : 'transparent',
                }}
                onMouseEnter={(e) => {
                  if (!isActive) (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)';
                }}
                onMouseLeave={(e) => {
                  if (!isActive) (e.currentTarget as HTMLElement).style.background = 'transparent';
                }}
              >
                {!collapsed ? (
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div
                      style={{
                        fontSize: '0.85rem',
                        fontWeight: 500,
                        color: 'var(--text-primary)',
                        whiteSpace: 'nowrap',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        marginBottom: 2,
                        lineHeight: 1.4,
                      }}
                    >
                      {session.title}
                    </div>
                    <div
                      style={{
                        display: 'flex',
                        justifyContent: 'space-between',
                        alignItems: 'center',
                        fontSize: '0.72rem',
                        color: 'var(--text-tertiary)',
                        gap: 4,
                      }}
                    >
                      <div style={{ display: 'flex', gap: 4, flexWrap: 'wrap' }}>
                        {session.tags.map((tag, i) => (
                          <span
                            key={i}
                            style={{
                              fontSize: '0.65rem',
                              padding: '1px 5px',
                              background: 'var(--border-light)',
                              borderRadius: 'var(--radius-full)',
                              whiteSpace: 'nowrap',
                            }}
                          >
                            {tag}
                          </span>
                        ))}
                      </div>
                      <span>{session.timeAgo}</span>
                    </div>
                  </div>
                ) : (
                  /* Collapsed: dot indicator */
                  <div
                    style={{
                      width: 8,
                      height: 8,
                      borderRadius: '50%',
                      background: isActive ? 'var(--accent)' : 'var(--border)',
                      flexShrink: 0,
                    }}
                  />
                )}
              </div>
            );
          })
        )}
      </div>
    </aside>
  );
});

AppSidebar.displayName = 'AppSidebar';
