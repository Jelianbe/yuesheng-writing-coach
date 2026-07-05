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
 * - 发送:Sprint 20 A-4 — 通过 useOrchestrator.send() 触发 chat:handleTurn,
 *   订阅 chat:event 累积 token/done/error
 */

import React, { useEffect, useRef, useState } from 'react';
import { ArrowLeft, Send, Plus, Type, Image, FileText, Settings, MessageSquare } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useSessionStore } from '../stores/session.store';
import { useOrchestrator } from '../hooks/useOrchestrator';
import type { OrchestratorEventEnvelope } from '../hooks/useOrchestrator';
import { isTokenEvent, isErrorEvent, isDoneEvent } from '../hooks/useOrchestrator';
import { MoreMenu } from '../components/navigation/MoreMenu';
import type { ChatMessage } from '../shared/types';

/* ── 欢迎引导区 ── */
const WelcomeGuide: React.FC<{ onPick: (text: string) => void }> = ({ onPick }) => (
  <div style={{
    display: 'flex', flexDirection: 'column', alignItems: 'center',
    padding: '32px 16px 24px', gap: 16,
  }}>
    <div style={{
      width: 56, height: 56, borderRadius: '50%',
      background: 'var(--accent-gradient)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: 'var(--text-on-accent)', fontSize: 22, fontWeight: 700,
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
          type="button"
          onClick={() => onPick(text)}
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
          background: 'var(--accent)', color: 'var(--text-on-accent)', fontSize: 14,
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

const ActionSheet: React.FC<{ open: boolean; onClose: () => void; onAction: (type: 'text' | 'image' | 'document' | 'settings') => void }> = ({ open, onClose, onAction }) => {
  if (!open) return null;
  const handleClick = (type: 'text' | 'image' | 'document' | 'settings') => {
    onAction(type);
    onClose();
  };
  return (
    <>
      <div
        onClick={onClose}
        style={{
          position: 'fixed', inset: 0, background: 'var(--overlay-scrim)',
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
        {TOOL_ACTIONS.map(({ Icon, label, desc }, i) => {
          const type = (['text', 'image', 'document', 'settings'] as const)[i];
          return (
            <button
              key={label}
              type="button"
              onClick={() => handleClick(type)}
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
          );
        })}
      </div>
    </>
  );
};

/* ── 输入栏 ── */
const InputBar: React.FC<{
  onSend: (text: string) => void;
  disabled?: boolean;
  onAction: (type: 'text' | 'image' | 'document' | 'settings') => void;
}> = ({ onSend, disabled, onAction }) => {
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
            color: hasContent && !disabled ? 'var(--text-on-accent)' : 'var(--text-tertiary)',
            cursor: hasContent && !disabled ? 'pointer' : 'default',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            transition: 'all 200ms', flexShrink: 0,
          }}
          aria-label="发送"
        >
          <Send size={16} />
        </button>
      </div>
      <ActionSheet open={sheetOpen} onClose={() => setSheetOpen(false)} onAction={onAction} />
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
  const [streamError, setStreamError] = useState<string | null>(null);
  const activeStreamIdRef = useRef<string | null>(null);
  const streamingMsgIdRef = useRef<string | null>(null);

  // Sprint 20 A-4: useOrchestrator 订阅 orchestrator 事件流
  const { send, subscribe, finishStream, streaming } = useOrchestrator();

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

  // 订阅 chat:event — 按 streamId 过滤本轮 turn
  useEffect(() => {
    const unsubscribe = subscribe((envelope: OrchestratorEventEnvelope) => {
      if (envelope.streamId !== activeStreamIdRef.current) return;
      const { event } = envelope;

      if (isTokenEvent(event)) {
        // token 累积到当前 AI 流式消息
        setLocalMessages(prev => {
          const msgId = streamingMsgIdRef.current;
          if (!msgId) return prev;
          return prev.map(m =>
            m.id === msgId ? { ...m, content: m.content + event.content } : m,
          );
        });
        return;
      }

      if (isErrorEvent(event)) {
        const payload = event.payload as { code: string; message: string };
        setStreamError(`${payload.code}: ${payload.message}`);
        activeStreamIdRef.current = null;
        streamingMsgIdRef.current = null;
        finishStream();
        return;
      }

      if (isDoneEvent(event)) {
        activeStreamIdRef.current = null;
        streamingMsgIdRef.current = null;
        finishStream();
        return;
      }

      // phase_transition / intent / training_triggered / diagnosis_extracted
      // 暂仅 console 留痕,Sprint 21 接入外部状态机
      if (event.type === 'phase_transition' || event.type === 'intent' || event.type === 'training_triggered' || event.type === 'diagnosis_extracted') {
        // eslint-disable-next-line no-console
        console.log('[ChatPage] orchestrator event:', event.type, event.payload);
      }
    });
    return unsubscribe;
  }, [subscribe, finishStream]);

  const title = params?.title ?? '对话';
  const handleSend = async (text: string) => {
    const sid = params?.id ?? currentSessionId;
    if (!sid) return;
    setStreamError(null);

    // 1. 立即插入用户消息
    const userMsgId = `tmp_u_${Date.now()}`;
    const aiMsgId = `tmp_a_${Date.now()}`;
    setLocalMessages(prev => [
      ...prev,
      { id: userMsgId, role: 'user', content: text, timestamp: Date.now() },
      { id: aiMsgId, role: 'assistant', content: '', timestamp: Date.now() },
    ]);
    streamingMsgIdRef.current = aiMsgId;

    // 2. 触发 orchestrator handleTurn
    const result = await send({ userMessage: text, sessionId: sid, phase: 'requirement' });
    if (!result) {
      setStreamError('发送失败,主进程未响应');
      streamingMsgIdRef.current = null;
      return;
    }
    activeStreamIdRef.current = result.streamId;
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
              {streaming ? '生成中…' : '教学对话'}
            </span>
          </div>
        </div>
        <MoreMenu options={[
          { label: '新建对话', icon: <MessageSquare size={16} />, onClick: async () => {
            const session = await useSessionStore.getState().createSession('新对话');
            if (session) push('chat', { id: session.id, title: session.title });
          }},
          { label: '对话配置', icon: <Settings size={16} />, onClick: () => push('settings', { label: '对话配置' }) },
        ]} />
      </div>

      {/* 错误提示条 */}
      {streamError && (
        <div style={{
          padding: '8px 12px', background: 'var(--error-light)',
          color: 'var(--error)', fontSize: 12, borderBottom: '1px solid var(--border)',
        }} role="alert">
          {streamError}
          <button onClick={() => setStreamError(null)} style={{ float: 'right', border: 'none', background: 'none', cursor: 'pointer' }} aria-label="关闭">×</button>
        </div>
      )}

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
          <WelcomeGuide onPick={handleSend} />
        ) : (
          messages.map(m => <MessageBubble key={m.id} msg={m} />)
        )}
        <div style={{ height: 8 }} />
      </div>

      {/* 输入栏 */}
      <InputBar
        onSend={handleSend}
        disabled={streaming}
        onAction={(type) => {
          if (type === 'settings') push('settings', { label: '对话配置' });
          else if (type === 'image' || type === 'document') {
            setStreamError('暂不支持文件上传，请直接粘贴文字内容');
          }
        }}
      />
    </div>
  );
};
