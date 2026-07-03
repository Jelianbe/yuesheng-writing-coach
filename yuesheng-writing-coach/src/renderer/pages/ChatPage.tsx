/**
 * ChatPage — 教学对话
 *
 * 对齐设计稿:
 * - Navbar: ‹ 返回 + 标题 + 副标题 + ⋯
 * - 欢迎引导区(月头像 + 快捷选项)
 * - 消息气泡(用户/AI)
 * - 输入栏(工具[+] + 输入框 + 发送按钮)
 *
 * 数据来源:
 * - useSessionStore 拿 currentSessionId + loadMessages
 * - 消息区渲染真实 session.messages
 * - 发送:Phase C 再接入 chatService (本步仅显示 + 占位)
 */

import React, { useEffect, useState } from 'react';
import { ArrowLeft, Send, Plus, Type, Image, FileText, Settings, MessageSquare } from 'lucide-react';
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
      嘿,今天想从哪里开始?
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

/* ── 消息气泡 ── */
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

/* ── 工具 ActionSheet ── */
const TOOL_ACTIONS = [
  { Icon: Type, label: '纯文字', desc: '直接输入文字消息' },
  { Icon: Image, label: '图片', desc: '上传图片辅助分析' },
  { Icon: FileText, label: '文档', desc: '上传作品章节' },
  { Icon: Settings, label: '设定', desc: '配置本次对话' },
];

const ActionSheet: React.FC<{ open: boolean; onClose: () => void }> = ({ open, onClose }) => {
  if (!open) return null;
  return (
    <>
      <div
        onClick={onClose}
        style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.4)',
          zIndex: 100, animation: 'fadeIn 200ms',
        }}
        aria-hidden
      />
      <div style={{
        position: 'fixed', left: 0, right: 0, bottom: 0, zIndex: 101,
        background: 'var(--bg-card)', borderRadius: '16px 16px 0 0',
        padding: '8px 0 calc(16px + env(safe-area-inset-bottom, 0px))',
        animation: 'slideUp 240ms cubic-bezier(0.25, 1, 0.5, 1)',
      }} role="dialog" aria-label="工具">
        <div style={{
          width: 36, height: 4, borderRadius: 2, background: 'var(--border)',
          margin: '0 auto 8px',
        }} />
        <div style={{ padding: '4px 16px 8px', fontSize: 13, fontWeight: 500, color: 'var(--text-secondary)' }}>
          添加工具
        </div>
        {TOOL_ACTIONS.map(({ Icon, label, desc }) => (
          <button
            key={label}
            type="button"
            onClick={onClose}
            style={{
              display: 'flex', alignItems: 'center', gap: 12,
              width: '100%', padding: '12px 16px',
              background: 'transparent', border: 'none', cursor: 'pointer',
              color: 'inherit', font: 'inherit', textAlign: 'left',
            }}
          >
            <div style={{
              width: 36, height: 36, borderRadius: 10,
              background: 'var(--accent-faint)', color: 'var(--accent)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icon size={18} strokeWidth={1.5} />
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 14, color: 'var(--text-primary)', fontWeight: 500 }}>{label}</div>
              <div style={{ fontSize: 11, color: 'var(--text-tertiary)', marginTop: 1 }}>{desc}</div>
            </div>
          </button>
        ))}
      </div>
    </>
  );
};

/* ── 输入栏 ── */
const InputBar: React.FC<{ onSend: (text: string) => void; disabled?: boolean }> = ({ onSend, disabled }) => {
  const [text, setText] = useState('');
  const [sheetOpen, setSheetOpen] = useState(false);
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
      <div style={{ display: 'flex', gap: 8, alignItems: 'center' }}>
        <button
          onClick={() => setSheetOpen(true)}
          aria-label="添加工具"
          style={{
            width: 38, height: 38, borderRadius: 8, border: 'none',
            background: 'var(--bg-input)', color: 'var(--text-secondary)',
            cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0,
          }}
        >
          <Plus size={18} strokeWidth={2} />
        </button>
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
            transition: 'all 200ms', flexShrink: 0,
          }}
          aria-label="发送"
        >
          <Send size={16} />
        </button>
      </div>
      <ActionSheet open={sheetOpen} onClose={() => setSheetOpen(false)} />
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

  useEffect(() => {
    if (params?.id && params.id !== currentSessionId) {
      switchSession(params.id);
    }
  }, [params?.id, currentSessionId, switchSession]);

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
