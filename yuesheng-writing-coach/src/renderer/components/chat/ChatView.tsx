/**
 * ChatView — 聊天主内容区（搜索栏 + 消息列表 + 诊断卡片 + 输入框）
 *
 * V2-019 增强：
 * - 消息搜索过滤
 * - 历史消息分页加载（通过 IPC session:getMessagesPaged）
 * - 时间分组展示（由 MessageList 内部处理）
 */

import React, { useState, useCallback } from 'react';
import type { ChatMessage, DiagnosisEntry, RewriteEvaluation } from '../../shared/types';
import { MessageList } from './MessageList';
import { OnboardingFlow } from './OnboardingFlow';
import { ChatSearchBar } from './ChatSearchBar';
import { WelcomeCard } from './WelcomeCard';
import { DiagnosisCard } from '../diagnosis/DiagnosisCard';
import { EditPanel } from '../diagnosis/EditPanel';
import { EvaluationCard } from '../diagnosis/EvaluationCard';
import { GrowthCard } from '../diagnosis/GrowthCard';
import { TrainingBridgeCard } from './TrainingBridgeCard';
import type { TrainingRecommendation } from '../../shared/types';
import { getInvoke } from '../../utils/ipc';
import { IPC_CHANNELS } from '../../shared/constants';
import { useChatStore } from '../../stores/chat.store';
import styles from './ChatView.module.css';
import { AlertTriangle } from 'lucide-react';

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
  /** 是否已配置 API Key（控制欢迎卡片和发送按钮禁用） */
  isConfigured?: boolean;
  // Q-02: 错误展示 + 重试
  error?: string | null;
  retryable?: boolean;
  onRetry?: () => void;
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

export const ChatView: React.FC<ChatViewProps> = ({
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
  isConfigured = true,
  error,
  retryable,
  onRetry,
  onSend: _onSend,
  onStop: _onStop,
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
    } catch (err) {
      console.warn('[ChatView] loadMore failed:', err);
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

  // P-04: 新用户引导状态
  const { onboardingActive, onboardingStep, completeOnboarding, skipOnboarding, setOnboardingStep } = useChatStore();

  // ── 无消息时的欢迎卡片（未配置 API Key 时显示）──
  const showWelcomeCard = !isConfigured && !onboardingActive && messages.length === 0;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', overflow: 'hidden' }}>
      {/* ── 搜索栏 ── */}
      {showSearch && (
        <ChatSearchBar
          searchQuery={searchQuery}
          onSearchChange={setSearchQuery}
          onClose={toggleSearch}
        />
      )}

      {/* ── P-04: 新用户引导流程 ── */}
      {onboardingActive && (
        <OnboardingFlow
          onboardingStep={onboardingStep}
          skipOnboarding={skipOnboarding}
          setOnboardingStep={setOnboardingStep}
          completeOnboarding={completeOnboarding}
        />
      )}

      {/* ── 主要内容区（flex:1 填充剩余空间）── */}
      <div style={{ flex: 1, overflowY: 'auto', minHeight: 0 }}>
        {!onboardingActive && (
          <>
            {showWelcomeCard ? (
              <WelcomeCard />
            ) : (
              <MessageList
                messages={loadedMessages}
                isStreaming={isStreaming}
                hasSession={!!currentSessionId}
                searchQuery={searchQuery}
                hasMore={hasMoreHistory && !searchQuery.trim()}
                isLoadingMore={isLoadingMore}
                onLoadMore={handleLoadMore}
              />
            )}

            {/* Q-02: 错误展示横幅 + 重试按钮 */}
            {error && !isStreaming && (
              <div className={styles.errorBanner}>
                <span className={styles.errorIcon}><AlertTriangle size={14} /></span>
                  <span className={styles.errorMessage}>{error}</span>
                {retryable && onRetry && (
                  <button className={styles.retryBtn} onClick={onRetry}>
                    重试
                  </button>
                )}
              </div>
            )}
          </>
        )}
      </div>

      {currentDiagnosis && !isStreaming && (
        <div className={styles.diagnosisArea}>
          <div className={styles.diagnosisInner}>
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

    </div>
  );
};
