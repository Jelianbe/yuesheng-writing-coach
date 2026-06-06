import React, { useState } from 'react';
import {
  MessageSquare,
  Dumbbell,
  Plus,
  Search,
  Trash2,
  ChevronRight,
  MessageCircle,
} from 'lucide-react';
import { Button } from '../common/Button';
import { TeachingPhase } from '../../shared/constants';
import type { Session } from '../../shared/types';

export type SidebarPage = 'chat' | 'tasks';

interface SidebarProps {
  currentPage: SidebarPage;
  onPageChange: (page: SidebarPage) => void;
  sessions: Session[];
  activeSessionId: string | null;
  onSessionSelect: (sessionId: string) => void;
  onNewSession: () => void;
  onDeleteSession: (sessionId: string) => void;
  isOpen: boolean;
  onClose?: () => void;
}

const phaseLabels: Record<TeachingPhase, string> = {
  [TeachingPhase.INIT]: '初次见面',
  [TeachingPhase.WORLD]: '世界观搭建',
  [TeachingPhase.PRACTICE_LOOP]: '诊断-训练',
  [TeachingPhase.REVIEW]: '复盘总结',
};

const getSessionPhase = (session: Session): TeachingPhase | null => {
  const msg = session.messages.find((m) => m.role === 'assistant' && m.diagnosis);
  if (!msg?.diagnosis) return null;
  return TeachingPhase.PRACTICE_LOOP;
};

export const Sidebar: React.FC<SidebarProps> = ({
  currentPage,
  onPageChange,
  sessions,
  activeSessionId,
  onSessionSelect,
  onNewSession,
  onDeleteSession,
  isOpen,
  onClose,
}) => {
  const [searchQuery, setSearchQuery] = useState('');

  const filteredSessions = sessions.filter((s) =>
    s.title.toLowerCase().includes(searchQuery.toLowerCase())
  );

  const navItems: { id: SidebarPage; label: string; icon: React.ReactNode }[] = [
    { id: 'chat', label: '对话', icon: <MessageSquare className="w-5 h-5" /> },
    { id: 'tasks', label: '训练任务', icon: <Dumbbell className="w-5 h-5" /> },
  ];

  return (
    <>
      {/* Overlay for mobile */}
      {isOpen && onClose && (
        <div
          className="fixed inset-0 bg-black/20 z-20 lg:hidden animate-fade-in"
          onClick={onClose}
          aria-hidden="true"
        />
      )}

      <aside
        className={[
          'flex flex-col bg-bg-secondary border-r border-border h-full',
          'w-sidebar flex-shrink-0',
          'transition-transform duration-slide',
          isOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0',
          'fixed lg:relative z-30 lg:z-auto',
        ].join(' ')}
        role="navigation"
        aria-label="Sidebar navigation"
      >
        {/* Navigation tabs */}
        <div className="flex border-b border-border flex-shrink-0">
          {navItems.map((item) => (
            <button
              key={item.id}
              onClick={() => onPageChange(item.id)}
              className={[
                'flex-1 flex items-center justify-center gap-2',
                'py-3 text-small font-medium',
                'transition-colors duration-fast',
                currentPage === item.id
                  ? 'text-accent-primary border-b-2 border-accent-primary bg-accent-primary-light/30'
                  : 'text-text-secondary hover:bg-bg-tertiary hover:text-text-primary',
              ].join(' ')}
              role="tab"
              aria-selected={currentPage === item.id}
            >
              {item.icon}
              <span>{item.label}</span>
            </button>
          ))}
        </div>

        {/* Session list (only on chat page) */}
        {currentPage === 'chat' && (
          <>
            {/* Search + New */}
            <div className="p-3 flex gap-2 flex-shrink-0">
              <div className="flex-1 relative">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-text-muted" />
                <input
                  type="text"
                  placeholder="搜索会话"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  className="w-full pl-9 pr-3 py-2 text-small bg-bg-tertiary border border-border rounded-md
                    placeholder:text-text-muted focus:outline-none focus:ring-2 focus:ring-accent-primary/50 focus:border-accent-primary
                    transition-all duration-fast"
                  aria-label="Search sessions"
                />
              </div>
              <Button
                variant="primary"
                size="sm"
                onClick={onNewSession}
                aria-label="New session"
                title="新建会话"
                className="flex-shrink-0"
              >
                <Plus className="w-4 h-4" />
              </Button>
            </div>

            {/* Session items */}
            <div className="flex-1 overflow-y-auto" role="list" aria-label="Session list">
              {filteredSessions.length === 0 ? (
                <div className="px-4 py-8 text-center text-text-muted text-small">
                  {searchQuery ? '未找到匹配的会话' : '暂无会话'}
                </div>
              ) : (
                <ul className="py-1">
                  {filteredSessions.map((session) => {
                    const isActive = session.id === activeSessionId;
                    const phase = getSessionPhase(session);

                    return (
                      <li key={session.id} role="listitem">
                        <div
                          className={[
                            'group flex items-center gap-3 px-3 py-2.5 mx-2 rounded-md cursor-pointer',
                            'transition-all duration-fast',
                            isActive
                              ? 'bg-accent-primary-light text-accent-primary'
                              : 'hover:bg-bg-tertiary text-text-primary',
                          ].join(' ')}
                          onClick={() => onSessionSelect(session.id)}
                          role="button"
                          tabIndex={0}
                          aria-label={`Session: ${session.title}`}
                          aria-current={isActive ? 'true' : undefined}
                          onKeyDown={(e) => {
                            if (e.key === 'Enter' || e.key === ' ') {
                              e.preventDefault();
                              onSessionSelect(session.id);
                            }
                          }}
                        >
                          <MessageCircle className="w-4 h-4 flex-shrink-0 opacity-70" />
                          <div className="flex-1 min-w-0">
                            <p className="text-small font-medium truncate">{session.title}</p>
                            {phase && (
                              <p className="text-tiny opacity-60 mt-0.5">
                                {phaseLabels[phase]}
                              </p>
                            )}
                          </div>
                          <Button
                            variant="icon"
                            size="sm"
                            onClick={(e) => {
                              e.stopPropagation();
                              onDeleteSession(session.id);
                            }}
                            className="opacity-0 group-hover:opacity-100 p-1"
                            aria-label={`Delete session ${session.title}`}
                          >
                            <Trash2 className="w-3.5 h-3.5 text-text-muted hover:text-accent-danger" />
                          </Button>
                        </div>
                      </li>
                    );
                  })}
                </ul>
              )}
            </div>
          </>
        )}

        {/* Tasks page sidebar content */}
        {currentPage === 'tasks' && (
          <div className="flex-1 p-4">
            <p className="text-small text-text-secondary">
              在这里查看和完成写作训练任务。
            </p>
            <div className="mt-4 p-3 bg-bg-tertiary rounded-md">
              <p className="text-small text-text-muted">
                完成任务后，系统会自动更新你的能力画像。
              </p>
            </div>
          </div>
        )}
      </aside>
    </>
  );
};

// Usage example:
// <Sidebar
//   currentPage="chat"
//   onPageChange={setPage}
//   sessions={sessions}
//   activeSessionId={activeId}
//   onSessionSelect={handleSelect}
//   onNewSession={handleNew}
//   onDeleteSession={handleDelete}
//   isOpen={sidebarOpen}
//   onClose={() => setSidebarOpen(false)}
// />
