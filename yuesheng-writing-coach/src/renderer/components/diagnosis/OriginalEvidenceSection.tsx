import React, { useState, useEffect } from 'react';
import { FileText, BookOpen } from 'lucide-react';
import type { EvidenceRecord } from '../../shared/types';
import { useDiagStore } from '../../stores/diag.store';
import { useChatStore } from '../../stores/chat.store';

interface OriginalEvidenceSectionProps {
  syndromeId: string;
}

/**
 * OriginalEvidenceSection — 原文证据区块
 *
 * 从数据库获取证据并展示。
 * 支持交叉引用标记（同段原文被多个症候引用时显示关联症候）。
 */
export const OriginalEvidenceSection: React.FC<OriginalEvidenceSectionProps> = ({ syndromeId }) => {
  const loadEvidence = useDiagStore((s) => s.loadEvidence);
  const getEvidence = useDiagStore((s) => s.getEvidence);
  const sessionId = useChatStore((s) => s.currentSessionId);
  const [evidence, setEvidence] = useState<EvidenceRecord[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    // 先尝试从缓存获取
    const cached = getEvidence(syndromeId);
    if (cached.length > 0) {
      setEvidence(cached);
      return;
    }

    // 无缓存则从 IPC 加载
    if (!sessionId) return;
    setLoading(true);
    loadEvidence(syndromeId, sessionId)
      .then((records) => setEvidence(records))
      .finally(() => setLoading(false));
  }, [syndromeId, sessionId]);

  if (loading) {
    return (
      <div className="bg-highlight rounded-[var(--radius-sm)] p-3 border border-border-light">
        <p className="text-xs text-text-tertiary">加载原文证据...</p>
      </div>
    );
  }

  if (evidence.length === 0) return null;

  return (
    <div className="bg-highlight rounded-[var(--radius-sm)] border border-border-light overflow-hidden">
      <div className="px-3 py-2 bg-bg-tertiary/30 border-b border-border-light flex items-center gap-2">
        <BookOpen className="w-3.5 h-3.5 text-accent-primary" />
        <span className="text-xs font-medium text-text-secondary">原文证据</span>
      </div>
      <div className="p-3 space-y-2">
        {evidence.map((ev) => {
          // 解析 contentJson 获取原文片段和问题描述
          let text = '';
          let issue = '';
          let relatedDiseases: string[] = [];
          try {
            const content = typeof ev.contentJson === 'string'
              ? JSON.parse(ev.contentJson)
              : ev.contentJson;
            text = content.text ?? content.keyPassage ?? content.quote ?? '';
            issue = content.issue ?? content.description ?? content.problem ?? '';
            relatedDiseases = content.relatedDiseases ?? [];
          } catch {
            text = String(ev.contentJson).slice(0, 200);
          }

          return (
            <div key={ev.evidenceId} className="space-y-1">
              {text && (
                <div className="flex items-start gap-2">
                  <FileText className="w-3.5 h-3.5 text-text-tertiary mt-0.5 flex-shrink-0" />
                  <p className="text-sm text-text-secondary leading-relaxed italic">
                    "{text}"
                  </p>
                </div>
              )}
              {issue && (
                <p className="text-xs text-accent-warning pl-5">
                  ⚠️ {issue}
                </p>
              )}
              {/* 交叉引用标记：同段原文被多个症候引用 */}
              {relatedDiseases.length > 1 && (
                <p className="text-xs text-text-tertiary pl-5">
                  关联症候：{relatedDiseases.join(' · ')}
                </p>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};
