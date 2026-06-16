import React, { useState } from 'react';
import { ChevronDown, ChevronRight, AlertTriangle, ClipboardList, HelpCircle, Eye, Lock } from 'lucide-react';
import { useDiagStore, selectCurrentSyndromes, selectCurrentActions, selectCurrentConfidence } from '../../stores/diag.store';
import { usePanelSessionStore } from '../../stores/panel-session.store';
import { HintPanel } from './HintPanel';
import { TemplateFormView } from './TemplateFormView';
import type { SyndromeResult, EvidenceRecord } from '../../shared/types';
import styles from './diagnosis-panel.module.css';
import shared from '../profile/panel-shared.module.css';

const severityLabel: Record<string, string> = { L3: '严重', L2: '中度', L1: '轻度' };
const severityColor: Record<string, string> = { L3: '#C0392B', L2: '#D4A04A', L1: '#7EA87E' };

const MIN_REFLECTION_LENGTH = 50;

/** 常见问题占位数据（待 B-01 落地后替换为配置源） */
const FAQ_PLACEHOLDER: Record<string, string[]> = {
  default: [
    '为什么我的文字读起来不够流畅？',
    '这里是否可以用更具体的描写替代抽象描述？',
    '句子长度是否需要调整以改善节奏？',
  ],
};

/** 单条症候卡片 */
const SyndromeCard: React.FC<{ syndrome: SyndromeResult }> = ({ syndrome }) => {
  const [expanded, setExpanded] = useState(false);
  const [reflection, setReflection] = useState('');
  const [revealed, setRevealed] = useState(false);
  const [faqExpanded, setFaqExpanded] = useState(false);
  const loadEvidence = useDiagStore(s => s.loadEvidence);
  const evidenceMap = useDiagStore(s => s.evidenceMap);
  const sidebarPhase = usePanelSessionStore(s => s.sidebarPhase);

  const handleToggle = () => {
    if (!expanded) {
      const sid = useDiagStore.getState().currentDiagnosis?.sessionId;
      if (sid) loadEvidence(syndrome.id, sid);
    }
    setExpanded(!expanded);
  };

  const handleReveal = () => {
    if (reflection.trim().length >= MIN_REFLECTION_LENGTH) {
      setRevealed(true);
    }
  };

  const evidence = evidenceMap[syndrome.id] ?? [];
  // F-02: 引导阶段显示常见问题链接（临时用 sidebarPhase，待 B-01 needsGuidePhase 替换）
  const showFaqLink = sidebarPhase === 'guide';
  const canReveal = reflection.trim().length >= MIN_REFLECTION_LENGTH;

  return (
    <div className={styles.card}>
      <button
        onClick={handleToggle}
        className={styles.cardHeader}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, overflow: 'hidden' }}>
          <AlertTriangle size={14} color={severityColor[syndrome.severity]} strokeWidth={1.8} />
          <span className={`${shared.fontMedium} ${shared.truncate}`}>
            {syndrome.name}
          </span>
        </div>
        <div className={`${shared.flexAlignCenter} ${shared.flexGap6}`}>
          <span
            className={styles.severityBadge}
            style={{
              background: `${severityColor[syndrome.severity]}18`,
              color: severityColor[syndrome.severity],
            }}
          >
            {severityLabel[syndrome.severity]}
          </span>
          {expanded ? <ChevronDown size={14} strokeWidth={1.6} /> : <ChevronRight size={14} strokeWidth={1.6} />}
        </div>
      </button>

      {expanded && (
        <div className={styles.contentArea}>
          {/* F-04: 战争迷雾 — 未揭示时显示反思输入 */}
          {!revealed ? (
            <div className={styles.fogOverlay}>
              <div className={`${shared.flexAlignCenter} ${shared.flexGap6} ${shared.textSm} ${shared.textTertiary}`} style={{ marginBottom: 8 }}>
                <Lock size={12} strokeWidth={1.6} />
                <span>写下你的自我反思（至少 {MIN_REFLECTION_LENGTH} 字）后解锁诊断详情</span>
              </div>
              <textarea
                value={reflection}
                onChange={(e) => setReflection(e.target.value)}
                placeholder="你觉得这段文字可能存在什么问题？为什么？"
                className={styles.reflectionTextarea}
              />
              <div style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                marginTop: 6,
              }}>
                <span style={{
                  fontSize: '0.68rem',
                  color: canReveal ? 'var(--success)' : 'var(--text-tertiary)',
                }}>
                  {reflection.trim().length} / {MIN_REFLECTION_LENGTH} 字
                </span>
                <button
                  onClick={handleReveal}
                  disabled={!canReveal}
                  className={`${styles.revealBtn} ${canReveal ? styles.revealBtnActive : styles.revealBtnDisabled}`}
                >
                  <Eye size={12} strokeWidth={1.6} />
                  <span>查看报告</span>
                </button>
              </div>
            </div>
          ) : (
            <>
              <p style={{ margin: '0 0 6px' }}>{syndrome.name}</p>
              {evidence.length > 0 && (
                <div style={{ marginTop: 6 }}>
                  <span className={`${shared.fontMedium} ${shared.textSm} ${shared.textTertiary}`}>
                    原文证据（{evidence.length} 条）
                  </span>
                  {evidence.slice(0, 3).map((ev: EvidenceRecord, i: number) => {
                    let excerpt = '';
                    try {
                      const p = JSON.parse(ev.contentJson) as Record<string, unknown>;
                      excerpt = (p.text as string) || (p.excerpt as string) || ev.contentJson.slice(0, 120);
                    } catch {
                      excerpt = ev.contentJson.slice(0, 120);
                    }
                    return (
                      <blockquote key={i} className={styles.evidenceBlock}>
                        {excerpt}
                      </blockquote>
                    );
                  })}
                  {evidence.length > 3 && (
                    <span style={{ fontSize: '0.68rem', color: 'var(--text-tertiary)' }}>
                      ...还有 {evidence.length - 3} 条证据
                    </span>
                  )}
                </div>
              )}
              {/* F-02: 常见问题渐进披露 */}
              {showFaqLink && (
                <div style={{ marginTop: 8 }}>
                  <button
                    onClick={() => setFaqExpanded(!faqExpanded)}
                    className={`${styles.faqBtn} ${faqExpanded ? styles.faqBtnExpanded : ''}`}
                  >
                    <HelpCircle size={12} strokeWidth={1.6} />
                    <span>常见问题：{syndrome.name}</span>
                    <span style={{ marginLeft: 'auto', fontSize: '0.68rem', color: 'var(--text-tertiary)' }}>
                      {faqExpanded ? '收起' : '展开'}
                    </span>
                  </button>
                  {faqExpanded && (
                    <div className={styles.faqList}>
                      {(FAQ_PLACEHOLDER[syndrome.id] ?? FAQ_PLACEHOLDER.default).map((q, i) => (
                        <div key={i} style={{
                          padding: '4px 0',
                          display: 'flex',
                          alignItems: 'flex-start',
                          gap: 6,
                          borderBottom: i < FAQ_PLACEHOLDER.default.length - 1 ? '1px dashed var(--border)' : 'none',
                        }}>
                          <span style={{ color: 'var(--accent)', fontWeight: 600, fontSize: '0.68rem', flexShrink: 0 }}>
                            Q{i + 1}
                          </span>
                          <span style={{ color: 'var(--text-secondary)' }}>{q}</span>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              )}
            </>
          )}
        </div>
      )}
    </div>
  );
};

/** 诊断面板主体 */
export const DiagnosisPanel: React.FC = () => {
  const syndromes = useDiagStore(selectCurrentSyndromes);
  const actions = useDiagStore(selectCurrentActions);
  const confidence = useDiagStore(selectCurrentConfidence);
  const currentDiagnosis = useDiagStore(s => s.currentDiagnosis);
  const sidebarPhase = usePanelSessionStore(s => s.sidebarPhase);
  const sidebarMode = usePanelSessionStore(s => s.sidebarMode);

  if (!currentDiagnosis || syndromes.length === 0) {
    return (
      <div className={shared.emptyState}>
        <ClipboardList size={36} strokeWidth={1.4} opacity={0.3} />
        <span className={shared.textLg}>暂无诊断结果</span>
        <span className={shared.textSm}>发送作品片段后，诊断结果将在此显示</span>
      </div>
    );
  }

  return (
    <div className={styles.mainContainer}>
      {sidebarMode === 'template' && (
        <TemplateFormView onSubmit={(_text) => { /* 发送到 ChatView — 通过 IPC 或 store 传递 */ }} />
      )}
      {confidence > 0 && (
        <div className={`${shared.flexAlignCenter} ${shared.flexGap6} ${shared.textSm} ${shared.textTertiary}`} style={{ padding: '0 2px' }}>
          <span>置信度</span>
          <div className={styles.confidenceBarTrack}>
            <div
              className={styles.confidenceBarFill}
              style={{ width: `${Math.round(confidence * 100)}%` }}
            />
          </div>
          <span style={{ fontWeight: 500, fontSize: '0.72rem' }}>
            {Math.round(confidence * 100)}%
          </span>
        </div>
      )}

      <div className={`${shared.flexCol} ${shared.flexGap4}`}>
        <span className={styles.sectionLabel}>
          识别到 {syndromes.length} 个症候
        </span>
        {syndromes.map((s) => (
          <SyndromeCard key={s.id} syndrome={s} />
        ))}
      </div>

      {actions.length > 0 && (
        <div style={{ marginTop: 4 }}>
          <span className={styles.sectionLabelWithMargin}>
            建议动作
          </span>
          <div className={`${shared.flexCol} ${shared.flexGap4}`}>
            {actions.map((action, i) => (
              <div key={i} className={styles.actionItem}>
                {typeof action === 'string' ? action : String(action)}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* F-04: 训练阶段显示分级提示面板 */}
      {sidebarPhase === 'training' && <HintPanel />}
    </div>
  );
};
