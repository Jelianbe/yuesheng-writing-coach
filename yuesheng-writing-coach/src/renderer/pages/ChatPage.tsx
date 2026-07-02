/**
 * ChatPage — 教学对话
 *
 * 对齐设计稿:
 * - Navbar: ‹ 返回 + 标题 + 副标题 + ⋯
 * - 欢迎引导区(月头像 + 快捷选项)
 * - 消息气泡(用户/诊断教学/AI思考中)
 * - 输入栏(工具条 + 输入框 + 发送按钮)
 *
 * 数据来源:
 * - useSessionStore 拿 currentSessionId + loadMessages
 * - 消息区渲染真实 session.messages
 * - 发送:Phase C 再接入 chatService (本步仅显示 + 占位)
 */

import React, { useEffect, useState } from 'react';
import { ArrowLeft, Send, Type, Image, FileText, Settings, MessageSquare } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useSessionStore } from '../stores/session.store';
import { MoreMenu } from '../components/navigation/MoreMenu';
import type { ChatMessage } from '../shared/types';

/* ── 欢迎引导区 ── */
const WelcomeGuide: React.FC = () => (
  <div style={{
    display: 'flex', flexDirection: 'column', alignItems: 'center',
    padding: '32px 16px 24px', gap: 16,
  }}>
    <div style={{
      width: 56, height: 56, borderRadius: '50%',
      background: 'linear-gradient(135deg, #8A7A9E, #B8A9D4)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: '#fff', fontSize: 22, fontWeight: 700,
    }}>
      月
    </div>
    <div style={{ fontSize: 15, color: 'var(--text-primary)', fontWeight: 500 }}>
      嘿，今天想从哪里开始？
    </div>
    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', justifyContent: 'center' }}>
      {['分析一下作品', '学点描写技法', '出个题目练练'].map(text => (
        <button
          key={text}
          style={{
            padding: '8px 14px', borderRadius: 20,
            border: '1px solid var(--border)', background: 'var(--bg-card)',
            color: 'var(--text-secondary)', fontSize: 13, cursor: 'pointer',
          }}
        >
          {text}
        </button>
      ))}
    </div>
  </div>
);

/* ── 消息气泡(根据 role 分支) ── */
const MessageBubble: React.FC<{ msg: ChatMessage }> = ({ msg }) => {
  if (msg.role === 'user') {
    return (
      <div style={{ display: 'flex', justifyContent: 'flex-end', padding: '0 16px 8px' }}>
        <div style={{
          maxWidth: '75%', padding: '10px 14px', borderRadius: 12,
          background: 'var(--accent)', color: '#fff', fontSize: 14,
          lineHeight: 1.5, borderBottomRightRadius: 4,
        }}>
          {msg.content}
        </div>
      </div>
    );
  }
  if (msg.role === 'assistant') {
    return (
      <div style={{ display: 'flex', padding: '0 16px 8px' }}>
        <div style={{
          maxWidth: '75%', padding: '10px 14px', borderRadius: 12,
          background: 'var(--bg-card)', color: 'var(--text-primary)',
          border: '1px solid var(--border)',
          fontSize: 14, lineHeight: 1.5, borderBottomLeftRadius: 4,
        }}>
          {msg.content}
        </div>
      </div>
    );
  }
  return null;
};

/* ── 输入栏 ── */
const TOOLBAR_ITEMS = [
  { Icon: Type, label: '文字' },
  { Icon: Image, label: '图片' },
  { Icon: FileText, label: '文档' },
  { Icon: Settings, label: '设定' },
];

const InputBar: React.FC<{ onSend: (text: string) => void; disabled?: boolean }> = ({ onSend, disabled }) => {
  const [text, setText] = useState('');
  const hasContent = text.trim().length > 0;

  const handleSend = () => {
    const t = text.trim();
    if (!t) return;
    onSend(t);
    setText('');
  };

  return (
    <div style={{
      borderTop: '1px solid var(--border)', background: 'var(--bg-card)',
      padding: '8px 12px', paddingBottom: `calc(8px + env(safe-area-inset-bottom, 0px))`,
    }}>
      <div style={{ display: 'flex', gap: 12, marginBottom: 6, paddingLeft: 4 }}>
        {TOOLBAR_ITEMS.map(({ Icon, label }) => (
          <button
            key={label}
            style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4, borderRadius: 6, transition: 'background 150ms' }}
            aria-label={label}
          >
            <Icon size={18} color="var(--text-tertiary)" strokeWidth={1.5} />
          </button>
        ))}
      </div>
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        <input
          value={text}
          onChange={e => setText(e.target.value)}
          onKeyDown={e => { if (e.key === 'Enter' && !e.shiftKey) { e.preventDefault(); handleSend(); } }}
          placeholder="输入你的问题和作品…"
          disabled={disabled}
          style={{
            flex: 1, height: 38, borderRadius: 8, border: 'none',
            background: 'var(--bg-input)', padding: '0 12px',
            fontSize: 13, color: 'var(--text-primary)', outline: 'none',
          }}
        />
        <button
          onClick={handleSend}
          disabled={!hasContent || disabled}
          style={{
            width: 38, height: 38, borderRadius: 8, border: 'none',
            background: hasContent && !disabled ? 'var(--accent)' : 'var(--bg-input)',
            color: hasContent && !disabled ? '#fff' : 'var(--text-tertiary)',
            cursor: hasContent && !disabled ? 'pointer' : 'default',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            transition: 'all 200ms',
          }}
          aria-label="发送"
        >
          <Send size={16} />
        </button>
      </div>
    </div>
  );
};

/* ── 主组件 ── */
export const ChatPage: React.FC<{ params?: Record<string, string> }> = ({ params }) => {
  const pop = usePageStackStore(s => s.pop);
  const push = usePageStackStore(s => s.push);
  const { currentSessionId, loadMessages, switchSession } = useSessionStore(
    useShallow(s => ({
      currentSessionId: s.currentSessionId,
      loadMessages: s.loadMessages,
      switchSession: s.switchSession,
    })),
  );
  const [messages, setLocalMessages] = useState<ChatMessage[]>([]);
  const [loading, setLoading] = useState(false);

  // 进入页面时,若 params.id 提供,切到该 session
  useEffect(() => {
    if (params?.id && params.id !== currentSessionId) {
      switchSession(params.id);
    }
  }, [params?.id, currentSessionId, switchSession]);

  // 切换 session 时加载消息
  useEffect(() => {
    const sid = params?.id ?? currentSessionId;
    if (!sid) return;
    setLoading(true);
    void loadMessages(sid)
      .then(list => setLocalMessages(Array.isArray(list) ? list : []))
      .finally(() => setLoading(false));
  }, [params?.id, currentSessionId, loadMessages]);

  const title = params?.title ?? '对话';
  const handleSend = (text: string) => {
    // Phase C: 接入 chatService.send + 流式响应监听
    // 本步仅本地追加用户消息,演示输入链路通
    setLocalMessages(prev => [...prev, {
      id: `tmp_${Date.now()}`,
      role: 'user',
      content: text,
      timestamp: Date.now(),
    }]);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%' }}>
      {/* Navbar */}
      <div style={{
        height: 52, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 12px', borderBottom: '1px solid var(--border)',
        background: 'var(--bg-card)', flexShrink: 0,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
          <button onClick={pop} aria-label="返回" style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4 }}>
            <ArrowLeft size={20} color="var(--text-primary)" strokeWidth={1.5} />
          </button>
          <div style={{ display: 'flex', flexDirection: 'column' }}>
            <span style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)', lineHeight: 1.3 }}>
              {title}
            </span>
            <span style={{ fontSize: 11, color: 'var(--color-teaching)' }}>
              教学对话
            </span>
          </div>
        </div>
        <MoreMenu options={[
          { label: '新建对话', icon: <MessageSquare size={16} />, onClick: () => push('chat', { title }) },
          { label: '对话配置', icon: <Settings size={16} />, onClick: () => {/* Phase C: 对话配置面板 */} },
        ]} />
      </div>

      {/* 消息区 */}
      <div style={{
        flex: 1, overflow: 'auto', display: 'flex', flexDirection: 'column',
        paddingTop: 8,
      }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center', color: 'var(--text-tertiary)', fontSize: 13 }}>
            加载消息中…
          </div>
        ) : messages.length === 0 ? (
          <WelcomeGuide />
        ) : (
          messages.map(m => <MessageBubble key={m.id} msg={m} />)
        )}
        <div style={{ height: 8 }} />
      </div>

      {/* 输入栏 */}
      <InputBar onSend={handleSend} />
    </div>
  );
};
