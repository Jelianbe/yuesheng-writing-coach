import React, { useState } from 'react';
import { ChevronDown, ChevronRight, AlertTriangle, ClipboardList } from 'lucide-react';
import { useDiagStore, selectCurrentSyndromes, selectCurrentActions, selectCurrentConfidence } from '../../stores/diag.store';
import type { SyndromeResult, EvidenceRecord } from '../../shared/types';

const severityLabel: Record<string, string> = { L3: '严重', L2: '中度', L1: '轻度' };
const severityColor: Record<string, string> = { L3: '#C0392B', L2: '#D4A04A', L1: '#7EA87E' };

/** 单条症候卡片 */
const SyndromeCard: React.FC<{ syndrome: SyndromeResult }> = ({ syndrome }) => {
  const [expanded, setExpanded] = useState(false);
  const loadEvidence = useDiagStore(s => s.loadEvidence);
  const evidenceMap = useDiagStore(s => s.evidenceMap);

  const handleToggle = () => {
    if (!expanded) {
      const sid = useDiagStore.getState().currentDiagnosis?.sessionId;
      if (sid) loadEvidence(syndrome.id, sid);
    }
    setExpanded(!expanded);
  };

  const evidence = evidenceMap[syndrome.id] ?? [];

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
    </div>
  );
};


