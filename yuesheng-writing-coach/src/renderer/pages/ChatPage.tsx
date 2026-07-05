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
import { ArrowLeft, Send, Plus, Type, Image, FileText, Settings, MessageSquare, GraduationCap } from 'lucide-react';
import { useShallow } from 'zustand/react/shallow';
import { usePageStackStore } from '../stores/page-stack.store';
import { useSessionStore } from '../stores/session.store';
import { useOrchestrator } from '../hooks/useOrchestrator';
import type { OrchestratorEventEnvelope } from '../hooks/useOrchestrator';
import { isTokenEvent, isErrorEvent, isDoneEvent } from '../hooks/useOrchestrator';
import { useDiagStore } from '../stores/diag.store';
import { useTrainingStore } from '../stores/training.store';
import { useTrainingPlanStore } from '../stores/training-plan.store';
import { activeTrainingService } from '../services/active-training.service';
import { MoreMenu } from '../components/navigation/MoreMenu';
import { FlowPanel } from '../components/training/flow/FlowPanel';
import { SYNDROME_NAMES } from '../../shared/mappings';
import type { ActiveTrainingGetResponse } from '../../shared/api-contracts/active-training.contract';
import type { ChatMessage } from '../shared/types';
import type { ActiveTrainingSession, TrainingFlow, TrainingStep } from '../shared/types-training';

/* ── 阶段中文名映射 ── */
const PHASE_LABELS = {
  trust_building: '建立信任',
  requirement: '需求了解',
  diagnosis: '诊断分析',
  training: '训练指导',
  reflection: '复盘反思',
} as const;

type PhaseKey = keyof typeof PHASE_LABELS;

/**
 * 系统消息渲染文本
 */
function systemMessageText(type: string | undefined, event: Record<string, unknown> | undefined): string {
  if (type === 'phase') {
    const phase = event?.phase as string | undefined;
    const phaseKey = phase as PhaseKey | undefined;
    if (phaseKey && PHASE_LABELS[phaseKey]) return `📋 进入${PHASE_LABELS[phaseKey]}阶段`;
    if (event?.summary) return `📋 ${event.summary}`;
    return '📋 对话阶段已变更';
  }
  if (type === 'diagnosis') {
    const syndromes = event?.syndromes as Array<unknown> | undefined;
    if (event?.summary) return `🔍 ${event.summary}`;
    return `🔍 诊断: 发现 ${syndromes?.length ?? 0} 个症候`;
  }
  if (type === 'training_trigger') {
    const syndromeId = event?.syndromeId as string | undefined;
    const syndromeName = syndromeId ? SYNDROME_NAMES[syndromeId] : undefined;
    if (syndromeName) return `💪 检测到「${syndromeName}」症候，建议进行专项训练`;
    const reason = event?.reason as string | undefined;
    if (reason) return `💪 ${reason}`;
    return '💪 AI 建议进行专项训练，是否开始？';
  }
  return '';
}

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
  // system 消息: 根据不同 contentType 渲染不同样式
  if (msg.role === 'system') {
    const ct = msg.metadata?.contentType as string | undefined;
    const text = msg.content || systemMessageText(ct, msg.metadata);
    if (ct === 'training_trigger') {
      return (
        <div style={{ display: 'flex', justifyContent: 'center', padding: '0 16px 12px' }}>
          <div style={{
            background: 'var(--bg-card)', border: '1px solid var(--border)',
            borderRadius: 12, padding: '12px 16px', maxWidth: '80%',
            fontSize: 13, color: 'var(--text-primary)', lineHeight: 1.5,
          }}>
            <div style={{ fontSize: 12, color: 'var(--accent)', fontWeight: 600, marginBottom: 6 }}>
              💪 训练建议
            </div>
            <div>{text}</div>
            <button
              type="button"
              onClick={() => {
                // 触发训练的事件由 ChatPage 统一处理
                window.dispatchEvent(new CustomEvent('start-training', { detail: msg.metadata }));
              }}
              style={{
                marginTop: 8, padding: '6px 16px', borderRadius: 8,
                border: 'none', background: 'var(--accent)',
                color: 'var(--text-on-accent)', fontSize: 13, cursor: 'pointer',
                fontWeight: 500,
              }}
            >
              开始训练
            </button>
          </div>
        </div>
      );
    }
    return (
      <div style={{ display: 'flex', justifyContent: 'center', padding: '0 16px 12px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6,
          background: 'var(--bg-subtle)', borderRadius: 8,
          padding: '8px 14px', fontSize: 12, color: 'var(--text-tertiary)',
          maxWidth: '80%', lineHeight: 1.4,
        }}>
          {text}
        </div>
      </div>
    );
  }
  return null;
};

/**
 * 将 activeTrainingService.create() 返回的 ActiveTrainingGetResponse
 * 映射为渲染层 ActiveTrainingSession。
 * 共有 3 处调用，抽取为共享函数以消除重复（R-019）。
 */
function toActiveTrainingSession(
  result: ActiveTrainingGetResponse,
  overrides?: { planItemId?: string },
): ActiveTrainingSession {
  return {
    challengeId: result.challengeId,
    challengeName: result.challengeName ?? '专项训练',
    challengeDescription: result.originalQuote ?? result.syndromeId ?? '写作技巧训练',
    mode: result.mode ?? 'flow5',
    steps: result.steps as TrainingStep[],
    currentStepIndex: result.currentStepIndex,
    originalQuote: result.originalQuote ?? '',
    constraint: result.constraint ?? '',
    userDraft: result.userDraft ?? '',
    trainingFlow: result.trainingFlow ?? undefined,
    flowType: result.flowType ?? undefined,
    planItemId: overrides?.planItemId,
  };
}

/* ── 工具 ActionSheet ── */
const TOOL_ACTIONS = [
  { Icon: Type, label: '纯文字', desc: '直接输入文字消息' },
  { Icon: Image, label: '图片', desc: '上传图片辅助分析' },
  { Icon: FileText, label: '文档', desc: '上传作品章节' },
  { Icon: GraduationCap, label: '训练', desc: '开始写作专项训练' },
  { Icon: Settings, label: '设定', desc: '配置本次对话' },
];

const ActionSheet: React.FC<{ open: boolean; onClose: () => void; onAction: (type: 'text' | 'image' | 'document' | 'training' | 'settings') => void }> = ({ open, onClose, onAction }) => {
  if (!open) return null;
  const handleClick = (type: 'text' | 'image' | 'document' | 'training' | 'settings') => {
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
          const type = (['text', 'image', 'document', 'training', 'settings'] as const)[i];
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
  onAction: (type: 'text' | 'image' | 'document' | 'training' | 'settings') => void;
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
  const MAX_VISIBLE = 200;
  const [messages, setLocalMessages] = useState<ChatMessage[]>([]);
  const [visibleLimit, setVisibleLimit] = useState(MAX_VISIBLE);
  const [loading, setLoading] = useState(false);
  const [streamError, setStreamError] = useState<string | null>(null);
  const [subtitle, setSubtitle] = useState('教学对话');
  const [showTraining, setShowTraining] = useState(false);
  const [trainingError, setTrainingError] = useState<string | null>(null);
  const [activeSession, setActiveSession] = useState<ActiveTrainingSession | null>(null);
  const [trainingFlow, setTrainingFlow] = useState<TrainingFlow | null>(null);
  const evaluationResult = useTrainingStore(s => s.evaluationResult);
  const mountActiveTraining = useTrainingStore(s => s.mountActiveTraining);
  const activeStreamIdRef = useRef<string | null>(null);
  const streamingMsgIdRef = useRef<string | null>(null);
  const pendingTrainingRef = useRef<Record<string, unknown> | null>(null);

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
    setVisibleLimit(MAX_VISIBLE);
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

      // orchestrator 事件处理: phase_transition / diagnosis_extracted / training_triggered
      if (event.type === 'phase_transition') {
        try {
          const payload = event.payload as Record<string, unknown> ?? {};
          const phase = payload.phase as PhaseKey | undefined;
          if (phase && PHASE_LABELS[phase]) setSubtitle(PHASE_LABELS[phase]);
          const sysMsg: ChatMessage = {
            id: `sys_phase_${Date.now()}`,
            role: 'system',
            content: '',
            timestamp: Date.now(),
            metadata: { contentType: 'phase', ...payload },
          };
          setLocalMessages(prev => [...prev, sysMsg]);
        } catch (e) {
          console.warn('[ChatPage] phase_transition handler:', e);
        }
        return;
      }
      if (event.type === 'diagnosis_extracted') {
        try {
          const payload = event.payload as Record<string, unknown> ?? {};
          const syndromeCount = (payload.syndromes as Array<unknown> | undefined)?.length ?? 0;
          const sysMsg: ChatMessage = {
            id: `sys_diag_${Date.now()}`,
            role: 'system',
            content: syndromeCount > 0 ? `🔍 已识别 ${syndromeCount} 个写作症候` : '🔍 诊断完成',
            timestamp: Date.now(),
            metadata: { contentType: 'diagnosis', ...payload },
          };
          setLocalMessages(prev => [...prev, sysMsg]);
          useDiagStore.getState().setCurrentDiagnosis(payload as never);
        } catch (e) {
          console.warn('[ChatPage] diagnosis_extracted handler:', e);
        }
        return;
      }
      if (event.type === 'training_triggered') {
        try {
          const payload = event.payload as Record<string, unknown> ?? {};
          pendingTrainingRef.current = payload;
          const sysMsg: ChatMessage = {
            id: `sys_train_${Date.now()}`,
            role: 'system',
            content: '',
            timestamp: Date.now(),
            metadata: { contentType: 'training_trigger', ...payload },
          };
          setLocalMessages(prev => [...prev, sysMsg]);
        } catch (e) {
          console.warn('[ChatPage] training_triggered handler:', e);
        }
        return;
      }
      // intent 事件暂不处理
      if (event.type === 'intent') return;
    });
    return unsubscribe;
  }, [subscribe, finishStream]);

  // Sprint 38: 从训练计划页跳转时,自动启动训练
  useEffect(() => {
    const cid = params?.challengeId;
    if (!cid) return;
    setTrainingError(null);
    void (async () => {
      try {
        const sid = params?.id ?? currentSessionId;
        if (!sid) return;
        const result = await activeTrainingService.create(sid, cid);
        if (result && result.trainingFlow) {
          const session = toActiveTrainingSession(result, { planItemId: params?.planItemId });
          setActiveSession(session);
          setTrainingFlow(result.trainingFlow);
          await mountActiveTraining(sid);
        }
        setShowTraining(true);
      } catch (e) {
        setTrainingError('创建训练失败: ' + (e instanceof Error ? e.message : String(e)));
      }
    })();
  }, [params?.challengeId, params?.planItemId, params?.id, currentSessionId, mountActiveTraining]);

  // 监听 start-training 自定义事件(由 MessageBubble 的训练按钮触发)
  useEffect(() => {
    const handler = () => {
      const payload = pendingTrainingRef.current;
      if (!payload) {
        setTrainingError('无训练数据,请先与 AI 对话');
        return;
      }
      const sid = params?.id ?? currentSessionId;
      if (!sid) return;
      setTrainingError(null);
      // 调用 activeTrainingService.create() 创建训练 session
      void (async () => {
        try {
          const result = await activeTrainingService.create(sid, 'training');
          if (result && result.trainingFlow) {
            const session = toActiveTrainingSession(result);
            setActiveSession(session);
            setTrainingFlow(result.trainingFlow);
            // 挂载训练状态订阅（接收主进程推送的评估结果等）
            await mountActiveTraining(sid);
          }
          setShowTraining(true);
        } catch (e) {
          setTrainingError('创建训练失败: ' + (e instanceof Error ? e.message : String(e)));
        }
      })();
    };
    window.addEventListener('start-training', handler);
    return () => window.removeEventListener('start-training', handler);
  }, [params?.id, currentSessionId]);

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
              {streaming ? '生成中…' : subtitle}
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
      {(streamError || trainingError) && (
        <div style={{
          padding: '8px 12px', background: 'var(--error-light)',
          color: 'var(--error)', fontSize: 12, borderBottom: '1px solid var(--border)',
        }} role="alert">
          {streamError ?? trainingError}
          <button onClick={() => { setStreamError(null); setTrainingError(null); }} style={{ float: 'right', border: 'none', background: 'none', cursor: 'pointer' }} aria-label="关闭">×</button>
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
          <>
            {messages.length > visibleLimit && (
              <button
                onClick={() => setVisibleLimit(prev => Math.min(prev + MAX_VISIBLE, messages.length))}
                style={{
                  margin: '4px auto 8px', padding: '6px 16px', border: '1px solid var(--border)',
                  borderRadius: 16, background: 'var(--bg-card)', color: 'var(--text-secondary)',
                  fontSize: 12, cursor: 'pointer',
                }}
              >
                显示更早消息（{messages.length - visibleLimit} 条）
              </button>
            )}
            {messages.slice(-visibleLimit).map(m => <MessageBubble key={m.id} msg={m} />)}
          </>
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
          } else if (type === 'training') {
            // 主动训练入口：复用 start-training handler 逻辑
            const sid = params?.id ?? currentSessionId;
            if (!sid) return;
            setTrainingError(null);
            void (async () => {
              try {
                const result = await activeTrainingService.create(sid, 'training');
                if (result && result.trainingFlow) {
                  const session = toActiveTrainingSession(result);
                  setActiveSession(session);
                  setTrainingFlow(result.trainingFlow);
                  await mountActiveTraining(sid);
                }
                setShowTraining(true);
              } catch (e) {
                setTrainingError('创建训练失败: ' + (e instanceof Error ? e.message : String(e)));
              }
            })();
          }
        }}
      />
      {/* 训练模式: 覆盖消息区 + 输入栏 */}
      {showTraining && (
        <div style={{
          position: 'absolute', inset: 0, zIndex: 50,
          background: 'var(--bg-page)',
          display: 'flex', flexDirection: 'column',
        }}>
          <div style={{
            height: 52, display: 'flex', alignItems: 'center',
            justifyContent: 'space-between', padding: '0 12px',
            borderBottom: '1px solid var(--border)',
            background: 'var(--bg-card)', flexShrink: 0,
          }}>
            <span style={{ fontSize: 15, fontWeight: 600, color: 'var(--text-primary)' }}>
              专项训练
            </span>
            <button
              onClick={() => setShowTraining(false)}
              style={{
                padding: '6px 12px', borderRadius: 8,
                border: '1px solid var(--border)',
                background: 'var(--bg-card)', cursor: 'pointer',
                fontSize: 12, color: 'var(--text-secondary)',
              }}
            >
              返回对话
            </button>
          </div>
          <div style={{ flex: 1, overflow: 'auto', padding: 16 }}>
            {activeSession && trainingFlow ? (
              <FlowPanel
                active={activeSession}
                flow={trainingFlow}
                evaluation={evaluationResult}
                onExit={() => {
                  // Sprint 38: 训练完成时标记计划项为 completed
                  if (activeSession?.planItemId) {
                    useTrainingPlanStore.getState().updateItemStatus(activeSession.planItemId, 'completed');
                  }
                  // 注入训练完成系统消息（不管是否走完 5 步都算退出）
                  const evalMsg = evaluationResult
                    ? `💪 训练已结束\n评分：${evaluationResult.score}/10\n反馈：${evaluationResult.feedback}`
                    : '💪 训练已结束，可以继续对话了';
                  const sysMsg: ChatMessage = {
                    id: `sys_train_end_${Date.now()}`,
                    role: 'system',
                    content: evalMsg,
                    timestamp: Date.now(),
                    metadata: { contentType: 'training_end' },
                  };
                  setLocalMessages(prev => [...prev, sysMsg]);
                  setActiveSession(null);
                  setTrainingFlow(null);
                  setShowTraining(false);
                }}
              />
            ) : (
              <div style={{ fontSize: 13, color: 'var(--text-tertiary)', textAlign: 'center', paddingTop: 40 }}>
                正在加载训练数据…
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
};
