/**
 * ConversationsPage — 对话列表
 *
 * 对齐设计稿:
 * - Navbar: "对话历史"
 * - 列表项: 标题 | 消息数 | 时间
 * - 空状态引导
 *
 * 数据来源:useSessionStore.loadSessions → session:listWithMeta
 *   返回字段: title, messageCount, lastMessageAt
 *
 * Sprint 19 PC 改造:顶部 h1 改为"对话历史",避免与 TabBar "对话" tab 重名
 */

import React, { useEffect } from 'react';
import { MessageCircle, Plus } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useSessionStore } from '../stores/session.store';

const formatTime = (ts?: number): string => {
  if (!ts) return '';
  const d = new Date(ts);
  const now = Date.now();
  const diff = now - ts;
  if (diff < 60_000) return '刚刚';
  if (diff < 3_600_000) return `${Math.floor(diff / 60_000)} 分钟前`;
  if (diff < 86_400_000) return `${Math.floor(diff / 3_600_000)} 小时前`;
  if (diff < 7 * 86_400_000) return `${Math.floor(diff / 86_400_000)} 天前`;
  return `${d.getMonth() + 1}/${d.getDate()}`;
};

export const ConversationsPage: React.FC = () => {
  const push = usePageStackStore(s => s.push);
  const { sessions, currentSessionId, loadSessions, createSession, switchSession, loading } = useSessionStore(
    useShallow(s => ({
      sessions: s.sessions,
      currentSessionId: s.currentSessionId,
      loadSessions: s.loadSessions,
      createSession: s.createSession,
      switchSession: s.switchSession,
      loading: s.loading,
    })),
  );

  useEffect(() => {
    void loadSessions();
  }, [loadSessions]);

  const handleCreate = async () => {
    const session = await createSession('新对话');
    if (session) push('chat', { id: session.id, title: session.title });
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <header style={{
        height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 16px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)',
      }}>
        <h1 style={{ fontSize: 18, fontWeight: 600, color: 'var(--text-primary)', margin: 0 }}>
          对话历史
        </h1>
        <button
          type="button"
          aria-label="新建对话"
          onClick={handleCreate}
          style={{ border: 'none', background: 'none', padding: 4, cursor: 'pointer', display: 'flex' }}
        >
          <Plus size={20} color="var(--text-secondary)" strokeWidth={1.5} />
        </button>
      </header>

      {/* 列表 */}
      <div style={{ flex: 1, overflow: 'auto', padding: '8px 16px' }}>
        {loading && sessions.length === 0 ? (
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            height: '100%', color: 'var(--text-tertiary)', fontSize: 13,
          }}>
            加载中…
          </div>
        ) : sessions.length === 0 ? (
          <div style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            justifyContent: 'center', height: '100%', gap: 12,
            color: 'var(--text-tertiary)',
          }}>
            <MessageCircle size={32} strokeWidth={1.5} />
            <div style={{ fontSize: 14 }}>还没有对话记录</div>
            <div style={{ fontSize: 12 }}>点击右上角开始新对话</div>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            {sessions.map(s => (
              <button
                key={s.id}
                type="button"
                onClick={() => {
                  switchSession(s.id);
                  push('chat', { id: s.id, title: s.title });
                }}
                style={{
                  display: 'flex', flexDirection: 'column', gap: 4,
                  padding: '12px 0',
                  cursor: 'pointer', textAlign: 'left',
                  background: s.id === currentSessionId ? 'var(--bg-card)' : 'transparent',
                  border: 'none',
                  borderBottom: '1px solid var(--border)',
                  color: 'inherit', font: 'inherit', width: '100%',
                }}
              >
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                  <span style={{ fontSize: 14, fontWeight: 500, color: 'var(--text-primary)' }}>{s.title}</span>
                  <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                    {formatTime(s.lastMessageAt ?? s.updatedAt)}
                  </span>
                </div>
                <span style={{ fontSize: 11, color: 'var(--text-tertiary)' }}>
                  {s.messageCount ?? 0} 条消息
                </span>
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};
