/**
 * ChatView — 聊天主内容区（消息列表 + 诊断卡片 + 输入框）
 */

import React from 'react';
import type { ChatMessage, DiagnosisEntry, RewriteEvaluation } from '../../shared/types';
import { MessageList } from './MessageList';
import { MessageInput } from './MessageInput';
import { DiagnosisCard } from '../diagnosis/DiagnosisCard';
import { EditPanel } from '../diagnosis/EditPanel';
import { EvaluationCard } from '../diagnosis/EvaluationCard';
import { GrowthCard } from '../diagnosis/GrowthCard';

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
  onSend: (text: string) => void;
  onStop: () => void;
  onStartEditing: (syndromeId: string, evidence: string[], name: string, severity: string) => void;
  onSubmitRewrite: (text: string) => void;
  onCancelEditing: () => void;
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
  onSend,
  onStop,
  onStartEditing,
  onSubmitRewrite,
  onCancelEditing,
}) => (
  <>
    <MessageList
      messages={messages}
      isStreaming={isStreaming}
      hasSession={!!currentSessionId}
    />

    {currentDiagnosis && !isStreaming && (
      <div className="px-4 pb-2">
        <div className="max-w-3xl mx-auto space-y-3">
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

export default ChatView;
