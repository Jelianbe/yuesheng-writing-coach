/**
 * ToolsPanel — 创作工具面板
 *
 * 提供写作辅助工具集合，当前包含：
 * - 文本分析器（字数/字符/句数统计）
 * - 写作建议速查
 */

import React, { useState } from 'react';
import { FileText, Lightbulb, BookOpen, RotateCcw } from 'lucide-react';

const EASE_OUT_QUART = 'cubic-bezier(0.25, 1, 0.5, 1)';

const WRITING_TIPS = [
  { title: '展示而非告知', desc: '用具体细节和动作展示角色的情感，而非直接描述。' },
  { title: '对话节奏', desc: '短对话加快节奏，长对话放慢节奏。在紧张场景中用短句。' },
  { title: '感官描写', desc: '调动至少三种感官（视觉、听觉、触觉、嗅觉、味觉）来丰富场景。' },
  { title: '开头钩子', desc: '故事开头三句话内必须制造悬念、冲突或强烈情感。' },
  { title: '段落变化', desc: '长短段落交替——长段用于描述和沉思，短段用于动作和紧张。' },
];

const TextAnalyzer: React.FC = () => {
  const [text, setText] = useState('');

  const stats = {
    chars: text.length,
    charsNoSpace: text.replace(/\s/g, '').length,
    words: text ? text.split(/\s+/).filter(Boolean).length : 0,
    sentences: text ? text.split(/[。！？.!?]/).filter(s => s.trim().length > 0).length : 0,
    paragraphs: text ? text.split(/\n\s*\n/).filter(p => p.trim().length > 0).length : 0,
    readingTime: Math.max(1, Math.ceil((text ? text.split(/\s+/).filter(Boolean).length : 0) / 200)),
  };

  return (
    <div>
      <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 8px', display: 'flex', alignItems: 'center', gap: 4 }}>
        <FileText size={13} strokeWidth={1.6} /> 文本分析
      </div>
      <div style={{ border: '1px solid var(--border-light)', borderRadius: 'var(--radius-md)', padding: 8 }}>
        <textarea
          value={text}
          onChange={e => setText(e.target.value)}
          placeholder="在此粘贴或输入文本..."
          rows={3}
          style={{
            width: '100%', resize: 'vertical',
            padding: '6px 8px',
            border: '1px solid var(--border)',
            borderRadius: 'var(--radius-sm)',
            background: 'var(--bg-input)',
            color: 'var(--text-primary)',
            fontFamily: 'var(--font-body)',
            fontSize: '0.72rem',
            lineHeight: 1.5,
            outline: 'none',
            boxSizing: 'border-box',
          }}
        />
        {text.length > 0 && (
          <>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 4, marginTop: 8 }}>
              <StatBox label="字数" value={stats.chars} />
              <StatBox label="字数(去空格)" value={stats.charsNoSpace} />
              <StatBox label="词数" value={stats.words} />
              <StatBox label="句数" value={stats.sentences} />
              <StatBox label="段落" value={stats.paragraphs} />
              <StatBox label="阅读时长" value={`${stats.readingTime}分`} />
            </div>
            <button onClick={() => setText('')}
              style={{ marginTop: 6, padding: '2px 10px', border: '1px solid var(--border)', borderRadius: 'var(--radius-sm)', background: 'transparent', color: 'var(--text-tertiary)', cursor: 'pointer', fontSize: '0.68rem', fontFamily: 'var(--font-body)', display: 'flex', alignItems: 'center', gap: 4 }}>
              <RotateCcw size={11} strokeWidth={1.6} /> 清空
            </button>
          </>
        )}
      </div>
    </div>
  );
};

const StatBox: React.FC<{ label: string; value: string | number }> = ({ label, value }) => (
  <div style={{ padding: '6px 4px', borderRadius: 'var(--radius-sm)', background: 'var(--bg-hover)', textAlign: 'center' }}>
    <div style={{ fontSize: '0.85rem', fontWeight: 600, color: 'var(--text-primary)' }}>{value}</div>
    <div style={{ fontSize: '0.58rem', color: 'var(--text-tertiary)', marginTop: 1 }}>{label}</div>
  </div>
);

const WritingTips: React.FC = () => {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);

  return (
    <div>
      <div style={{ fontSize: '0.72rem', fontWeight: 600, color: 'var(--text-secondary)', letterSpacing: '0.03em', padding: '0 2px 8px', display: 'flex', alignItems: 'center', gap: 4 }}>
        <Lightbulb size={13} strokeWidth={1.6} /> 写作建议
      </div>
      <div style={{ border: '1px solid var(--border-light)', borderRadius: 'var(--radius-md)', display: 'flex', flexDirection: 'column' }}>
        {WRITING_TIPS.map((tip, i) => (
          <div key={i}
            onClick={() => setActiveIndex(activeIndex === i ? null : i)}
            style={{
              padding: '8px 10px',
              cursor: 'pointer',
              borderBottom: i < WRITING_TIPS.length - 1 ? '1px solid var(--border-light)' : 'none',
              transition: `background 150ms ${EASE_OUT_QUART}`,
            }}
            onMouseEnter={e => { e.currentTarget.style.background = 'var(--bg-hover)'; }}
            onMouseLeave={e => { e.currentTarget.style.background = 'transparent'; }}
          >
            <div style={{ fontSize: '0.78rem', fontWeight: 500, color: 'var(--text-primary)', display: 'flex', alignItems: 'center', gap: 6 }}>
              <BookOpen size={12} strokeWidth={1.6} style={{ color: 'var(--accent)' }} />
              {tip.title}
            </div>
            {activeIndex === i && (
              <div style={{ fontSize: '0.72rem', color: 'var(--text-secondary)', marginTop: 4, lineHeight: 1.5 }}>
                {tip.desc}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};

export const ToolsPanel: React.FC = () => {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <TextAnalyzer />
      <WritingTips />
    </div>
  );
};


