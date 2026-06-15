import React, { useState } from 'react';
import { ChevronDown, ChevronRight, AlertTriangle, ClipboardList, HelpCircle, Eye, Lock } from 'lucide-react';
import { useDiagStore, selectCurrentSyndromes, selectCurrentActions, selectCurrentConfidence } from '../../stores/diag.store';
import { usePanelSessionStore } from '../../stores/panel-session.store';
import { HintPanel } from './HintPanel';
import type { SyndromeResult, EvidenceRecord } from '../../shared/types';

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
    <div style={{
      border: '1px solid var(--border)',
      borderRadius: 'var(--radius-md)',
      overflow: 'hidden',
      background: 'var(--bg-card)',
    }}>
      <button
        onClick={handleToggle}
        style={{
          width: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '10px 12px',
          border: 'none',
          background: 'transparent',
          cursor: 'pointer',
          color: 'var(--text-primary)',
          fontSize: '0.82rem',
          fontFamily: 'var(--font-body)',
          textAlign: 'left',
          gap: 8,
        }}
        onMouseEnter={e => { e.currentTarget.style.background = 'var(--bg-hover)'; }}
        onMouseLeave={e => { e.currentTarget.style.background = 'transparent'; }}
      >
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, overflow: 'hidden' }}>
          <AlertTriangle size={14} color={severityColor[syndrome.severity]} strokeWidth={1.8} />
          <span style={{ fontWeight: 500, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
            {syndrome.name}
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{
            fontSize: '0.68rem',
            padding: '1px 6px',
            borderRadius: 'var(--radius-full)',
            background: `${severityColor[syndrome.severity]}18`,
            color: severityColor[syndrome.severity],
            fontWeight: 500,
          }}>
            {severityLabel[syndrome.severity]}
          </span>
          {expanded ? <ChevronDown size={14} strokeWidth={1.6} /> : <ChevronRight size={14} strokeWidth={1.6} />}
        </div>
      </button>

      {expanded && (
        <div style={{ padding: '0 12px 10px', fontSize: '0.78rem', color: 'var(--text-secondary)', lineHeight: 1.6 }}>
          {/* F-04: 战争迷雾 — 未揭示时显示反思输入 */}
          {!revealed ? (
            <div style={{
              position: 'relative',
              padding: '12px',
              background: 'var(--bg-secondary)',
              borderRadius: 'var(--radius-sm)',
              border: '1px dashed var(--border)',
            }}>
              <div style={{
                display: 'flex',
                alignItems: 'center',
                gap: 6,
                marginBottom: 8,
                color: 'var(--text-tertiary)',
                fontSize: '0.72rem',
              }}>
                <Lock size={12} strokeWidth={1.6} />
                <span>写下你的自我反思（至少 {MIN_REFLECTION_LENGTH} 字）后解锁诊断详情</span>
              </div>
              <textarea
                value={reflection}
                onChange={(e) => setReflection(e.target.value)}
                placeholder="你觉得这段文字可能存在什么问题？为什么？"
                style={{
                  width: '100%',
                  minHeight: 60,
                  padding: '8px',
                  border: '1px solid var(--border)',
                  borderRadius: 'var(--radius-sm)',
                  background: 'var(--bg-card)',
                  color: 'var(--text-primary)',
                  fontSize: '0.75rem',
                  fontFamily: 'var(--font-body)',
                  resize: 'vertical',
                  outline: 'none',
                  boxSizing: 'border-box',
                }}
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
                  style={{
                    display: 'flex',
                    alignItems: 'center',
                    gap: 4,
                    padding: '4px 10px',
                    border: 'none',
                    borderRadius: 'var(--radius-sm)',
                    background: canReveal ? 'var(--accent)' : 'var(--bg-hover)',
                    color: canReveal ? '#fff' : 'var(--text-tertiary)',
                    fontSize: '0.72rem',
                    cursor: canReveal ? 'pointer' : 'not-allowed',
                    transition: 'all 200ms ease',
                  }}
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
                  <span style={{ fontWeight: 500, fontSize: '0.72rem', color: 'var(--text-tertiary)' }}>
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
                      <blockquote key={i} style={{
                        margin: '4px 0',
                        padding: '4px 8px',
                        borderLeft: '2px solid var(--accent)',
                        background: 'var(--bg-secondary)',
                        borderRadius: 'var(--radius-sm)',
                        fontSize: '0.75rem',
                        color: 'var(--text-secondary)',
                        fontStyle: 'italic',
                      }}>
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
                    style={{
                      display: 'flex',
                      alignItems: 'center',
                      gap: 4,
                      padding: '4px 8px',
                      border: '1px dashed var(--border)',
                      borderRadius: 'var(--radius-sm)',
                      background: faqExpanded ? 'var(--bg-hover)' : 'transparent',
                      color: 'var(--accent)',
                      fontSize: '0.72rem',
                      cursor: 'pointer',
                      transition: 'all 200ms ease',
                      width: '100%',
                    }}
                    onMouseEnter={e => {
                      if (!faqExpanded) e.currentTarget.style.background = 'var(--bg-hover)';
                    }}
                    onMouseLeave={e => {
                      if (!faqExpanded) e.currentTarget.style.background = 'transparent';
                    }}
                  >
                    <HelpCircle size={12} strokeWidth={1.6} />
                    <span>常见问题：{syndrome.name}</span>
                    <span style={{ marginLeft: 'auto', fontSize: '0.68rem', color: 'var(--text-tertiary)' }}>
                      {faqExpanded ? '收起' : '展开'}
                    </span>
                  </button>
                  {faqExpanded && (
                    <div style={{
                      marginTop: 6,
                      padding: '8px 10px',
                      background: 'var(--bg-secondary)',
                      borderRadius: 'var(--radius-sm)',
                      fontSize: '0.75rem',
                      lineHeight: 1.7,
                    }}>
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

  if (!currentDiagnosis || syndromes.length === 0) {
    return (
      <div style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '40px 20px',
        color: 'var(--text-tertiary)',
        gap: 12,
        textAlign: 'center',
      }}>
        <ClipboardList size={36} strokeWidth={1.4} opacity={0.3} />
        <span style={{ fontSize: '0.85rem' }}>暂无诊断结果</span>
        <span style={{ fontSize: '0.72rem' }}>发送作品片段后，诊断结果将在此显示</span>
      </div>
    );
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      {confidence > 0 && (
        <div style={{
          display: 'flex',
          alignItems: 'center',
          gap: 6,
          fontSize: '0.72rem',
          color: 'var(--text-tertiary)',
          padding: '0 2px',
        }}>
          <span>置信度</span>
          <div style={{
            flex: 1,
            height: 4,
            borderRadius: 2,
            background: 'var(--bg-hover)',
            overflow: 'hidden',
          }}>
            <div style={{
              width: `${Math.round(confidence * 100)}%`,
              height: '100%',
              background: 'var(--accent)',
              borderRadius: 2,
              transition: 'width 400ms ease',
            }} />
          </div>
          <span style={{ fontWeight: 500, fontSize: '0.72rem' }}>
            {Math.round(confidence * 100)}%
          </span>
        </div>
      )}

      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        <span style={{
          fontSize: '0.72rem',
          fontWeight: 600,
          color: 'var(--text-tertiary)',
          letterSpacing: '0.03em',
          padding: '0 2px',
        }}>
          识别到 {syndromes.length} 个症候
        </span>
        {syndromes.map((s) => (
          <SyndromeCard key={s.id} syndrome={s} />
        ))}
      </div>

      {actions.length > 0 && (
        <div style={{ marginTop: 4 }}>
          <span style={{
            fontSize: '0.72rem',
            fontWeight: 600,
            color: 'var(--text-tertiary)',
            letterSpacing: '0.03em',
            padding: '0 2px 4px',
            display: 'block',
          }}>
            建议动作
          </span>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
            {actions.map((action, i) => (
              <div key={i} style={{
                fontSize: '0.78rem',
                color: 'var(--text-secondary)',
                padding: '6px 10px',
                background: 'var(--bg-secondary)',
                borderRadius: 'var(--radius-sm)',
                lineHeight: 1.5,
              }}>
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


