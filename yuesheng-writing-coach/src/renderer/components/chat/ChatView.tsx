/**
 * ChatView — 聊天主内容区（搜索栏 + 消息列表 + 诊断卡片 + 输入框）
 *
 * V2-019 增强：
 * - 消息搜索过滤
 * - 历史消息分页加载（通过 IPC session:getMessagesPaged）
 * - 时间分组展示（由 MessageList 内部处理）
 */

import React, { useState, useCallback } from 'react';
import { Search, X } from 'lucide-react';
import type { ChatMessage, DiagnosisEntry, RewriteEvaluation } from '../../shared/types';
import { MessageList } from './MessageList';
import { MessageInput } from './MessageInput';
import { DiagnosisCard } from '../diagnosis/DiagnosisCard';
import { EditPanel } from '../diagnosis/EditPanel';
import { EvaluationCard } from '../diagnosis/EvaluationCard';
import { GrowthCard } from '../diagnosis/GrowthCard';
import TrainingBridgeCard from './TrainingBridgeCard';
import type { TrainingRecommendation } from '../../shared/types';
import { getInvoke } from '../../utils/ipc';
import { IPC_CHANNELS } from '../../shared/constants';

interface ChatViewProps {
  messages: ChatMessage[];
  isStreaming: boolean;
  currentSessionId: string | null;
  currentDiagnosis: DiagnosisEntry | null;
  editingSyndrome: { id: string; name: string; evidence: string[] } | null;
  isSubmitting: boolean;
  lastEvaluation: RewriteEvaluation | null;
  lastOriginalText: string | null;
  lastRewrittenText: string | null;
  growthLoading: boolean;
  hasHistory: boolean;
  growthSummary: string | null;
  /** 桥接卡片推荐（null = 无推荐或已关闭） */
  bridgeRecommendation: TrainingRecommendation | null;
  onSend: (text: string) => void;
  onStop: () => void;
  onStartEditing: (syndromeId: string, evidence: string[], name: string, severity: string) => void;
  onSubmitRewrite: (text: string) => void;
  onCancelEditing: () => void;
  /** 进入训练工坊（通过桥接卡片） */
  onEnterWorkshopFromBridge: (challengeId: string) => void;
  /** 关闭桥接卡片 */
  onDismissBridge: () => void;
}

const ChatView: React.FC<ChatViewProps> = ({
  messages,
  isStreaming,
  currentSessionId,
  currentDiagnosis,
  editingSyndrome,
  isSubmitting,
  lastEvaluation,
  lastOriginalText,
  lastRewrittenText,
  growthLoading,
  hasHistory,
  growthSummary,
  bridgeRecommendation,
  onSend,
  onStop,
  onStartEditing,
  onSubmitRewrite,
  onCancelEditing,
  onEnterWorkshopFromBridge,
  onDismissBridge,
}) => {
  // ── 搜索状态 ──
  const [searchQuery, setSearchQuery] = useState('');
  const [showSearch, setShowSearch] = useState(false);

  // ── 历史消息加载状态 ──
  const [loadedMessages, setLoadedMessages] = useState<ChatMessage[]>(messages);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [hasMoreHistory, setHasMoreHistory] = useState(false);

  // 同步外部 messages 变化（如切换会话）
  React.useEffect(() => {
    setLoadedMessages(messages);
    // 检查是否有更多历史（当消息来自 IPC 全量加载时，默认已有全部）
    setHasMoreHistory(false);
  }, [messages]);

  // ── 加载更多历史消息 ──
  const handleLoadMore = useCallback(async () => {
    if (!currentSessionId || isLoadingMore) return;
    setIsLoadingMore(true);
    try {
      const invoke = getInvoke();
      const offset = loadedMessages.length;
      const limit = 20;
      const result = await invoke(IPC_CHANNELS.SESSION_GET_MESSAGES_PAGED, {
        sessionId: currentSessionId,
        offset,
        limit,
      }) as { success: boolean; data?: { messages: ChatMessage[]; total: number; hasMore: boolean }; error?: string };

      if (result.success && result.data) {
        const existingIds = new Set(loadedMessages.map(m => m.id));
        const newMsgs = result.data.messages.filter(m => !existingIds.has(m.id));
        if (newMsgs.length > 0) {
          setLoadedMessages(prev => [...newMsgs, ...prev]);
        }
        setHasMoreHistory(result.data.hasMore);
      }
    } catch {
      // 静默失败
    } finally {
      setIsLoadingMore(false);
    }
  }, [currentSessionId, isLoadingMore, loadedMessages]);

  // ── 搜索栏切换 ──
  const toggleSearch = useCallback(() => {
    setShowSearch(prev => !prev);
    if (showSearch) setSearchQuery('');
  }, [showSearch]);

  // Ctrl+F / Cmd+F 触发搜索
  React.useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'f' && !isStreaming) {
        e.preventDefault();
        setShowSearch(prev => !prev);
        if (showSearch) setSearchQuery('');
      }
      if (e.key === 'Escape' && showSearch) {
        setShowSearch(false);
        setSearchQuery('');
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [isStreaming, showSearch]);

  return (
    <>
      {/* ── 搜索栏 ── */}
      {showSearch && (
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            gap: 8,
            padding: '8px 20px',
            borderBottom: '1px solid var(--border)',
            background: 'var(--bg-sidebar)',
            flexShrink: 0,
          }}
        >
          <Search size={14} strokeWidth={1.6} style={{ color: 'var(--text-tertiary)', flexShrink: 0 }} />
          <input
            type="text"
            value={searchQuery}
            onChange={e => setSearchQuery(e.target.value)}
            placeholder="搜索消息内容..."
            autoFocus
            style={{
              flex: 1,
              border: 'none',
              outline: 'none',
              background: 'transparent',
              color: 'var(--text-primary)',
              fontFamily: 'var(--font-body)',
              fontSize: '0.82rem',
            }}
            onKeyDown={e => { if (e.key === 'Escape') { setShowSearch(false); setSearchQuery(''); } }}
          />
          {searchQuery && (
            <button
              onClick={() => setSearchQuery('')}
              style={{
                border: 'none', background: 'transparent', cursor: 'pointer',
                color: 'var(--text-tertiary)', padding: 2, display: 'flex',
              }}
              aria-label="清除搜索"
            >
              <X size={14} strokeWidth={1.6} />
            </button>
          )}
          <button
            onClick={toggleSearch}
            style={{
              border: 'none', background: 'transparent', cursor: 'pointer',
              color: 'var(--text-tertiary)', padding: 2, display: 'flex',
            }}
            aria-label="关闭搜索"
          >
            <X size={14} strokeWidth={1.6} />
          </button>
        </div>
      )}

      <MessageList
        messages={searchQuery.trim() ? loadedMessages : loadedMessages}
        isStreaming={isStreaming}
        hasSession={!!currentSessionId}
        searchQuery={searchQuery}
        hasMore={hasMoreHistory && !searchQuery.trim()}
        isLoadingMore={isLoadingMore}
        onLoadMore={handleLoadMore}
      />

      {currentDiagnosis && !isStreaming && (
        <div style={{ padding: '0 20px 8px' }}>
          <div style={{ maxWidth: '48rem', margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 12 }}>
            <DiagnosisCard
              diagnosis={currentDiagnosis}
              onStartEditing={onStartEditing}
            />

            {editingSyndrome && (
              <EditPanel
                originalTexts={editingSyndrome.evidence}
                syndromeName={editingSyndrome.name}
                onSubmit={(rewrittenText) => onSubmitRewrite(rewrittenText)}
                onCancel={onCancelEditing}
                isSubmitting={isSubmitting}
              />
            )}

            {lastEvaluation && (
              <EvaluationCard
                evaluation={lastEvaluation}
                originalText={lastOriginalText ?? undefined}
                rewrittenText={lastRewrittenText ?? undefined}
              />
            )}

            {(growthLoading || hasHistory || growthSummary !== null) && (
              <GrowthCard
                summary={growthSummary ?? ''}
                hasHistory={hasHistory}
                isLoading={growthLoading}
              />
            )}

            {bridgeRecommendation && (
              <TrainingBridgeCard
                recommendation={bridgeRecommendation}
                onEnterWorkshop={onEnterWorkshopFromBridge}
                onDismiss={onDismissBridge}
              />
            )}
          </div>
        </div>
      )}

      <MessageInput
        onSend={onSend}
        onStop={onStop}
        isStreaming={isStreaming}
        disabled={false}
      />
    </>
  );
};

export default ChatView;
