/**
 * TemplateSelector — 模板辅助选择器（V4 I-02）
 *
 * 功能：
 * - 点击模板辅助按钮后弹出 5 类模板选择
 * - 选择后发送预设 prompt 到对话
 */

import React from 'react';

export interface TemplateItem {
  id: string;
  label: string;
  prompt: string;
  description?: string;
}

const TEMPLATES: TemplateItem[] = [
  { id: 'diagnose', label: '作品诊断', prompt: '请帮我诊断这段写作的问题：', description: '分析文本中的写作问题' },
  { id: 'rewrite', label: '润色优化', prompt: '请帮我优化这段文字，保持原意：', description: '改写建议与示范' },
  { id: 'compare', label: '对比分析', prompt: '请对比分析这两段文字的效果差异：', description: '展示修改前后的效果对比' },
  { id: 'skill', label: '技法点评', prompt: '请分析这段文字用了哪些写作技法：', description: '识别和评价写作技法应用' },
  { id: 'example', label: '示范仿写', prompt: '请针对这个写作问题提供一个示范段落：', description: '针对痛点给出示范' },
];

interface TemplateSelectorProps {
  onSelect: (prompt: string) => void;
  onClose: () => void;
}

export const TemplateSelector: React.FC<TemplateSelectorProps> = ({ onSelect, onClose }) => {
  return (
    <div style={{
      position: 'absolute',
      bottom: '100%',
      left: 0,
      right: 0,
      marginBottom: 8,
      background: 'var(--bg-card)',
      border: '1px solid var(--border)',
      borderRadius: 'var(--radius-lg)',
      boxShadow: '0 4px 16px rgba(0,0,0,0.12)',
      overflow: 'hidden',
      zIndex: 100,
    }}>
      <div style={{
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '8px 12px',
        borderBottom: '1px solid var(--border-light)',
        fontSize: '0.72rem',
        fontWeight: 600,
        color: 'var(--text-secondary)',
      }}>
        <span>选择模板</span>
        <button
          onClick={onClose}
          style={{ border: 'none', background: 'transparent', color: 'var(--text-tertiary)', cursor: 'pointer', fontSize: '0.82rem', padding: '2px 6px' }}
          aria-label="关闭"
        >✕</button>
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
        {TEMPLATES.map(t => (
          <button
            key={t.id}
            onClick={() => onSelect(t.prompt)}
            style={{
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'flex-start',
              gap: 2,
              padding: '10px 12px',
              border: 'none',
              borderBottom: '1px solid var(--border-light)',
              background: 'transparent',
              cursor: 'pointer',
              textAlign: 'left',
              transition: 'background 0.1s ease',
            }}
            onMouseEnter={e => { (e.currentTarget as HTMLElement).style.background = 'var(--bg-hover)'; }}
            onMouseLeave={e => { (e.currentTarget as HTMLElement).style.background = 'transparent'; }}
          >
            <span style={{ fontSize: '0.82rem', fontWeight: 500, color: 'var(--text-primary)' }}>
              {t.label}
            </span>
            {t.description && (
              <span style={{ fontSize: '0.68rem', color: 'var(--text-tertiary)' }}>
                {t.description}
              </span>
            )}
          </button>
        ))}
      </div>
    </div>
  );
};
