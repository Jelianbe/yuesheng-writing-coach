import React, { useState, useEffect } from 'react';
import { FileText, BookOpen } from 'lucide-react';
import type { EvidenceRecord } from '../../shared/types';
import { useDiagStore } from '../../stores/diag.store';
import { useChatStore } from '../../stores/chat.store';
import styles from './OriginalEvidenceSection.module.css';

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
      <div className={styles.loadingBox}>
        <p className={styles.loadingText}>加载原文证据...</p>
      </div>
    );
  }

  if (evidence.length === 0) return null;

  return (
    <div className={styles.container}>
      <div className={styles.header}>
        <BookOpen className={styles.headerIcon} />
        <span className={styles.headerText}>原文证据</span>
      </div>
      <div className={styles.body}>
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
            <div key={ev.evidenceId} className={styles.evidenceItem}>
              {text && (
                <div className={styles.textRow}>
                  <FileText className={styles.textIcon} />
                  <p className={styles.textContent}>
                    &ldquo;{text}&rdquo;
                  </p>
                </div>
              )}
              {issue && (
                <p className={styles.issueText}>
                  ⚠️ {issue}
                </p>
              )}
              {/* 交叉引用标记：同段原文被多个症候引用 */}
              {relatedDiseases.length > 1 && (
                <p className={styles.relatedText}>
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
