import React, { useEffect, useCallback } from 'react';
import { useSessionStore } from '../stores/session.store';

function groupByDate(sessions: { id: string; title: string; createdAt: number | string; updatedAt: number | string; lastMessage?: string }[]) {
  const now = new Date();
  const todayStr = now.toISOString().slice(0, 10);
  const yesterdayStr = new Date(now.getTime() - 86400000).toISOString().slice(0, 10);

  const toDateStr = (v: number | string): string => {
    if (typeof v === 'number') return new Date(v).toISOString().slice(0, 10);
    return v.slice(0, 10);
  };

  const groups: { label: string; sessions: typeof sessions }[] = [];
  const todaySessions = sessions.filter(s => toDateStr(s.createdAt) === todayStr);
  const yesterdaySessions = sessions.filter(s => toDateStr(s.createdAt) === yesterdayStr);
  const earlierSessions = sessions.filter(s => {
    const d = toDateStr(s.createdAt);
    return d !== todayStr && d !== yesterdayStr;
  });

  if (todaySessions.length) groups.push({ label: '今天', sessions: todaySessions });
  if (yesterdaySessions.length) groups.push({ label: '昨天', sessions: yesterdaySessions });
  if (earlierSessions.length) groups.push({ label: '更早', sessions: earlierSessions });
  return groups;
}

export function SessionSidebar({ collapsed }: { collapsed: boolean }): React.ReactElement {
  const { sessions, currentSessionId, loadSessions, createSession, deleteSession, switchSession } = useSessionStore();

  useEffect(() => {
    loadSessions();
  }, [loadSessions]);

  const groups = groupByDate(sessions);

  const handleDelete = useCallback(async (e: React.MouseEvent, sessionId: string) => {
    e.stopPropagation();
    if (sessions.length <= 1) return;
    await deleteSession(sessionId);
  }, [sessions.length, deleteSession]);

  return (
    <aside className="flex flex-col h-full bg-gray-900 border-r border-gray-800">
      <div className="p-3 border-b border-gray-800">
        <button
          onClick={createSession}
          className="w-full py-2 px-3 bg-blue-600 hover:bg-blue-500 text-white text-sm font-medium rounded-lg transition-colors flex items-center justify-center gap-1.5"
        >
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <line x1="12" y1="5" x2="12" y2="19" /><line x1="5" y1="12" x2="19" y2="12" />
          </svg>
          {!collapsed && <span>新会话</span>}
        </button>
      </div>

      <div className="flex-1 overflow-y-auto px-2 py-1">
        {groups.map(group => (
          <div key={group.label}>
            {!collapsed && (
              <div className="text-xs text-gray-500 uppercase tracking-wider px-2 py-2">{group.label}</div>
            )}
            {group.sessions.map(session => (
              <div
                key={session.id}
                onClick={() => switchSession(session.id)}
                className={`flex items-center gap-2 px-3 py-2 rounded-lg cursor-pointer transition-colors group ${
                  session.id === currentSessionId
                    ? 'bg-blue-900/30 text-blue-300 border-l-2 border-blue-500'
                    : 'text-gray-400 hover:bg-gray-800 hover:text-gray-200'
                }`}
              >
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" className="flex-shrink-0">
                  <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
                </svg>
                {!collapsed && (
                  <>
                    <span className="text-sm truncate flex-1">{session.title}</span>
                    <button
                      onClick={(e) => handleDelete(e, session.id)}
                      className="opacity-0 group-hover:opacity-100 w-5 h-5 flex items-center justify-center rounded hover:bg-red-900/50 text-gray-500 hover:text-red-400 text-xs transition-opacity flex-shrink-0"
                    >✕</button>
                  </>
                )}
              </div>
            ))}
          </div>
        ))}
      </div>
    </aside>
  );
}
